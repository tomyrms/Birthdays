import ImageIO
import SwiftUI
import UIKit
import WidgetKit

/// Une extension de widget dispose d'un budget mémoire de l'ordre de 30 Mo.
/// Décoder une photo de 640 px produit déjà ~1,6 Mo, que chaque passe de rendu
/// duplique. On la redimensionne donc au décodage, sans jamais matérialiser
/// l'image pleine taille.
enum WidgetPhoto {
    static func downsampled(_ data: Data, maxPixel: CGFloat = 420) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.82)
    }
}

struct BirthdaysWidgetEntry: TimelineEntry {
    let date: Date
    let occurrences: [BirthdayOccurrence]
}

struct BirthdaysTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> BirthdaysWidgetEntry {
        BirthdaysWidgetEntry(date: .now, occurrences: sampleOccurrences)
    }

    func getSnapshot(in context: Context, completion: @escaping (BirthdaysWidgetEntry) -> Void) {
        // En aperçu (galerie de widgets), iOS attend une réponse immédiate :
        // aller lire le trousseau ici risque de laisser la vignette figée.
        guard !context.isPreview else {
            completion(BirthdaysWidgetEntry(date: .now, occurrences: sampleOccurrences))
            return
        }
        completion(makeEntry(for: context.family))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BirthdaysWidgetEntry>) -> Void) {
        let entry = makeEntry(for: context.family)
        let nextMidnight = Calendar.current.date(
            byAdding: .day,
            value: 1,
            to: Calendar.current.startOfDay(for: .now)
        ) ?? Date.now.addingTimeInterval(86_400)
        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }

    /// Chaque photo coûte une lecture du trousseau et une image décompressée en
    /// mémoire. On n'en charge donc que le nombre réellement affiché par la
    /// famille demandée, jamais plus.
    private func photoBudget(for family: WidgetFamily) -> Int {
        switch family {
        case .systemLarge: 5
        case .systemSmall, .systemMedium: 1
        default: 0
        }
    }

    private func makeEntry(for family: WidgetFamily) -> BirthdaysWidgetEntry {
        BirthdayAccent.invalidateSharedCache()
        let snapshot = SharedBirthdayStorage.load(includingPhotos: false)
        let visible = Array(
            BirthdayDateCalculator.sortedOccurrences(for: snapshot.entries).prefix(5)
        )
        let budget = photoBudget(for: family)

        let occurrences = visible.enumerated().map { index, occurrence -> BirthdayOccurrence in
            guard index < budget,
                  occurrence.entry.avatarStyle == .photo,
                  occurrence.entry.photoData == nil,
                  let data = SharedBirthdayStorage.photoData(forEntry: occurrence.entry.id),
                  let reduced = WidgetPhoto.downsampled(data) else {
                return occurrence
            }
            var hydrated = occurrence.entry
            hydrated.photoData = reduced
            return BirthdayOccurrence(
                entry: hydrated,
                date: occurrence.date,
                daysUntil: occurrence.daysUntil,
                turningAge: occurrence.turningAge
            )
        }
        return BirthdaysWidgetEntry(date: .now, occurrences: occurrences)
    }

    private var sampleOccurrences: [BirthdayOccurrence] {
        BirthdayDateCalculator.sortedOccurrences(for: [
            BirthdayEntry(name: "Léa Martin", month: 8, day: 19, birthYear: 2002),
            BirthdayEntry(name: "Noah", month: 9, day: 4),
            BirthdayEntry(name: "Camille Roux", month: 9, day: 12, birthYear: 1996)
        ])
    }
}

// MARK: - Avatar

/// L'avatar du widget est autonome : la vue du design system appartient à la
/// cible principale et n'est pas compilée dans l'extension.
private struct WidgetAvatar: View {
    let entry: BirthdayEntry
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            switch entry.avatarStyle {
            case .photo:
                if let data = entry.photoData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    initialsLayer
                }
            case .emoji:
                Color(hexString: entry.avatarColorHex).opacity(0.9)
                Text(entry.emoji)
                    .font(.system(size: size * 0.5))
            case .initials:
                initialsLayer
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .strokeBorder(.white.opacity(0.22), lineWidth: 1)
        }
    }

    private var initialsLayer: some View {
        ZStack {
            Color(hexString: entry.avatarColorHex)
            Text(entry.initials)
                .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
    }
}

// MARK: - Vue principale

struct BirthdaysWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var contentMargins
    let entry: BirthdaysWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryInline: inline
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .systemSmall: small
            case .systemLarge: large
            default: medium
            }
        }
        // Les marges sont désormais gérées ici : le décor va jusqu'au bord,
        // seul le texte est retiré des bords. L'écran verrouillé garde
        // exactement l'espacement système.
        .padding(isLockScreen ? contentMargins : EdgeInsets())
        .containerBackground(for: .widget) { widgetBackground }
    }

    private var textInsets: EdgeInsets {
        EdgeInsets(
            top: max(contentMargins.top, 14),
            leading: max(contentMargins.leading, 14),
            bottom: max(contentMargins.bottom, 14),
            trailing: max(contentMargins.trailing, 14)
        )
    }

    private var isLockScreen: Bool {
        family == .accessoryInline || family == .accessoryCircular || family == .accessoryRectangular
    }

    // MARK: Écran verrouillé

    private var inline: some View {
        Group {
            if let next = entry.occurrences.first {
                Label(inlineText(next), systemImage: next.daysUntil == 0 ? "gift.fill" : "calendar")
            } else {
                Label("Aucun anniversaire", systemImage: "calendar")
            }
        }
        .widgetURL(nextURL)
    }

    private var circular: some View {
        Group {
            if let next = entry.occurrences.first {
                if next.daysUntil == 0 {
                    // Le jour J, un compte à rebours à zéro n'apprend rien :
                    // les initiales disent enfin de qui il s'agit.
                    ZStack {
                        AccessoryWidgetBackground()
                        VStack(spacing: -1) {
                            Image(systemName: "gift.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text(next.entry.initials.prefix(3))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                        }
                    }
                    .widgetAccentable()
                } else {
                    Gauge(value: circularProgress(next), in: 0...1) {
                        Text(next.entry.initials.prefix(2))
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                    } currentValueLabel: {
                        Text("\(min(next.daysUntil, 99))")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .monospacedDigit()
                    }
                    .gaugeStyle(.accessoryCircular)
                    .widgetAccentable()
                }
            } else {
                Image(systemName: "calendar.badge.plus").font(.title2)
            }
        }
        .widgetURL(nextURL ?? URL(string: "birthdays://add"))
        .accessibilityLabel(circularAccessibilityLabel)
    }

    private var rectangular: some View {
        Group {
            if let next = entry.occurrences.first {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: next.daysUntil == 0 ? "gift.fill" : "birthday.cake.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .widgetAccentable()
                        Text(next.entry.name)
                            .font(.headline)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(compactCountdown(next))
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .monospacedDigit()
                    }
                    Text(detailLine(next))
                        .font(.caption)
                        .lineLimit(1)

                    // La deuxième ligne exploite la hauteur disponible plutôt
                    // que de la laisser vide.
                    if let following = entry.occurrences.dropFirst().first {
                        HStack(spacing: 4) {
                            Text("puis")
                                .font(.caption2)
                                .opacity(0.6)
                            Text(following.entry.name)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text(compactCountdown(following))
                                .font(.caption2.monospacedDigit())
                                .opacity(0.7)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Birthdays", systemImage: "gift.fill").font(.headline)
                    Text("Ajoutez un anniversaire").font(.caption)
                }
            }
        }
        .widgetURL(nextURL ?? URL(string: "birthdays://add"))
        .accessibilityLabel(rectangularAccessibilityLabel)
    }

    // MARK: Écran d'accueil

    private var small: some View {
        Group {
            if let next = entry.occurrences.first {
                ZStack(alignment: .bottomLeading) {
                    memoryLens(next, widthRatio: 0.82)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 3) {
                            Text(next.daysUntil == 0 ? "AUJOURD’HUI" : "PROCHAIN")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.8)
                                .foregroundStyle(.white.opacity(0.72))
                        }
                        Spacer(minLength: 4)
                        countdownBlock(next, digitSize: 40, labelSize: 11, labelBottomPadding: 5, messageSize: 22)
                        Text(next.entry.name)
                                                        .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(shortDate(next))
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                        // Sans cette ligne, un message court le jour J laisse
                        // un grand vide au-dessus du bloc, tout collé en bas.
                        if let following = entry.occurrences.dropFirst().first {
                            followingLine(following, fontSize: 10, topPadding: 4)
                        }
                    }
                    .padding(textInsets)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
                .overlay(alignment: .topTrailing) { favoriteBadge(next, size: 9) }
            } else {
                emptyHomeState
            }
        }
        .widgetURL(nextURL ?? URL(string: "birthdays://add"))
    }

    /// Coin supérieur droit : le seul endroit qui reste libre quel que soit le
    /// format, la photo occupant la droite et le texte le bas.
    @ViewBuilder
    private func favoriteBadge(_ occurrence: BirthdayOccurrence, size: CGFloat) -> some View {
        if occurrence.entry.isFavorite {
            Image(systemName: "star.fill")
                .font(.system(size: size))
                .foregroundStyle(BirthdayTheme.Palette.hot)
                .padding(10)
                .accessibilityLabel("Favori")
        }
    }

    /// La carte horizontale reprend la carte vedette de l'app à l'identique.
    private var medium: some View {
        Group {
            if let next = entry.occurrences.first {
                ZStack(alignment: .bottomLeading) {
                    memoryLens(next, widthRatio: 0.70)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 4) {
                            Text(next.daysUntil == 0 ? "AUJOURD’HUI" : "PROCHAIN ANNIVERSAIRE")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(1)
                                .foregroundStyle(.white.opacity(0.74))
                        }
                        Spacer(minLength: 6)
                        countdownBlock(next, digitSize: 46, labelSize: 11, labelBottomPadding: 7, messageSize: 26)
                        Text(next.entry.name)
                                                        .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(shortDate(next))
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.66))
                            .lineLimit(1)
                        if let following = entry.occurrences.dropFirst().first {
                            followingLine(following, fontSize: 11, topPadding: 5)
                        }
                    }
                    .padding(textInsets)
                    .padding(.trailing, 90)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
                .overlay(alignment: .topTrailing) { favoriteBadge(next, size: 11) }
                .widgetURL(url(for: next))
            } else {
                emptyHomeState
            }
        }
    }

    /// La photo est cadrée à droite et fondue vers la gauche, pour que le texte
    /// reste sur une zone unie quelle que soit l'image.

    private var large: some View {
        Group {
            if let next = entry.occurrences.first {
                VStack(spacing: 0) {
                    ZStack(alignment: .bottomLeading) {
                        memoryLens(next, widthRatio: 0.66)
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 4) {
                                Text(next.daysUntil == 0 ? "AUJOURD’HUI" : "PROCHAIN ANNIVERSAIRE")
                                    .font(.system(size: 9, weight: .bold))
                                    .tracking(1)
                                    .foregroundStyle(.white.opacity(0.74))
                            }
                            Spacer(minLength: 6)
                            countdownBlock(next, digitSize: 50, labelSize: 12, labelBottomPadding: 8, messageSize: 30)
                            Text(next.entry.name)
                                .font(.system(size: 21, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Text(shortDate(next))
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.66))
                                .lineLimit(1)
                            if let following = entry.occurrences.dropFirst(2).first ?? entry.occurrences.dropFirst().first {
                                followingLine(following, fontSize: 12, topPadding: 6)
                            }
                        }
                        .padding(textInsets)
                        .padding(.trailing, 84)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    }
                    .overlay(alignment: .topTrailing) { favoriteBadge(next, size: 12) }
                    .frame(maxHeight: .infinity)

                    if entry.occurrences.count > 1 {
                        Divider().overlay(.white.opacity(0.14))
                        VStack(spacing: 10) {
                            ForEach(entry.occurrences.dropFirst().prefix(4)) { occurrence in
                                Link(destination: url(for: occurrence)) {
                                    compactRow(occurrence, showsDate: true)
                                }
                            }
                        }
                        .padding(.top, 11)
                        .padding(.horizontal, textInsets.leading)
                        .padding(.bottom, textInsets.bottom)
                    }
                }
            } else {
                emptyHomeState
            }
        }
    }

    /// « 0 jour J » n'a pas de sens : le jour même, un message remplace le
    /// compte à rebours à zéro, comme dans l'app.
    @ViewBuilder
    private func countdownBlock(
        _ next: BirthdayOccurrence,
        digitSize: CGFloat,
        labelSize: CGFloat,
        labelBottomPadding: CGFloat,
        messageSize: CGFloat
    ) -> some View {
        if next.daysUntil == 0 {
            // Le message tient sur deux lignes plutôt qu'une seule rétrécie à
            // l'extrême : un chiffre à 50pt laissait un vrai vide derrière lui,
            // qu'un texte minuscule sur une ligne n'aurait pas comblé.
            Text("Joyeux anniversaire ! 🎉")
                .font(.system(size: messageSize, weight: .black, design: .rounded))
                .foregroundStyle(BirthdayTheme.Palette.hot)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(alignment: .lastTextBaseline, spacing: 5) {
                Text("\(next.daysUntil)")
                    .font(.system(size: digitSize, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(next.daysUntil <= 7 ? BirthdayTheme.Palette.hot : .white)
                Text(next.daysUntil == 1 ? "jour" : "jours")
                    .font(.system(size: labelSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.66))
                    .padding(.bottom, labelBottomPadding)
            }
        }
    }

    /// Un aperçu compact du prochain anniversaire suivant, glissé sous la date :
    /// comble le vide qu'un message court laisse au-dessus, sans dépendre de la
    /// liste qui n'existe que dans le format large.
    private func followingLine(_ following: BirthdayOccurrence, fontSize: CGFloat, topPadding: CGFloat) -> some View {
        HStack(spacing: 4) {
            Text("puis")
                .font(.system(size: fontSize - 1))
                .opacity(0.55)
            Text(following.entry.name)
                .font(.system(size: fontSize, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(compactCountdown(following))
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .opacity(0.72)
        }
        .foregroundStyle(.white)
        .padding(.top, topPadding)
    }

    // MARK: Briques communes


    private func compactRow(_ occurrence: BirthdayOccurrence, showsDate: Bool = false) -> some View {
        HStack(spacing: 8) {
            WidgetAvatar(entry: occurrence.entry, size: showsDate ? 32 : 27)
            VStack(alignment: .leading, spacing: 0) {
                Text(occurrence.entry.name)
                    .appendingFavoriteStar(occurrence.entry.isFavorite, color: BirthdayTheme.Palette.hot, font: .system(size: 7))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if showsDate {
                    Text(shortDate(occurrence))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 2)
            Text(compactCountdown(occurrence))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(occurrence.daysUntil <= 7 ? BirthdayTheme.Palette.hot : .white.opacity(0.82))
        }
    }

    /// Photo en fond quand elle existe, dégradé de marque sinon. Le voile sombre
    /// garantit que le texte blanc reste lisible sur n'importe quelle image.

    @ViewBuilder
    private func photoImage(_ image: UIImage) -> some View {
        if #available(iOS 18.0, *) {
            // En mode teinté (iOS 18), une photo passée en couleur unie devient
            // une tache : la désaturation conserve le sujet reconnaissable.
            Image(uiImage: image)
                .resizable()
                .widgetAccentedRenderingMode(.accentedDesaturated)
                .scaledToFill()
        } else {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        }
    }

    private var emptyHomeState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "gift.fill")
                .font(.title3)
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            Text("Aucun anniversaire")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Touchez pour en ajouter un")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
    }

    @ViewBuilder
    private var widgetBackground: some View {
        if isLockScreen {
            Color.clear
        } else {
            // Le même dégradé que la carte de l'app : il suit la teinte choisie.
            BirthdayTheme.Palette.heroGradient
        }
    }

    /// Transposition de `BirthdayMemoryLensView` : la photo est cadrée à droite,
    /// fondue par un masque long, puis reliée au dégradé par un voile de la
    /// couleur d'accent. C'est ce voile qui évite l'effet « image collée ».
    @ViewBuilder
    private func memoryLens(_ occurrence: BirthdayOccurrence, widthRatio: CGFloat) -> some View {
        if occurrence.entry.avatarStyle == .photo,
           let data = occurrence.entry.photoData,
           let image = UIImage(data: data) {
            GeometryReader { proxy in
                let lensWidth = proxy.size.width * widthRatio
                let identityColor = Color(hexString: BirthdayAccent.currentHex)

                ZStack(alignment: .trailing) {
                    // Sans cette couche, le ZStack se réduit à la photo et
                    // celle-ci flotte au lieu de border le bord droit.
                    Color.clear

                    photoImage(image)
                        .frame(width: lensWidth, height: proxy.size.height)
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
            }
        }
    }

    // MARK: Textes

    private func url(for occurrence: BirthdayOccurrence) -> URL {
        URL(string: "birthdays://birthday/\(occurrence.entry.id.uuidString)")!
    }

    private var nextURL: URL? {
        entry.occurrences.first.flatMap { URL(string: "birthdays://birthday/\($0.entry.id.uuidString)") }
    }

    private func inlineText(_ occurrence: BirthdayOccurrence) -> String {
        occurrence.daysUntil == 0
            ? "\(occurrence.entry.name) aujourd’hui"
            : "\(occurrence.entry.name) · \(occurrence.daysUntil) j"
    }

    private func compactCountdown(_ occurrence: BirthdayOccurrence) -> String {
        occurrence.daysUntil == 0 ? "auj." : "\(occurrence.daysUntil) j"
    }

    private func detailLine(_ occurrence: BirthdayOccurrence) -> String {
        var value = occurrence.date.formatted(
            Date.FormatStyle().weekday(.abbreviated).day().month(.abbreviated)
                .locale(Locale(identifier: "fr_CH"))
        )
        if let age = occurrence.turningAge { value += " · \(age) ans" }
        return value
    }

    private func shortDate(_ occurrence: BirthdayOccurrence) -> String {
        var value = occurrence.date.formatted(
            Date.FormatStyle().day().month(.abbreviated).locale(Locale(identifier: "fr_CH"))
        )
        if let age = occurrence.turningAge { value += " · \(age) ans" }
        return value
    }

    private func circularProgress(_ occurrence: BirthdayOccurrence) -> Double {
        let remaining = min(max(occurrence.daysUntil, 0), 30)
        return Double(30 - remaining) / 30
    }

    private var circularAccessibilityLabel: String {
        guard let next = entry.occurrences.first else { return "Aucun anniversaire à venir" }
        return next.daysUntil == 0
            ? "Anniversaire de \(next.entry.name) aujourd’hui"
            : "Anniversaire de \(next.entry.name) dans \(next.daysUntil) jours"
    }

    private var rectangularAccessibilityLabel: String {
        guard let next = entry.occurrences.first else { return "Ajouter un anniversaire" }
        let base = next.daysUntil == 0
            ? "\(next.entry.name) aujourd’hui"
            : "\(next.entry.name) dans \(next.daysUntil) jours"
        guard let following = entry.occurrences.dropFirst().first else { return base }
        return "\(base), puis \(following.entry.name) dans \(following.daysUntil) jours"
    }
}

struct BirthdaysWidget: Widget {
    let kind = "BirthdaysUpcoming"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BirthdaysTimelineProvider()) { entry in
            BirthdaysWidgetView(entry: entry)
        }
        .configurationDisplayName("Prochains anniversaires")
        .description("Le prochain anniversaire sur l’écran d’accueil ou l’écran verrouillé.")
        // Sans cela, le décor s'arrête à la marge de contenu alors que le fond
        // occupe tout le widget : la bordure laisse voir le dégradé nu, sans le
        // voile de couleur, et une rupture de ton apparaît sur les bords.
        .contentMarginsDisabled()
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}

@main
struct BirthdaysWidgetBundle: WidgetBundle {
    var body: some Widget { BirthdaysWidget() }
}
