import SwiftUI
import UIKit

struct GlobalRemindersView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: BirthdayStore
    @State private var settings: BirthdayReminderSettings
    @State private var permissionStatus: String?

    init(settings: BirthdayReminderSettings = BirthdayReminderSettings()) {
        _settings = State(initialValue: settings)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BirthdayTheme.Spacing.lg) {
                    Text("Ces réglages s’appliquent à tous les anniversaires qui n’ont pas de rappels personnalisés.")
                        .font(.birthdayMeta)
                        .foregroundStyle(BirthdayTheme.Palette.secondaryText)

                    ReminderSettingsEditor(settings: $settings)
                        .padding(.horizontal, BirthdayTheme.Spacing.md)
                        .background(BirthdayTheme.Palette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: BirthdayTheme.Radius.card, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: BirthdayTheme.Radius.card, style: .continuous)
                                .strokeBorder(BirthdayTheme.Palette.line, lineWidth: 1)
                        }

                    // Le message d'origine constatait le refus sans rien
                    // proposer : il mène désormais aux réglages iOS.
                    if let permissionStatus {
                        Button {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            UIApplication.shared.open(url)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "bell.slash.fill")
                                    .foregroundStyle(BirthdayTheme.Palette.hot)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(permissionStatus)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(BirthdayTheme.Palette.text)
                                        .multilineTextAlignment(.leading)
                                    Text("Vos réglages sont enregistrés et s’appliqueront dès l’autorisation.")
                                        .font(.caption)
                                        .foregroundStyle(BirthdayTheme.Palette.secondaryText)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 8)
                                Text("Réglages")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(BirthdayTheme.Palette.accent)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(BirthdayTheme.Palette.hot.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(BirthdayTheme.Palette.hot.opacity(0.30), lineWidth: 1)
                            }
                        }
                        .buttonStyle(SharpPressStyle())
                    }
                }
                .padding(BirthdayTheme.Spacing.md)
            }
            .birthdayScreenBackground(isAnimated: true)
            .navigationTitle("Rappels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Enregistrer") { save() }.fontWeight(.semibold)
                }
            }
            .onAppear { settings = store.defaultReminders }
        }
        .presentationCornerRadius(24)
    }

    private func save() {
        Task {
            let granted = await NotificationScheduler.shared.requestAuthorizationIfNeeded()
            if granted {
                store.updateDefaultReminders(settings)
                dismiss()
            } else {
                permissionStatus = "Les notifications sont désactivées. Vous pouvez les autoriser dans Réglages iOS."
                store.updateDefaultReminders(settings)
            }
        }
    }
}
