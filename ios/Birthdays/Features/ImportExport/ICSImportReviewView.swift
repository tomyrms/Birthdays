import SwiftUI

struct ICSImportPayload: Identifiable {
    let id = UUID()
    let filename: String
    let entries: [BirthdayEntry]
}

struct ICSImportReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let payload: ICSImportPayload
    let onImport: ([BirthdayEntry]) -> Void

    @State private var selection: Set<UUID>

    init(payload: ICSImportPayload, onImport: @escaping ([BirthdayEntry]) -> Void) {
        self.payload = payload
        self.onImport = onImport
        _selection = State(initialValue: Set(payload.entries.map(\.id)))
    }

    var body: some View {
        NavigationStack {
            List(payload.entries) { entry in
                Button {
                    if selection.contains(entry.id) { selection.remove(entry.id) }
                    else { selection.insert(entry.id) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selection.contains(entry.id) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(selection.contains(entry.id) ? BirthdayTheme.Palette.accent : BirthdayTheme.Palette.secondaryText)
                        BirthdayAvatarView(entry: entry, size: 38)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.name)
                                .foregroundStyle(BirthdayTheme.Palette.text)
                            Text(dateText(for: entry))
                                .font(.birthdayMeta)
                                .foregroundStyle(BirthdayTheme.Palette.secondaryText)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .scrollContentBackground(.hidden)
            .birthdayScreenBackground(isAnimated: true)
            .navigationTitle("\(selection.count) sur \(payload.entries.count)")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Text(payload.filename)
                    .font(.caption)
                    .foregroundStyle(BirthdayTheme.Palette.secondaryText)
                    .lineLimit(1)
                    .padding(.vertical, 8)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") { dismiss() }
                }
                // Cocher cinquante entrées une par une n'est pas tenable.
                ToolbarItem(placement: .topBarLeading) {
                    Button(selection.count == payload.entries.count ? "Aucun" : "Tout") {
                        selection = selection.count == payload.entries.count
                            ? []
                            : Set(payload.entries.map(\.id))
                    }
                    .font(.subheadline.weight(.semibold))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Importer") {
                        onImport(payload.entries.filter { selection.contains($0.id) })
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(selection.isEmpty)
                }
            }
        }
        .presentationCornerRadius(24)
    }

    private func dateText(for entry: BirthdayEntry) -> String {
        BirthdayDateCalculator.date(year: 2000, month: entry.month, day: entry.day)
            .formatted(Date.FormatStyle().day().month(.wide).locale(Locale(identifier: "fr_CH")))
    }
}
