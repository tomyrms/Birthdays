import SwiftUI
import UIKit

struct BirthdayDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: BirthdayStore

    let entryID: UUID
    let onEdit: (BirthdayEntry) -> Void
    @State private var confirmDelete = false
    @State private var showGroupManager = false
    @State private var showGreeting = false
    @State private var showYearPrompt = false
    @State private var yearDraft = ""
    @State private var yearError = false

    private var entry: BirthdayEntry? { store.entry(id: entryID) }

    var body: some View {
        NavigationStack {
            Group {
                if let entry {
                    let occurrence = BirthdayDateCalculator.occurrence(for: entry)
                    ScrollView {
                        VStack(alignment: .leading, spacing: BirthdayTheme.Spacing.lg) {
                            hero(entry, occurrence: occurrence)
                            quickActions(entry, occurrence: occurrence)
                            section("GROUPES") { groupChips(entry) }
                            section("INFORMATIONS") { information(entry) }
                            if !entry.note.isEmpty {
                                section("NOTE") {
                                    Text(entry.note)
                                        .font(.birthdayBody)
                                        .foregroundStyle(BirthdayTheme.Palette.text)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .padding(BirthdayTheme.Spacing.lg)
                    }
                    .birthdayScreenBackground(isAnimated: true)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Fermer") { dismiss() }
                        }
                        // L'action destructrice quitte le corps de la page :
                        // elle doit rester atteignable sans être le contrôle
                        // le plus voyant de l'écran.
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                Button { onEdit(entry) } label: {
                                    Label("Modifier", systemImage: "pencil")
                                }
                                Divider()
                                Button(role: .destructive) { confirmDelete = true } label: {
                                    Label("Supprimer l’anniversaire", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            .accessibilityLabel("Plus d’options")
                        }
                    }
                    .confirmationDialog("Supprimer \(entry.name) ?", isPresented: $confirmDelete) {
                        Button("Supprimer", role: .destructive) {
                            store.remove(entry)
                            dismiss()
                        }
                    }
                    .alert("Année de naissance", isPresented: $showYearPrompt) {
                        TextField("Ex. 1998 ou 28", text: $yearDraft)
                            .keyboardType(.numberPad)
                        Button("Annuler", role: .cancel) {}
                        Button("Enregistrer") { saveYear(for: entry) }
                    } message: {
                        Text("Indiquez l’année de naissance, ou simplement l’âge.")
                    }
                    .alert("Valeur non comprise", isPresented: $yearError) {
                        Button("Réessayer") { showYearPrompt = true }
                        Button("Annuler", role: .cancel) {}
                    } message: {
                        Text("Saisissez une année entre 1900 et aujourd’hui, ou un âge en années.")
                    }
                } else {
                    ContentUnavailableView("Anniversaire introuvable", systemImage: "calendar.badge.exclamationmark")
                }
            }
            .navigationTitle("Anniversaire")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationCornerRadius(24)
    }

    private func hero(_ entry: BirthdayEntry, occurrence: BirthdayOccurrence) -> some View {
        let hasPhoto = entry.avatarStyle == .photo && entry.photoData != nil

        return ZStack {
            BirthdayHeroBackground(entry: entry)
            if hasPhoto {
                BirthdayMemoryLensView(
                    entry: entry,
                    widthRatio: 0.72,
                    minimumWidth: 238
                )
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.42),
                        .init(color: Color(hexString: "17151F").opacity(0.58), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            // Un seul bloc de texte, du côté du dégradé : le compte à rebours
            // ne tombe plus sur la photo, où sa lisibilité dépendait de l'image.
            VStack(spacing: 0) {
                if !hasPhoto {
                    HStack {
                        BirthdayAvatarView(entry: entry, size: 64)
                            .overlay {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .strokeBorder(.white.opacity(0.28), lineWidth: 1)
                            }
                        Spacer()
                    }
                }
                Spacer()
                VStack(alignment: .leading, spacing: 5) {
                    Text(countdownLabel(occurrence))
                        .font(.caption2.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.82))
                    Text(entry.name)
                        .font(.birthdayTitle)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .padding(.trailing, hasPhoto ? 92 : 0)
                    Text(heroDateLine(occurrence))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.68))
                        .padding(.trailing, hasPhoto ? 88 : 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(22)
            .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, minHeight: hasPhoto ? 310 : 270)
        .clipShape(RoundedRectangle(cornerRadius: BirthdayTheme.Radius.hero, style: .continuous))            .overlay(alignment: .topTrailing) {
                if entry.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.subheadline)
                        .foregroundStyle(BirthdayTheme.Palette.hot)
                        .padding(14)
                        .accessibilityLabel("Favori")
                }
            }
        .shadow(color: BirthdayTheme.Palette.accent.opacity(0.22), radius: 22, x: 0, y: 12)
    }

    /// Accepte indifféremment une année (1998) ou un âge (28), comme l'éditeur.
    private func saveYear(for entry: BirthdayEntry) {
        guard let birthYear = BirthdayDateCalculator.birthYear(
            fromInput: yearDraft,
            month: entry.month,
            day: entry.day
        ) else {
            // Une saisie incomprise fermait la fenêtre sans rien enregistrer
            // ni rien signaler : l'utilisateur croyait l'année ajoutée.
            yearError = true
            return
        }

        store.updateEntry(id: entry.id) { $0.birthYear = birthYear }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Sur la fiche, « Âge » doit dire l'âge d'aujourd'hui. L'âge à venir
    /// figure sous la date, où il ne peut pas être pris pour l'âge actuel.
    private func ageValue(_ age: Int, occurrence: BirthdayOccurrence) -> String {
        occurrence.daysUntil == 0 ? "\(age) ans aujourd’hui" : "\(age) ans"
    }

    private func heroDateLine(_ occurrence: BirthdayOccurrence) -> String {
        var value = occurrence.date.formatted(
            Date.FormatStyle().weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_CH"))
        )
        if let turning = occurrence.turningAge, occurrence.daysUntil > 0 {
            value += " · \(turning) ans"
        }
        return value
    }

    private func countdownLabel(_ occurrence: BirthdayOccurrence) -> String {
        switch occurrence.daysUntil {
        case 0: "C’EST AUJOURD’HUI"
        case 1: "DEMAIN"
        default: "DANS \(occurrence.daysUntil) JOURS"
        }
    }

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: BirthdayTheme.Spacing.sm) {
            Text(title)
                .font(.birthdaySection)
                .tracking(1.5)
                .foregroundStyle(BirthdayTheme.Palette.secondaryText)
            content()
        }
    }

    /// Les actions courantes étaient absentes de la fiche : seule la
    /// suppression y figurait. Elles passent devant, à portée de pouce.
    private func quickActions(_ entry: BirthdayEntry, occurrence: BirthdayOccurrence) -> some View {
        HStack(spacing: BirthdayTheme.Spacing.sm) {
            actionButton("Message", icon: "paperplane.fill", highlighted: true) {
                showGreeting = true
            }
            actionButton(
                entry.isFavorite ? "Favori" : "Favori",
                icon: entry.isFavorite ? "star.fill" : "star",
                tinted: entry.isFavorite
            ) {
                UISelectionFeedbackGenerator().selectionChanged()
                store.toggleFavorite(entry)
            }
            actionButton("Modifier", icon: "pencil") { onEdit(entry) }
            ShareLink(item: shareText(entry, occurrence: occurrence)) {
                actionLabel("Partager", icon: "square.and.arrow.up")
            }
            .buttonStyle(SharpPressStyle())
        }
        .sheet(isPresented: $showGreeting) {
            GreetingPickerView(occurrence: occurrence)
        }
    }

    private func actionButton(
        _ title: String,
        icon: String,
        highlighted: Bool = false,
        tinted: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            actionLabel(title, icon: icon, highlighted: highlighted, tinted: tinted)
        }
        .buttonStyle(SharpPressStyle())
    }

    private func actionLabel(
        _ title: String,
        icon: String,
        highlighted: Bool = false,
        tinted: Bool = false
    ) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(
            highlighted ? Color.white
                : (tinted ? BirthdayTheme.Palette.hot : BirthdayTheme.Palette.text)
        )
        .frame(maxWidth: .infinity, minHeight: 60)
        .background {
            if highlighted {
                RoundedRectangle(cornerRadius: BirthdayTheme.Radius.control, style: .continuous)
                    .fill(BirthdayTheme.Palette.actionGradient)
            } else {
                RoundedRectangle(cornerRadius: BirthdayTheme.Radius.control, style: .continuous)
                    .fill(BirthdayTheme.Palette.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: BirthdayTheme.Radius.control, style: .continuous)
                            .strokeBorder(BirthdayTheme.Palette.line, lineWidth: 1)
                    }
            }
        }
    }

    private func shareText(_ entry: BirthdayEntry, occurrence: BirthdayOccurrence) -> String {
        let date = occurrence.date.formatted(
            Date.FormatStyle().day().month(.wide).locale(Locale(identifier: "fr_CH"))
        )
        return "L’anniversaire de \(entry.name), c’est le \(date) 🎂"
    }

    private func groupChips(_ entry: BirthdayEntry) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if store.groups.isEmpty {
                    Button { showGroupManager = true } label: {
                        Label("Créer un groupe", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(BirthdayTheme.Palette.accent)
                } else {
                    ForEach(store.groups) { group in
                        groupChip(group, isSelected: entry.groupIDs.contains(group.id)) {
                            toggleGroup(group.id, for: entry)
                        }
                    }
                    Button { showGroupManager = true } label: {
                        Image(systemName: "plus")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(BirthdayTheme.Palette.secondaryText)
                            .frame(width: 36, height: 36)
                            .background(BirthdayTheme.Palette.surface)
                            .clipShape(Circle())
                            .overlay { Circle().strokeBorder(BirthdayTheme.Palette.line, lineWidth: 1) }
                    }
                    .accessibilityLabel("Gérer les groupes")
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
        .sheet(isPresented: $showGroupManager) {
            GroupManagerView().environmentObject(store)
        }
    }

    private func groupChip(_ group: BirthdayGroup, isSelected: Bool, action: @escaping () -> Void) -> some View {
        let color = Color(hexString: group.colorHex)
        return Button(action: action) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(group.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(isSelected ? color.opacity(0.16) : BirthdayTheme.Palette.surface)
            .clipShape(Capsule())
            .overlay {
                Capsule().strokeBorder(isSelected ? color : BirthdayTheme.Palette.line, lineWidth: 1)
            }
            .foregroundStyle(isSelected ? color : BirthdayTheme.Palette.secondaryText)
        }
        .buttonStyle(SharpPressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func toggleGroup(_ groupID: UUID, for entry: BirthdayEntry) {
        UISelectionFeedbackGenerator().selectionChanged()
        store.updateEntry(id: entry.id) { current in
            if let index = current.groupIDs.firstIndex(of: groupID) {
                current.groupIDs.remove(at: index)
            } else {
                current.groupIDs.append(groupID)
            }
        }
    }

    private func information(_ entry: BirthdayEntry) -> some View {
        VStack(spacing: 0) {
            infoRow("Date", value: formattedDate(entry))
            Divider().overlay(BirthdayTheme.Palette.line)
            if let age = BirthdayDateCalculator.occurrence(for: entry).currentAge {
                infoRow("Âge", value: ageValue(age, occurrence: BirthdayDateCalculator.occurrence(for: entry)))
            } else {
                // Une valeur vide n'apprend rien : la ligne devient l'action
                // qui permet justement de la remplir, sur place.
                Button {
                    yearDraft = ""
                    showYearPrompt = true
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text("ÂGE")
                            .font(.caption2.weight(.bold))
                            .tracking(0.8)
                            .foregroundStyle(BirthdayTheme.Palette.secondaryText)
                        Spacer()
                        Label("Ajouter l’année", systemImage: "plus.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BirthdayTheme.Palette.accent)
                    }
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Divider().overlay(BirthdayTheme.Palette.line)
            // Consultable mais pas modifiable : la ligne conduit maintenant
            // là où le réglage se change.
            Button { onEdit(entry) } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text("RAPPELS")
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(BirthdayTheme.Palette.secondaryText)
                    Spacer()
                    Text(reminderSummary(entry))
                        .foregroundStyle(BirthdayTheme.Palette.text)
                    Image(systemName: "chevron.right")
                        .font(.caption2.bold())
                        .foregroundStyle(BirthdayTheme.Palette.secondaryText)
                }
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, BirthdayTheme.Spacing.md)
        .background(BirthdayTheme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: BirthdayTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BirthdayTheme.Radius.card, style: .continuous)
                .strokeBorder(BirthdayTheme.Palette.line, lineWidth: 1)
        }
    }

    private func infoRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(BirthdayTheme.Palette.secondaryText)
            Spacer()
            Text(value)
                .foregroundStyle(BirthdayTheme.Palette.text)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 14)
    }


    private func formattedDate(_ entry: BirthdayEntry) -> String {
        let year = entry.birthYear ?? 2000
        let date = BirthdayDateCalculator.date(year: year, month: entry.month, day: entry.day)
        let locale = Locale(identifier: "fr_CH")
        if entry.birthYear == nil {
            return date.formatted(
                Date.FormatStyle().day().month(.wide).locale(locale)
            )
        }
        return date.formatted(
            Date.FormatStyle().day().month(.wide).year().locale(locale)
        )
    }

    /// La fiche indique seulement d'où viennent les rappels ; le détail des
    /// délais se règle dans l'éditeur et n'a pas à encombrer la lecture.
    private func reminderSummary(_ entry: BirthdayEntry) -> String {
        let settings = entry.reminderSettings(defaults: store.defaultReminders)
        guard !settings.enabledOffsets.isEmpty else { return "Désactivés" }
        return entry.customReminders == nil ? "Par défaut" : "Personnalisés"
    }
}
