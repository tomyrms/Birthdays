import SwiftUI

/// Rend un fond calculé par la carte graphique.
///
/// Le seul travail du processeur central est de faire avancer une valeur de
/// temps ; tout le dessin se fait dans le shader. C'est la raison pour laquelle
/// ces fonds, bien plus riches que les précédents, coûtent moins cher.
struct BirthdayShaderBackground: View {
    enum Kind {
        case silk
        case aurora
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
    }

    let kind: Kind
    var isAnimated = true

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            if runsTimeline {
                TimelineView(.animation(minimumInterval: frameInterval)) { timeline in
                    canvas(size: size, time: phase(at: timeline.date))
                }
            } else {
                canvas(size: size, time: 0)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func canvas(size: CGSize, time: Double) -> some View {
        Rectangle()
            .fill(base)
            .colorEffect(shader(size: size, time: time))
            .drawingGroup()
            // Voile posé par-dessus le fond : blanc en thème clair, noir en
            // sombre. Il fait reculer la texture d'un cran pour que les dates
            // restent lisibles quel que soit le motif dessous.
            .overlay((colorScheme == .dark ? Color.black : Color.white).opacity(veil))
    }

    /// Les motifs très contrastés ont besoin d'un voile plus dense.
    ///
    /// Le voile est allégé en thème clair : cumulé à l'atténuation du motif, il
    /// effaçait complètement le fond.
    private var veil: Double {
        (colorScheme == .dark ? 1.0 : 0.70) * rawVeil
    }

    private var rawVeil: Double {
        switch kind {
        case .iridescence, .chrome, .swirl: 0.62
        case .threads, .ripple, .rays, .caustics, .neon, .burst: 0.55
        case .dust, .dotGrid, .rippleGrid: 0.46
        case .grainient: 0.52
        default: 0.50
        }
    }

    private func shader(size: CGSize, time: Double) -> Shader {
        let dimensions = Shader.Argument.float2(Float(size.width), Float(size.height))
        let clock = Shader.Argument.float(Float(time))

        switch kind {
        case .silk:
            return ShaderLibrary.birthdaySilk(
                dimensions, clock,
                rgb(accent), rgb(baseColor), .float(Float(strength))
            )
        case .aurora:
            return ShaderLibrary.birthdayAurora(
                dimensions, clock,
                rgb(accent), rgb(secondary), rgb(baseColor), .float(Float(strength)), .float(Float(inkMode))
            )
        case .nebula:
            return ShaderLibrary.birthdayNebula(
                dimensions, clock,
                rgb(accent), rgb(secondary), rgb(baseColor), .float(Float(strength))
            )
        case .iridescence:
            return ShaderLibrary.birthdayIridescence(
                dimensions, clock,
                rgb(accent), rgb(baseColor), .float(Float(strength))
            )
        case .chrome:
            return ShaderLibrary.birthdayChrome(
                dimensions, clock,
                rgb(accent), rgb(baseColor), .float(Float(strength)), .float(Float(inkMode))
            )
        case .threads:
            return ShaderLibrary.birthdayThreads(
                dimensions, clock,
                rgb(accent), rgb(baseColor), .float(Float(strength))
            )
        case .swirl:
            return ShaderLibrary.birthdaySwirl(
                dimensions, clock,
                rgb(accent), rgb(secondary), rgb(baseColor), .float(Float(strength))
            )
        case .rays:
            return ShaderLibrary.birthdayRays(
                dimensions, clock,
                rgb(accent), rgb(baseColor), .float(Float(strength))
            )
        case .waves:
            return ShaderLibrary.birthdayWaves(
                dimensions, clock,
                rgb(accent), rgb(secondary), rgb(baseColor), .float(Float(strength))
            )
        case .grain:
            return ShaderLibrary.birthdayGrain(
                dimensions, clock,
                rgb(accent), rgb(secondary), rgb(baseColor), .float(Float(strength))
            )
        case .ripple:
            return ShaderLibrary.birthdayRipple(
                dimensions, clock,
                rgb(accent), rgb(baseColor), .float(Float(strength))
            )
        case .bokeh:
            return ShaderLibrary.birthdayBokeh(
                dimensions, clock,
                rgb(accent), rgb(secondary), rgb(baseColor), .float(Float(strength))
            )
        case .burst:
            return ShaderLibrary.birthdayBurst(
                dimensions, clock,
                rgb(accent), rgb(secondary), rgb(baseColor), .float(Float(strength))
            )
        case .marble:
            return ShaderLibrary.birthdayMarble(
                dimensions, clock,
                rgb(accent), rgb(baseColor), .float(Float(strength))
            )
        case .neon:
            return ShaderLibrary.birthdayNeon(
                dimensions, clock,
                rgb(accent), rgb(secondary), rgb(baseColor), .float(Float(strength)), .float(Float(inkMode))
            )
        case .dust:
            return ShaderLibrary.birthdayDust(
                dimensions, clock,
                rgb(accent), rgb(baseColor), .float(Float(strength)), .float(Float(inkMode))
            )
        case .spiral:
            return ShaderLibrary.birthdaySpiral(
                dimensions, clock,
                rgb(accent), rgb(secondary), rgb(baseColor), .float(Float(strength))
            )
        case .caustics:
            return ShaderLibrary.birthdayCaustics(
                dimensions, clock,
                rgb(accent), rgb(baseColor), .float(Float(strength))
            )
        case .dotGrid:
            return ShaderLibrary.birthdayDotGrid(
                dimensions, clock,
                rgb(accent), rgb(baseColor), .float(Float(strength))
            )
        case .boreal:
            return ShaderLibrary.birthdayBoreal(
                dimensions, clock,
                rgb(accent), rgb(secondary), rgb(baseColor), .float(Float(strength))
            )
        case .lightning:
            return ShaderLibrary.birthdayLightning(
                dimensions, clock,
                rgb(accent), rgb(baseColor), .float(Float(strength))
            )
        case .grainient:
            return ShaderLibrary.birthdayGrainient(
                dimensions, clock,
                rgb(accent), rgb(secondary), rgb(baseColor), .float(Float(strength))
            )
        case .rippleGrid:
            return ShaderLibrary.birthdayRippleGrid(
                dimensions, clock,
                rgb(accent), rgb(baseColor), .float(Float(strength))
            )
        }
    }

    // MARK: Couleurs

    private var accent: Color {
        // En mode encre la teinte est assombrie : une couleur claire déposée
        // sur du papier clair ne se verrait pas davantage qu'une lumière.
        guard colorScheme != .dark else {
            return BirthdayAccent.variant(saturation: 1.05, brightness: 1, minimumBrightness: 0.35)
        }
        return usesInk
            ? BirthdayAccent.variant(saturation: 1.15, brightness: 0.62, minimumBrightness: 0.18)
            : BirthdayAccent.variant(saturation: 1.05, brightness: 0.92, minimumBrightness: 0.35)
    }

    /// Motifs qui éclairent au lieu de peindre : invisibles en thème clair
    /// sans cette bascule.
    private var usesInk: Bool {
        switch kind {
        case .aurora, .chrome, .neon, .dust: colorScheme != .dark
        default: false
        }
    }

    private var inkMode: Double { usesInk ? 1 : 0 }

    /// Une teinte voisine plutôt qu'une couleur fixe : les deux doivent
    /// s'accorder quelle que soit la couleur choisie par l'utilisateur.
    private var secondary: Color {
        BirthdayAccent.variant(saturation: 0.62, brightness: colorScheme == .dark ? 1.25 : 1.05, minimumBrightness: 0.55)
    }

    private var baseColor: Color {
        colorScheme == .dark ? Color(hexString: "0B0A10") : Color(hexString: "F4F2F7")
    }

    private var base: Color { baseColor }

    /// Un fond reste un fond : trop présent, il concurrence les dates au lieu
    /// de les porter. Ces valeurs le maintiennent en retrait.
    private var strength: Double {
        // Le thème clair est calibré pour atteindre la même présence perçue
        // que le sombre, pas la même valeur brute : sur fond pâle le motif
        // dispose de moins d'écart de luminosité.
        let base: Double = colorScheme == .dark ? 0.52 : 0.42
        // Nacre et Mercure sont bien plus contrastés que les trois autres.
        switch kind {
        case .iridescence, .chrome: return base * 0.62
        default: return base
        }
    }

    private func rgb(_ color: Color) -> Shader.Argument {
        let components = UIColor(color).resolvedComponents
        return .float3(Float(components.red), Float(components.green), Float(components.blue))
    }

    // MARK: Temps

    /// « Fils » évalue dix-huit brins par pixel : à trente images par seconde
    /// le mouvement reste fluide pour un fond, et la charge est divisée.
    private var frameInterval: Double {
        kind == .threads ? 1.0 / 30.0 : 1.0 / 60.0
    }

    private var runsTimeline: Bool {
        isAnimated && !reduceMotion && scenePhase == .active
    }

    /// Boucle sur une période longue : repartir de zéro évite qu'une valeur de
    /// temps sans cesse croissante ne finisse par perdre en précision.
    private func phase(at date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 600)
    }
}

private extension UIColor {
    var resolvedComponents: (red: CGFloat, green: CGFloat, blue: CGFloat) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return (0.4, 0.35, 0.9)
        }
        return (red, green, blue)
    }
}
