import PhotosUI
import SwiftUI
import UIKit

private let birthdayMonthNames: [String] = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "fr_CH")
    return calendar.monthSymbols.map(\.capitalized)
}()

struct BirthdayEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: BirthdayStore

    let originalEntry: BirthdayEntry?
    let onSave: (BirthdayEntry) -> Void

    @State private var name: String
    @State private var month: Int
    @State private var day: Int
    @State private var yearOrAge: String
    @State private var avatarStyle: BirthdayAvatarStyle
    @State private var emoji: String
    @State private var photoData: Data?
    @State private var avatarColorHex: String
    @State private var selectedGroupIDs: Set<UUID>
    @State private var usesCustomReminders: Bool
    @State private var reminderSettings: BirthdayReminderSettings
    @State private var note: String
    @State private var photoItem: PhotosPickerItem?
    @State private var showValidation = false
    @State private var hasChosenAvatarColor = false
    @State private var showEmojiPicker = false
    @State private var confirmDiscard = false
    @State private var isFavorite: Bool

    private let colors = ["6856E8", "C95565", "218078", "C57A2D", "3472B8", "A94E83", "66733A", "7A5EAE"]

    init(entry: BirthdayEntry?, onSave: @escaping (BirthdayEntry) -> Void) {
        originalEntry = entry
        self.onSave = onSave
        _name = State(initialValue: entry?.name ?? "")
        _month = State(initialValue: entry?.month ?? Calendar.current.component(.month, from: .now))
        _day = State(initialValue: entry?.day ?? Calendar.current.component(.day, from: .now))
        _yearOrAge = State(initialValue: entry?.birthYear.map(String.init) ?? "")
        _avatarStyle = State(initialValue: entry?.avatarStyle ?? .initials)
        _emoji = State(initialValue: entry?.emoji ?? "🎂")
        _photoData = State(initialValue: entry?.photoData)
        _avatarColorHex = State(initialValue: entry?.avatarColorHex ?? "6856E8")
        _selectedGroupIDs = State(initialValue: Set(entry?.groupIDs ?? []))
        _usesCustomReminders = State(initialValue: entry?.customReminders != nil)
        _reminderSettings = State(initialValue: entry?.customReminders ?? BirthdayReminderSettings())
        _note = State(initialValue: entry?.note ?? "")
        _isFavorite = State(initialValue: entry?.isFavorite ?? false)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BirthdayTheme.Spacing.xl) {
                    identitySection
                    dateSection
                    groupsSection
                    remindersSection
                    noteSection
                }
                .padding(BirthdayTheme.Spacing.md)
                .padding(.bottom, BirthdayTheme.Spacing.xl)
            }
            .birthdayScreenBackground(isAnimated: true)
            .navigationTitle(originalEntry == nil ? "Nouvel anniversaire" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") {
                        if hasUnsavedChanges { confirmDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Enregistrer") { save() }
                        .fontWeight(.semibold)
                }
            }
            // Un glissement vers le bas effaçait la saisie sans prévenir.
            .interactiveDismissDisabled(hasUnsavedChanges)
            .confirmationDialog(
                "Abandonner les modifications ?",
                isPresented: $confirmDiscard,
                titleVisibility: .visible
            ) {
                Button("Abandonner", role: .destructive) { dismiss() }
                Button("Continuer la saisie", role: .cancel) {}
            }
            .alert("Nom requis", isPresented: $showValidation) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Ajoutez un nom avant d’enregistrer l’anniversaire.")
            }
            .sheet(isPresented: $showEmojiPicker) {
                EmojiPickerView(selection: $emoji)
            }
            .onChange(of: month) { _, _ in day = min(day, dayCount) }
            .onChange(of: photoItem) { _, item in loadPhoto(item) }
            .onChange(of: name) { _, value in
                guard originalEntry == nil, !hasChosenAvatarColor, !value.isEmpty else { return }
                avatarColorHex = BirthdayAvatarPalette.colorHex(for: value)
            }
            .onAppear {
                if originalEntry?.customReminders == nil {
                    reminderSettings = store.defaultReminders
                }
            }
        }
        .presentationCornerRadius(24)
    }

    private var identitySection: some View {
        editorSection("PERSONNE") {
            VStack(spacing: BirthdayTheme.Spacing.md) {
                TextField("Nom", text: $name)
                    .font(.title3.weight(.semibold))
                    .textContentType(.name)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 52)
                    .background(BirthdayTheme.Palette.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: BirthdayTheme.Radius.control, style: .continuous))

                HStack(spacing: BirthdayTheme.Spacing.sm) {
                    ForEach(BirthdayAvatarStyle.allCases) { style in
                        avatarChoice(style)
                    }
                }

                // Le favori se réglait partout sauf ici, le seul écran où l'on
                // modifie tout le reste de la fiche.
                Toggle(isOn: $isFavorite) {
                    Label("Favori", systemImage: isFavorite ? "star.fill" : "star")
                        .font(.birthdayBody.weight(.medium))
                        .foregroundStyle(isFavorite ? BirthdayTheme.Palette.hot : BirthdayTheme.Palette.text)
                }
                .tint(BirthdayTheme.Palette.accent)

                switch avatarStyle {
                case .initials:
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(colors, id: \.self) { color in
                                Button {
                                    avatarColorHex = color
                                    hasChosenAvatarColor = true
                                } label: {
                                    Circle()
                                        .fill(Color(hexString: color))
                                        .frame(width: 30, height: 30)
                                        .overlay {
                                            if avatarColorHex == color {
                                                Image(systemName: "checkmark")
                                                    .font(.caption.bold())
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                        .frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("Couleur d’avatar")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                case .emoji:
                    Button { showEmojiPicker = true } label: {
                        HStack(spacing: 12) {
                            Text(emoji)
                                .font(.system(size: 30))
                                .frame(width: 46, height: 46)
                                .background(BirthdayTheme.Palette.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            Text("Choisir un emoji")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(BirthdayTheme.Palette.text)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(BirthdayTheme.Palette.secondaryText)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(minHeight: 54)
                        .background(BirthdayTheme.Palette.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: BirthdayTheme.Radius.control, style: .continuous))
                    }
                    .buttonStyle(.plain)
                case .photo:
                    HStack(spacing: BirthdayTheme.Spacing.sm) {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label(photoData == nil ? "Choisir une photo" : "Changer la photo", systemImage: "photo")
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.bordered)

                        // Il n'existait aucun moyen de retirer une photo :
                        // seulement de la remplacer par une autre.
                        if photoData != nil {
                            Button(role: .destructive) {
                                photoItem = nil
                                photoData = nil
                                avatarStyle = .initials
                            } label: {
                                Image(systemName: "trash")
                                    .frame(minWidth: 48, minHeight: 48)
                            }
                            .buttonStyle(.bordered)
                            .tint(BirthdayTheme.Palette.destructive)
                            .accessibilityLabel("Retirer la photo")
                        }
                    }
                }
            }
        }
    }

    private var dateSection: some View {
        editorSection("DATE") {
            VStack(alignment: .leading, spacing: BirthdayTheme.Spacing.md) {
                HStack(spacing: BirthdayTheme.Spacing.sm) {
                    Picker("Mois", selection: $month) {
                        ForEach(1...12, id: \.self) { value in
                            Text(monthName(value)).tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(BirthdayTheme.Palette.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: BirthdayTheme.Radius.control, style: .continuous))

                    Picker("Jour", selection: $day) {
                        ForEach(1...dayCount, id: \.self) { value in Text("\(value)").tag(value) }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(BirthdayTheme.Palette.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: BirthdayTheme.Radius.control, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Année de naissance ou âge")
                        .font(.birthdayMeta)
                        .foregroundStyle(BirthdayTheme.Palette.secondaryText)
                    TextField("Ex. 1998 ou 28", text: $yearOrAge)
                        .keyboardType(.numberPad)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 50)
                        .background(BirthdayTheme.Palette.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: BirthdayTheme.Radius.control, style: .continuous))
                }
            }
        }
    }

    private var groupsSection: some View {
        editorSection("GROUPES") {
            if store.groups.isEmpty {
                Text("Aucun groupe. Vous pourrez en créer depuis l’accueil.")
                    .font(.birthdayMeta)
                    .foregroundStyle(BirthdayTheme.Palette.secondaryText)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(store.groups) { group in
                        let selected = selectedGroupIDs.contains(group.id)
                        Button {
                            if selected { selectedGroupIDs.remove(group.id) }
                            else { selectedGroupIDs.insert(group.id) }
                        } label: {
                            HStack(spacing: 7) {
                                Circle().fill(Color(hexString: group.colorHex)).frame(width: 8, height: 8)
                                Text(group.name)
                                if selected { Image(systemName: "checkmark").font(.caption.bold()) }
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BirthdayTheme.Palette.text)
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(selected ? BirthdayTheme.Palette.elevated : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: BirthdayTheme.Radius.control, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: BirthdayTheme.Radius.control, style: .continuous)
                                    .strokeBorder(selected ? Color(hexString: group.colorHex) : BirthdayTheme.Palette.line, lineWidth: 1)
                            }
                        }
                        .buttonStyle(SharpPressStyle())
                    }
                }
            }
        }
    }

    private var remindersSection: some View {
        editorSection("RAPPELS") {
            VStack(spacing: 0) {
                Toggle("Personnaliser pour cette personne", isOn: $usesCustomReminders)
                    .font(.birthdayBody.weight(.medium))
                    .padding(.vertical, 8)
                if usesCustomReminders {
                    Divider().overlay(BirthdayTheme.Palette.line)
                    ReminderSettingsEditor(settings: $reminderSettings)
                } else {
                    Text("Les réglages globaux seront utilisés.")
                        .font(.birthdayMeta)
                        .foregroundStyle(BirthdayTheme.Palette.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
            }
        }
    }

    private var noteSection: some View {
        editorSection("NOTE") {
            TextField("Idée cadeau, préférence…", text: $note, axis: .vertical)
                .lineLimit(3...6)
                .padding(12)
                .background(BirthdayTheme.Palette.elevated)
                .clipShape(RoundedRectangle(cornerRadius: BirthdayTheme.Radius.control, style: .continuous))
        }
    }

    private func avatarChoice(_ style: BirthdayAvatarStyle) -> some View {
        Button { avatarStyle = style } label: {
            VStack(spacing: 8) {
                if style == avatarStyle {
                    BirthdayAvatarView(entry: previewEntry, size: 46)
                } else {
                    Image(systemName: icon(for: style))
                        .font(.title3)
                        .foregroundStyle(BirthdayTheme.Palette.secondaryText)
                        .frame(width: 46, height: 46)
                        .background(BirthdayTheme.Palette.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                Text(style.title).font(.caption.weight(.semibold))
            }
            .foregroundStyle(avatarStyle == style ? BirthdayTheme.Palette.accent : BirthdayTheme.Palette.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 88)
            .background(avatarStyle == style ? BirthdayTheme.Palette.accent.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: BirthdayTheme.Radius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: BirthdayTheme.Radius.control, style: .continuous)
                    .strokeBorder(avatarStyle == style ? BirthdayTheme.Palette.accent : BirthdayTheme.Palette.line, lineWidth: 1)
            }
        }
        .buttonStyle(SharpPressStyle())
    }

    private var previewEntry: BirthdayEntry {
        BirthdayEntry(
            name: name.isEmpty ? "Prénom Nom" : name,
            month: month,
            day: day,
            avatarStyle: avatarStyle,
            emoji: emoji,
            photoData: photoData,
            avatarColorHex: avatarColorHex
        )
    }

    private func editorSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: BirthdayTheme.Spacing.sm) {
            Text(title)
                .font(.birthdaySection)
                .tracking(1.2)
                .foregroundStyle(BirthdayTheme.Palette.secondaryText)
            content()
                .padding(BirthdayTheme.Spacing.md)
                .background(BirthdayTheme.Palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: BirthdayTheme.Radius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: BirthdayTheme.Radius.card, style: .continuous)
                        .strokeBorder(BirthdayTheme.Palette.line, lineWidth: 1)
                }
        }
    }

    private var dayCount: Int {
        let date = Calendar.current.date(from: DateComponents(year: 2000, month: month, day: 1))!
        return Calendar.current.range(of: .day, in: .month, for: date)?.count ?? 31
    }

    private func monthName(_ month: Int) -> String {
        birthdayMonthNames[min(max(month - 1, 0), birthdayMonthNames.count - 1)]
    }

    private func icon(for style: BirthdayAvatarStyle) -> String {
        switch style {
        case .initials: "textformat"
        case .emoji: "face.smiling"
        case .photo: "photo"
        }
    }

    /// Comparé au point de départ plutôt qu'à un simple drapeau « touché » :
    /// revenir soi-même sur ses pas ne doit pas déclencher d'avertissement.
    private var hasUnsavedChanges: Bool {
        guard let original = originalEntry else {
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || photoData != nil
                || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !selectedGroupIDs.isEmpty
        }
        return original.name != BirthdayLimits.clampedName(name)
            || original.month != month
            || original.day != day
            || original.birthYear != parsedBirthYear()
            || original.avatarStyle != avatarStyle
            || original.emoji != emoji
            || original.photoData != photoData
            || original.avatarColorHex != avatarColorHex
            || Set(original.groupIDs) != selectedGroupIDs
            || original.note != BirthdayLimits.clampedNote(note)
            || original.customReminders != (usesCustomReminders ? reminderSettings : nil)
            || original.isFavorite != isFavorite
    }

    private func parsedBirthYear() -> Int? {
        BirthdayDateCalculator.birthYear(fromInput: yearOrAge, month: month, day: day)
    }

    private func save() {
        let cleanedName = BirthdayLimits.clampedName(name)
        guard !cleanedName.isEmpty else { showValidation = true; return }
        let existing = originalEntry
        let entry = BirthdayEntry(
            id: existing?.id ?? UUID(),
            name: cleanedName,
            month: month,
            day: day,
            birthYear: parsedBirthYear(),
            avatarStyle: avatarStyle,
            emoji: emoji.isEmpty ? "🎂" : emoji,
            photoData: photoData,
            avatarColorHex: avatarColorHex,
            groupIDs: Array(selectedGroupIDs),
            customReminders: usesCustomReminders ? reminderSettings : nil,
            note: BirthdayLimits.clampedNote(note),
            // L'éditeur reconstruit la fiche entière : tout champ oublié ici
            // est réinitialisé en silence. C'était le cas du favori.
            isFavorite: isFavorite,
            source: existing?.source ?? .manual,
            sourceIdentifier: existing?.sourceIdentifier,
            createdAt: existing?.createdAt ?? .now,
            updatedAt: .now
        )
        onSave(entry)
        dismiss()
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let processed = ImageProcessor.thumbnailData(from: data) else { return }
            photoData = processed
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
