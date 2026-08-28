import EventKit
import SwiftUI

struct CalendarImportView: View {
    @Environment(\.dismiss) private var dismiss
    let onImport: ([BirthdayEntry]) -> Void

    @State private var candidates: [CalendarBirthdayCandidate] = []
    @State private var selection = Set<String>()
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Lecture du calendrier…")
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("Accès impossible", systemImage: "calendar.badge.exclamationmark")
                    } description: {
                        Text(errorMessage)
                    }
                } else if candidates.isEmpty {
                    ContentUnavailableView(
                        "Aucun anniversaire détecté",
                        systemImage: "calendar",
                        description: Text("Les événements annuels ou contenant “anniversaire” apparaîtront ici.")
                    )
                } else {
                    List(candidates) { candidate in
                        Button {
                            if selection.contains(candidate.id) { selection.remove(candidate.id) }
                            else { selection.insert(candidate.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selection.contains(candidate.id) ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(selection.contains(candidate.id) ? BirthdayTheme.Palette.accent : BirthdayTheme.Palette.secondaryText)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(candidate.name).foregroundStyle(BirthdayTheme.Palette.text)
                                    Text(candidate.dateText)
                                        .font(.birthdayMeta)
                                        .foregroundStyle(BirthdayTheme.Palette.secondaryText)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .birthdayScreenBackground(isAnimated: true)
            .navigationTitle(candidates.isEmpty ? "Depuis Calendrier" : "\(selection.count) sur \(candidates.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    if !candidates.isEmpty {
                        Button(selection.count == candidates.count ? "Aucun" : "Tout") {
                            selection = selection.count == candidates.count
                                ? []
                                : Set(candidates.map(\.id))
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Importer") {
                        let entries = candidates.filter { selection.contains($0.id) }.map(\.entry)
                        onImport(entries)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(selection.isEmpty)
                }
            }
            .task { await load() }
        }
        .presentationCornerRadius(24)
    }

    private func load() async {
        do {
            candidates = try await CalendarImportService.loadCandidates()
            selection = Set(candidates.map(\.id))
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Autorisez l’accès complet à Calendrier dans Réglages iOS."
        }
        isLoading = false
    }
}

struct CalendarBirthdayCandidate: Identifiable {
    let id: String
    let entry: BirthdayEntry

    var name: String { entry.name }
    var dateText: String {
        BirthdayDateCalculator.date(year: 2000, month: entry.month, day: entry.day)
            .formatted(Date.FormatStyle().day().month(.wide).locale(Locale(identifier: "fr_CH")))
    }
}

enum CalendarImportService {
    static func loadCandidates() async throws -> [CalendarBirthdayCandidate] {
        let store = EKEventStore()
        let granted = try await store.requestFullAccessToEvents()
        guard granted else { throw CalendarTransferError.accessDenied }

        let calendar = Calendar.autoupdatingCurrent
        let year = calendar.component(.year, from: .now)
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
        let end = calendar.date(byAdding: .year, value: 2, to: start)!
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        // `EKEvent.title` peut être nul : un événement sans titre faisait
        // planter le filtre au moment de la lecture du calendrier.
        let events = store.events(matching: predicate).filter { event in
            guard let rawTitle = event.title, !rawTitle.isEmpty else { return false }
            let title = rawTitle.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            let annual = event.recurrenceRules?.contains(where: { $0.frequency == .yearly }) == true
            return annual || title.contains("anniversaire") || title.contains("birthday")
        }

        var seen = Set<String>()
        return events.compactMap { event -> CalendarBirthdayCandidate? in
            guard let rawTitle = event.title, let startDate = event.startDate else { return nil }
            let components = calendar.dateComponents([.month, .day], from: startDate)
            guard let month = components.month, let day = components.day else { return nil }
            let key = "\(event.calendarItemIdentifier)-\(month)-\(day)"
            guard seen.insert(key).inserted else { return nil }
            let cleanName = BirthdayNameFormatter.personName(fromEventTitle: rawTitle)
            guard !cleanName.isEmpty else { return nil }
            let entry = BirthdayEntry(
                name: cleanName,
                month: month,
                day: day,
                source: .calendar,
                sourceIdentifier: event.calendarItemIdentifier
            )
            return CalendarBirthdayCandidate(id: key, entry: entry)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
