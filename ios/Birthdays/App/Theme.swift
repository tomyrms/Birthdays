import SwiftUI
import UIKit

enum BirthdayTheme {
    enum Palette {
        static let background = Color.dynamic(light: 0xF6F4F1, dark: 0x09090C)
        static let surface = Color.dynamic(light: 0xFFFEFC, dark: 0x151519)
        static let elevated = Color.dynamic(light: 0xEEEBF2, dark: 0x222228)
        static let text = Color.dynamic(light: 0x151319, dark: 0xF8F6FA)
        static let secondaryText = Color.dynamic(light: 0x75717D, dark: 0xAAA5B1)
        static let line = Color.dynamic(light: 0xE2DEE6, dark: 0x2E2D35)
        static var accent: Color {
            BirthdayAccent.color(for: BirthdayAccent.currentHex)
        }
        static let hot = Color.dynamic(light: 0xF06467, dark: 0xFF7C7F)
        static let destructive = Color.dynamic(light: 0xD84848, dark: 0xFF7575)

        static var signatureGradient: LinearGradient {
            BirthdayAccent.signatureGradient(for: BirthdayAccent.currentHex)
        }

        static var actionGradient: LinearGradient {
            BirthdayAccent.actionGradient(for: BirthdayAccent.currentHex)
        }

        static var heroGradient: LinearGradient {
            BirthdayAccent.heroGradient(for: BirthdayAccent.currentHex)
        }
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Radius {
        static let control: CGFloat = 14
        static let card: CGFloat = 20
        static let hero: CGFloat = 28
    }
}

enum BirthdayAccent {
    struct Preset: Identifiable {
        let title: String
        let hex: String

        var id: String { hex }
    }

    static let storageKey = "birthdays.appearance.accentHex"
    static let defaultHex = "654CFF"
    static let presets: [Preset] = [
        Preset(title: "Violet", hex: "654CFF"),
        Preset(title: "Bleu", hex: "1677D2"),
        Preset(title: "Menthe", hex: "168276"),
        Preset(title: "Rose", hex: "C84778"),
        Preset(title: "Ambre", hex: "C66A28"),
        Preset(title: "Graphite", hex: "586273"),
        Preset(title: "Turquoise", hex: "0E8C9B"),
        Preset(title: "Prune", hex: "8B4A9C"),
        Preset(title: "Forêt", hex: "3F7A46"),
        Preset(title: "Corail", hex: "D9594C"),
        Preset(title: "Océan", hex: "1D5C86"),
        Preset(title: "Lilas", hex: "8E7BD1"),
        Preset(title: "Sable", hex: "A8834E")
    ]

    private static var sharedHexCache: String?

    static var currentHex: String {
        // Dans l'app, UserDefaults fait foi. Dans l'extension widget il est
        // vide : la teinte vient alors du trousseau partagé, lue une seule fois
        // car un accès trousseau par couleur serait bien trop coûteux.
        if let local = UserDefaults.standard.string(forKey: storageKey) {
            return sanitized(local)
        }
        if let cached = sharedHexCache { return cached }
        let resolved = sanitized(SharedBirthdayStorage.readAccentHex() ?? defaultHex)
        sharedHexCache = resolved
        return resolved
    }

    /// À appeler avant de composer une vue de widget : le processus d'extension
    /// peut survivre à un changement de teinte et resservir l'ancienne.
    static func invalidateSharedCache() {
        sharedHexCache = nil
    }

    /// Publie la teinte pour le widget et invalide le cache local.
    static func publishToSharedStorage(_ hex: String) {
        let cleaned = sanitized(hex)
        sharedHexCache = cleaned
        SharedBirthdayStorage.writeAccentHex(cleaned)
    }

    static func sanitized(_ value: String) -> String {
        let cleaned = value.replacingOccurrences(of: "#", with: "").uppercased()
        guard cleaned.count == 6, cleaned.allSatisfy({ $0.isHexDigit }) else {
            return defaultHex
        }
        return cleaned
    }

    static func color(for hex: String) -> Color {
        let base = uiColor(for: hex)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? base.adjusted(saturation: 0.94, minimumBrightness: 0.68)
                : base
        })
    }

    static func variant(
        for hex: String = currentHex,
        saturation: CGFloat = 1,
        brightness: CGFloat = 1,
        minimumBrightness: CGFloat = 0
    ) -> Color {
        Color(uiColor: uiColor(for: hex).adjusted(
            saturation: saturation,
            brightness: brightness,
            minimumBrightness: minimumBrightness
        ))
    }

    static func signatureGradient(for hex: String) -> LinearGradient {
        let base = uiColor(for: hex)
        return LinearGradient(
            colors: [
                Color(uiColor: base.adjusted(brightness: 0.88)),
                Color(uiColor: base.adjusted(saturation: 0.78, minimumBrightness: 0.82)),
                BirthdayTheme.Palette.hot
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func actionGradient(for hex: String) -> LinearGradient {
        let base = uiColor(for: hex)
        return LinearGradient(
            colors: [
                Color(uiColor: base.adjusted(brightness: 0.88)),
                Color(uiColor: base.adjusted(saturation: 0.80, minimumBrightness: 0.80))
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func heroGradient(for hex: String) -> LinearGradient {
        let base = uiColor(for: hex)
        return LinearGradient(
            colors: [
                Color(uiColor: base.adjusted(saturation: 0.92, brightness: 0.86, minimumBrightness: 0.48)),
                Color(uiColor: base.adjusted(saturation: 0.54, brightness: 0.46, minimumBrightness: 0.25)),
                Color(hexString: "1D1C22")
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private static func uiColor(for hex: String) -> UIColor {
        UIColor(hex: UInt(sanitized(hex), radix: 16) ?? 0x654CFF)
    }
}

enum BirthdayBackgroundStyle: String, CaseIterable, Identifiable {
    case pastelMesh
    case watermark
    case floatingCards
    case confetti
    case livingMesh
    case orbit
    case halo
    case satin
    case silk
    case auroraFlow
    case nebula
    case iridescence
    case chrome
    case threads
    case swirl
    case rays
    case waves
    case grain
    case ripple
    case bokeh
    case burst
    case marble
    case neon
    case dust
    case spiral
    case caustics
    case dotGrid
    case boreal
    case lightning
    case grainient
    case rippleGrid
    case tinted

    static let storageKey = "birthdays.appearance.background"
    static let selectableStyles: [Self] = [
        .silk, .auroraFlow, .chrome,
        .swirl, .waves, .ripple,
        .bokeh, .neon, .dust,
        .spiral, .lightning, .watermark,
        .floatingCards, .confetti
    ]

    /// Les fonds calculés par la carte graphique sortent du dessin sur
    /// processeur : ils ont leur propre vue de rendu.
    var shaderKind: BirthdayShaderBackground.Kind? {
        switch self {
        case .silk: .silk
        case .auroraFlow: .aurora
        case .nebula: .nebula
        case .iridescence: .iridescence
        case .chrome: .chrome
        case .threads: .threads
        case .swirl: .swirl
        case .rays: .rays
        case .waves: .waves
        case .grain: .grain
        case .ripple: .ripple
        case .bokeh: .bokeh
        case .burst: .burst
        case .marble: .marble
        case .neon: .neon
        case .dust: .dust
        case .spiral: .spiral
        case .caustics: .caustics
        case .dotGrid: .dotGrid
        case .boreal: .boreal
        case .lightning: .lightning
        case .grainient: .grainient
        case .rippleGrid: .rippleGrid
        default: nil
        }
    }

    static func resolved(from rawValue: String) -> Self {
        guard let style = Self(rawValue: rawValue), selectableStyles.contains(style) else {
            return .watermark
        }
        return style
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pastelMesh: "Pastel"
        case .watermark: "Célébration"
        case .floatingCards: "Essentiel"
        case .confetti: "Confettis"
        case .livingMesh: "Nuage"
        case .orbit: "Orbites"
        case .halo: "Halo"
        case .satin: "Satin"
        case .silk: "Soie"
        case .auroraFlow: "Aurore"
        case .nebula: "Nébuleuse"
        case .iridescence: "Nacre"
        case .chrome: "Mercure"
        case .threads: "Fils"
        case .swirl: "Tourbillon"
        case .rays: "Rayons"
        case .waves: "Vagues"
        case .grain: "Grain"
        case .ripple: "Ondes"
        case .bokeh: "Bokeh"
        case .burst: "Éclats"
        case .marble: "Marbre"
        case .neon: "Néon"
        case .dust: "Poussière"
        case .spiral: "Spirale"
        case .caustics: "Caustiques"
        case .dotGrid: "Trame"
        case .boreal: "Boréale"
        case .lightning: "Foudre"
        case .grainient: "Grainé"
        case .rippleGrid: "Grille"
        case .tinted: "Uni"
        }
    }

    var subtitle: String {
        switch self {
        case .pastelMesh: "Pêche, ciel et lavande"
        case .watermark: "Motifs en filigrane"
        case .floatingCards: "Cartes sur fond neutre"
        case .confetti: "Chute lente et légère"
        case .livingMesh: "Maillage en mouvement"
        case .orbit: "Anneaux de verre"
        case .halo: "Maillage lumineux"
        case .satin: "Rubans liquides"
        case .silk: "Tissu qui ondule"
        case .auroraFlow: "Voiles de lumière"
        case .nebula: "Volutes colorées"
        case .iridescence: "Reflets irisés"
        case .chrome: "Métal liquide"
        case .threads: "Brins de lumière"
        case .swirl: "Matière enroulée"
        case .rays: "Faisceaux obliques"
        case .waves: "Houle lente"
        case .grain: "Dégradé matiéré"
        case .ripple: "Cercles concentriques"
        case .bokeh: "Halos hors foyer"
        case .burst: "Gerbes de lumière"
        case .marble: "Veines de pierre"
        case .neon: "Tubes lumineux"
        case .dust: "Éclats scintillants"
        case .spiral: "Bras qui s’enroulent"
        case .caustics: "Reflets d’eau"
        case .dotGrid: "Points en onde"
        case .boreal: "Voile polaire"
        case .lightning: "Décharge lente"
        case .grainient: "Dégradé texturé"
        case .rippleGrid: "Onde sur trame"
        case .tinted: "Un soupçon de votre couleur"
        }
    }

    var category: BirthdayBackgroundCategory {
        switch self {
        case .silk, .auroraFlow, .nebula, .iridescence, .chrome, .threads, .swirl, .rays, .waves, .grain, .ripple,
             .bokeh, .burst, .marble, .neon, .dust, .spiral, .caustics, .dotGrid, .boreal, .lightning, .grainient, .rippleGrid: .signatureStyles
        case .tinted, .watermark, .floatingCards: .staticStyles
        case .confetti, .halo, .satin, .orbit: .animatedStyles
        // Legacy values remain decodable only so existing installations can
        // migrate cleanly to a supported style. They are no longer exposed in settings.
        case .pastelMesh, .livingMesh: .staticStyles
        }
    }

    var usesAnimation: Bool {
        switch self {
        case .tinted, .watermark, .floatingCards, .pastelMesh: false
        case .confetti, .halo, .satin, .orbit, .livingMesh: true
        case .silk, .auroraFlow, .nebula, .iridescence, .chrome, .threads, .swirl, .rays, .waves, .grain, .ripple,
             .bokeh, .burst, .marble, .neon, .dust, .spiral, .caustics, .dotGrid, .boreal, .lightning, .grainient, .rippleGrid: true
        }
    }
}

enum BirthdayBackgroundCategory: String, CaseIterable, Identifiable {
    case signatureStyles
    case staticStyles
    case animatedStyles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .signatureStyles: "TEXTURES VIVANTES"
        case .staticStyles: "FONDS STATIQUES"
        case .animatedStyles: "FONDS ANIMÉS"
        }
    }

    var subtitle: String {
        switch self {
        case .signatureStyles: "Dessinés par la carte graphique, en mouvement continu."
        case .staticStyles: "Simples, lisibles et sans mouvement."
        case .animatedStyles: "Des mouvements très lents, sans raccord visible."
        }
    }
}

/// Présentation des listes. Cet effet n'existait qu'attaché au fond
/// « Essentiel » : le choisir imposait ce fond, et inversement. Il devient un
/// réglage à part, valable avec n'importe quelle texture.
enum BirthdayCardStyle {
    static let storageKey = "birthdays.appearance.floatingCards"
}

enum BirthdayBackgroundContext {
    static let seasonalTintKey = "birthdays.appearance.seasonalTint"
}

extension Color {
    init(hexString: String) {
        let cleaned = hexString.replacingOccurrences(of: "#", with: "")
        let value = UInt(cleaned, radix: 16) ?? 0x5753E8
        self.init(uiColor: UIColor(hex: value))
    }

    static func dynamic(light: UInt, dark: UInt) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    func adjusted(
        saturation saturationMultiplier: CGFloat = 1,
        brightness brightnessMultiplier: CGFloat = 1,
        minimumBrightness: CGFloat = 0
    ) -> UIColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return self
        }
        return UIColor(
            hue: hue,
            saturation: min(max(saturation * saturationMultiplier, 0), 1),
            brightness: min(max(brightness * brightnessMultiplier, minimumBrightness), 1),
            alpha: alpha
        )
    }
}

extension Text {
    /// Enchaîne l'étoile à la suite du texte au lieu de la poser à côté. Dans
    /// une colonne voisine, elle s'aligne sur la première ligne et se retrouve
    /// à flotter au milieu dès que le nom passe sur deux lignes.
    func appendingFavoriteStar(_ isFavorite: Bool, color: Color, font: Font = .caption2) -> Text {
        guard isFavorite else { return self }
        // Taille fixée explicitement : par défaut le symbole adopte celle du
        // texte qui l'accueille, ce qui le rendait énorme dans les titres.
        return self + Text(" ") + Text(Image(systemName: "star.fill"))
            .font(font)
            .foregroundStyle(color)
    }
}

extension Font {
    static let birthdayTitle = Font.system(.largeTitle, design: .rounded).weight(.black)
    static let birthdaySection = Font.system(.caption2, design: .default).weight(.bold)
    static let birthdayName = Font.system(.headline, design: .default).weight(.semibold)
    static let birthdayBody = Font.system(.body, design: .default)
    static let birthdayMeta = Font.system(.subheadline, design: .default)
    static let birthdayCountdown = Font.system(.title2, design: .rounded).weight(.semibold)
    static let birthdayDisplay = Font.system(size: 58, weight: .black, design: .rounded)
}

extension View {
    func birthdayScreenBackground(isAnimated: Bool = false) -> some View {
        background(BirthdayAppBackground(isAnimated: isAnimated).ignoresSafeArea())
    }
}

struct BirthdayAppBackground: View {
    var isAnimated = false

    @AppStorage(BirthdayBackgroundStyle.storageKey) private var selectedStyle = BirthdayBackgroundStyle.pastelMesh.rawValue
    @AppStorage(BirthdayBackgroundContext.seasonalTintKey) private var seasonalTintEnabled = true

    var body: some View {
        ZStack {
            BirthdayBackgroundArtwork(
                style: currentStyle,
                isAnimated: isAnimated,
                showsSeasonalContext: seasonalTintEnabled
            )
                .id(currentStyle)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.45), value: selectedStyle)
        .onAppear {
            let resolvedStyle = BirthdayBackgroundStyle.resolved(from: selectedStyle)
            if selectedStyle != resolvedStyle.rawValue {
                selectedStyle = resolvedStyle.rawValue
            }
        }
    }

    private var currentStyle: BirthdayBackgroundStyle {
        BirthdayBackgroundStyle.resolved(from: selectedStyle)
    }
}

struct BirthdayBackgroundArtwork: View {
    let style: BirthdayBackgroundStyle
    var isAnimated = true
    var showsSeasonalContext = true

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @ViewBuilder
    var body: some View {
        if let kind = style.shaderKind {
            BirthdayShaderBackground(kind: kind, isAnimated: isAnimated)
        } else {
            canvasBody
        }
    }

    @ViewBuilder
    private var canvasBody: some View {
        GeometryReader { proxy in
            ZStack {
                baseColor
                if runsTimeline {
                    TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                        dynamicLayers(in: proxy.size, phase: animationPhase(at: timeline.date))
                    }
                } else {
                    dynamicLayers(in: proxy.size, phase: 0)
                }
                // Ces deux couches sont immobiles : les sortir de la timeline
                // évite de les redessiner plusieurs fois par seconde.
                grain
                edgeVignette
            }
            .clipped()
        }
        .accessibilityHidden(true)
    }

    private func dynamicLayers(in size: CGSize, phase: CGFloat) -> some View {
        ZStack {
            artwork(in: size, phase: phase)
                .opacity(artworkOpacity)
            contextualAtmosphere(in: size, phase: phase)
                .opacity(colorScheme == .dark ? 1 : 0.88)
        }
    }

    @ViewBuilder
    private func artwork(in size: CGSize, phase: CGFloat) -> some View {
        switch style {
        // Ces styles sont rendus par le shader, jamais par ce dessin.
        case .silk, .auroraFlow, .nebula, .iridescence, .chrome, .threads, .swirl, .rays, .waves, .grain, .ripple,
             .bokeh, .burst, .marble, .neon, .dust, .spiral, .caustics, .dotGrid, .boreal, .lightning, .grainient, .rippleGrid:
            EmptyView()
        case .tinted:
            // Deux voiles très légers de la couleur d'accent : un aplat pur
            // paraîtrait plat, alors qu'un dégradé à peine perceptible donne
            // de la profondeur sans jamais concurrencer le contenu.
            ZStack {
                LinearGradient(
                    colors: [
                        BirthdayAccent.variant(saturation: 0.85, brightness: 1, minimumBrightness: 0.5)
                            .opacity(colorScheme == .dark ? 0.16 : 0.13),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottom
                )
                RadialGradient(
                    colors: [
                        BirthdayAccent.variant(saturation: 0.7, brightness: 1, minimumBrightness: 0.6)
                            .opacity(colorScheme == .dark ? 0.12 : 0.10),
                        .clear
                    ],
                    center: UnitPoint(x: 0.85, y: 0.9),
                    startRadius: 0,
                    endRadius: max(size.width, size.height) * 0.8
                )
            }

        case .pastelMesh:
            ZStack {
                RadialGradient(
                    colors: [brandPale.opacity(0.72), brandPale.opacity(0.08), .clear],
                    center: UnitPoint(x: 0.08, y: 0.08),
                    startRadius: 0,
                    endRadius: max(size.width, size.height) * 0.78
                )
                RadialGradient(
                    colors: [brandSoft.opacity(0.60), brandSoft.opacity(0.06), .clear],
                    center: UnitPoint(x: 0.94, y: 0.36),
                    startRadius: 0,
                    endRadius: max(size.width, size.height) * 0.72
                )
                RadialGradient(
                    colors: [brand.opacity(0.46), .clear],
                    center: UnitPoint(x: 0.34, y: 0.96),
                    startRadius: 0,
                    endRadius: max(size.width, size.height) * 0.66
                )
                Canvas { context, canvasSize in
                    for index in 0..<7 {
                        context.stroke(
                            meshLine(in: canvasSize, index: index, phase: 0),
                            with: .color(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.18)),
                            lineWidth: 0.7
                        )
                    }
                }
            }

        case .watermark:
            Canvas { context, canvasSize in
                let spacing = CGSize(width: 112, height: 126)
                let columns = Int(canvasSize.width / spacing.width) + 2
                let rows = Int(canvasSize.height / spacing.height) + 2
                for row in 0..<rows {
                    for column in 0..<columns {
                        let index = row * columns + column
                        let center = CGPoint(
                            x: CGFloat(column) * spacing.width + (row.isMultiple(of: 2) ? 18 : 72),
                            y: CGFloat(row) * spacing.height + 28
                        )
                        context.stroke(
                            watermarkPath(center: center, motif: index % 3),
                            with: .color(watermarkInk),
                            lineWidth: 1.05
                        )
                    }
                }
            }

        case .floatingCards:
            ZStack {
                RadialGradient(
                    colors: [violet.opacity(0.055), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: max(size.width, size.height) * 0.70
                )
                Canvas { context, canvasSize in
                    for index in 0..<42 {
                        let x = CGFloat((index * 61 + 17) % 137) / 137 * canvasSize.width
                        let y = CGFloat((index * index * 31 + 9) % 163) / 163 * canvasSize.height
                        context.fill(
                            Path(ellipseIn: CGRect(x: x, y: y, width: 1.2, height: 1.2)),
                            with: .color(BirthdayTheme.Palette.secondaryText.opacity(0.055))
                        )
                    }
                }
            }

        case .confetti:
            Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: true) { context, canvasSize in
                let cycle = normalizedCycle(phase)
                let travel = canvasSize.height + 72
                let colors = [
                    brand, brandSoft, BirthdayTheme.Palette.hot, brandPale
                ]
                for index in 0..<20 {
                    // Multiples entiers du cycle : la boucle reste sans raccord
                    // tout en donnant une chute visible (20 s et 15 s).
                    let speed = CGFloat(index.isMultiple(of: 2) ? 6 : 8)
                    let offset = CGFloat((index * 37) % 101) / 101
                    let progress = (cycle * speed + offset).truncatingRemainder(dividingBy: 1)
                    let baseX = CGFloat((index * 71 + 23) % 149) / 149 * canvasSize.width
                    let sway = wave(phase * CGFloat(1 + index % 3) + CGFloat(index) * 0.73) * 13
                    let y = -36 + progress * travel
                    let width: CGFloat = index.isMultiple(of: 3) ? 8 : 4
                    let height: CGFloat = index.isMultiple(of: 3) ? 2.4 : 7
                    let rect = CGRect(x: baseX + sway - width / 2, y: y - height / 2, width: width, height: height)
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: min(width, height) / 2),
                        with: .color(colors[index % colors.count].opacity(colorScheme == .dark ? 0.22 : 0.18))
                    )
                }
            }

        case .livingMesh:
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [brandPale.opacity(0.66), .clear], center: .center, startRadius: 0, endRadius: size.width * 0.58))
                    .frame(width: size.width * 1.16, height: size.width * 1.16)
                    .offset(x: -size.width * (0.34 + wave(phase) * 0.08), y: -size.height * 0.26)
                Circle()
                    .fill(RadialGradient(colors: [brandSoft.opacity(0.62), .clear], center: .center, startRadius: 0, endRadius: size.width * 0.64))
                    .frame(width: size.width * 1.28, height: size.width * 1.28)
                    .offset(x: size.width * (0.40 + cosine(phase) * 0.09), y: size.height * (0.02 + wave(phase) * 0.05))
                Circle()
                    .fill(RadialGradient(colors: [brand.opacity(0.58), .clear], center: .center, startRadius: 0, endRadius: size.width * 0.58))
                    .frame(width: size.width * 1.12, height: size.width * 1.12)
                    .offset(x: -size.width * (0.08 + cosine(phase) * 0.07), y: size.height * (0.42 + wave(phase) * 0.06))
                Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: true) { context, canvasSize in
                    for index in 0..<8 {
                        context.stroke(
                            meshLine(in: canvasSize, index: index, phase: phase),
                            with: .color(lavender.opacity(0.13)),
                            lineWidth: 0.65
                        )
                    }
                }
            }

        case .orbit:
            Canvas { context, canvasSize in
                let base = min(canvasSize.width, canvasSize.height)
                let primaryCenter = CGPoint(x: canvasSize.width * 0.92, y: canvasSize.height * 0.27)
                let secondaryCenter = CGPoint(x: canvasSize.width * 0.04, y: canvasSize.height * 0.86)

                context.drawLayer { glow in
                    glow.addFilter(.blur(radius: 13))
                    for index in 0..<7 {
                        let width = base * (0.48 + CGFloat(index) * 0.31)
                        let height = width * (1.08 + CGFloat(index) * 0.025)
                        let rect = CGRect(
                            x: primaryCenter.x - width / 2,
                            y: primaryCenter.y - height / 2,
                            width: width,
                            height: height
                        )
                        glow.stroke(
                            Path(ellipseIn: rect),
                            with: .color(violet.opacity(index.isMultiple(of: 3) ? 0.20 : 0.07)),
                            lineWidth: index.isMultiple(of: 3) ? 5 : 1
                        )
                    }
                }

                for index in 0..<7 {
                    let width = base * (0.48 + CGFloat(index) * 0.31)
                    let height = width * (1.08 + CGFloat(index) * 0.025)
                    let rect = CGRect(
                        x: primaryCenter.x - width / 2,
                        y: primaryCenter.y - height / 2,
                        width: width,
                        height: height
                    )
                    context.stroke(
                        Path(ellipseIn: rect),
                        with: .color(index.isMultiple(of: 3) ? lavender.opacity(0.24) : violet.opacity(0.13)),
                        lineWidth: index.isMultiple(of: 3) ? 1.25 : 0.7
                    )
                }

                for index in 0..<4 {
                    let width = base * (0.72 + CGFloat(index) * 0.36)
                    let rect = CGRect(
                        x: secondaryCenter.x - width / 2,
                        y: secondaryCenter.y - width * 0.38,
                        width: width,
                        height: width * 0.76
                    )
                    context.stroke(
                        Path(ellipseIn: rect),
                        with: .color(violet.opacity(index == 1 ? 0.15 : 0.065)),
                        lineWidth: index == 1 ? 1.1 : 0.6
                    )
                }

                for index in 0..<5 {
                    let orbitWidth = base * (0.48 + CGFloat(index) * 0.31)
                    let orbitHeight = orbitWidth * (1.08 + CGFloat(index) * 0.025)
                    let direction: CGFloat = index.isMultiple(of: 2) ? 1 : -1
                    let angle = phase * direction + CGFloat(index) * 1.19
                    let point = CGPoint(
                        x: primaryCenter.x + cosine(angle) * orbitWidth / 2,
                        y: primaryCenter.y + wave(angle) * orbitHeight / 2
                    )
                    let radius: CGFloat = index == 1 ? 3.7 : 2.1
                    context.fill(
                        Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                        with: .color(index == 1 ? coral.opacity(0.88) : lavender.opacity(0.46))
                    )
                }
            }

        case .halo:
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [violet.opacity(0.68), plum.opacity(0.18), .clear], center: .center, startRadius: 0, endRadius: size.width * 0.62))
                    .frame(width: size.width * 1.18, height: size.width * 1.18)
                    .blur(radius: 38)
                    .offset(x: -size.width * (0.42 + wave(phase) * 0.07), y: -size.height * 0.28)
                    .blendMode(.plusLighter)
                Circle()
                    .fill(RadialGradient(colors: [indigo.opacity(0.62), violet.opacity(0.18), .clear], center: .center, startRadius: 0, endRadius: size.width * 0.72))
                    .frame(width: size.width * 1.38, height: size.width * 1.38)
                    .blur(radius: 48)
                    .offset(x: size.width * (0.48 + cosine(phase + 0.82) * 0.06), y: size.height * 0.06)
                    .blendMode(.plusLighter)
                Circle()
                    .fill(RadialGradient(colors: [coral.opacity(0.42), plum.opacity(0.12), .clear], center: .center, startRadius: 0, endRadius: size.width * 0.52))
                    .frame(width: size.width, height: size.width)
                    .blur(radius: 44)
                    .offset(x: size.width * 0.42, y: size.height * (0.44 + wave(phase + 1.74) * 0.05))
                    .blendMode(.plusLighter)
                Canvas { context, canvasSize in
                    for index in 0..<8 {
                        let path = auroraVein(in: canvasSize, index: index, phase: phase)
                        context.stroke(
                            path,
                            with: .linearGradient(
                                Gradient(colors: [.clear, lavender.opacity(0.24), violet.opacity(0.10), .clear]),
                                startPoint: CGPoint(x: 0, y: 0),
                                endPoint: CGPoint(x: canvasSize.width, y: canvasSize.height)
                            ),
                            lineWidth: 0.7 + CGFloat(index % 3) * 0.35
                        )
                    }
                }
                Ellipse()
                    .fill(BirthdayTheme.Palette.background.opacity(0.54))
                    .frame(width: size.width * 0.68, height: size.height * 0.74)
                    .blur(radius: 72)
            }

        case .satin:
            Canvas { context, canvasSize in
                context.drawLayer { glow in
                    glow.addFilter(.blur(radius: 22))
                    for index in 0..<7 {
                        glow.stroke(
                            satinPath(in: canvasSize, index: index, phase: phase),
                            with: .linearGradient(
                                Gradient(colors: [violet.opacity(0.03), violet.opacity(0.30), coral.opacity(0.10), .clear]),
                                startPoint: CGPoint(x: 0, y: 0),
                                endPoint: CGPoint(x: canvasSize.width, y: canvasSize.height)
                            ),
                            lineWidth: 18 + CGFloat(index) * 7
                        )
                    }
                }
                for index in 0..<7 {
                    context.stroke(
                        satinPath(in: canvasSize, index: index, phase: phase),
                        with: .linearGradient(
                            Gradient(colors: [.clear, lavender.opacity(0.24), violet.opacity(0.16), coral.opacity(index == 4 ? 0.18 : 0.04), .clear]),
                            startPoint: CGPoint(x: canvasSize.width, y: 0),
                            endPoint: CGPoint(x: 0, y: canvasSize.height)
                        ),
                        lineWidth: 1.1 + CGFloat(index % 3) * 0.55
                    )
                }
            }
        }
    }

    private var grain: some View {
        Canvas { context, size in
            for index in 0..<120 {
                let x = CGFloat((index * 47 + 19) % 127) / 127 * size.width
                let y = CGFloat((index * index * 29 + 11) % 149) / 149 * size.height
                let alpha = 0.012 + CGFloat(index % 5) * 0.004
                context.fill(
                    Path(CGRect(x: x, y: y, width: index.isMultiple(of: 7) ? 1.2 : 0.7, height: index.isMultiple(of: 7) ? 1.2 : 0.7)),
                    with: .color(.white.opacity(colorScheme == .dark ? alpha : alpha * 0.45))
                )
            }
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    private var edgeVignette: some View {
        RadialGradient(
            colors: [.clear, BirthdayTheme.Palette.background.opacity(colorScheme == .dark ? 0.34 : 0.12)],
            center: .center,
            startRadius: 80,
            endRadius: 680
        )
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func contextualAtmosphere(in size: CGSize, phase: CGFloat) -> some View {
        if showsSeasonalContext {
            RadialGradient(
                colors: [seasonalAccent.opacity(0.10), seasonalAccent.opacity(0.025), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: max(size.width, size.height) * 0.88
            )
            .blendMode(.plusLighter)
        }

    }


    private func meshLine(in size: CGSize, index: Int, phase: CGFloat) -> Path {
        var path = Path()
        let offset = CGFloat(index) * size.height * 0.13
        path.move(to: CGPoint(x: -size.width * 0.12, y: offset - size.height * 0.05))
        path.addCurve(
            to: CGPoint(x: size.width * 1.12, y: offset + size.height * 0.19),
            control1: CGPoint(
                x: size.width * (0.22 + wave(phase + CGFloat(index) * 0.41) * 0.05),
                y: offset + size.height * 0.12
            ),
            control2: CGPoint(
                x: size.width * (0.72 + cosine(phase + CGFloat(index) * 0.53) * 0.05),
                y: offset - size.height * 0.02
            )
        )
        return path
    }

    private func watermarkPath(center: CGPoint, motif: Int) -> Path {
        var path = Path()
        switch motif {
        case 0:
            path.addEllipse(in: CGRect(x: center.x - 11, y: center.y - 18, width: 22, height: 29))
            path.move(to: CGPoint(x: center.x, y: center.y + 11))
            path.addCurve(
                to: CGPoint(x: center.x + 5, y: center.y + 31),
                control1: CGPoint(x: center.x - 5, y: center.y + 18),
                control2: CGPoint(x: center.x + 8, y: center.y + 21)
            )
        case 1:
            path.addRect(CGRect(x: center.x - 17, y: center.y - 11, width: 34, height: 27))
            path.move(to: CGPoint(x: center.x, y: center.y - 11))
            path.addLine(to: CGPoint(x: center.x, y: center.y + 16))
            path.move(to: CGPoint(x: center.x - 17, y: center.y - 1))
            path.addLine(to: CGPoint(x: center.x + 17, y: center.y - 1))
            path.addEllipse(in: CGRect(x: center.x - 11, y: center.y - 18, width: 11, height: 9))
            path.addEllipse(in: CGRect(x: center.x, y: center.y - 18, width: 11, height: 9))
        default:
            path.addRect(CGRect(x: center.x - 18, y: center.y - 3, width: 36, height: 19))
            path.move(to: CGPoint(x: center.x - 11, y: center.y - 3))
            path.addLine(to: CGPoint(x: center.x - 11, y: center.y - 16))
            path.move(to: CGPoint(x: center.x, y: center.y - 3))
            path.addLine(to: CGPoint(x: center.x, y: center.y - 20))
            path.move(to: CGPoint(x: center.x + 11, y: center.y - 3))
            path.addLine(to: CGPoint(x: center.x + 11, y: center.y - 16))
        }
        return path
    }


    private func auroraVein(in size: CGSize, index: Int, phase: CGFloat) -> Path {
        var path = Path()
        let inset = CGFloat(index) * size.width * 0.055
        path.move(to: CGPoint(x: -size.width * 0.18 + inset, y: size.height * (0.16 + wave(phase + CGFloat(index) * 0.63) * 0.025)))
        path.addCurve(
            to: CGPoint(x: size.width * 1.16 - inset * 0.35, y: size.height * (0.82 - CGFloat(index) * 0.035)),
            control1: CGPoint(x: size.width * (0.26 + wave(phase + 0.92) * 0.06), y: size.height * (0.32 + CGFloat(index) * 0.025)),
            control2: CGPoint(x: size.width * (0.58 + cosine(phase + CGFloat(index) * 0.47) * 0.05), y: size.height * (0.66 - CGFloat(index) * 0.02))
        )
        return path
    }



    private func satinPath(in size: CGSize, index: Int, phase: CGFloat) -> Path {
        var path = Path()
        let drift = wave(phase + CGFloat(index) * 0.7) * size.width * 0.06
        path.move(to: CGPoint(x: -size.width * 0.24 + CGFloat(index) * size.width * 0.10, y: -size.height * 0.08))
        path.addCurve(
            to: CGPoint(x: size.width * (0.76 + CGFloat(index) * 0.055) + drift, y: size.height * 1.10),
            control1: CGPoint(x: size.width * (0.72 + CGFloat(index) * 0.03) + drift, y: size.height * 0.21),
            control2: CGPoint(x: -size.width * (0.08 - CGFloat(index) * 0.035) - drift, y: size.height * 0.68)
        )
        return path
    }

    private func animationPhase(at date: Date) -> CGFloat {
        guard shouldAnimate, !reduceMotion else { return 0 }
        // Every animated value is derived from this closed 0...2π phase using
        // whole-number cycles. Values therefore match exactly at both ends.
        let duration: TimeInterval = 120
        let cycle = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: duration)
        return CGFloat(cycle / duration) * .pi * 2
    }

    private func wave(_ value: CGFloat) -> CGFloat { CGFloat(sin(Double(value))) }
    private func cosine(_ value: CGFloat) -> CGFloat { CGFloat(cos(Double(value))) }

    private func normalizedCycle(_ phase: CGFloat) -> CGFloat {
        let fullTurn = CGFloat.pi * 2
        return phase.truncatingRemainder(dividingBy: fullTurn) / fullTurn
    }

    private var shouldAnimate: Bool {
        guard isAnimated else { return false }
        return style.usesAnimation
    }

    private var runsTimeline: Bool {
        shouldAnimate && !reduceMotion && scenePhase == .active
    }

    private var baseColor: Color {
        style == .floatingCards
            ? Color(uiColor: .systemGroupedBackground)
            : BirthdayTheme.Palette.background
    }

    private var artworkOpacity: Double {
        guard colorScheme == .light else { return 1 }
        switch style {
        case .silk, .auroraFlow, .nebula, .iridescence, .chrome, .threads, .swirl, .rays, .waves, .grain, .ripple,
             .bokeh, .burst, .marble, .neon, .dust, .spiral, .caustics, .dotGrid, .boreal, .lightning, .grainient, .rippleGrid: return 1
        case .tinted: return 1
        case .pastelMesh, .livingMesh: return 0.96
        case .watermark: return 1
        case .floatingCards: return 0.84
        case .confetti: return 1
        case .orbit, .halo, .satin: return 0.34
        }
    }

    private var watermarkInk: Color {
        colorScheme == .dark ? Color.white.opacity(0.065) : Color.black.opacity(0.085)
    }

    private var brand: Color { BirthdayTheme.Palette.accent }
    private var brandSoft: Color {
        BirthdayAccent.variant(saturation: 0.62, brightness: 1.10, minimumBrightness: 0.78)
    }
    private var brandPale: Color {
        BirthdayAccent.variant(saturation: 0.32, brightness: 1.18, minimumBrightness: 0.90)
    }
    private var violet: Color { brand }
    private var coral: Color { Color(hexString: "FF777B") }
    private var lavender: Color { brandPale }
    private var plum: Color {
        BirthdayAccent.variant(saturation: 0.78, brightness: 0.52, minimumBrightness: 0.24)
    }
    private var indigo: Color {
        BirthdayAccent.variant(saturation: 0.92, brightness: 0.66, minimumBrightness: 0.34)
    }

    private var seasonalAccent: Color {
        switch Calendar.current.component(.month, from: .now) {
        case 12, 1, 2: BirthdayAccent.variant(saturation: 0.52, brightness: 1.10, minimumBrightness: 0.86)
        case 3, 4, 5: BirthdayAccent.variant(saturation: 0.70, brightness: 1.04, minimumBrightness: 0.78)
        case 6, 7, 8: BirthdayAccent.variant(saturation: 0.86, brightness: 1.00, minimumBrightness: 0.70)
        default: BirthdayAccent.variant(saturation: 0.64, brightness: 0.86, minimumBrightness: 0.58)
        }
    }
}

struct BirthdayBrandMark: View {
    var size: CGFloat = 38

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .fill(Color(hexString: "17151D"))
            RoundedRectangle(cornerRadius: size * 0.19, style: .continuous)
                .stroke(BirthdayTheme.Palette.actionGradient, lineWidth: size * 0.085)
                .frame(width: size * 0.62, height: size * 0.62)
            RoundedRectangle(cornerRadius: size * 0.13, style: .continuous)
                .stroke(BirthdayTheme.Palette.accent.opacity(0.62), lineWidth: size * 0.07)
                .frame(width: size * 0.38, height: size * 0.38)
            Circle()
                .fill(Color(hexString: "17151D"))
                .frame(width: size * 0.30, height: size * 0.30)
                .offset(x: size * 0.22, y: size * 0.22)
            Image(systemName: "sparkle")
                .font(.system(size: size * 0.19, weight: .black))
                .foregroundStyle(BirthdayTheme.Palette.hot)
                .offset(x: size * 0.22, y: size * 0.22)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct BirthdayYearOrbit: View {
    let daysUntil: [Int]

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width * 0.83, y: size.height * 0.47)
            let orbitSizes = [
                CGSize(width: size.width * 0.59, height: size.height * 1.26),
                CGSize(width: size.width * 0.82, height: size.height * 1.66)
            ]

            for (index, orbitSize) in orbitSizes.enumerated() {
                let rect = CGRect(
                    x: center.x - orbitSize.width / 2,
                    y: center.y - orbitSize.height / 2,
                    width: orbitSize.width,
                    height: orbitSize.height
                )
                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(.white.opacity(index == 0 ? 0.13 : 0.075)),
                    lineWidth: 1
                )
            }

            let markerOrbit = orbitSizes[0]
            for (index, value) in daysUntil.prefix(4).enumerated() {
                let annualProgress = Double(max(0, value) % 365) / 365
                let angle = annualProgress * Double.pi * 2 - Double.pi / 2
                let point = CGPoint(
                    x: center.x + cos(angle) * markerOrbit.width / 2,
                    y: center.y + sin(angle) * markerOrbit.height / 2
                )
                let radius: CGFloat = index == 0 ? 4.5 : 3
                let marker = Path(ellipseIn: CGRect(
                    x: point.x - radius,
                    y: point.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
                let isUrgent = index == 0 && value <= 7
                context.fill(
                    marker,
                    with: .color(isUrgent ? BirthdayTheme.Palette.hot : .white.opacity(index == 0 ? 0.92 : 0.52))
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct BirthdayTodayPulse: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: reduceMotion || scenePhase != .active)) { timeline in
            let phase = pulsePhase(at: timeline.date)
            let breath = (1 - CGFloat(cos(Double(phase)))) / 2
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(BirthdayTheme.Palette.hot, lineWidth: 2)
                .scaleEffect(1 + breath * 0.22)
                .opacity(0.84 - breath * 0.48)
            }
        .accessibilityHidden(true)
    }

    private func pulsePhase(at date: Date) -> CGFloat {
        guard !reduceMotion else { return 0 }
        let duration: TimeInterval = 3.2
        let cycle = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: duration)
        return CGFloat(cycle / duration) * .pi * 2
    }
}

struct BirthdayTodayCardGlow: View {
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 15.0,
                paused: reduceMotion || scenePhase != .active
            )
        ) { timeline in
            let phase = pulsePhase(at: timeline.date)
            let breath = (1 - CGFloat(cos(Double(phase)))) / 2
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(BirthdayTheme.Palette.hot.opacity(0.22 - breath * 0.08))
                .scaleEffect(1.01 + breath * 0.025)
                .blur(radius: 14 + breath * 8)
                .opacity(0.72 - breath * 0.18)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func pulsePhase(at date: Date) -> CGFloat {
        guard !reduceMotion else { return 0 }
        let duration: TimeInterval = 4.4
        let cycle = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: duration)
        return CGFloat(cycle / duration) * .pi * 2
    }
}
