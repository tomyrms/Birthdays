import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WidgetKit

struct BirthdayHomeView: View {
    @EnvironmentObject private var store: BirthdayStore
    @EnvironmentObject private var notificationRouter: NotificationRouter
    @ObservedObject private var launchCelebration = LaunchCelebration.shared
    @AppStorage(BirthdayAccent.storageKey) private var accentHex = BirthdayAccent.defaultHex
    @AppStorage(BirthdayAppIcon.storageKey) private var selectedAppIconName = BirthdayAppIcon.defaultValue.rawValue

    @State private var query = ""
    @State private var selectedGroupID: UUID?
    @State private var favoritesOnly = false
    @State private var selectedEntry: BirthdayEntry?
    @State private var editorPresentation: BirthdayEditorPresentation?
    @State private var showAddMenu = false
    @State private var showGroups = false
    @State private var showReminders = false
    @State private var showAppearance = false
    @State private var showContactPicker = false
    @State private var showCalendarImport = false
    @State private var showICSImporter = false
    @State private var isSearchExpanded = false
    @State private var icsImportPayload: ICSImportPayload?
    @State private var showFileExporter = false
    @State private var exportDocument = ICSFileDocument(text: "")
    @State private var statusMessage: String?
    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var confirmBulkDelete = false
    @State private var entryPendingDelete: BirthdayEntry?
    @State private var showBackupExporter = false
    @State private var showBackupImporter = false
    @State private var backupDocument = BackupFileDocument(data: Data())
    @State private var restorePlan: BackupRestorePlan?
    @State private var undoBanner: UndoBanner?
    @State private var undoDismissTask: Task<Void, Never>?
    @State private var notificationsDenied = false
    @State private var greetingOccurrence: BirthdayOccurrence?
    @State private var contactSuggestions: [BirthdayEntry] = []
    @State private var canForceCalendarExport = false
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var searchIsFocused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var heroCountdownSize: CGFloat = 50

    private var visibleEntries: [BirthdayEntry] {
        store.entries.filter { entry in
            let groupMatches = selectedGroupID.map { entry.groupIDs.contains($0) } ?? true
            let favoriteMatches = !favoritesOnly || entry.isFavorite
            let searchMatches = query.isEmpty
                || entry.name.localizedCaseInsensitiveContains(query)
                || entry.note.localizedCaseInsensitiveContains(query)
                || groupNames(for: entry).contains { $0.localizedCaseInsensitiveContains(query) }
            return groupMatches && favoriteMatches && searchMatches
        }
    }

    private func groupNames(for entry: BirthdayEntry) -> [String] {
        store.groups.filter { entry.groupIDs.contains($0.id) }.map(\.name)
    }

    private func makeSections(from occurrences: [BirthdayOccurrence]) -> [OccurrenceSection] {
        var result: [OccurrenceSection] = []
        for occurrence in occurrences.dropFirst() {
            let title = BirthdayDateCalculator.sectionTitle(for: occurrence)
            if result.last?.title == title {
                result[result.count - 1].occurrences.append(occurrence)
            } else {
                result.append(OccurrenceSection(title: title, occurrences: [occurrence]))
            }
        }
        return result
    }

    private var selectedGroup: BirthdayGroup? {
        guard let selectedGroupID else { return nil }
        return store.groups.first { $0.id == selectedGroupID }
    }

    private var selectedEntries: [BirthdayEntry] {
        store.entries.filter { selectedIDs.contains($0.id) }
    }

    private var isPresentingOverlay: Bool {
        editorPresentation != nil
            || selectedEntry != nil
            || showAddMenu
            || showGroups
            || showReminders
            || showAppearance
            || showContactPicker
            || showCalendarImport
            || showICSImporter
            || icsImportPayload != nil
            || showFileExporter
            || statusMessage != nil
            || greetingOccurrence != nil
            || restorePlan != nil
            || showBackupExporter
            || showBackupImporter
    }

    var body: some View {
        let currentEntries = visibleEntries
        let currentOccurrences = BirthdayDateCalculator.sortedOccurrences(for: currentEntries)
        let currentSections = makeSections(from: currentOccurrences)

        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: BirthdayTheme.Spacing.lg) {
                    if !isSelecting {
                        homeHeader
                        if let saveError = store.lastSaveError { saveErrorBanner(saveError) }
                        if notificationsDenied { notificationsDisabledBanner }
                        if !contactSuggestions.isEmpty { contactSuggestionBanner }
                    }

                    if currentEntries.isEmpty {
                        emptyState
                    } else {
                        if let featuredOccurrence = currentOccurrences.first {
                            featuredCard(
                                featuredOccurrence,
                                isSelecting: isSelecting,
                                isSelected: selectedIDs.contains(featuredOccurrence.entry.id)
                            )
                        }
                        listHeading(occurrenceCount: currentOccurrences.count)
                        ForEach(currentSections) { section in
                            Section {
                                BirthdayRowsGroup(
                                    section: section,
                                    isSelecting: isSelecting,
                                    selectedIDs: selectedIDs,
                                    onEdit: requestEdit,
                                    onDelete: requestDelete,
                                    onGreet: { greetingOccurrence = $0 },
                                    onToggleFavorite: { store.toggleFavorite($0) },
                                    onStartSelection: { beginSelecting(with: $0.id) }
                                ) { entry in
                                    if isSelecting {
                                        toggleSelection(entry.id)
                                    } else {
                                        selectedEntry = entry
                                    }
                                }
                            } header: {
                                BirthdayMonthHeader(title: section.title)
                            }
                        }
                    }
                }
                .padding(.horizontal, BirthdayTheme.Spacing.md)
                .padding(.top, BirthdayTheme.Spacing.sm)
                .padding(.bottom, BirthdayTheme.Spacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .birthdayScreenBackground(isAnimated: !isPresentingOverlay)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top) {
                if isSelecting {
                    selectionHeader(allIDs: currentOccurrences.map { $0.entry.id })
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if let undoBanner {
                        undoBannerView(undoBanner)
                    }
                    if isSelecting {
                        selectionDock
                    } else {
                        bottomDock
                    }
                }
            }
            // Les couleurs du design system sont calculées depuis UserDefaults.
            // Cette identité ne remonte que la couche visuelle quand la teinte
            // change, sans perdre les états de navigation ou de présentation.
            .id(BirthdayAccent.sanitized(accentHex))
            .sheet(item: $editorPresentation) { presentation in
                BirthdayEditorView(entry: presentation.entry) { saved in
                    store.upsert(saved)
                }
                .environmentObject(store)
            }
            .sheet(item: $selectedEntry) { entry in
                BirthdayDetailView(entryID: entry.id) { entry in
                    selectedEntry = nil
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 220_000_000)
                        editorPresentation = BirthdayEditorPresentation(entry: entry)
                    }
                }
                .environmentObject(store)
            }
            .sheet(isPresented: $showGroups) {
                GroupManagerView().environmentObject(store)
            }
            .sheet(isPresented: $showReminders) {
                GlobalRemindersView().environmentObject(store)
            }
            .sheet(isPresented: $showAppearance) {
                AppearanceSettingsView()
            }
            .sheet(isPresented: $showAddMenu) { addSourceSheet }
            .sheet(item: $greetingOccurrence) { occurrence in
                GreetingPickerView(occurrence: occurrence)
            }
            .sheet(isPresented: $showContactPicker) {
                ContactBirthdayPicker { entries in
                    let count = store.importEntries(entries)
                    ContactSyncService.isEnabled = true
                    statusMessage = importMessage(count)
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showCalendarImport) {
                CalendarImportView { entries in
                    let count = store.importEntries(entries)
                    statusMessage = importMessage(count)
                }
            }
            .sheet(item: $icsImportPayload) { payload in
                ICSImportReviewView(payload: payload) { entries in
                    let count = store.importEntries(entries)
                    statusMessage = importMessage(count)
                }
            }
            .fileImporter(
                isPresented: $showICSImporter,
                allowedContentTypes: [.calendarEvent]
            ) { result in
                switch result {
                case .success(let url): importICSFile(at: url)
                case .failure(let error): statusMessage = error.localizedDescription
                }
            }
            .fileExporter(
                isPresented: $showFileExporter,
                document: exportDocument,
                contentType: .calendarEvent,
                defaultFilename: "Anniversaires"
            ) { result in
                if case .failure = result { statusMessage = "L’export a été annulé ou a échoué." }
            }
            .fileExporter(
                isPresented: $showBackupExporter,
                document: backupDocument,
                contentType: .json,
                defaultFilename: backupFilename
            ) { result in
                switch result {
                case .success: statusMessage = "Sauvegarde enregistrée."
                case .failure: statusMessage = "La sauvegarde a été annulée ou a échoué."
                }
            }
            .fileImporter(
                isPresented: $showBackupImporter,
                allowedContentTypes: [.json]
            ) { result in
                switch result {
                case .success(let url): prepareRestore(from: url)
                case .failure(let error): statusMessage = error.localizedDescription
                }
            }
            .confirmationDialog(
                restorePlan.map { "Restaurer \($0.incomingCount) personne\($0.incomingCount > 1 ? "s" : "") ?" } ?? "",
                isPresented: restorePlanBinding,
                titleVisibility: .visible,
                presenting: restorePlan
            ) { plan in
                Button("Remplacer mes \(plan.currentCount) date\(plan.currentCount > 1 ? "s" : "")", role: .destructive) {
                    applyRestore(plan, replacing: true)
                }
                Button("Ajouter sans rien écraser") {
                    applyRestore(plan, replacing: false)
                }
            } message: { plan in
                Text("Sauvegarde du \(plan.archive.exportedAt.formatted(date: .abbreviated, time: .shortened)) · \(plan.archive.summary)")
            }
            .alert("Birthdays", isPresented: statusBinding) {
                // Si les événements ont été supprimés du calendrier à la main,
                // notre mémoire d'export devient fausse : il faut pouvoir la
                // remettre à zéro plutôt que rester bloqué.
                if canForceCalendarExport {
                    Button("Exporter quand même") {
                        CalendarExportService.forgetExports()
                        exportToCalendar()
                    }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text(statusMessage ?? "")
            }
            .confirmationDialog(
                entryPendingDelete.map { "Supprimer \($0.name) ?" } ?? "",
                isPresented: entryPendingDeleteBinding,
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) { confirmDeleteEntry() }
            }
            .onOpenURL(perform: handleDeepLink)
            .onChange(of: currentEntries.map(\.id)) { _, visibleIDs in
                // Sélectionner puis filtrer laisserait des fiches cochées hors
                // écran : une suppression groupée en emporterait sans qu'elles
                // soient visibles. La sélection est ramenée au visible.
                guard isSelecting else { return }
                let visible = Set(visibleIDs)
                guard !selectedIDs.isSubset(of: visible) else { return }
                selectedIDs.formIntersection(visible)
            }
            .task {
                synchronizeSelectedAppIcon()
                await refreshNotificationStatus()
                await scanContacts()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                synchronizeSelectedAppIcon()
                Task {
                    await refreshNotificationStatus()
                    await scanContacts()
                }
            }
            .onChange(of: notificationRouter.pendingAddRequest) { _, requested in
                guard requested else { return }
                notificationRouter.pendingAddRequest = false
                editorPresentation = BirthdayEditorPresentation(entry: nil)
            }
            .onChange(of: notificationRouter.pendingBirthdayID) { _, id in
                guard let id, let entry = store.entry(id: id) else { return }
                selectedEntry = entry
                notificationRouter.pendingBirthdayID = nil
            }
        }
        .overlay {
            if launchCelebration.isActive {
                ConfettiView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
    }

    private var homeHeader: some View {
        HStack(spacing: 11) {
            Image(selectedAppIcon.previewAssetName)
                .resizable()
                .scaledToFill()
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Birthdays")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(BirthdayTheme.Palette.text)
                Text("Votre cercle · \(store.entries.count) date\(store.entries.count > 1 ? "s" : "")")
                    .font(.caption)
                    .foregroundStyle(BirthdayTheme.Palette.secondaryText)
            }
            Spacer(minLength: BirthdayTheme.Spacing.sm)
            headerButton(icon: "bell") { showReminders = true }
                .accessibilityLabel("Rappels")
            Menu { exportMenu } label: {
                headerButtonLabel(icon: "ellipsis")
            }
            .accessibilityLabel("Plus d’options")
        }
    }

    private var selectedAppIcon: BirthdayAppIcon {
        BirthdayAppIcon(rawValue: selectedAppIconName) ?? .defaultValue
    }

    private func synchronizeSelectedAppIcon() {
        guard let currentIcon = AppIconService.currentIcon,
              selectedAppIconName != currentIcon.rawValue else { return }
        selectedAppIconName = currentIcon.rawValue
    }

    private func selectionHeader(allIDs: [UUID]) -> some View {
        HStack(spacing: 11) {
            Button("Annuler") { endSelecting() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BirthdayTheme.Palette.accent)
            Spacer()
            Text(selectedIDs.isEmpty ? "Sélection" : "\(selectedIDs.count) sélectionné\(selectedIDs.count > 1 ? "s" : "")")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(BirthdayTheme.Palette.text)
            Spacer()
            Button(selectedIDs.count == allIDs.count && !allIDs.isEmpty ? "Aucun" : "Tout") {
                toggleSelectAll(allIDs: allIDs)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(BirthdayTheme.Palette.accent)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(BirthdayTheme.Palette.line.opacity(0.8), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 6)
        .padding(.horizontal, BirthdayTheme.Spacing.md)
        .padding(.bottom, 6)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var contactSuggestionBanner: some View {
        let count = contactSuggestions.count
        return HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(BirthdayTheme.Palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count) nouvel\(count > 1 ? "s" : "") anniversaire\(count > 1 ? "s" : "") dans Contacts")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BirthdayTheme.Palette.text)
                Text(contactSuggestions.prefix(3).map(\.name).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(BirthdayTheme.Palette.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(spacing: 2) {
                Button("Ajouter") { addContactSuggestions() }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BirthdayTheme.Palette.accent)
                Button("Ignorer") { ignoreContactSuggestions() }
                    .font(.caption)
                    .foregroundStyle(BirthdayTheme.Palette.secondaryText)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BirthdayTheme.Palette.accent.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(BirthdayTheme.Palette.accent.opacity(0.28), lineWidth: 1)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// Un échec d'enregistrement était stocké sans jamais être montré :
    /// l'utilisateur croyait sa modification enregistrée alors qu'elle était
    /// perdue. Le bandeau disparaît de lui-même au prochain succès.
    private func saveErrorBanner(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(BirthdayTheme.Palette.destructive)
            VStack(alignment: .leading, spacing: 2) {
                Text(message)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BirthdayTheme.Palette.text)
                Text("Vérifiez l’espace disponible sur l’appareil.")
                    .font(.caption)
                    .foregroundStyle(BirthdayTheme.Palette.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BirthdayTheme.Palette.destructive.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(BirthdayTheme.Palette.destructive.opacity(0.30), lineWidth: 1)
        }
    }

    private var notificationsDisabledBanner: some View {
        Button {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bell.slash.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(BirthdayTheme.Palette.hot)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Les rappels n’arriveront pas")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(BirthdayTheme.Palette.text)
                    Text("Les notifications sont refusées pour Birthdays.")
                        .font(.caption)
                        .foregroundStyle(BirthdayTheme.Palette.secondaryText)
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
        .accessibilityHint("Ouvre les réglages iOS pour autoriser les notifications")
    }

    private func featuredCard(_ occurrence: BirthdayOccurrence, isSelecting: Bool, isSelected: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? BirthdayTheme.Palette.accent : BirthdayTheme.Palette.secondaryText.opacity(0.5))
                    .padding(.top, 6)
                    .transition(.scale.combined(with: .opacity))
            }
            featuredCardContent(occurrence, isSelecting: isSelecting, isSelected: isSelected)
        }
    }

    private func featuredCardContent(_ occurrence: BirthdayOccurrence, isSelecting: Bool, isSelected: Bool) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Button {
                if isSelecting {
                    toggleSelection(occurrence.entry.id)
                } else {
                    selectedEntry = occurrence.entry
                }
            } label: {
                ZStack(alignment: .topTrailing) {
                    BirthdayHeroBackground(entry: occurrence.entry)
                    if occurrence.entry.avatarStyle == .photo, occurrence.entry.photoData != nil {
                        BirthdayMemoryLensView(entry: occurrence.entry)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top) {
                            Text(occurrence.daysUntil == 0 ? "AUJOURD’HUI" : "PROCHAIN")
                                .font(.caption.weight(.bold))
                                .tracking(1.2)
                                .foregroundStyle(.white.opacity(0.72))
                            Spacer()
                            // Sur la carte vedette on ne montre que la photo ou
                            // l'emoji : une pastille d'initiales n'apporte rien
                            // qu'on ne lise déjà dans le nom, juste un carré de
                            // couleur en plus. L'emoji est posé nu, sans cadre.
                            if let emoji = featuredEmoji(occurrence.entry) {
                                if occurrence.entry.isFavorite {
                                    Image(systemName: "star.fill")
                                        .font(.caption)
                                        .foregroundStyle(BirthdayTheme.Palette.hot)
                                        .padding(.top, 5)
                                        .accessibilityLabel("Favori")
                                }
                                Text(emoji)
                                    .font(.system(size: 42))
                                    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                            }
                        }
                        Spacer(minLength: 12)
                        // « 00 JOUR » le jour J n'avait pas de sens : ce compte à
                        // rebours cède la place à un message le jour même.
                        if occurrence.daysUntil == 0 {
                            Text("Joyeux anniversaire ! 🎉")
                                .font(.system(size: heroCountdownSize * 0.44, weight: .black, design: .rounded))
                                .foregroundStyle(BirthdayTheme.Palette.hot)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        } else {
                            HStack(alignment: .lastTextBaseline, spacing: 7) {
                                Text(String(format: "%02d", occurrence.daysUntil))
                                    .font(.system(size: heroCountdownSize, weight: .black, design: .rounded))
                                    .monospacedDigit()
                                Text(occurrence.daysUntil == 1 ? "JOUR" : "JOURS")
                                    .font(.caption.weight(.bold))
                                    .tracking(1)
                                    .padding(.bottom, 7)
                                    .foregroundStyle(.white.opacity(0.65))
                            }
                            .foregroundStyle(occurrence.daysUntil <= 7 ? BirthdayTheme.Palette.hot : .white)
                        }
                        Text(occurrence.entry.name)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.trailing, occurrence.entry.avatarStyle == .photo ? 116 : 0)
                        Text(featuredMeta(occurrence))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.68))
                            .lineLimit(1)
                            .padding(.top, 2)
                            .padding(.trailing, occurrence.entry.avatarStyle == .photo ? 120 : 56)
                    }
                    .padding(20)
                }
                .frame(minHeight: 190)
                .clipShape(RoundedRectangle(cornerRadius: BirthdayTheme.Radius.hero, style: .continuous))
                .background {
                    if occurrence.daysUntil == 0 {
                        BirthdayTodayCardGlow(cornerRadius: BirthdayTheme.Radius.hero)
                    }
                }
                .shadow(color: BirthdayTheme.Palette.accent.opacity(0.22), radius: 20, x: 0, y: 11)            .overlay(alignment: .topTrailing) {
                if occurrence.entry.isFavorite, featuredEmoji(occurrence.entry) == nil {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(BirthdayTheme.Palette.hot)
                        .padding(13)
                        .accessibilityLabel("Favori")
                }
            }
            }
            .buttonStyle(SharpPressStyle())
            .accessibilityLabel(featuredAccessibilityLabel(occurrence))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .contextMenu {
                if !isSelecting {
                    Button { greetingOccurrence = occurrence } label: {
                        Label("Envoyer un message", systemImage: "paperplane")
                    }
                    Button { store.toggleFavorite(occurrence.entry) } label: {
                        Label(
                            occurrence.entry.isFavorite ? "Retirer des favoris" : "Mettre en favori",
                            systemImage: occurrence.entry.isFavorite ? "star.slash" : "star"
                        )
                    }
                    Button { requestEdit(occurrence.entry) } label: {
                        Label("Modifier", systemImage: "pencil")
                    }
                    Divider()
                    Button { beginSelecting(with: occurrence.entry.id) } label: {
                        Label("Sélectionner", systemImage: "checkmark.circle")
                    }
                    Button(role: .destructive) { requestDelete(occurrence.entry) } label: {
                        Label("Supprimer", systemImage: "trash")
                    }
                }
            }

            if !isSelecting {
                Button { greetingOccurrence = occurrence } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                        }
                }
                .buttonStyle(SharpPressStyle())
                .padding(14)
                .accessibilityLabel("Préparer un message pour \(occurrence.entry.name)")
            }
        }
    }

    private func listHeading(occurrenceCount: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: BirthdayTheme.Spacing.sm) {
            Text(query.isEmpty ? "À venir" : "Résultats")
                .font(.title3.weight(.bold))
                .foregroundStyle(BirthdayTheme.Palette.text)
            if let selectedGroup {
                Text(selectedGroup.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(hexString: selectedGroup.colorHex))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hexString: selectedGroup.colorHex).opacity(0.11))
                    .clipShape(Capsule())
            }
            Spacer()
            Text("\(max(0, occurrenceCount - 1)) ensuite")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(BirthdayTheme.Palette.secondaryText)
        }
    }

    private var bottomDock: some View {
        HStack(spacing: BirthdayTheme.Spacing.sm) {
            if isSearchExpanded {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(BirthdayTheme.Palette.secondaryText)
                TextField("Rechercher une personne", text: $query)
                    .focused($searchIsFocused)
                    .textInputAutocapitalization(.words)
                    .font(.body)
                    .submitLabel(.search)
                Button { closeSearch() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(BirthdayTheme.Palette.secondaryText)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Fermer la recherche")
            } else {
                Button { openSearch() } label: {
                    dockButtonLabel(icon: "magnifyingglass", title: "Rechercher")
                }
                .buttonStyle(SharpPressStyle())

                Menu { filterMenu } label: {
                    dockButtonLabel(
                        icon: "line.3.horizontal.decrease",
                        title: selectedGroup?.name ?? (favoritesOnly ? "Favoris" : "Tout")
                    )
                }
                .accessibilityLabel("Filtrer les anniversaires")
                Spacer(minLength: 0)
            }

            Button { openAddMenu() } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(BirthdayTheme.Palette.actionGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: BirthdayTheme.Palette.accent.opacity(0.28), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(SharpPressStyle())
            .accessibilityLabel("Ajouter un anniversaire")
        }
        .padding(7)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .strokeBorder(BirthdayTheme.Palette.line.opacity(0.8), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.15), radius: 18, x: 0, y: 8)
        .padding(.horizontal, BirthdayTheme.Spacing.md)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .animation(.easeOut(duration: 0.18), value: isSearchExpanded)
    }

    private func undoBannerView(_ banner: UndoBanner) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BirthdayTheme.Palette.secondaryText)
            Text(banner.message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(BirthdayTheme.Palette.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button("Annuler") { performUndo() }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(BirthdayTheme.Palette.accent)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(BirthdayTheme.Palette.line.opacity(0.8), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 14, x: 0, y: 6)
        .padding(.horizontal, BirthdayTheme.Spacing.md)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var selectionDock: some View {
        HStack(spacing: BirthdayTheme.Spacing.sm) {
            Menu {
                if store.groups.isEmpty {
                    Text("Aucun groupe")
                } else {
                    ForEach(store.groups) { group in
                        Button { bulkAddToGroup(group.id) } label: {
                            Label(group.name, systemImage: "person.2")
                        }
                    }
                }
            } label: {
                dockButtonLabel(icon: "person.2", title: "Groupe")
            }
            .disabled(selectedIDs.isEmpty || store.groups.isEmpty)
            .opacity(selectedIDs.isEmpty ? 0.5 : 1)

            ShareLink(item: ICSExporter.calendar(entries: selectedEntries, defaults: store.defaultReminders)) {
                dockButtonLabel(icon: "square.and.arrow.up", title: "Partager")
            }
            .disabled(selectedIDs.isEmpty)
            .opacity(selectedIDs.isEmpty ? 0.5 : 1)

            Spacer(minLength: 0)

            Button(role: .destructive) { confirmBulkDelete = true } label: {
                Image(systemName: "trash")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(selectedIDs.isEmpty ? AnyShapeStyle(BirthdayTheme.Palette.secondaryText.opacity(0.35)) : AnyShapeStyle(BirthdayTheme.Palette.destructive))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(SharpPressStyle())
            .disabled(selectedIDs.isEmpty)
            .accessibilityLabel("Supprimer la sélection")
        }
        .padding(7)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .strokeBorder(BirthdayTheme.Palette.line.opacity(0.8), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.15), radius: 18, x: 0, y: 8)
        .padding(.horizontal, BirthdayTheme.Spacing.md)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .confirmationDialog(
            "Supprimer \(selectedIDs.count) anniversaire\(selectedIDs.count > 1 ? "s" : "") ?",
            isPresented: $confirmBulkDelete,
            titleVisibility: .visible
        ) {
            Button("Supprimer \(selectedIDs.count) anniversaire\(selectedIDs.count > 1 ? "s" : "")", role: .destructive) {
                bulkDelete()
            }
        }
    }

    private func dockButtonLabel(icon: String, title: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(BirthdayTheme.Palette.text)
        .padding(.horizontal, 11)
        .frame(minHeight: 44)
        .background(BirthdayTheme.Palette.surface.opacity(0.76))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    @ViewBuilder
    private var filterMenu: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.easeOut(duration: 0.16)) { favoritesOnly.toggle() }
        } label: {
            Label("Favoris uniquement", systemImage: favoritesOnly ? "checkmark" : "star")
        }
        Divider()
        Button { selectGroup(nil) } label: {
            Label("Tout", systemImage: selectedGroupID == nil ? "checkmark" : "circle")
        }
        ForEach(store.groups) { group in
            Button { selectGroup(group.id) } label: {
                Label(group.name, systemImage: selectedGroupID == group.id ? "checkmark" : "circle")
            }
        }
        Divider()
        Button { showGroups = true } label: {
            Label("Gérer les groupes", systemImage: "slider.horizontal.3")
        }
    }

    private var emptyState: some View {
        let libraryIsEmpty = store.entries.isEmpty
        return VStack(spacing: 14) {
            BirthdayBrandMark(size: 62)
                .padding(.bottom, 4)
            Text(libraryIsEmpty ? "Votre cercle commence ici" : "Aucun résultat")
                .font(.title2.weight(.bold))
                .foregroundStyle(BirthdayTheme.Palette.text)
            Text(libraryIsEmpty
                 ? "Ajoutez les personnes qui comptent. Birthdays gardera le rythme pour vous."
                 : "Essayez un autre nom ou choisissez un autre groupe.")
                .font(.body)
                .foregroundStyle(BirthdayTheme.Palette.secondaryText)
                .multilineTextAlignment(.center)
            if libraryIsEmpty {
                Button("Ajouter une première date") { openAddMenu() }
                    .buttonStyle(.borderedProminent)
                    .tint(BirthdayTheme.Palette.accent)
                    .controlSize(.large)
                    .padding(.top, 6)
            } else if hasActiveFilter {
                // Le bouton de sortie ne dépendait que du filtre par groupe :
                // filtrer sur les favoris sans en avoir laissait l'écran sans
                // aucun moyen de revenir en arrière.
                Button("Afficher tout") { clearFilters() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 30)
        .padding(.top, 54)
    }

    private func headerButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { headerButtonLabel(icon: icon) }
            .buttonStyle(SharpPressStyle())
    }

    private func headerButtonLabel(icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(BirthdayTheme.Palette.text)
            .frame(width: 44, height: 44)
            .background(BirthdayTheme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(BirthdayTheme.Palette.line, lineWidth: 1)
            }
    }

    @ViewBuilder
    private var exportMenu: some View {
        Section {
            Button { beginSelecting() } label: {
                Label("Sélectionner", systemImage: "checkmark.circle")
            }
        }
        Section("Personnaliser") {
            Button { showAppearance = true } label: {
                Label("Apparence", systemImage: "circle.lefthalf.filled")
            }
            Button { showGroups = true } label: {
                Label("Gérer les groupes", systemImage: "person.2")
            }
        }
        Section("Sauvegarde") {
            Button { prepareBackupExport() } label: {
                Label("Enregistrer une sauvegarde", systemImage: "arrow.down.doc")
            }
            Button { showBackupImporter = true } label: {
                Label("Restaurer une sauvegarde", systemImage: "arrow.up.doc")
            }
        }
        Section("Partager") {
            Button { prepareFileExport() } label: {
                Label("Exporter un fichier ICS", systemImage: "doc.badge.arrow.up")
            }
            Button { exportToCalendar() } label: {
                Label("Ajouter au calendrier", systemImage: "calendar.badge.plus")
            }
            ShareLink(item: requestMessage) {
                Label("Demander une date", systemImage: "paperplane")
            }
        }
    }

    private var addSourceSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: BirthdayTheme.Spacing.md) {
                HStack(spacing: 12) {
                    BirthdayBrandMark(size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("UNE NOUVELLE DATE")
                            .font(.birthdaySection)
                            .tracking(1.4)
                            .foregroundStyle(BirthdayTheme.Palette.accent)
                        Text("Comment l’ajouter ?")
                            .font(.title2.weight(.bold))
                    }
                    Spacer()
                    Button { showAddMenu = false } label: {
                        Image(systemName: "xmark")
                            .font(.caption.bold())
                            .foregroundStyle(BirthdayTheme.Palette.text)
                            .frame(width: 44, height: 44)
                            .background(BirthdayTheme.Palette.elevated)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .accessibilityLabel("Fermer")
                }
                sourceButton("Ajouter manuellement", subtitle: "Nom, date et rappels", icon: "square.and.pencil", highlighted: true) {
                    showAddMenu = false
                    presentAfterAddMenu {
                        editorPresentation = BirthdayEditorPresentation(entry: nil)
                    }
                }
                sourceButton("Depuis Contacts", subtitle: "Choisir dans votre carnet", icon: "person.crop.circle.badge.plus") {
                    showAddMenu = false
                    presentAfterAddMenu { showContactPicker = true }
                }
                sourceButton("Depuis Calendrier", subtitle: "Détecter les événements annuels", icon: "calendar.badge.plus") {
                    showAddMenu = false
                    presentAfterAddMenu { showCalendarImport = true }
                }
                sourceButton("Depuis un fichier ICS", subtitle: "Ouvrir un calendrier exporté", icon: "doc.badge.plus") {
                    showAddMenu = false
                    presentAfterAddMenu { showICSImporter = true }
                }
                ShareLink(item: requestMessage) {
                    Label("Demander sa date à quelqu’un", systemImage: "paperplane")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BirthdayTheme.Palette.accent)
                        .frame(minHeight: 44)
                }
                Spacer()
            }
            .padding(BirthdayTheme.Spacing.md)
            .birthdayScreenBackground(isAnimated: true)
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.height(600)])
        .presentationCornerRadius(30)
    }

    private func sourceButton(
        _ title: String,
        subtitle: String,
        icon: String,
        highlighted: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(highlighted ? Color.white.opacity(0.16) : BirthdayTheme.Palette.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold))
                    Text(subtitle).font(.caption).opacity(0.68)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .opacity(0.58)
            }
            .foregroundStyle(highlighted ? Color.white : BirthdayTheme.Palette.text)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
            .background(highlighted ? AnyShapeStyle(BirthdayTheme.Palette.actionGradient) : AnyShapeStyle(BirthdayTheme.Palette.surface))
            .clipShape(RoundedRectangle(cornerRadius: BirthdayTheme.Radius.card, style: .continuous))
            .overlay {
                if !highlighted {
                    RoundedRectangle(cornerRadius: BirthdayTheme.Radius.card, style: .continuous)
                        .strokeBorder(BirthdayTheme.Palette.line, lineWidth: 1)
                }
            }
        }
        .buttonStyle(SharpPressStyle())
    }

    /// L'emoji à poser sur la carte vedette, s'il y en a un. Une fiche en
    /// initiales n'en reçoit aucun : rien ne remplace la pastille.
    private func featuredEmoji(_ entry: BirthdayEntry) -> String? {
        guard entry.avatarStyle == .emoji else { return nil }
        let emoji = entry.emoji.trimmingCharacters(in: .whitespaces)
        return emoji.isEmpty ? "🎂" : emoji
    }

    private func featuredMeta(_ occurrence: BirthdayOccurrence) -> String {
        var value = occurrence.date.formatted(
            Date.FormatStyle().weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_CH"))
        )
        if let age = occurrence.turningAge { value += " · \(age) ans" }
        return value
    }

    private func featuredAccessibilityLabel(_ occurrence: BirthdayOccurrence) -> String {
        if occurrence.daysUntil == 0 {
            return "Anniversaire de \(occurrence.entry.name) aujourd’hui"
        }
        return "Prochain anniversaire, \(occurrence.entry.name), dans \(occurrence.daysUntil) jours"
    }


    private var requestMessage: String {
        "Salut ! J’organise mes rappels d’anniversaire. Tu peux me répondre avec ton jour et ton mois de naissance ? 🎈"
    }

    private var statusBinding: Binding<Bool> {
        Binding(get: { statusMessage != nil }, set: { if !$0 { statusMessage = nil } })
    }

    private var entryPendingDeleteBinding: Binding<Bool> {
        Binding(get: { entryPendingDelete != nil }, set: { if !$0 { entryPendingDelete = nil } })
    }

    private func requestEdit(_ entry: BirthdayEntry) {
        editorPresentation = BirthdayEditorPresentation(entry: entry)
    }

    private func requestDelete(_ entry: BirthdayEntry) {
        entryPendingDelete = entry
    }

    private func confirmDeleteEntry() {
        guard let entry = entryPendingDelete else { return }
        presentUndo(store.remove(entry))
        entryPendingDelete = nil
    }

    private func openSearch() {
        withAnimation(.easeOut(duration: 0.18)) { isSearchExpanded = true }
        Task { @MainActor in searchIsFocused = true }
    }

    private func closeSearch() {
        query = ""
        searchIsFocused = false
        withAnimation(.easeOut(duration: 0.18)) { isSearchExpanded = false }
    }

    private var hasActiveFilter: Bool {
        selectedGroupID != nil || favoritesOnly || !query.isEmpty
    }

    private func clearFilters() {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.easeOut(duration: 0.16)) {
            selectedGroupID = nil
            favoritesOnly = false
            query = ""
        }
    }

    private func selectGroup(_ id: UUID?) {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.easeOut(duration: 0.16)) { selectedGroupID = id }
    }

    private func beginSelecting(with id: UUID? = nil) {
        searchIsFocused = false
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        withAnimation(.easeOut(duration: 0.18)) {
            isSelecting = true
            if let id { selectedIDs.insert(id) }
        }
    }

    private func endSelecting() {
        withAnimation(.easeOut(duration: 0.18)) {
            isSelecting = false
            selectedIDs.removeAll()
        }
    }

    private func toggleSelection(_ id: UUID) {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.easeOut(duration: 0.12)) {
            if selectedIDs.contains(id) {
                selectedIDs.remove(id)
            } else {
                selectedIDs.insert(id)
            }
        }
    }

    private func toggleSelectAll(allIDs: [UUID]) {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.easeOut(duration: 0.16)) {
            selectedIDs = selectedIDs.count == allIDs.count ? [] : Set(allIDs)
        }
    }

    private func bulkDelete() {
        let removed = store.remove(ids: selectedIDs)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        endSelecting()
        presentUndo(removed)
    }

    private func bulkAddToGroup(_ groupID: UUID) {
        store.addToGroup(groupID, entryIDs: selectedIDs)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        endSelecting()
    }

    private func openAddMenu() {
        searchIsFocused = false
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        showAddMenu = true
    }

    private func importMessage(_ count: Int) -> String {
        count == 0 ? "Aucun nouvel anniversaire à importer." : "\(count) anniversaire\(count > 1 ? "s" : "") importé\(count > 1 ? "s" : "")."
    }

    private var backupFilename: String {
        "Birthdays-\(Date.now.formatted(.iso8601.year().month().day()))"
    }

    private var restorePlanBinding: Binding<Bool> {
        Binding(get: { restorePlan != nil }, set: { if !$0 { restorePlan = nil } })
    }

    private func scanContacts() async {
        let found = await ContactSyncService.newBirthdays(existing: store.entries)
        withAnimation(.easeOut(duration: 0.25)) { contactSuggestions = found }
    }

    private func addContactSuggestions() {
        let count = store.importEntries(contactSuggestions)
        withAnimation(.easeOut(duration: 0.2)) { contactSuggestions = [] }
        statusMessage = importMessage(count)
    }

    private func ignoreContactSuggestions() {
        ContactSyncService.ignore(contactSuggestions)
        withAnimation(.easeOut(duration: 0.2)) { contactSuggestions = [] }
    }

    private func refreshNotificationStatus() async {
        let authorized = await NotificationScheduler.shared.isAuthorized()
        let hasReminders = !store.entries.isEmpty
        withAnimation(.easeOut(duration: 0.2)) {
            notificationsDenied = !authorized && hasReminders
        }
    }

    private func prepareBackupExport() {
        backupDocument = BackupFileDocument(data: BackupArchive.encoded(from: store.snapshot))
        showBackupExporter = true
    }

    private func prepareRestore(from url: URL) {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer { if accessGranted { url.stopAccessingSecurityScopedResource() } }

        do {
            let archive = try BackupArchive.decoded(from: Data(contentsOf: url))
            let plan = BackupRestorePlan(
                archive: archive,
                filename: url.lastPathComponent,
                currentCount: store.entries.count
            )
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 220_000_000)
                restorePlan = plan
            }
        } catch let error as BackupArchive.RestoreError {
            statusMessage = error.errorDescription
        } catch {
            statusMessage = "Ce fichier n’est pas une sauvegarde Birthdays valide."
        }
    }

    private func applyRestore(_ plan: BackupRestorePlan, replacing: Bool) {
        if replacing {
            store.replaceAll(with: plan.archive.snapshot)
            // Les réglages ne sont rétablis que sur une restauration complète :
            // ajouter des personnes ne doit pas changer l'apparence de l'app.
            plan.archive.preferences?.apply()
            // Ces fiches n'ont jamais été exportées depuis cet appareil :
            // garder l'ancienne mémoire bloquerait tout export.
            CalendarExportService.forgetExports()
            WidgetCenter.shared.reloadAllTimelines()
            statusMessage = "Sauvegarde restaurée · \(plan.archive.summary)"
        } else {
            let added = store.merge(plan.archive.snapshot)
            statusMessage = added == 0
                ? "Tout était déjà présent, rien n’a été ajouté."
                : "\(added) date\(added > 1 ? "s" : "") ajoutée\(added > 1 ? "s" : "")."
        }
        restorePlan = nil
    }

    private func presentUndo(_ removed: [BirthdayEntry]) {
        guard !removed.isEmpty else { return }
        undoDismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            undoBanner = UndoBanner(entries: removed)
        }
        undoDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { undoBanner = nil }
        }
    }

    private func performUndo() {
        guard let banner = undoBanner else { return }
        undoDismissTask?.cancel()
        store.reinsert(banner.entries)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.easeOut(duration: 0.2)) { undoBanner = nil }
    }

    private func prepareFileExport() {
        exportDocument = ICSFileDocument(text: ICSExporter.calendar(entries: store.entries, defaults: store.defaultReminders))
        showFileExporter = true
    }

    private func calendarExportMessage(_ result: CalendarExportResult) -> String {
        if result.added == 0 {
            return result.skipped > 0
                ? "Ces anniversaires sont déjà dans votre calendrier."
                : "Aucun anniversaire à exporter."
        }
        var message = "\(result.added) anniversaire\(result.added > 1 ? "s" : "") ajouté\(result.added > 1 ? "s" : "") au calendrier."
        if result.skipped > 0 {
            message += " \(result.skipped) y étai\(result.skipped > 1 ? "en" : "")t déjà."
        }
        return message
    }

    private func exportToCalendar() {
        Task {
            do {
                let result = try await CalendarExportService.export(store.entries)
                canForceCalendarExport = result.added == 0 && result.skipped > 0
                statusMessage = calendarExportMessage(result)
            } catch {
                canForceCalendarExport = false
                statusMessage = (error as? LocalizedError)?.errorDescription ?? "Export vers Calendrier impossible."
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        if url.isFileURL || url.pathExtension.caseInsensitiveCompare("ics") == .orderedSame {
            importICSFile(at: url)
            return
        }
        guard url.scheme == "birthdays" else { return }
        if url.host == "add" {
            editorPresentation = BirthdayEditorPresentation(entry: nil)
            return
        }
        guard url.host == "birthday",
              let id = UUID(uuidString: url.lastPathComponent),
              let entry = store.entry(id: id) else { return }
        selectedEntry = entry
    }

    private func importICSFile(at url: URL) {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer { if accessGranted { url.stopAccessingSecurityScopedResource() } }

        do {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size <= BirthdayLimits.importFileBytes else {
                throw ICSImportError.unreadableFile
            }
            let entries = try ICSImporter.entries(from: Data(contentsOf: url))
            let payload = ICSImportPayload(filename: url.lastPathComponent, entries: entries)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 220_000_000)
                icsImportPayload = payload
            }
        } catch {
            statusMessage = (error as? LocalizedError)?.errorDescription ?? "Import du fichier ICS impossible."
        }
    }

    private func presentAfterAddMenu(_ action: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            action()
        }
    }
}

struct UndoBanner: Identifiable, Equatable {
    let id = UUID()
    let entries: [BirthdayEntry]

    var message: String {
        entries.count == 1
            ? "\(entries[0].name) supprimé"
            : "\(entries.count) anniversaires supprimés"
    }
}

private struct BirthdayEditorPresentation: Identifiable {
    let id = UUID()
    let entry: BirthdayEntry?
}

struct OccurrenceSection: Identifiable {
    let title: String
    var occurrences: [BirthdayOccurrence]
    var id: String { title }
}

private struct BirthdayMonthHeader: View {
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BirthdayTheme.Palette.text)
            Rectangle()
                .fill(BirthdayTheme.Palette.line)
                .frame(height: 1)
        }
        .padding(.vertical, BirthdayTheme.Spacing.sm)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct BirthdayRowsGroup: View {
    @AppStorage(BirthdayCardStyle.storageKey) private var usesFloatingCards = true
    let section: OccurrenceSection
    let isSelecting: Bool
    let selectedIDs: Set<UUID>
    let onEdit: (BirthdayEntry) -> Void
    let onDelete: (BirthdayEntry) -> Void
    let onGreet: (BirthdayOccurrence) -> Void
    let onToggleFavorite: (BirthdayEntry) -> Void
    let onStartSelection: (BirthdayEntry) -> Void
    let onSelect: (BirthdayEntry) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(section.occurrences) { occurrence in
                Button { onSelect(occurrence.entry) } label: {
                    BirthdayRow(
                        occurrence: occurrence,
                        isSelecting: isSelecting,
                        isSelected: selectedIDs.contains(occurrence.entry.id)
                    )
                }
                .buttonStyle(SharpPressStyle())
                .contextMenu {
                    if !isSelecting {
                        Button { onGreet(occurrence) } label: {
                            Label("Envoyer un message", systemImage: "paperplane")
                        }
                        Button { onToggleFavorite(occurrence.entry) } label: {
                            Label(
                                occurrence.entry.isFavorite ? "Retirer des favoris" : "Mettre en favori",
                                systemImage: occurrence.entry.isFavorite ? "star.slash" : "star"
                            )
                        }
                        Button { onEdit(occurrence.entry) } label: {
                            Label("Modifier", systemImage: "pencil")
                        }
                        Divider()
                        Button { onStartSelection(occurrence.entry) } label: {
                            Label("Sélectionner", systemImage: "checkmark.circle")
                        }
                        Button(role: .destructive) { onDelete(occurrence.entry) } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                    }
                }
                if occurrence.id != section.occurrences.last?.id {
                    Divider()
                        .overlay(BirthdayTheme.Palette.line)
                        .padding(.leading, 58)
                }
            }
        }
        .padding(.horizontal, usesFloatingCards ? 12 : 0)
        .background(usesFloatingCards ? BirthdayTheme.Palette.surface.opacity(0.94) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: usesFloatingCards ? BirthdayTheme.Radius.card : 0, style: .continuous))
        .overlay {
            if usesFloatingCards {
                RoundedRectangle(cornerRadius: BirthdayTheme.Radius.card, style: .continuous)
                    .strokeBorder(BirthdayTheme.Palette.line.opacity(0.84), lineWidth: 1)
            }
        }
        .shadow(color: usesFloatingCards ? Color.black.opacity(0.08) : .clear, radius: 14, x: 0, y: 7)
    }

}

private struct BirthdayRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let occurrence: BirthdayOccurrence
    var isSelecting: Bool = false
    var isSelected: Bool = false

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                standardLayout
            }
        }
        .padding(.vertical, 10)
        .frame(minHeight: 68)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var selectionIndicator: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22))
            .foregroundStyle(isSelected ? BirthdayTheme.Palette.accent : BirthdayTheme.Palette.secondaryText.opacity(0.45))
            .transition(.scale.combined(with: .opacity))
    }

    private var standardLayout: some View {
        HStack(spacing: 12) {
            if isSelecting { selectionIndicator }
            BirthdayAvatarView(entry: occurrence.entry, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(occurrence.entry.name)
                    .appendingFavoriteStar(occurrence.entry.isFavorite, color: BirthdayTheme.Palette.hot, font: .system(size: 9))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(BirthdayTheme.Palette.text)
                    .lineLimit(2)
                Text(meta)
                    .font(.subheadline)
                    .foregroundStyle(BirthdayTheme.Palette.secondaryText)
                    .lineLimit(2)
            }
            Spacer(minLength: BirthdayTheme.Spacing.sm)
            countdownLabel
        }
    }

    private var accessibilityLayout: some View {
        HStack(alignment: .top, spacing: 12) {
            if isSelecting { selectionIndicator }
            BirthdayAvatarView(entry: occurrence.entry, size: 46)
            VStack(alignment: .leading, spacing: 5) {
                Text(occurrence.entry.name)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(BirthdayTheme.Palette.text)
                Text(meta)
                    .font(.subheadline)
                    .foregroundStyle(BirthdayTheme.Palette.secondaryText)
                countdownLabel
            }
            Spacer(minLength: 0)
        }
    }

    private var countdownLabel: some View {
        Text(countdown)
            .font(.title3.monospacedDigit().weight(.bold))
            .foregroundStyle(occurrence.daysUntil <= 7 ? BirthdayTheme.Palette.hot : BirthdayTheme.Palette.text)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var countdown: String {
        occurrence.daysUntil == 0 ? "Jour J" : "\(occurrence.daysUntil) j"
    }

    private var meta: String {
        var value = occurrence.date.formatted(
            Date.FormatStyle().weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_CH"))
        )
        if let age = occurrence.turningAge { value += " · \(age) ans" }
        return value
    }

    private var accessibilityLabel: String {
        let favorite = occurrence.entry.isFavorite ? "Favori, " : ""
        if occurrence.daysUntil == 0 {
            return "\(favorite)\(occurrence.entry.name), \(meta), aujourd’hui"
        }
        return "\(favorite)\(occurrence.entry.name), \(meta), dans \(occurrence.daysUntil) jours"
    }
}
