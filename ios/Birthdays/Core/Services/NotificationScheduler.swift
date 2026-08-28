import Foundation
import UserNotifications

actor NotificationScheduler {
    static let shared = NotificationScheduler()

    private let center = UNUserNotificationCenter.current()
    private let calendar = Calendar.autoupdatingCurrent
    private let identifierPrefix = "birthday."

    func isAuthorized() async -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    func reschedule(entries: [BirthdayEntry], defaults: BirthdayReminderSettings) async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral else { return }

        let pending = await center.pendingNotificationRequests()
        let birthdayIDs = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: birthdayIDs)

        let candidates = entries.flatMap { notificationCandidates(for: $0, defaults: defaults) }

        // Plusieurs personnes fêtées le même jour donnaient autant de
        // notifications d'affilée. Elles sont regroupées en une seule, ce qui
        // évite la rafale et libère de la place dans la limite de 64
        // notifications programmables imposée par iOS.
        let groups = Dictionary(grouping: candidates) { candidate in
            NotificationSlot(date: candidate.date, offset: candidate.offset)
        }
        .map { slot, members in
            (slot: slot, members: members.sorted { $0.entry.name < $1.entry.name })
        }
        .sorted { $0.slot.date < $1.slot.date }
        .prefix(60)

        for group in groups {
            let members = group.members
            let content = UNMutableNotificationContent()
            content.sound = .default
            content.interruptionLevel = members.contains(where: { $0.settings.timeSensitive })
                ? .timeSensitive
                : .active

            if let only = members.first, members.count == 1 {
                content.title = only.offset == 0
                    ? "C’est l’anniversaire de \(only.entry.name)"
                    : "Anniversaire à venir"
                content.body = body(for: only)
                // Un seul destinataire : l'appui peut ouvrir sa fiche.
                content.userInfo = ["birthdayID": only.entry.id.uuidString]
            } else {
                let names = members.map(\.entry.name)
                content.title = group.slot.offset == 0
                    ? "\(members.count) anniversaires aujourd’hui"
                    : "\(members.count) anniversaires à venir"
                content.body = groupedBody(names: names, offset: group.slot.offset)
            }

            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: group.slot.date
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: "\(identifierPrefix)\(group.slot.offset).\(group.slot.date.timeIntervalSince1970)",
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    private func groupedBody(names: [String], offset: Int) -> String {
        // Au-delà de trois noms la notification devient illisible : on nomme
        // les premiers et on compte le reste.
        let shown = names.prefix(3).joined(separator: ", ")
        let remaining = names.count - min(names.count, 3)
        let list = remaining > 0 ? "\(shown) et \(remaining) autre\(remaining > 1 ? "s" : "")" : shown
        switch offset {
        case 0: return "\(list) fêtent leur anniversaire aujourd’hui."
        case 1: return "\(list) fêtent leur anniversaire demain."
        default: return "\(list), dans \(offset) jours."
        }
    }

    private func notificationCandidates(
        for entry: BirthdayEntry,
        defaults: BirthdayReminderSettings,
        now: Date = .now
    ) -> [NotificationCandidate] {
        let settings = entry.reminderSettings(defaults: defaults)
        let currentYear = calendar.component(.year, from: now)

        return settings.enabledOffsets.compactMap { offset in
            for year in currentYear...(currentYear + 2) {
                let birthday = BirthdayDateCalculator.date(
                    year: year,
                    month: entry.month,
                    day: entry.day,
                    calendar: calendar
                )
                guard let reminderDay = calendar.date(byAdding: .day, value: -offset, to: birthday),
                      let reminder = calendar.date(
                        bySettingHour: settings.hour,
                        minute: settings.minute,
                        second: 0,
                        of: reminderDay
                      ) else { continue }
                if reminder > now {
                    return NotificationCandidate(
                        entry: entry,
                        settings: settings,
                        offset: offset,
                        date: reminder
                    )
                }
            }
            return nil
        }
    }

    private func body(for candidate: NotificationCandidate) -> String {
        switch candidate.offset {
        case 0:
            if let year = candidate.entry.birthYear {
                let occurrenceYear = calendar.component(.year, from: candidate.date)
                return "\(candidate.entry.name) fête ses \(max(0, occurrenceYear - year)) ans aujourd’hui."
            }
            return "Pensez à lui envoyer un message aujourd’hui."
        case 1:
            return "L’anniversaire de \(candidate.entry.name) est demain."
        case 7:
            return "L’anniversaire de \(candidate.entry.name) est dans une semaine."
        case 14:
            return "L’anniversaire de \(candidate.entry.name) est dans deux semaines."
        case 30:
            return "L’anniversaire de \(candidate.entry.name) est dans un mois."
        default:
            return "L’anniversaire de \(candidate.entry.name) est dans \(candidate.offset) jours."
        }
    }
}

/// Identifie un créneau de notification : une même date et un même délai
/// doivent donner un seul rappel, quel que soit le nombre de personnes.
private struct NotificationSlot: Hashable {
    let date: Date
    let offset: Int
}

private struct NotificationCandidate: Sendable {
    let entry: BirthdayEntry
    let settings: BirthdayReminderSettings
    let offset: Int
    let date: Date
}
