import SwiftUI

struct GroupManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: BirthdayStore
    @State private var newName = ""
    @State private var selectedColor = "6856E8"
    @State private var editingGroup: BirthdayGroup?
    @State private var groupPendingDeletion: BirthdayGroup?

    private let colors = ["6856E8", "C95565", "218078", "C57A2D", "3472B8", "A94E83"]

    var body: some View {
        NavigationStack {
            List {
                Section("Nouveau groupe") {
                    TextField("Nom du groupe", text: $newName)
                    colorRow(selection: $selectedColor)
                    Button("Créer le groupe") {
                        store.addGroup(name: newName, colorHex: selectedColor)
                        newName = ""
                        // Sans cela, tous les groupes suivants héritaient de la
                        // couleur du précédent.
                        selectedColor = colors.randomElement() ?? "6856E8"
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("Groupes") {
                    if store.groups.isEmpty {
                        Text("Aucun groupe")
                            .foregroundStyle(BirthdayTheme.Palette.secondaryText)
                    }
                    ForEach(store.groups) { group in
                        Button { editingGroup = group } label: {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(hexString: group.colorHex))
                                    .frame(width: 14, height: 14)
                                Text(group.name)
                                    .foregroundStyle(BirthdayTheme.Palette.text)
                                Spacer()
                                Text("\(store.memberCount(of: group))")
                                    .foregroundStyle(BirthdayTheme.Palette.secondaryText)
                                    .monospacedDigit()
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(BirthdayTheme.Palette.secondaryText)
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            // La suppression retire aussi le groupe de toutes
                            // les fiches : elle passe par une confirmation qui
                            // annonce combien de personnes sont concernées.
                            Button(role: .destructive) {
                                groupPendingDeletion = group
                            } label: {
                                Label("Supprimer", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .birthdayScreenBackground(isAnimated: true)
            .navigationTitle("Groupes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } }
            }
            .sheet(item: $editingGroup) { group in
                GroupEditorView(group: group).environmentObject(store)
            }
            .confirmationDialog(
                groupPendingDeletion.map { deletionTitle(for: $0) } ?? "",
                isPresented: deletionBinding,
                titleVisibility: .visible,
                presenting: groupPendingDeletion
            ) { group in
                Button("Supprimer le groupe", role: .destructive) {
                    store.removeGroup(group)
                    groupPendingDeletion = nil
                }
            } message: { group in
                Text(store.memberCount(of: group) == 0
                     ? "Ce groupe n’est utilisé par personne."
                     : "Les anniversaires ne seront pas supprimés, seulement retirés de ce groupe.")
            }
        }
        .presentationCornerRadius(24)
    }

    private var deletionBinding: Binding<Bool> {
        Binding(get: { groupPendingDeletion != nil }, set: { if !$0 { groupPendingDeletion = nil } })
    }

    private func deletionTitle(for group: BirthdayGroup) -> String {
        let count = store.memberCount(of: group)
        guard count > 0 else { return "Supprimer « \(group.name) » ?" }
        return "Retirer « \(group.name) » de \(count) anniversaire\(count > 1 ? "s" : "") ?"
    }

    private func colorRow(selection: Binding<String>) -> some View {
        HStack {
            ForEach(colors, id: \.self) { color in
                Button { selection.wrappedValue = color } label: {
                    Circle()
                        .fill(Color(hexString: color))
                        .frame(width: 30, height: 30)
                        .overlay {
                            if selection.wrappedValue == color {
                                Image(systemName: "checkmark")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Couleur du groupe")
            }
        }
    }
}

/// Renommer ou recolorer était impossible : une faute de frappe obligeait à
/// supprimer le groupe — donc à le retirer de toutes les fiches — puis à tout
/// refaire à la main.
private struct GroupEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: BirthdayStore

    let group: BirthdayGroup
    @State private var name: String
    @State private var colorHex: String

    private let colors = ["6856E8", "C95565", "218078", "C57A2D", "3472B8", "A94E83"]

    init(group: BirthdayGroup) {
        self.group = group
        _name = State(initialValue: group.name)
        _colorHex = State(initialValue: group.colorHex)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var nameConflicts: Bool {
        !trimmedName.isEmpty && store.groups.contains {
            $0.id != group.id && $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Nom") {
                    TextField("Nom du groupe", text: $name)
                    if nameConflicts {
                        Label("Un autre groupe porte déjà ce nom.", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(BirthdayTheme.Palette.destructive)
                    }
                }
                Section("Couleur") {
                    HStack {
                        ForEach(colors, id: \.self) { color in
                            Button { colorHex = color } label: {
                                Circle()
                                    .fill(Color(hexString: color))
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        if colorHex == color {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Couleur du groupe")
                        }
                    }
                }
                Section {
                    Text(memberSummary)
                        .font(.footnote)
                        .foregroundStyle(BirthdayTheme.Palette.secondaryText)
                }
            }
            .scrollContentBackground(.hidden)
            .birthdayScreenBackground(isAnimated: true)
            .navigationTitle("Modifier le groupe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Enregistrer") {
                        store.updateGroup(group, name: name, colorHex: colorHex)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(trimmedName.isEmpty || nameConflicts)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(24)
    }

    private var memberSummary: String {
        let count = store.memberCount(of: group)
        return count == 0
            ? "Aucun anniversaire dans ce groupe"
            : "\(count) anniversaire\(count > 1 ? "s" : "") dans ce groupe"
    }
}
