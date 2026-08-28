import Foundation

enum ICSImportError: LocalizedError {
    case unreadableFile
    case invalidCalendar
    case noBirthdays

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            "Ce fichier ICS ne peut pas être lu."
        case .invalidCalendar:
            "Le fichier sélectionné n’est pas un calendrier ICS valide."
        case .noBirthdays:
            "Aucun anniversaire annuel n’a été détecté dans ce fichier."
        }
    }
}

enum ICSImporter {
    static func entries(from data: Data) throws -> [BirthdayEntry] {
        // Un fichier hors norme ne sera jamais un calendrier d'anniversaires :
        // on refuse avant de le décoder plutôt que de le charger en mémoire.
        guard data.count <= BirthdayLimits.importFileBytes else {
            throw ICSImportError.unreadableFile
        }
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? String(data: data, encoding: .isoLatin1) else {
            throw ICSImportError.unreadableFile
        }
        return try entries(from: text)
    }

    static func entries(from text: String) throws -> [BirthdayEntry] {
        let lines = unfoldedLines(in: text)
        guard lines.contains(where: { $0.uppercased() == "BEGIN:VCALENDAR" }) else {
            throw ICSImportError.invalidCalendar
        }

        var events: [[String: String]] = []
        var currentEvent: [String: String]?
        var nestedComponentDepth = 0

        for line in lines {
            let uppercase = line.uppercased()
            if uppercase == "BEGIN:VEVENT" {
                currentEvent = [:]
                nestedComponentDepth = 0
                continue
            }
            if uppercase == "END:VEVENT" {
                if let currentEvent { events.append(currentEvent) }
                currentEvent = nil
                nestedComponentDepth = 0
                continue
            }
            guard currentEvent != nil else { continue }

            if uppercase.hasPrefix("BEGIN:") {
                nestedComponentDepth += 1
                continue
            }
            if uppercase.hasPrefix("END:") {
                nestedComponentDepth = max(0, nestedComponentDepth - 1)
                continue
            }
            guard nestedComponentDepth == 0,
                  let separator = line.firstIndex(of: ":") else { continue }

            let rawKey = String(line[..<separator])
            let key = rawKey.split(separator: ";", maxSplits: 1).first.map(String.init)?.uppercased() ?? ""
            let value = String(line[line.index(after: separator)...])
            if currentEvent?[key] == nil { currentEvent?[key] = value }
        }

        var seen = Set<String>()
        let imported = events.compactMap { properties -> BirthdayEntry? in
            guard let rawSummary = properties["SUMMARY"],
                  let rawStart = properties["DTSTART"],
                  let date = monthAndDay(from: rawStart) else { return nil }

            let summary = unescape(rawSummary).trimmingCharacters(in: .whitespacesAndNewlines)
            let recurrence = properties["RRULE"]?.uppercased() ?? ""
            let categories = properties["CATEGORIES"]?.uppercased() ?? ""
            let normalizedSummary = summary.folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "fr_CH")
            )
            let looksLikeBirthday = recurrence.contains("FREQ=YEARLY")
                || categories.contains("BIRTHDAY")
                || normalizedSummary.contains("anniversaire")
                || normalizedSummary.contains("birthday")
            guard looksLikeBirthday else { return nil }

            let name = cleanName(summary)
            guard !name.isEmpty else { return nil }
            let duplicateKey = "\(normalized(name))|\(date.month)|\(date.day)"
            guard seen.insert(duplicateKey).inserted else { return nil }

            let uid = properties["UID"].map(unescape)
            let explicitBirthYear = properties["X-BIRTHDAYS-BIRTH-YEAR"].flatMap(Int.init)
            let note = BirthdayLimits.clampedNote(properties["DESCRIPTION"].map(unescape) ?? "")
            return BirthdayEntry(
                name: name,
                month: date.month,
                day: date.day,
                birthYear: explicitBirthYear,
                avatarColorHex: BirthdayAvatarPalette.colorHex(for: name),
                note: note,
                source: .calendar,
                sourceIdentifier: uid.map { "ics:\($0)" } ?? "ics:\(duplicateKey)"
            )
        }

        guard !imported.isEmpty else { throw ICSImportError.noBirthdays }
        return imported
            .prefix(BirthdayLimits.importedEntries)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func unfoldedLines(in text: String) -> [String] {
        let normalizedText = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var result: [String] = []
        for substring in normalizedText.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(substring)
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), !result.isEmpty {
                result[result.count - 1] += String(line.dropFirst())
            } else {
                result.append(line)
            }
        }
        return result
    }

    private static func monthAndDay(from value: String) -> (month: Int, day: Int)? {
        let datePart = value.split(separator: "T", maxSplits: 1).first.map(String.init) ?? value
        let digits = datePart.filter(\.isNumber)
        let monthText: Substring
        let dayText: Substring
        if digits.count >= 8 {
            monthText = digits.dropFirst(4).prefix(2)
            dayText = digits.dropFirst(6).prefix(2)
        } else if digits.count == 4 {
            monthText = digits.prefix(2)
            dayText = digits.suffix(2)
        } else {
            return nil
        }
        guard let month = Int(monthText), let day = Int(dayText) else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: 2000, month: month, day: day)),
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day else { return nil }
        return (month, day)
    }

    private static func cleanName(_ summary: String) -> String {
        BirthdayNameFormatter.personName(fromEventTitle: summary)
    }

    private static func unescape(_ value: String) -> String {
        var result = ""
        var isEscaped = false
        for character in value {
            if isEscaped {
                switch character {
                case "n", "N": result.append("\n")
                case "\\", ",", ";": result.append(character)
                default: result.append(character)
                }
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else {
                result.append(character)
            }
        }
        if isEscaped { result.append("\\") }
        return result
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
