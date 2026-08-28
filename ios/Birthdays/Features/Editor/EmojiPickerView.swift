import SwiftUI
import UIKit

struct EmojiPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String

    private let columns = [GridItem(.adaptive(minimum: 46), spacing: 6)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: BirthdayTheme.Spacing.lg) {
                    ForEach(EmojiCatalog.categories) { category in
                        VStack(alignment: .leading, spacing: BirthdayTheme.Spacing.sm) {
                            Text(category.title.uppercased())
                                .font(.birthdaySection)
                                .tracking(1.2)
                                .foregroundStyle(BirthdayTheme.Palette.secondaryText)
                            LazyVGrid(columns: columns, spacing: 6) {
                                ForEach(category.emojis, id: \.self) { emoji in
                                    Button {
                                        UISelectionFeedbackGenerator().selectionChanged()
                                        selection = emoji
                                        dismiss()
                                    } label: {
                                        Text(emoji)
                                            .font(.system(size: 28))
                                            .frame(width: 46, height: 46)
                                            .background(selection == emoji ? BirthdayTheme.Palette.accent.opacity(0.14) : Color.clear)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                    .accessibilityLabel(Text(emoji))
                                }
                            }
                        }
                    }
                }
                .padding(BirthdayTheme.Spacing.md)
            }
            .birthdayScreenBackground(isAnimated: true)
            .navigationTitle("Choisir un emoji")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(24)
    }
}

private struct EmojiCategory: Identifiable {
    let title: String
    let emojis: [String]
    var id: String { title }
}

private enum EmojiCatalog {
    static let categories: [EmojiCategory] = [
        EmojiCategory(title: "Fête", emojis: ["🎂", "🎉", "🎈", "🎁", "🥳", "🍰", "🧁", "✨", "🎊", "🍾", "🎇", "🎀"]),
        EmojiCategory(title: "Visages", emojis: ["😀", "😄", "😁", "😊", "😍", "🥰", "😎", "🤩", "😇", "🙂", "😜", "🤗", "🥲", "😏"]),
        EmojiCategory(title: "Personnes", emojis: ["👶", "🧒", "👦", "👧", "🧑", "👨", "👩", "🧓", "👴", "👵", "👨‍👩‍👧", "🧑‍🤝‍🧑", "🤴", "👸"]),
        EmojiCategory(title: "Animaux", emojis: ["🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐨", "🐯", "🦁", "🐮", "🐷", "🐸", "🐵", "🐔", "🐧", "🦄", "🐢", "🐬"]),
        EmojiCategory(title: "Nature", emojis: ["🌟", "⭐️", "🌈", "☀️", "🌙", "🔥", "🌸", "🌻", "🍀", "🌊", "❄️", "🌵"]),
        EmojiCategory(title: "Cœurs", emojis: ["❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "💖", "💗", "💫", "💯"]),
        EmojiCategory(title: "Activités", emojis: ["⚽️", "🏀", "🎮", "🎸", "🎨", "📚", "✈️", "🚀", "⚡️", "🏆", "🎯", "🎧"])
    ]
}
