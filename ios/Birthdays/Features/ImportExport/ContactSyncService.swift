import Contacts
import Foundation

/// L'import ponctuel laisse filer tous les anniversaires ajoutés au carnet
/// d'adresses après coup. Ce service cherche au lancement ce qui manque encore,
/// sans jamais rien écrire sans validation de l'utilisateur.
enum ContactSyncService {
    static let optInKey = "birthdays.contacts.autoScan"
    private static let ignoredKey = "birthdays.contacts.ignoredIdentifiers"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: optInKey) }
        set { UserDefaults.standard.set(newValue, forKey: optInKey) }
    }

    static var hasAccess: Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .authorized { return true }
        if #available(iOS 18.0, *), status == .limited { return true }
        return false
    }

    private static var ignoredIdentifiers: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: ignoredKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: ignoredKey) }
    }

    static func ignore(_ entries: [BirthdayEntry]) {
        var ignored = ignoredIdentifiers
        for entry in entries {
            if let identifier = entry.sourceIdentifier { ignored.insert(identifier) }
        }
        ignoredIdentifiers = ignored
    }

    /// Renvoie uniquement les contacts dont l'anniversaire n'est ni déjà
    /// enregistré, ni précédemment écarté.
    private static let lastScanKey = "birthdays.contacts.lastScan"
    /// Parcourir tout le carnet d'adresses à chaque retour au premier plan est
    /// inutile : les anniversaires n'y apparaissent pas toutes les minutes.
    private static let minimumScanInterval: TimeInterval = 6 * 3_600

    static func newBirthdays(existing: [BirthdayEntry], force: Bool = false) async -> [BirthdayEntry] {
        guard isEnabled, hasAccess else { return [] }

        let defaults = UserDefaults.standard
        let last = defaults.object(forKey: lastScanKey) as? Date
        if !force, let last, Date.now.timeIntervalSince(last) < minimumScanInterval {
            return []
        }
        defaults.set(Date.now, forKey: lastScanKey)

        let knownIdentifiers = Set(existing.compactMap { $0.source == .contacts ? $0.sourceIdentifier : nil })
        let knownNameDates = Set(existing.map { key(name: $0.name, month: $0.month, day: $0.day) })
        let ignored = ignoredIdentifiers

        return await Task.detached(priority: .utility) { () -> [BirthdayEntry] in
            let keys: [CNKeyDescriptor] = [
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactOrganizationNameKey as CNKeyDescriptor,
                CNContactBirthdayKey as CNKeyDescriptor,
                CNContactThumbnailImageDataKey as CNKeyDescriptor,
                CNContactFormatter.descriptorForRequiredKeys(for: .fullName)
            ]
            let request = CNContactFetchRequest(keysToFetch: keys)
            var found: [BirthdayEntry] = []

            try? CNContactStore().enumerateContacts(with: request) { contact, _ in
                guard !knownIdentifiers.contains(contact.identifier),
                      !ignored.contains(contact.identifier),
                      let birthday = contact.birthday,
                      let month = birthday.month,
                      let day = birthday.day else { return }

                let formatted = CNContactFormatter.string(from: contact, style: .fullName)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let fallback = contact.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
                let name = formatted.isEmpty ? fallback : formatted
                guard !name.isEmpty,
                      !knownNameDates.contains(key(name: name, month: month, day: day)) else { return }

                found.append(
                    BirthdayEntry(
                        name: name,
                        month: month,
                        day: day,
                        birthYear: birthday.year,
                        avatarStyle: contact.thumbnailImageData == nil ? .initials : .photo,
                        photoData: contact.thumbnailImageData.flatMap { ImageProcessor.thumbnailData(from: $0) },
                        avatarColorHex: BirthdayAvatarPalette.colorHex(for: name),
                        source: .contacts,
                        sourceIdentifier: contact.identifier
                    )
                )
            }
            return found
        }.value
    }

    private static func key(name: String, month: Int, day: Int) -> String {
        let normalized = name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(normalized)|\(month)|\(day)"
    }
}
