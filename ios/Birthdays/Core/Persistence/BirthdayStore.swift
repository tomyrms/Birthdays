import Combine
import Foundation
import WidgetKit

@MainActor
final class BirthdayStore: ObservableObject {
    @Published private(set) var snapshot: BirthdaySnapshot
    @Published private(set) var lastSaveError: String?
    private var notificationRefreshTask: Task<Void, Never>?

    init(snapshot: BirthdaySnapshot? = nil) {
        self.snapshot = snapshot ?? SharedBirthdayStorage.load()
        if snapshot == nil { SharedBirthdayStorage.refreshRecoveryCopies(for: self.snapshot) }
    }

    var entries: [BirthdayEntry] { snapshot.entries }
    var groups: [BirthdayGroup] { snapshot.groups }
    var defaultReminders: BirthdayReminderSettings { snapshot.defaultReminders }

    /// Y a-t-il quelqu'un à fêter aujourd'hui ? Sert à décider si l'ouverture
    /// de l'app mérite des confettis.
    var hasBirthdayToday: Bool {
        entries.contains { BirthdayDateCalculator.occurrence(for: $0).daysUntil == 0 }
    }

    func entry(id: UUID) -> BirthdayEntry? {
        entries.first { $0.id == id }
    }

    func upsert(_ entry: BirthdayEntry) {
        var value = entry
        value.updatedAt = .now
        if let index = snapshot.entries.firstIndex(where: { $0.id == value.id }) {
            snapshot.entries[index] = value
        } else {
            snapshot.entries.append(value)
        }
        commit()
    }

    @discardableResult
    func remove(_ entry: BirthdayEntry) -> [BirthdayEntry] {
        remove(ids: [entry.id])
    }

    /// Renvoie les entrées retirées pour que l'appelant puisse proposer une
    /// annulation : sans cela une suppression groupée serait irréversible.
    @discardableResult
    func remove(ids: Set<UUID>) -> [BirthdayEntry] {
        guard !ids.isEmpty else { return [] }
        let removed = snapshot.entries.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return [] }
        snapshot.entries.removeAll { ids.contains($0.id) }
        commit()
        return removed
    }

    /// Modifie la fiche telle qu'elle est enregistrée, plutôt qu'une copie
    /// capturée par la vue : réécrire une copie périmée efface les champs
    /// changés entre-temps, comme le favori perdu à chaque modification.
    func updateEntry(id: UUID, _ mutate: (inout BirthdayEntry) -> Void) {
        guard let index = snapshot.entries.firstIndex(where: { $0.id == id }) else { return }
        mutate(&snapshot.entries[index])
        snapshot.entries[index].updatedAt = .now
        commit()
    }

    func toggleFavorite(_ entry: BirthdayEntry) {
        guard let index = snapshot.entries.firstIndex(where: { $0.id == entry.id }) else { return }
        snapshot.entries[index].isFavorite.toggle()
        snapshot.entries[index].updatedAt = .now
        commit()
    }

    func reinsert(_ entries: [BirthdayEntry]) {
        let existing = Set(snapshot.entries.map(\.id))
        let restored = entries.filter { !existing.contains($0.id) }
        guard !restored.isEmpty else { return }
        snapshot.entries.append(contentsOf: restored)
        commit()
    }

    func replaceAll(with incoming: BirthdaySnapshot) {
        snapshot = incoming
        commit()
    }

    /// Fusionne une sauvegarde sans rien écraser : les personnes déjà connues
    /// sont conservées telles quelles.
    @discardableResult
    func merge(_ incoming: BirthdaySnapshot) -> Int {
        // Comparer aussi les noms : une sauvegarde venue d'une autre
        // installation a d'autres identifiants et créerait un second
        // « Famille » à côté du premier.
        for group in incoming.groups {
            let known = snapshot.groups.contains {
                $0.id == group.id || $0.name.caseInsensitiveCompare(group.name) == .orderedSame
            }
            if !known { snapshot.groups.append(group) }
        }
        return importEntries(incoming.entries)
    }

    func addToGroup(_ groupID: UUID, entryIDs: Set<UUID>) {
        guard !entryIDs.isEmpty else { return }
        var changed = false
        for index in snapshot.entries.indices where entryIDs.contains(snapshot.entries[index].id) {
            if !snapshot.entries[index].groupIDs.contains(groupID) {
                snapshot.entries[index].groupIDs.append(groupID)
                changed = true
            }
        }
        if changed { commit() }
    }

    func updateDefaultReminders(_ settings: BirthdayReminderSettings) {
        snapshot.defaultReminders = settings
        commit()
    }

    func addGroup(name: String, colorHex: String) {
        let cleaned = BirthdayLimits.clampedName(name)
        guard !cleaned.isEmpty,
              !snapshot.groups.contains(where: { $0.name.caseInsensitiveCompare(cleaned) == .orderedSame }) else {
            return
        }
        snapshot.groups.append(BirthdayGroup(name: cleaned, colorHex: colorHex))
        commit()
    }

    func updateGroup(_ group: BirthdayGroup, name: String, colorHex: String) {
        guard let index = snapshot.groups.firstIndex(where: { $0.id == group.id }) else { return }
        let cleaned = BirthdayLimits.clampedName(name)
        guard !cleaned.isEmpty else { return }
        // Le doublon se juge sur les autres groupes : renommer un groupe en
        // ne changeant que la casse doit rester possible.
        let conflict = snapshot.groups.contains {
            $0.id != group.id && $0.name.caseInsensitiveCompare(cleaned) == .orderedSame
        }
        guard !conflict else { return }

        snapshot.groups[index].name = cleaned
        snapshot.groups[index].colorHex = colorHex
        commit()
    }

    func memberCount(of group: BirthdayGroup) -> Int {
        snapshot.entries.filter { $0.groupIDs.contains(group.id) }.count
    }

    func removeGroup(_ group: BirthdayGroup) {
        snapshot.groups.removeAll { $0.id == group.id }
        for index in snapshot.entries.indices {
            snapshot.entries[index].groupIDs.removeAll { $0 == group.id }
        }
        commit()
    }

    @discardableResult
    func importEntries(_ candidates: [BirthdayEntry]) -> Int {
        var imported = 0
        for candidate in candidates {
            let duplicate = snapshot.entries.contains { existing in
                if let sourceIdentifier = candidate.sourceIdentifier,
                   existing.source == candidate.source,
                   existing.sourceIdentifier == sourceIdentifier {
                    return true
                }
                return normalized(existing.name) == normalized(candidate.name)
                    && existing.month == candidate.month
                    && existing.day == candidate.day
            }
            if !duplicate {
                snapshot.entries.append(candidate)
                imported += 1
            }
        }
        if imported > 0 { commit() }
        return imported
    }

    /// Reprogrammer efface puis réinscrit jusqu'à 60 notifications. Le faire à
    /// chaque modification — y compris un favori, sans effet sur les rappels —
    /// est inutilement coûteux : les changements rapprochés sont regroupés.
    private func scheduleNotificationRefresh() {
        notificationRefreshTask?.cancel()
        notificationRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.rescheduleNotifications()
        }
    }

    func rescheduleNotifications() async {
        await NotificationScheduler.shared.reschedule(
            entries: snapshot.entries,
            defaults: snapshot.defaultReminders
        )
    }

    private func commit() {
        do {
            try SharedBirthdayStorage.save(snapshot)
            lastSaveError = nil
            WidgetCenter.shared.reloadAllTimelines()
            scheduleNotificationRefresh()
        } catch {
            lastSaveError = "Impossible d’enregistrer les changements."
        }
    }


    private func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

}
