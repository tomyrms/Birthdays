import SwiftUI
import UIKit

struct BirthdayMemoryLensView: View {
    let entry: BirthdayEntry
    var widthRatio: CGFloat = 0.70
    var minimumWidth: CGFloat = 230

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var artwork: MemoryLensArtwork?
    @State private var fallbackImage: UIImage?
    @State private var isRevealed = false

    /// Le recadrage soigné (visage, teinte dominante) part en tâche de fond et
    /// peut traîner au démarrage à froid, quand Vision charge ses modèles en
    /// même temps que le reste de l'app. Sans ce repli, la carte restait vide
    /// tant que ce traitement n'était pas fini — parfois jamais avant un
    /// relancement. Le décodage brut, lui, est immédiat et sert de photo le
    /// temps que la version soignée arrive.
    private var displayImage: UIImage? { artwork?.image ?? fallbackImage }

    var body: some View {
        GeometryReader { proxy in
            if let displayImage {
                let lensWidth = min(proxy.size.width, max(proxy.size.width * widthRatio, minimumWidth))
                let identityColor = Color(hexString: BirthdayAccent.currentHex)

                ZStack(alignment: .trailing) {
                    if let accentColor = artwork?.accentColor {
                        RadialGradient(
                            colors: [Color(uiColor: accentColor).opacity(0.18), .clear],
                            center: .trailing,
                            startRadius: 0,
                            endRadius: lensWidth * 0.72
                        )
                            .frame(width: lensWidth * 1.24)
                    }

                    lensImage(displayImage, width: lensWidth, height: proxy.size.height)
                        .saturation(0.96)
                        .contrast(1.02)
                        .opacity(0.96)

                    // Une teinte identitaire fait le lien entre le fond et la photo,
                    // puis un voile anthracite très léger protège la lisibilité avant
                    // de disparaître totalement sur les visages.
                    LinearGradient(
                        stops: [
                            .init(color: identityColor.opacity(0.48), location: 0),
                            .init(color: identityColor.opacity(0.24), location: 0.28),
                            .init(color: Color(hexString: "1D1C22").opacity(0.16), location: 0.52),
                            .init(color: Color(hexString: "1D1C22").opacity(0.05), location: 0.70),
                            .init(color: .clear, location: 0.86)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .opacity(isRevealed ? 1 : 0)
                .scaleEffect(isRevealed ? 1 : 1.025, anchor: .trailing)
                .onAppear {
                    guard !reduceMotion else { isRevealed = true; return }
                    withAnimation(.easeOut(duration: 0.42)) { isRevealed = true }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: PhotoTaskID(entry: entry)) {
            isRevealed = false
            artwork = nil
            fallbackImage = nil
            guard entry.avatarStyle == .photo, let data = entry.photoData else { return }
            fallbackImage = UIImage(data: data)
            let generated = await MemoryLensArtworkCache.shared.artwork(from: data)
            guard !Task.isCancelled else { return }
            if let generated { artwork = generated }
        }
    }

    private func lensImage(
        _ image: UIImage,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        Image(uiImage: image)
            .resizable()
            .interpolation(.medium)
            .scaledToFill()
            .frame(width: width, height: height)
            .clipped()
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white.opacity(0.04), location: 0.10),
                        .init(color: .white.opacity(0.16), location: 0.24),
                        .init(color: .white.opacity(0.44), location: 0.42),
                        .init(color: .white.opacity(0.78), location: 0.60),
                        .init(color: .white, location: 0.76)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// Identifie la photo, pas la fiche : se baser sur `updatedAt` relançait le
/// chargement au moindre changement sans rapport (mise en favori, groupe…),
/// ce qui faisait disparaître l'image le temps du recalcul.
private struct PhotoTaskID: Hashable {
    let entryID: UUID
    let avatarStyle: BirthdayAvatarStyle
    let photoSize: Int

    init(entry: BirthdayEntry) {
        entryID = entry.id
        avatarStyle = entry.avatarStyle
        photoSize = entry.photoData?.count ?? 0
    }
}
