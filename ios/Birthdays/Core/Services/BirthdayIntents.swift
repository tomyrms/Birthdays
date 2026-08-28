import AppIntents
import Foundation

/// Sans App Intent, l'app reste invisible pour Siri, les Raccourcis et les
/// automatisations. Ces intents lisent l'instantané partagé, donc ils
/// fonctionnent même quand l'app n'est pas lancée.
struct NextBirthdayIntent: AppIntent {
    static var title: LocalizedStringResource = "Prochain anniversaire"
    static var description = IntentDescription("Indique quel anniversaire arrive et dans combien de temps.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = SharedBirthdayStorage.load()
        let occurrences = BirthdayDateCalculator.sortedOccurrences(for: snapshot.entries)

        guard let next = occurrences.first else {
            return .result(dialog: "Aucun anniversaire enregistré pour l’instant.")
        }
        return .result(dialog: IntentDialog(stringLiteral: Self.phrase(for: next)))
    }

    static func phrase(for occurrence: BirthdayOccurrence) -> String {
        let name = occurrence.entry.name
        switch occurrence.daysUntil {
        case 0:
            if let age = occurrence.turningAge {
                return "C’est l’anniversaire de \(name) aujourd’hui, \(age) ans."
            }
            return "C’est l’anniversaire de \(name) aujourd’hui."
        case 1:
            return "L’anniversaire de \(name) est demain."
        default:
            return "Le prochain anniversaire est celui de \(name), dans \(occurrence.daysUntil) jours."
        }
    }
}

struct UpcomingBirthdaysIntent: AppIntent {
    static var title: LocalizedStringResource = "Anniversaires à venir"
    static var description = IntentDescription("Liste les anniversaires des prochaines semaines.")
    static var openAppWhenRun = false

    @Parameter(title: "Nombre de jours", default: 30)
    var days: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<[String]> {
        let snapshot = SharedBirthdayStorage.load()
        let window = max(1, days)
        let upcoming = BirthdayDateCalculator.sortedOccurrences(for: snapshot.entries)
            .filter { $0.daysUntil <= window }

        guard !upcoming.isEmpty else {
            return .result(
                value: [],
                dialog: "Aucun anniversaire dans les \(window) prochains jours."
            )
        }

        let lines = upcoming.map { occurrence in
            occurrence.daysUntil == 0
                ? "\(occurrence.entry.name) aujourd’hui"
                : "\(occurrence.entry.name) dans \(occurrence.daysUntil) jours"
        }
        return .result(
            value: lines,
            dialog: IntentDialog(stringLiteral: lines.joined(separator: ", "))
        )
    }
}

struct AddBirthdayIntent: AppIntent {
    static var title: LocalizedStringResource = "Ajouter un anniversaire"
    static var description = IntentDescription("Ouvre Birthdays sur la saisie d’une nouvelle date.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationRouter.shared.pendingAddRequest = true
        return .result()
    }
}

struct BirthdaysShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextBirthdayIntent(),
            phrases: [
                "Prochain anniversaire dans \(.applicationName)",
                "Quel est le prochain anniversaire dans \(.applicationName)",
                "Next birthday in \(.applicationName)"
            ],
            shortTitle: "Prochain anniversaire",
            systemImageName: "gift"
        )
        AppShortcut(
            intent: UpcomingBirthdaysIntent(),
            phrases: [
                "Anniversaires à venir dans \(.applicationName)",
                "Upcoming birthdays in \(.applicationName)"
            ],
            shortTitle: "Anniversaires à venir",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: AddBirthdayIntent(),
            phrases: [
                "Ajouter un anniversaire dans \(.applicationName)",
                "Add a birthday in \(.applicationName)"
            ],
            shortTitle: "Ajouter un anniversaire",
            systemImageName: "plus.circle"
        )
    }
}
