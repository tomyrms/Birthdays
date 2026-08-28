import Foundation

enum BirthdayAvatarStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case initials
    case emoji
    case photo

    var id: Self { self }

    var title: String {
        switch self {
        case .initials: "Initiales"
        case .emoji: "Emoji"
        case .photo: "Photo"
        }
    }
}

enum BirthdaySource: String, Codable, Sendable {
    case manual
    case contacts
    case calendar
}

enum BirthdayAvatarPalette {
    private static let colors = [
        "6856E8", "C95565", "218078", "C57A2D",
        "3472B8", "A94E83", "66733A", "7A5EAE"
    ]

    static func colorHex(for name: String) -> String {
        let normalized = name.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "fr_CH")
        )
        let hash = normalized.utf8.reduce(UInt32(2_166_136_261)) { value, byte in
            (value ^ UInt32(byte)) &* 16_777_619
        }
        return colors[Int(hash % UInt32(colors.count))]
    }
}

struct BirthdayReminderSettings: Codable, Equatable, Sendable {
    /// Un rappel la veille arrive trop tard pour commander un cadeau : les
    /// délais longs sont là pour laisser le temps d'agir.
    static let availableOffsets = [0, 1, 3, 7, 14, 30]

    var hour: Int = 10
    var minute: Int = 0
    var timeSensitive = true
    /// Nombre de jours avant l'anniversaire. 0 correspond au jour même.
    var offsets: [Int] = [0]

    var enabledOffsets: [Int] { offsets.sorted() }

    init() {}

    static func label(forOffset offset: Int) -> String {
        switch offset {
        case 0: "Le jour même"
        case 1: "La veille"
        case 7: "Une semaine avant"
        case 14: "Deux semaines avant"
        case 30: "Un mois avant"
        default: "\(offset) jours avant"
        }
    }


    mutating func toggle(offset: Int) {
        if let index = offsets.firstIndex(of: offset) {
            offsets.remove(at: index)
        } else {
            offsets.append(offset)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case hour, minute, timeSensitive, offsets
        case onBirthday, oneDayBefore, oneWeekBefore
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hour = try container.decodeIfPresent(Int.self, forKey: .hour) ?? 10
        minute = try container.decodeIfPresent(Int.self, forKey: .minute) ?? 0
        timeSensitive = try container.decodeIfPresent(Bool.self, forKey: .timeSensitive) ?? true

        if let stored = try container.decodeIfPresent([Int].self, forKey: .offsets) {
            offsets = stored
            return
        }
        // Reprise des trois interrupteurs historiques pour les installations
        // enregistrées avant l'ajout des délais libres.
        var migrated: [Int] = []
        if try container.decodeIfPresent(Bool.self, forKey: .onBirthday) ?? true { migrated.append(0) }
        if try container.decodeIfPresent(Bool.self, forKey: .oneDayBefore) ?? false { migrated.append(1) }
        if try container.decodeIfPresent(Bool.self, forKey: .oneWeekBefore) ?? false { migrated.append(7) }
        offsets = migrated
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hour, forKey: .hour)
        try container.encode(minute, forKey: .minute)
        try container.encode(timeSensitive, forKey: .timeSensitive)
        try container.encode(offsets, forKey: .offsets)
    }
}

struct BirthdayGroup: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var colorHex: String

    init(id: UUID = UUID(), name: String, colorHex: String) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }

    static let friends = BirthdayGroup(
        id: UUID(uuidString: "A51EE859-D825-43E2-B50A-D7E70FD7F5A1")!,
        name: "Amis",
        colorHex: "6B66FF"
    )

    static let family = BirthdayGroup(
        id: UUID(uuidString: "5FB40F8C-9F73-4E9C-8C86-AB6552E7C3BA")!,
        name: "Famille",
        colorHex: "E16A54"
    )
}

struct BirthdayEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var month: Int
    var day: Int
    var birthYear: Int?
    var avatarStyle: BirthdayAvatarStyle
    var emoji: String
    var photoData: Data?
    var avatarColorHex: String
    var groupIDs: [UUID]
    var customReminders: BirthdayReminderSettings?
    var note: String
    var isFavorite: Bool
    var source: BirthdaySource
    var sourceIdentifier: String?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        month: Int,
        day: Int,
        birthYear: Int? = nil,
        avatarStyle: BirthdayAvatarStyle = .initials,
        emoji: String = "🎂",
        photoData: Data? = nil,
        avatarColorHex: String = "6B66FF",
        groupIDs: [UUID] = [],
        customReminders: BirthdayReminderSettings? = nil,
        note: String = "",
        isFavorite: Bool = false,
        source: BirthdaySource = .manual,
        sourceIdentifier: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.month = month
        self.day = day
        self.birthYear = birthYear
        self.avatarStyle = avatarStyle
        self.emoji = emoji
        self.photoData = photoData
        self.avatarColorHex = avatarColorHex
        self.groupIDs = groupIDs
        self.customReminders = customReminders
        self.note = note
        self.isFavorite = isFavorite
        self.source = source
        self.sourceIdentifier = sourceIdentifier
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, month, day, birthYear, avatarStyle, emoji, photoData
        case avatarColorHex, groupIDs, customReminders, note, isFavorite
        case source, sourceIdentifier, createdAt, updatedAt
    }

    /// Décodage tolérant : les champs ajoutés après coup doivent rester
    /// facultatifs, sinon un enregistrement écrit par une version antérieure
    /// devient illisible et toute la bibliothèque paraît vide.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        month = try container.decodeIfPresent(Int.self, forKey: .month) ?? 1
        day = try container.decodeIfPresent(Int.self, forKey: .day) ?? 1
        birthYear = try container.decodeIfPresent(Int.self, forKey: .birthYear)
        avatarStyle = try container.decodeIfPresent(BirthdayAvatarStyle.self, forKey: .avatarStyle) ?? .initials
        emoji = try container.decodeIfPresent(String.self, forKey: .emoji) ?? "🎂"
        photoData = try container.decodeIfPresent(Data.self, forKey: .photoData)
        avatarColorHex = try container.decodeIfPresent(String.self, forKey: .avatarColorHex) ?? "6B66FF"
        groupIDs = try container.decodeIfPresent([UUID].self, forKey: .groupIDs) ?? []
        customReminders = try container.decodeIfPresent(BirthdayReminderSettings.self, forKey: .customReminders)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        source = try container.decodeIfPresent(BirthdaySource.self, forKey: .source) ?? .manual
        sourceIdentifier = try container.decodeIfPresent(String.self, forKey: .sourceIdentifier)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
    }

    var initials: String {
        let words = name.split(separator: " ")
        let letters = words.prefix(2).compactMap(\.first)
        let value = String(letters).uppercased()
        return value.isEmpty ? "?" : value
    }

    func reminderSettings(defaults: BirthdayReminderSettings) -> BirthdayReminderSettings {
        customReminders ?? defaults
    }
}

struct BirthdaySnapshot: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var entries: [BirthdayEntry] = []
    var groups: [BirthdayGroup] = [.family, .friends]
    var defaultReminders = BirthdayReminderSettings()
}
