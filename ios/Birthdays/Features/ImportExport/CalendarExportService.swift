import EventKit
import Foundation

enum CalendarTransferError: LocalizedError {
    case accessDenied
    case noCalendar

    var errorDescription: String? {
        switch self {
        case .accessDenied: "L’accès à Calendrier a été refusé."
        case .noCalendar: "Aucun calendrier disponible pour l’export."
        }
    }
}

struct CalendarExportResult {
    let added: Int
    let skipped: Int
}

enum CalendarExportService {
    /// L'app ne demande qu'un accès en écriture : elle ne peut donc pas relire
    /// le calendrier pour repérer ce qu'elle y a déjà mis. On garde nous-mêmes
    /// la trace des exports, sinon chaque appui recréait un événement annuel
    /// par personne — et le calendrier se remplissait de doublons.
    private static let exportedKey = "birthdays.calendarExportedEntries"

    private static var exportedIdentifiers: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: exportedKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: exportedKey) }
    }

    static func forgetExports() {
        UserDefaults.standard.removeObject(forKey: exportedKey)
    }

    @discardableResult
    static func export(_ entries: [BirthdayEntry]) async throws -> CalendarExportResult {
        guard !entries.isEmpty else { return CalendarExportResult(added: 0, skipped: 0) }

        var exported = exportedIdentifiers
        let pending = entries.filter { !exported.contains($0.id.uuidString) }
        let skipped = entries.count - pending.count
        guard !pending.isEmpty else {
            return CalendarExportResult(added: 0, skipped: skipped)
        }

        let store = EKEventStore()
        let granted = try await store.requestWriteOnlyAccessToEvents()
        guard granted else { throw CalendarTransferError.accessDenied }
        guard let calendar = store.defaultCalendarForNewEvents else { throw CalendarTransferError.noCalendar }

        for entry in pending {
            let occurrence = BirthdayDateCalculator.occurrence(for: entry)
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = "Anniversaire de \(entry.name)"
            event.isAllDay = true
            event.startDate = occurrence.date
            event.endDate = Calendar.current.date(byAdding: .day, value: 1, to: occurrence.date)
            event.url = URL(string: "birthdays://birthday/\(entry.id.uuidString)")
            event.addRecurrenceRule(EKRecurrenceRule(
                recurrenceWith: .yearly,
                interval: 1,
                end: nil
            ))
            try store.save(event, span: .futureEvents, commit: false)
            exported.insert(entry.id.uuidString)
        }
        try store.commit()
        // Enregistré seulement après un commit réussi : un échec ne doit pas
        // faire croire que l'export a eu lieu.
        exportedIdentifiers = exported
        return CalendarExportResult(added: pending.count, skipped: skipped)
    }
}
