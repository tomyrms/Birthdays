import SwiftUI
import UIKit

/// Coordonne le déclenchement des confettis : une seule explosion par
/// lancement de process, jamais à chaque recomposition de l'écran d'accueil
/// (changement de teinte, retour d'un sheet…).
@MainActor
final class LaunchCelebration: ObservableObject {
    static let shared = LaunchCelebration()

    @Published private(set) var isActive = false
    private var hasFiredThisLaunch = false

    private init() {}

    /// Les confettis fêtent quelqu'un, pas l'ouverture de l'app : un jour
    /// ordinaire, il n'y a rien à célébrer et l'explosion devient du bruit.
    func fireOnce(hasBirthdayToday: Bool) {
        guard hasBirthdayToday, !hasFiredThisLaunch else { return }
        hasFiredThisLaunch = true
        isActive = true
        Task {
            try? await Task.sleep(nanoseconds: 4_600_000_000)
            isActive = false
        }
    }
}

/// Une explosion de confettis qui part du bas de l'écran. Basée sur
/// `CAEmitterLayer` (Core Animation) plutôt qu'une dépendance tierce : c'est
/// natif, léger, et ne rate jamais un lancement pour une histoire de paquet
/// qui ne se résout pas.
struct ConfettiView: UIViewRepresentable {
    func makeUIView(context: Context) -> ConfettiEmitterView {
        let view = ConfettiEmitterView()
        view.burst()
        return view
    }

    func updateUIView(_ uiView: ConfettiEmitterView, context: Context) {}
}

final class ConfettiEmitterView: UIView {
    private let emitter = CAEmitterLayer()

    /// Le vrai confetti mélange peu de teintes très saturées : trop de
    /// couleurs proches (comme le duo corail/rose ou bleu/violet du premier
    /// jet) rendait le nuage flou plutôt que graphique.
    private static let palette: [UIColor] = [
        UIColor(red: 1.00, green: 0.21, blue: 0.35, alpha: 1), // rouge framboise
        UIColor(red: 1.00, green: 0.72, blue: 0.06, alpha: 1), // ambre
        UIColor(red: 1.00, green: 0.93, blue: 0.24, alpha: 1), // jaune citron
        UIColor(red: 0.20, green: 0.78, blue: 0.55, alpha: 1), // vert émeraude
        UIColor(red: 0.16, green: 0.62, blue: 0.98, alpha: 1), // bleu azur
        UIColor(red: 0.69, green: 0.36, blue: 0.98, alpha: 1)  // violet
    ]

    /// Trois profils physiques distincts plutôt qu'une seule forme dupliquée :
    /// c'est ce mélange — petits carrés de papier, rubans qui scintillent en
    /// tournant, pastilles rondes plus lourdes — qui lit comme « du confetti »
    /// plutôt que « des formes aléatoires qui tombent ».
    private enum ConfettiShape: CaseIterable {
        case square, ribbon, dot

        var imageSize: CGSize {
            switch self {
            case .square: CGSize(width: 11, height: 11)
            case .ribbon: CGSize(width: 14, height: 6)
            case .dot: CGSize(width: 8, height: 8)
            }
        }

        /// Beaucoup de petites pastilles, moins de grands rubans : un vrai
        /// sachet de confettis n'est pas réparti à parts égales entre formes.
        var birthRate: Float {
            switch self {
            case .square: 22
            case .ribbon: 20
            case .dot: 30
            }
        }

        var scale: CGFloat {
            switch self {
            case .square: 0.62
            case .ribbon: 0.68
            case .dot: 0.42
            }
        }

        var scaleRange: CGFloat {
            switch self {
            case .square: 0.22
            case .ribbon: 0.24
            case .dot: 0.18
            }
        }

        /// Un ruban plat tourne vite sur lui-même et scintille (il présente
        /// tour à tour sa face pleine et sa tranche) ; un carré tombe plus
        /// posément ; une pastille tourne à peine.
        var spinRange: CGFloat {
            switch self {
            case .square: 3.2
            case .ribbon: 7.5
            case .dot: 1.6
            }
        }

        /// Le papier léger flotte (faible accélération, chute plus longue) ;
        /// la pastille, plus dense visuellement, tombe plus franchement.
        var yAcceleration: CGFloat {
            switch self {
            case .square: 210
            case .ribbon: 230
            case .dot: 270
            }
        }
    }

    private static let shapeImages: [ConfettiShape: CGImage] = Dictionary(
        uniqueKeysWithValues: ConfettiShape.allCases.map { ($0, confettiImage($0)) }
    )

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        emitter.emitterCells = Self.makeCells()
        emitter.birthRate = 0
        layer.addSublayer(emitter)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        emitter.emitterShape = .line
        // Une ligne sur toute la largeur du bas plutôt qu'un point unique :
        // le jet part de partout en bas de l'écran, pas d'un seul endroit.
        emitter.emitterSize = CGSize(width: bounds.width * 0.9, height: 1)
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.height + 16)
    }

    /// Coupe la naissance de nouvelles particules très vite après le
    /// déclenchement : celles déjà émises continuent leur vol selon leur
    /// propre durée de vie, ce qui donne une explosion et non une pluie.
    func burst() {
        emitter.birthRate = 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            self?.emitter.birthRate = 0
        }
    }

    private static func makeCells() -> [CAEmitterCell] {
        ConfettiShape.allCases.flatMap { shape -> [CAEmitterCell] in
            let image = shapeImages[shape]
            return palette.map { color in
                let cell = CAEmitterCell()
                cell.contents = image
                cell.color = color.cgColor
                // Une pointe de variation par particule : des teintes toutes
                // identiques au pixel près lisent comme un motif imprimé,
                // pas comme du vrai papier découpé.
                cell.redRange = 0.05
                cell.greenRange = 0.05
                cell.blueRange = 0.05
                cell.alphaRange = 0.12
                cell.birthRate = shape.birthRate
                cell.lifetime = 3.0
                cell.lifetimeRange = 1.0
                // Vitesse assez haute pour traverser tout l'écran, du bas
                // vers le haut, avant que la gravité ne les fasse retomber.
                cell.velocity = 640
                cell.velocityRange = 220
                cell.emissionLongitude = -.pi / 2 // vers le haut
                cell.emissionRange = .pi * 0.6    // éventail large mais qui reste vertical
                cell.yAcceleration = shape.yAcceleration
                cell.xAcceleration = CGFloat.random(in: -14...14)
                cell.spin = CGFloat.random(in: -1...1) * shape.spinRange
                cell.spinRange = shape.spinRange
                cell.scale = shape.scale
                cell.scaleRange = shape.scaleRange
                cell.alphaSpeed = -0.4
                return cell
            }
        }
    }

    private static func confettiImage(_ shape: ConfettiShape) -> CGImage {
        let size = shape.imageSize
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            UIColor.white.setFill()
            switch shape {
            case .dot:
                UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
            case .square:
                UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 2).fill()
            case .ribbon:
                UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 1.5).fill()
            }
        }
        return image.cgImage!
    }
}
