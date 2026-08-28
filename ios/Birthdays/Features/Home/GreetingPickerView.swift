import SwiftUI
import UIKit

/// Le moment qui compte est le passage du rappel au message envoyé. Proposer
/// plusieurs formulations évite d'avoir à tout réécrire à chaque fois.
enum GreetingCatalog {
    struct Template: Identifiable {
        let id = UUID()
        let tone: String
        let body: String
    }

    static func templates(for occurrence: BirthdayOccurrence) -> [Template] {
        let name = occurrence.entry.name.split(separator: " ").first.map(String.init)
            ?? occurrence.entry.name

        if occurrence.daysUntil == 0 {
            var templates = [
                Template(tone: "Chaleureux", body: "Joyeux anniversaire \(name) ! Je te souhaite une magnifique journée 🎈"),
                Template(tone: "Court", body: "Joyeux anniversaire \(name) ! 🎂"),
                Template(tone: "Complice", body: "Bon anniversaire \(name) ! On se fait quelque chose pour fêter ça ?"),
                Template(tone: "Sincère", body: "Très bel anniversaire \(name). Merci d’être là, profite bien de ta journée.")
            ]
            if let age = occurrence.turningAge {
                templates.insert(
                    Template(tone: "Avec l’âge", body: "Joyeux \(age) ans \(name) ! 🎉"),
                    at: 1
                )
            }
            return templates
        }

        return [
            Template(tone: "En avance", body: "J’ai pensé à ton anniversaire \(name) 🎈 Bonne journée à toi !"),
            Template(tone: "Organiser", body: "Ton anniversaire approche \(name) — tu fais quelque chose ? J’aimerais en être."),
            Template(tone: "Discret", body: "Petite pensée pour toi \(name), à très vite.")
        ]
    }
}

struct GreetingPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let occurrence: BirthdayOccurrence

    @State private var draft: String = ""
    @State private var selectedID: UUID?

    private var isDraftEmpty: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var templates: [GreetingCatalog.Template] {
        GreetingCatalog.templates(for: occurrence)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BirthdayTheme.Spacing.md) {
                    Text(occurrence.daysUntil == 0
                         ? "C’est aujourd’hui — choisissez un message"
                         : "Dans \(occurrence.daysUntil) jours — prenez de l’avance")
                        .font(.subheadline)
                        .foregroundStyle(BirthdayTheme.Palette.secondaryText)

                    ForEach(templates) { template in
                        templateCard(template)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("VOTRE VERSION")
                            .font(.birthdaySection)
                            .tracking(1.2)
                            .foregroundStyle(BirthdayTheme.Palette.secondaryText)
                        TextField("Écrire un message", text: $draft, axis: .vertical)
                            .lineLimit(3...6)
                            .padding(12)
                            .background(BirthdayTheme.Palette.elevated)
                            .clipShape(RoundedRectangle(cornerRadius: BirthdayTheme.Radius.control, style: .continuous))
                    }
                    .padding(.top, 4)
                }
                .padding(BirthdayTheme.Spacing.md)
            }
            .birthdayScreenBackground(isAnimated: true)
            .navigationTitle("Message")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    Button {
                        UIPasteboard.general.string = draft
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } label: {
                        Label("Copier", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isDraftEmpty)

                    // Le .disabled posé sur le conteneur ne bloquait pas le
                    // partage : un message vide restait envoyable.
                    ShareLink(item: draft) {
                        Label("Envoyer", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BirthdayTheme.Palette.accent)
                    .disabled(isDraftEmpty)
                }
                .padding(BirthdayTheme.Spacing.md)
                .background(.ultraThinMaterial)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .presentationCornerRadius(24)
        .onAppear {
            guard draft.isEmpty, let first = templates.first else { return }
            draft = first.body
            selectedID = first.id
        }
    }

    private func templateCard(_ template: GreetingCatalog.Template) -> some View {
        let isSelected = selectedID == template.id

        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            draft = template.body
            selectedID = template.id
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(template.tone.uppercased())
                    .font(.birthdaySection)
                    .tracking(1.1)
                    .foregroundStyle(isSelected ? BirthdayTheme.Palette.accent : BirthdayTheme.Palette.secondaryText)
                Text(template.body)
                    .font(.birthdayBody)
                    .foregroundStyle(BirthdayTheme.Palette.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(BirthdayTheme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: BirthdayTheme.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: BirthdayTheme.Radius.card, style: .continuous)
                    .strokeBorder(
                        isSelected ? BirthdayTheme.Palette.accent : BirthdayTheme.Palette.line,
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(SharpPressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
