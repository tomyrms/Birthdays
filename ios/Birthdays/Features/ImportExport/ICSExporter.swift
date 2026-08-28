import SwiftUI
import UniformTypeIdentifiers

struct ICSFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.calendarEvent] }
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

enum ICSExporter {
    static func calendar(entries: [BirthdayEntry], defaults: BirthdayReminderSettings) -> String {
        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Shulker//Birthdays//FR",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH"
        ]

        for entry in entries {
            let settings = entry.reminderSettings(defaults: defaults)
            lines.append(contentsOf: [
                "BEGIN:VEVENT",
                "UID:\(entry.id.uuidString)@birthdays.shulker.ch",
                "DTSTAMP:\(timestamp(.now))",
                String(format: "DTSTART;VALUE=DATE:2000%02d%02d", entry.month, entry.day),
                "RRULE:FREQ=YEARLY",
                "SUMMARY:\(escape("Anniversaire de \(entry.name)"))",
                "URL:birthdays://birthday/\(entry.id.uuidString)"
            ])
            if let birthYear = entry.birthYear {
                lines.append("X-BIRTHDAYS-BIRTH-YEAR:\(birthYear)")
            }
            for offset in settings.enabledOffsets {
                lines.append(contentsOf: [
                    "BEGIN:VALARM",
                    "ACTION:DISPLAY",
                    "DESCRIPTION:\(escape("Anniversaire de \(entry.name)"))",
                    "TRIGGER;RELATED=START:\(alarmDuration(offsetDays: offset, hour: settings.hour, minute: settings.minute))",
                    "END:VALARM"
                ])
            }
            lines.append("END:VEVENT")
        }
        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    private static func escape(_ value: String) -> String {
        value
            // Un retour chariot non normalisé casserait le pliage de lignes du
            // fichier et rendrait l'événement illisible pour les autres apps.
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            // Les retours chariot sont normalisés avant échappement : laissés
            // tels quels, ils couperaient la ligne et rendraient l'événement
            // illisible pour les autres applications de calendrier.
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func alarmDuration(offsetDays: Int, hour: Int, minute: Int) -> String {
        let totalMinutes = hour * 60 + minute - offsetDays * 24 * 60
        let sign = totalMinutes < 0 ? "-" : ""
        let absolute = abs(totalMinutes)
        let days = absolute / (24 * 60)
        let hours = (absolute % (24 * 60)) / 60
        let minutes = absolute % 60
        return "\(sign)P\(days)DT\(hours)H\(minutes)M"
    }
}
