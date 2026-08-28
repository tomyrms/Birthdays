import Foundation

@main
enum VerifyICSImport {
    static func main() throws {
        if CommandLine.arguments.count > 1 {
            let url = URL(fileURLWithPath: CommandLine.arguments[1])
            let entries = try ICSImporter.entries(from: Data(contentsOf: url))
            precondition(Set(entries.map(\.sourceIdentifier)).count == entries.count)
            print("\(entries.count) anniversaires ICS vérifiés sans simulateur.")
            return
        }

        let calendar = """
        BEGIN:VCALENDAR\r
        VERSION:2.0\r
        BEGIN:VEVENT\r
        UID:lea@example.com\r
        DTSTART;VALUE=DATE:20000819\r
        RRULE:FREQ=YEARLY\r
        SUMMARY:Anniversaire de Léa\r
         Martin\r
        X-BIRTHDAYS-BIRTH-YEAR:2002\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        DTSTART:20260820T090000Z\r
        SUMMARY:Réunion produit\r
        END:VEVENT\r
        END:VCALENDAR\r
        """
        let entries = try ICSImporter.entries(from: calendar)
        precondition(entries.count == 1)
        precondition(entries[0].name == "LéaMartin")
        precondition(entries[0].month == 8 && entries[0].day == 19)
        precondition(entries[0].birthYear == 2002)
        print("Import ICS vérifié sans simulateur.")
    }
}
