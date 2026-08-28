import XCTest
@testable import Birthdays

final class BirthdayDateCalculatorTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testTodayHasZeroDaysRemaining() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: 12))!
        let entry = BirthdayEntry(name: "Léa", month: 8, day: 15)
        let occurrence = BirthdayDateCalculator.occurrence(for: entry, from: now, calendar: calendar)
        XCTAssertEqual(occurrence.daysUntil, 0)
    }

    func testPastBirthdayMovesToNextYearAndComputesTurningAge() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 15))!
        let entry = BirthdayEntry(name: "Léa", month: 2, day: 2, birthYear: 2000)
        let occurrence = BirthdayDateCalculator.occurrence(for: entry, from: now, calendar: calendar)
        XCTAssertEqual(calendar.component(.year, from: occurrence.date), 2027)
        XCTAssertEqual(occurrence.turningAge, 27)
    }

    func testLeapDayFallsBackToFebruary28InNonLeapYear() {
        let date = BirthdayDateCalculator.date(year: 2027, month: 2, day: 29, calendar: calendar)
        XCTAssertEqual(calendar.component(.month, from: date), 2)
        XCTAssertEqual(calendar.component(.day, from: date), 28)
    }

    func testSortingUsesNextOccurrence() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 15))!
        let later = BirthdayEntry(name: "Plus tard", month: 9, day: 1)
        let sooner = BirthdayEntry(name: "Bientôt", month: 8, day: 16)
        let values = BirthdayDateCalculator.sortedOccurrences(for: [later, sooner], from: now, calendar: calendar)
        XCTAssertEqual(values.map(\.entry.name), ["Bientôt", "Plus tard"])
    }

    func testICSImportReadsAnnualBirthdayAndBirthYear() throws {
        let text = """
        BEGIN:VCALENDAR\r
        VERSION:2.0\r
        BEGIN:VEVENT\r
        UID:lea@example.com\r
        DTSTART;VALUE=DATE:20000819\r
        RRULE:FREQ=YEARLY\r
        SUMMARY:Anniversaire de Léa Martin\r
        X-BIRTHDAYS-BIRTH-YEAR:2002\r
        END:VEVENT\r
        END:VCALENDAR\r
        """

        let entries = try ICSImporter.entries(from: text)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.name, "Léa Martin")
        XCTAssertEqual(entries.first?.month, 8)
        XCTAssertEqual(entries.first?.day, 19)
        XCTAssertEqual(entries.first?.birthYear, 2002)
    }

    func testICSImportIgnoresOrdinaryEvents() {
        let text = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        DTSTART:20260820T090000Z
        SUMMARY:Réunion produit
        END:VEVENT
        END:VCALENDAR
        """

        XCTAssertThrowsError(try ICSImporter.entries(from: text))
    }
}
