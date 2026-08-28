import Foundation

@main
struct VerifyBirthdayDomain {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: 12))!

        let today = BirthdayEntry(name: "Aujourd’hui", month: 8, day: 15, birthYear: 2000)
        let tomorrow = BirthdayEntry(name: "Demain", month: 8, day: 16)
        let nextYear = BirthdayEntry(name: "Passé", month: 2, day: 2, birthYear: 1990)

        let todayOccurrence = BirthdayDateCalculator.occurrence(for: today, from: now, calendar: calendar)
        let nextOccurrence = BirthdayDateCalculator.occurrence(for: nextYear, from: now, calendar: calendar)
        let sorted = BirthdayDateCalculator.sortedOccurrences(
            for: [nextYear, tomorrow, today],
            from: now,
            calendar: calendar
        )
        let leapFallback = BirthdayDateCalculator.date(
            year: 2027,
            month: 2,
            day: 29,
            calendar: calendar
        )

        precondition(todayOccurrence.daysUntil == 0)
        precondition(todayOccurrence.turningAge == 26)
        precondition(calendar.component(.year, from: nextOccurrence.date) == 2027)
        precondition(sorted.map(\.entry.name) == ["Aujourd’hui", "Demain", "Passé"])
        precondition(calendar.component(.day, from: leapFallback) == 28)
        print("Calculs d’anniversaire vérifiés sans simulateur.")
    }
}
