import Foundation
import Security

enum SharedBirthdayStorage {
    private static let filename = "birthdays.json"
    private static let keychainService = "ch.shulker.birthdays.widget-snapshot"
    private static let keychainAccount = "upcoming-birthdays"
    private static let cloudCatalogService = "ch.shulker.birthdays.cloud-catalog"
    private static let cloudCatalogAccount = "birthday-catalog-v1"
    private static let localPhotoService = "ch.shulker.birthdays.photo-vault.local"
    private static let cloudPhotoService = "ch.shulker.birthdays.photo-vault.icloud"
    private static let appearanceService = "ch.shulker.birthdays.appearance"
    private static let appearanceAccount = "accent-hex"

    /// `includingPhotos: false` évite de charger toutes les images d'un coup.
    /// Le widget dispose d'un budget mémoire très serré : au-delà de quelques
    /// photos, le système le termine et la vignette reste vide.
    static func load(includingPhotos: Bool = true) -> BirthdaySnapshot {
        func finish(_ snapshot: BirthdaySnapshot) -> BirthdaySnapshot {
            includingPhotos ? restoringPhotos(in: snapshot) : snapshot
        }

        if let data = try? Data(contentsOf: localFileURL()),
           let snapshot = try? decoder.decode(BirthdaySnapshot.self, from: data) {
            return finish(snapshot)
        }

        if let data = readSharedSnapshot(),
           let snapshot = try? decoder.decode(BirthdaySnapshot.self, from: data) {
            return finish(snapshot)
        }

        if let data = readKeychainData(
            service: cloudCatalogService,
            account: cloudCatalogAccount,
            synchronizable: true
        ), let snapshot = try? decoder.decode(BirthdaySnapshot.self, from: data) {
            return finish(snapshot)
        }

        return BirthdaySnapshot()
    }

    /// La teinte doit traverser la frontière app / extension. UserDefaults n'est
    /// pas partagé avec le widget, qui afficherait sinon toujours la couleur
    /// par défaut quelle que soit celle choisie dans l'app.
    static func writeAccentHex(_ hex: String) {
        writeKeychainData(
            Data(hex.utf8),
            service: appearanceService,
            account: appearanceAccount,
            synchronizable: false
        )
    }

    static func readAccentHex() -> String? {
        readKeychainData(
            service: appearanceService,
            account: appearanceAccount,
            synchronizable: false
        ).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// La copie locale d'abord : une requête sur le trousseau iCloud peut
    /// attendre le réseau, ce qui dépasse le budget de temps d'un widget et le
    /// laisse bloqué sur son écran de chargement.
    static func photoData(forEntry id: UUID) -> Data? {
        let account = id.uuidString.lowercased()
        return readKeychainData(
            service: localPhotoService,
            account: account,
            synchronizable: false
        ) ?? readKeychainData(
            service: cloudPhotoService,
            account: account,
            synchronizable: true
        )
    }

    static func save(_ snapshot: BirthdaySnapshot) throws {
        let url = localFileURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Les photos sont écrites AVANT d'être retirées du JSON : si une
        // écriture échoue, l'image reste présente dans l'ancien fichier plutôt
        // que d'être perdue entre les deux étapes.
        refreshPhotoVault(using: snapshot)
        writePhotoFiles(for: snapshot)

        // Encodées en base64 dans le JSON, les photos le faisaient gonfler de
        // plusieurs mégaoctets — réécrits en entier au moindre changement.
        let lean = strippingPhotos(from: snapshot)
        let data = try encoder.encode(lean)
        // Notes et photos restent illisibles tant que l'appareil est
        // verrouillé. Sans risque ici : l'app ne travaille jamais en fond, et
        // le widget lit le trousseau, pas ce fichier.
        try data.write(to: url, options: [.atomic, .completeFileProtection])

        if let sharedData = try? encoder.encode(lean) {
            writeSharedSnapshot(sharedData)
            writeKeychainData(
                sharedData,
                service: cloudCatalogService,
                account: cloudCatalogAccount,
                synchronizable: true
            )
        }
    }

    /// Migrates photos already stored in the local JSON into the recovery vault.
    /// Calling this at launch protects existing users without requiring an edit first.
    static func refreshRecoveryCopies(for snapshot: BirthdaySnapshot) {
        writePhotoFiles(for: snapshot)
        let catalog = strippingPhotos(from: snapshot)
        if let data = try? encoder.encode(catalog) {
            writeSharedSnapshot(data)
            writeKeychainData(
                data,
                service: cloudCatalogService,
                account: cloudCatalogAccount,
                synchronizable: true
            )
        }
        refreshPhotoVault(using: snapshot)
    }

    private static func strippingPhotos(from snapshot: BirthdaySnapshot) -> BirthdaySnapshot {
        var lean = snapshot
        for index in lean.entries.indices { lean.entries[index].photoData = nil }
        return lean
    }

    private static func photosDirectoryURL() -> URL {
        localFileURL().deletingLastPathComponent().appendingPathComponent("Photos", isDirectory: true)
    }

    private static func photoFileURL(for id: UUID) -> URL {
        photosDirectoryURL().appendingPathComponent("\(id.uuidString.lowercased()).jpg")
    }

    /// Chaque photo devient un fichier autonome : le JSON principal redevient
    /// minuscule et n'est plus réécrit avec plusieurs mégaoctets d'images à
    /// chaque changement.
    private static func writePhotoFiles(for snapshot: BirthdaySnapshot) {
        let manager = FileManager.default
        let directory = photosDirectoryURL()
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)

        var keep = Set<String>()
        for entry in snapshot.entries where entry.avatarStyle == .photo {
            let url = photoFileURL(for: entry.id)
            keep.insert(url.lastPathComponent)
            guard let data = entry.photoData else { continue }
            // Inutile de réécrire une image identique.
            if let existing = try? Data(contentsOf: url), existing == data { continue }
            try? data.write(to: url, options: [.atomic, .completeFileProtection])
        }

        // Les fichiers des fiches supprimées ne doivent pas s'accumuler.
        let existing = (try? manager.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in existing where !keep.contains(name) {
            try? manager.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    private static func photoFileData(for id: UUID) -> Data? {
        try? Data(contentsOf: photoFileURL(for: id))
    }

    private static func localFileURL() -> URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return support
            .appendingPathComponent("Birthdays", isDirectory: true)
            .appendingPathComponent(filename)
    }

    private static func readSharedSnapshot() -> Data? {
        readKeychainData(
            service: keychainService,
            account: keychainAccount,
            synchronizable: false
        )
    }

    private static func writeSharedSnapshot(_ data: Data) {
        writeKeychainData(
            data,
            service: keychainService,
            account: keychainAccount,
            synchronizable: false
        )
    }

    private static func restoringPhotos(in snapshot: BirthdaySnapshot) -> BirthdaySnapshot {
        var restored = snapshot
        for index in restored.entries.indices where restored.entries[index].photoData == nil {
            guard restored.entries[index].avatarStyle == .photo else { continue }
            let id = restored.entries[index].id
            restored.entries[index].photoData = photoFileData(for: id) ?? photoData(forEntry: id)
        }
        return restored
    }

    private static let photoDigestsKey = "birthdays.photoVaultDigests"

    private static func refreshPhotoVault(using snapshot: BirthdaySnapshot) {
        let photoEntries = snapshot.entries.filter { $0.avatarStyle == .photo }
        let activeAccounts = Set(photoEntries.map { $0.id.uuidString.lowercased() })

        // Sans cette empreinte, la moindre modification (un favori, un groupe)
        // réécrivait toutes les photos dans le trousseau, deux fois chacune.
        var digests = UserDefaults.standard.dictionary(forKey: photoDigestsKey) as? [String: String] ?? [:]

        for entry in photoEntries {
            guard let photoData = entry.photoData else { continue }
            let account = entry.id.uuidString.lowercased()
            let digest = checksum(photoData)
            guard digests[account] != digest else { continue }

            // The local copy makes reinstall recovery work even when iCloud Keychain is off.
            let localWritten = writeKeychainData(
                photoData,
                service: localPhotoService,
                account: account,
                synchronizable: false
            )
            // A synchronizable item follows the user's iCloud Keychain to their other devices.
            let cloudWritten = writeKeychainData(
                photoData,
                service: cloudPhotoService,
                account: account,
                synchronizable: true
            )
            if localWritten || cloudWritten { digests[account] = digest }
        }

        digests = digests.filter { activeAccounts.contains($0.key) }
        UserDefaults.standard.set(digests, forKey: photoDigestsKey)

        removeStaleItems(service: localPhotoService, synchronizable: false, keeping: activeAccounts)
        removeStaleItems(service: cloudPhotoService, synchronizable: true, keeping: activeAccounts)
    }

    private static func readKeychainData(
        service: String,
        account: String,
        synchronizable: Bool
    ) -> Data? {
        var query = keychainIdentity(
            service: service,
            account: account,
            synchronizable: synchronizable
        )
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    @discardableResult
    private static func writeKeychainData(
        _ data: Data,
        service: String,
        account: String,
        synchronizable: Bool
    ) -> Bool {
        let identity = keychainIdentity(
            service: service,
            account: account,
            synchronizable: synchronizable
        )
        let status = SecItemUpdate(
            identity as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecSuccess { return true }

        if status != errSecItemNotFound {
            SecItemDelete(identity as CFDictionary)
        }

        var item = identity
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = synchronizable
            ? kSecAttrAccessibleAfterFirstUnlock
            : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    private static func keychainIdentity(
        service: String,
        account: String,
        synchronizable: Bool
    ) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: synchronizable ? kCFBooleanTrue! : kCFBooleanFalse!
        ]
    }

    private static func removeStaleItems(
        service: String,
        synchronizable: Bool,
        keeping accounts: Set<String>
    ) {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: synchronizable ? kCFBooleanTrue! : kCFBooleanFalse!,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return }

        let records: [[String: Any]]
        if let values = result as? [[String: Any]] {
            records = values
        } else if let value = result as? [String: Any] {
            records = [value]
        } else {
            return
        }

        for record in records {
            guard let account = record[kSecAttrAccount as String] as? String,
                  !accounts.contains(account) else { continue }
            query = keychainIdentity(
                service: service,
                account: account,
                synchronizable: synchronizable
            )
            SecItemDelete(query as CFDictionary)
        }
    }

    /// Empreinte stable d'une exécution à l'autre — contrairement à `hashValue`,
    /// dont la graine change à chaque lancement du processus.
    private static func checksum(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16) + "-" + String(data.count, radix: 16)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
