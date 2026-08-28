import SwiftUI
import UniformTypeIdentifiers

/// Réglages d'apparence et d'usage. Ils vivaient hors de la sauvegarde : une
/// restauration rendait les dates et les photos, mais laissait l'app avec la
/// couleur, l'icône et le fond d'une installation neuve.
/// Tout est facultatif pour qu'une sauvegarde antérieure reste lisible.
struct BackupPreferences: Codable, Sendable {
    var accentHex: String?
    var appIcon: String?
    var backgroundStyle: String?
    var seasonalTint: Bool?
    var photoTintedHero: Bool?
    var contactsAutoScan: Bool?

    @MainActor
    static func capture() -> BackupPreferences {
        let defaults = UserDefaults.standard
        return BackupPreferences(
            accentHex: BirthdayAccent.sanitized(
                defaults.string(forKey: BirthdayAccent.storageKey) ?? BirthdayAccent.defaultHex
            ),
            appIcon: AppIconService.currentIcon?.rawValue,
            backgroundStyle: BirthdayBackgroundStyle.resolved(
                from: defaults.string(forKey: BirthdayBackgroundStyle.storageKey) ?? ""
            ).rawValue,
            seasonalTint: defaults.object(forKey: BirthdayBackgroundContext.seasonalTintKey) as? Bool ?? true,
            photoTintedHero: defaults.object(forKey: BirthdayHeroTint.storageKey) as? Bool ?? true,
            contactsAutoScan: defaults.object(forKey: ContactSyncService.optInKey) as? Bool ?? false
        )
    }

    @MainActor
    func apply() {
        let defaults = UserDefaults.standard
        if let accentHex {
            let cleaned = BirthdayAccent.sanitized(accentHex)
            defaults.set(cleaned, forKey: BirthdayAccent.storageKey)
            // La teinte doit repartir vers le widget, sinon seuls les écrans
            // de l'app suivraient la couleur restaurée.
            BirthdayAccent.publishToSharedStorage(cleaned)
        }
        if let appIcon, let icon = BirthdayAppIcon(rawValue: appIcon) {
            AppIconService.apply(icon)
        }
        if let backgroundStyle {
            defaults.set(
                BirthdayBackgroundStyle.resolved(from: backgroundStyle).rawValue,
                forKey: BirthdayBackgroundStyle.storageKey
            )
        }
        if let seasonalTint {
            defaults.set(seasonalTint, forKey: BirthdayBackgroundContext.seasonalTintKey)
        }
        if let photoTintedHero {
            defaults.set(photoTintedHero, forKey: BirthdayHeroTint.storageKey)
        }
        if let contactsAutoScan {
            defaults.set(contactsAutoScan, forKey: ContactSyncService.optInKey)
        }
    }

    var summary: String {
        var parts: [String] = []
        if accentHex != nil { parts.append("couleur") }
        if appIcon != nil { parts.append("icône") }
        if backgroundStyle != nil { parts.append("fond") }
        if seasonalTint != nil || photoTintedHero != nil { parts.append("ambiance") }
        return parts.isEmpty ? "" : parts.joined(separator: ", ")
    }
}

/// Sauvegarde complète : contrairement à l'export ICS qui ne retient que les
/// noms et les dates, cette archive conserve notes, groupes, photos, emoji,
/// couleurs et réglages. C'est le seul format qui permet de revenir à l'état
/// exact d'avant.
struct BackupArchive: Codable, Sendable {
    static let currentVersion = 2

    var version = BackupArchive.currentVersion
    var exportedAt: Date
    var snapshot: BirthdaySnapshot
    var preferences: BackupPreferences?

    init(
        snapshot: BirthdaySnapshot,
        preferences: BackupPreferences? = nil,
        exportedAt: Date = .now
    ) {
        self.snapshot = snapshot
        self.preferences = preferences
        self.exportedAt = exportedAt
    }

    @MainActor
    static func encoded(from snapshot: BirthdaySnapshot) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let archive = BackupArchive(snapshot: snapshot, preferences: .capture())
        return (try? encoder.encode(archive)) ?? Data()
    }

    enum RestoreError: LocalizedError {
        case tooLarge
        case empty

        var errorDescription: String? {
            switch self {
            case .tooLarge: "Ce fichier est trop volumineux pour être une sauvegarde Birthdays."
            case .empty: "Cette sauvegarde ne contient aucun anniversaire."
            }
        }
    }

    /// Le fichier vient de l'extérieur : on borne avant de le décoder, et on
    /// nettoie les champs après, pour qu'une sauvegarde trafiquée ou corrompue
    /// ne casse ni l'affichage ni le stockage.
    static func decoded(from data: Data) throws -> BackupArchive {
        guard data.count <= BirthdayLimits.backupFileBytes else { throw RestoreError.tooLarge }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var archive = try decoder.decode(BackupArchive.self, from: data)

        archive.snapshot.entries = archive.snapshot.entries
            .prefix(BirthdayLimits.importedEntries)
            .map { entry in
                var sanitized = entry
                sanitized.name = BirthdayLimits.clampedName(entry.name)
                sanitized.note = BirthdayLimits.clampedNote(entry.note)
                return sanitized
            }
            .filter { !$0.name.isEmpty }

        guard !archive.snapshot.entries.isEmpty else { throw RestoreError.empty }
        return archive
    }

    var summary: String {
        let people = snapshot.entries.count
        let photos = snapshot.entries.filter { $0.photoData != nil }.count
        var parts = ["\(people) personne\(people > 1 ? "s" : "")"]
        if !snapshot.groups.isEmpty {
            parts.append("\(snapshot.groups.count) groupe\(snapshot.groups.count > 1 ? "s" : "")")
        }
        if photos > 0 { parts.append("\(photos) photo\(photos > 1 ? "s" : "")") }
        let settings = preferences?.summary ?? ""
        if !settings.isEmpty { parts.append(settings) }
        return parts.joined(separator: " · ")
    }
}

struct BackupFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Décrit ce qu'une restauration va changer, pour que l'utilisateur décide en
/// connaissance de cause avant que quoi que ce soit ne soit écrasé.
struct BackupRestorePlan: Identifiable {
    let id = UUID()
    let archive: BackupArchive
    let filename: String
    let currentCount: Int

    var incomingCount: Int { archive.snapshot.entries.count }
}
