import Foundation

struct BirthdayOccurrence: Identifiable, Equatable {
    let entry: BirthdayEntry
    let date: Date
    let daysUntil: Int
    /// Âge atteint au prochain anniversaire.
    let turningAge: Int?

    var id: UUID { entry.id }

    /// Âge d'aujourd'hui. Tant que l'anniversaire n'a pas eu lieu, la personne
    /// a un an de moins que ce qu'elle va fêter — d'où la confusion possible si
    /// l'on affiche `turningAge` sous un simple libellé « Âge ».
    var currentAge: Int? {
        guard let turningAge else { return nil }
        return daysUntil == 0 ? turningAge : max(0, turningAge - 1)
    }
}

enum BirthdayDateCalculator {
    static func occurrence(
        for entry: BirthdayEntry,
        from now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> BirthdayOccurrence {
        let today = calendar.startOfDay(for: now)
        let currentYear = calendar.component(.year, from: today)
        var occurrenceDate = date(
            year: currentYear,
            month: entry.month,
            day: entry.day,
            calendar: calendar
        )
        if occurrenceDate < today {
            occurrenceDate = date(
                year: currentYear + 1,
                month: entry.month,
                day: entry.day,
                calendar: calendar
            )
        }
        let days = calendar.dateComponents([.day], from: today, to: occurrenceDate).day ?? 0
        let occurrenceYear = calendar.component(.year, from: occurrenceDate)
        let age = entry.birthYear.map { max(0, occurrenceYear - $0) }
        return BirthdayOccurrence(entry: entry, date: occurrenceDate, daysUntil: days, turningAge: age)
    }

    static func sortedOccurrences(
        for entries: [BirthdayEntry],
        from date: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [BirthdayOccurrence] {
        entries
            .map { occurrence(for: $0, from: date, calendar: calendar) }
            .sorted {
                if $0.date == $1.date {
                    return $0.entry.name.localizedCaseInsensitiveCompare($1.entry.name) == .orderedAscending
                }
                return $0.date < $1.date
            }
    }

    static func sectionTitle(
        for occurrence: BirthdayOccurrence,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        if occurrence.daysUntil == 0 { return "Aujourd’hui" }
        if occurrence.daysUntil == 1 { return "Demain" }

        let today = calendar.startOfDay(for: now)
        let week = calendar.dateInterval(of: .weekOfYear, for: today)
        if let week, week.contains(occurrence.date) { return "Cette semaine" }
        if let nextWeekDate = calendar.date(byAdding: .weekOfYear, value: 1, to: today),
           let nextWeek = calendar.dateInterval(of: .weekOfYear, for: nextWeekDate),
           nextWeek.contains(occurrence.date) {
            return "La semaine prochaine"
        }

        let occurrenceYear = calendar.component(.year, from: occurrence.date)
        let currentYear = calendar.component(.year, from: today)
        let locale = Locale(identifier: "fr_CH")
        if occurrenceYear == currentYear {
            return occurrence.date.formatted(
                Date.FormatStyle().month(.wide).locale(locale)
            ).capitalized
        }
        return occurrence.date.formatted(
            Date.FormatStyle().month(.wide).year().locale(locale)
        ).capitalized
    }

    /// Convertit une saisie libre — une année (« 1998 ») ou un âge (« 28 ») —
    /// en année de naissance.
    ///
    /// Un âge se compte depuis le dernier anniversaire : si celui-ci n'a pas
    /// encore eu lieu cette année, l'année de naissance recule d'un an. Sans
    /// cette correction, saisir un âge donnait une année fausse pour toutes les
    /// personnes dont l'anniversaire est encore à venir.
    static func birthYear(
        fromInput text: String,
        month: Int,
        day: Int,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let value = Int(trimmed), value > 0 else { return nil }

        let currentYear = calendar.component(.year, from: now)
        if value <= 130 {
            let today = calendar.startOfDay(for: now)
            let thisYear = date(year: currentYear, month: month, day: day, calendar: calendar)
            let hasOccurred = thisYear <= today
            return currentYear - value - (hasOccurred ? 0 : 1)
        }
        if (1900...currentYear).contains(value) { return value }
        return nil
    }

    static func date(
        year: Int,
        month: Int,
        day: Int,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date {
        let safeMonth = min(max(month, 1), 12)
        let monthStart = calendar.date(from: DateComponents(year: year, month: safeMonth, day: 1))!
        let dayRange = calendar.range(of: .day, in: .month, for: monthStart)!
        let safeDay = min(max(day, 1), dayRange.count)
        return calendar.date(from: DateComponents(year: year, month: safeMonth, day: safeDay))!
    }
}
