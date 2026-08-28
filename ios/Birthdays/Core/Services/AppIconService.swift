import UIKit

/// Réservé à l'app : l'extension widget compile aussi le design system, mais
/// `UIApplication` y est interdit — d'où ce fichier séparé.
enum BirthdayAppIcon: String, CaseIterable, Identifiable, Codable, Sendable {
    case original = "AppIcon"
    case dark = "AppIcon-Dark"
    case light = "AppIcon-Light"
    case blue = "AppIcon-Blue"
    case purple = "AppIcon-Purple"
    case green = "AppIcon-Green"
    case red = "AppIcon-Red"
    case navy = "AppIcon-Navy"
    case gold = "AppIcon-Gold"
    case silver = "AppIcon-Silver"

    static let storageKey = "birthdays.appearance.appIcon"
    static let defaultValue = BirthdayAppIcon.original

    var id: String { rawValue }

    var alternateIconName: String? {
        self == .original ? nil : rawValue
    }

    /// Les catalogues AppIcon ne sont pas exposés comme des images SwiftUI.
    /// Le script d'assets maintient une copie légère dans une `.imageset`.
    var previewAssetName: String {
        "\(rawValue)-Preview"
    }

    var title: String {
        switch self {
        case .original: "Originale"
        case .dark: "Sombre"
        case .light: "Claire"
        case .blue: "Bleue"
        case .purple: "Violette"
        case .green: "Verte"
        case .red: "Rouge"
        case .navy: "Marine"
        case .gold: "Or"
        case .silver: "Argent"
        }
    }

    init?(alternateIconName: String?) {
        guard let alternateIconName else {
            self = .original
            return
        }
        self.init(rawValue: alternateIconName)
    }
}

@MainActor
enum AppIconService {
    enum ServiceError: LocalizedError {
        case unsupported

        var errorDescription: String? {
            switch self {
            case .unsupported:
                "Cet appareil ne permet pas de modifier l’icône de l’app."
            }
        }
    }

    static var currentIcon: BirthdayAppIcon? {
        BirthdayAppIcon(alternateIconName: UIApplication.shared.alternateIconName)
    }

    static func apply(
        _ icon: BirthdayAppIcon,
        completion: @escaping (Result<BirthdayAppIcon, Error>) -> Void = { _ in }
    ) {
        guard UIApplication.shared.supportsAlternateIcons else {
            completion(.failure(ServiceError.unsupported))
            return
        }

        let iconName = icon.alternateIconName
        guard UIApplication.shared.alternateIconName != iconName else {
            persist(icon)
            completion(.success(icon))
            return
        }

        UIApplication.shared.setAlternateIconName(iconName) { error in
            Task { @MainActor in
                if let error {
                    completion(.failure(error))
                } else {
                    persist(icon)
                    completion(.success(icon))
                }
            }
        }
    }

    private static func persist(_ icon: BirthdayAppIcon) {
        UserDefaults.standard.set(icon.rawValue, forKey: BirthdayAppIcon.storageKey)
    }
}
