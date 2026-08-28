import SwiftUI
import UIKit

enum BirthdayHeroTint {
    static let storageKey = "birthdays.appearance.photoTintedHero"
}

/// Fond des cartes vedettes. Par défaut il suit la couleur d'accent ; quand
/// l'option est active et qu'une photo est présente, il reprend la teinte
/// dominante de cette photo pour que la carte s'accorde à l'image.
struct BirthdayHeroBackground: View {
    let entry: BirthdayEntry

    @AppStorage(BirthdayHeroTint.storageKey) private var photoTintEnabled = true
    @State private var tintHex: String?

    var body: some View {
        Group {
            if let tintHex {
                // On réutilise la construction du dégradé de l'app plutôt que
                // de superposer des opacités : mélanger la teinte avec du
                // transparent la délave et donne une carte grisâtre.
                BirthdayAccent.heroGradient(for: tintHex)
            } else {
                BirthdayTheme.Palette.heroGradient
            }
        }
        .animation(.easeOut(duration: 0.35), value: tintHex)
        .task(id: TintTaskID(entry: entry, enabled: photoTintEnabled)) {
            await resolveTint()
        }
    }

    private func resolveTint() async {
        guard photoTintEnabled,
              entry.avatarStyle == .photo,
              let data = entry.photoData else {
            tintHex = nil
            return
        }
        // Le calcul est déjà mis en cache par MemoryLensArtworkCache : la carte
        // et la photo partagent donc le même travail, fait une seule fois.
        let artwork = await MemoryLensArtworkCache.shared.artwork(from: data)
        guard !Task.isCancelled else { return }
        tintHex = artwork.map { Self.hexString(from: $0.accentColor) }
    }

    private static func hexString(from color: UIColor) -> String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return BirthdayAccent.currentHex
        }
        return String(
            format: "%02X%02X%02X",
            Int(round(red * 255)),
            Int(round(green * 255)),
            Int(round(blue * 255))
        )
    }
}

/// Même principe que pour la photo : la teinte ne dépend que de l'image.
private struct TintTaskID: Hashable {
    let entryID: UUID
    let avatarStyle: BirthdayAvatarStyle
    let photoSize: Int
    let enabled: Bool

    init(entry: BirthdayEntry, enabled: Bool) {
        entryID = entry.id
        avatarStyle = entry.avatarStyle
        photoSize = entry.photoData?.count ?? 0
        self.enabled = enabled
    }
}
