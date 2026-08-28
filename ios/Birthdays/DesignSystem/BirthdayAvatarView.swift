import SwiftUI
import UIKit

struct BirthdayAvatarView: View {
    let entry: BirthdayEntry
    var size: CGFloat = 48

    var body: some View {
        Group {
            switch entry.avatarStyle {
            case .photo:
                if let data = entry.photoData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    initials
                }
            case .emoji:
                Text(entry.emoji.isEmpty ? "🎂" : entry.emoji)
                    .font(.system(size: size * 0.48))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(BirthdayTheme.Palette.elevated)
            case .initials:
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
        .accessibilityHidden(true)
    }

    private var initials: some View {
        Color(hexString: entry.avatarColorHex)
            .overlay {
                Text(entry.initials)
                    .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
            }
    }
}

struct SharpPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
