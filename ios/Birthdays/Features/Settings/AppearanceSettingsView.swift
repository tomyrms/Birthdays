import SwiftUI
import UIKit
import WidgetKit

struct AppearanceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(BirthdayBackgroundStyle.storageKey) private var selectedStyle = BirthdayBackgroundStyle.pastelMesh.rawValue
    @AppStorage(BirthdayBackgroundContext.seasonalTintKey) private var seasonalTintEnabled = true
    @AppStorage(BirthdayHeroTint.storageKey) private var photoTintEnabled = true
    @AppStorage(BirthdayCardStyle.storageKey) private var floatingCards = true
    @AppStorage(BirthdayAccent.storageKey) private var accentHex = BirthdayAccent.defaultHex
    @AppStorage(BirthdayAppIcon.storageKey) private var selectedAppIconName = BirthdayAppIcon.defaultValue.rawValue
    @State private var updatingAppIcon: BirthdayAppIcon?
    @State private var appIconErrorMessage: String?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    appIconSettings

                    accentSettings

                    // Les textures GPU sont la pièce maîtresse : elles ont
                    // droit à de grandes cartes, pas à une case de grille.
                    if !styles(in: .signatureStyles).isEmpty {
                        featuredStyles
                    }

                    ForEach(visibleCategories.filter { $0 != .signatureStyles }) { category in
                        sectionHeader(category.title, subtitle: category.subtitle)
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(styles(in: category)) { style in
                                backgroundChoice(style)
                            }
                        }
                    }

                    contextualSettings
                }
                .padding(16)
            }
            .birthdayScreenBackground(isAnimated: true)
            .navigationTitle("Apparence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Terminé") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            let resolvedStyle = BirthdayBackgroundStyle.resolved(from: selectedStyle)
            if selectedStyle != resolvedStyle.rawValue {
                selectedStyle = resolvedStyle.rawValue
            }
            accentHex = BirthdayAccent.sanitized(accentHex)
            BirthdayAccent.publishToSharedStorage(accentHex)
            if let currentIcon = AppIconService.currentIcon {
                selectedAppIconName = currentIcon.rawValue
            } else {
                // Une ancienne version peut encore référencer une icône qui ne
                // fait plus partie du sélecteur. Aucune option n'est alors
                // cochée jusqu'au prochain choix explicite de l'utilisateur.
                selectedAppIconName = ""
            }
        }
        .onChange(of: accentHex) { _, newValue in
            BirthdayAccent.publishToSharedStorage(newValue)
            WidgetCenter.shared.reloadAllTimelines()
        }
        .alert(
            "Impossible de modifier l’icône",
            isPresented: Binding(
                get: { appIconErrorMessage != nil },
                set: { if !$0 { appIconErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { appIconErrorMessage = nil }
        } message: {
            Text(appIconErrorMessage ?? "Une erreur inconnue s’est produite.")
        }
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.birthdaySection)
                .tracking(1.2)
                .foregroundStyle(BirthdayTheme.Palette.text)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(BirthdayTheme.Palette.secondaryText)
        }
    }




    private var appIconSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                "ICÔNE DE L’APP",
                subtitle: "Choisissez l’icône indépendamment des couleurs et du fond."
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(BirthdayAppIcon.allCases) { icon in
                        appIconChoice(icon)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }

    private func appIconChoice(_ icon: BirthdayAppIcon) -> some View {
        let isSelected = selectedAppIconName == icon.rawValue
        let isUpdating = updatingAppIcon == icon

        return Button {
            selectAppIcon(icon)
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Image(icon.previewAssetName)
                        .resizable()
                        .scaledToFill()

                    if isUpdating {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.black.opacity(0.28))
                        ProgressView()
                            .tint(.white)
                    }
                }
                .frame(width: 68, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            isSelected ? BirthdayTheme.Palette.accent : BirthdayTheme.Palette.line,
                            lineWidth: isSelected ? 3 : 1
                        )
                }
                .overlay(alignment: .topTrailing) {
                    if isSelected && !isUpdating {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white, BirthdayTheme.Palette.accent)
                            .offset(x: 5, y: -5)
                    }
                }

                Text(icon.title)
                    .font(.caption2.weight(isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? BirthdayTheme.Palette.text : BirthdayTheme.Palette.secondaryText)
                    .lineLimit(1)
            }
            .frame(width: 76)
            .padding(.vertical, 6)
        }
        .buttonStyle(SharpPressStyle())
        .disabled(updatingAppIcon != nil)
        .accessibilityLabel("Icône \(icon.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func selectAppIcon(_ icon: BirthdayAppIcon) {
        guard updatingAppIcon == nil, selectedAppIconName != icon.rawValue else { return }
        updatingAppIcon = icon
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()

        AppIconService.apply(icon) { result in
            updatingAppIcon = nil
            switch result {
            case .success(let appliedIcon):
                selectedAppIconName = appliedIcon.rawValue
            case .failure(let error):
                appIconErrorMessage = error.localizedDescription
            }
        }
    }

    private var featuredStyles: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                BirthdayBackgroundCategory.signatureStyles.title,
                subtitle: BirthdayBackgroundCategory.signatureStyles.subtitle
            )
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(styles(in: .signatureStyles)) { style in
                        featuredChoice(style)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }

    private func featuredChoice(_ style: BirthdayBackgroundStyle) -> some View {
        let isSelected = selectedStyle == style.rawValue

        return Button {
            withAnimation(.snappy(duration: 0.25)) { selectedStyle = style.rawValue }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } label: {
            ZStack(alignment: .bottomLeading) {
                // Vignettes figées : n'animer que l'aperçu du haut évite de
                // faire tourner plusieurs shaders en même temps.
                BirthdayBackgroundArtwork(style: style, isAnimated: false, showsSeasonalContext: false)
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 2) {
                    Text(style.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                    Text(style.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                .padding(12)
            }
            .frame(width: 150, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        isSelected ? BirthdayTheme.Palette.accent : Color.white.opacity(0.12),
                        lineWidth: isSelected ? 2.5 : 1
                    )
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white, BirthdayTheme.Palette.accent)
                        .padding(10)
                }
            }
            .shadow(color: isSelected ? BirthdayTheme.Palette.accent.opacity(0.22) : .clear, radius: 14, y: 6)
        }
        .buttonStyle(SharpPressStyle())
        .accessibilityLabel("Fond \(style.title), \(isSelected ? "sélectionné" : style.subtitle)")
    }

    private var accentSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("COULEUR D’ACCENT")
                    .font(.birthdaySection)
                    .tracking(1.2)
                    .foregroundStyle(BirthdayTheme.Palette.text)
                Text("Interface, dégradés et fonds suivent cette couleur. Faites défiler pour voir toutes les teintes.")
                    .font(.footnote)
                    .foregroundStyle(BirthdayTheme.Palette.secondaryText)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(BirthdayAccent.presets) { preset in
                        accentChoice(preset)
                    }
                }
                .padding(.vertical, 2)
                .padding(.trailing, 28)
            }
            // Rien n'indiquait que la rangée continuait : la dernière pastille
            // s'estompe au bord, ce qui signale qu'il y en a d'autres.
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.86),
                        .init(color: .black.opacity(0.15), location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .overlay(alignment: .trailing) {
                Image(systemName: "chevron.compact.right")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(BirthdayTheme.Palette.secondaryText.opacity(0.55))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

        }
    }

    private func accentChoice(_ preset: BirthdayAccent.Preset) -> some View {
        let isSelected = BirthdayAccent.sanitized(accentHex) == preset.hex

        return Button {
            withAnimation(.snappy(duration: 0.22)) {
                accentHex = preset.hex
            }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } label: {
            VStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(Color(hexString: preset.hex))
                        .frame(width: 38, height: 38)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(.white)
                    }
                }
                .overlay {
                    Circle()
                        .strokeBorder(isSelected ? BirthdayTheme.Palette.text.opacity(0.72) : .clear, lineWidth: 2)
                        .padding(-3)
                }
                Text(preset.title)
                    .font(.caption2.weight(isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? BirthdayTheme.Palette.text : BirthdayTheme.Palette.secondaryText)
            }
            .frame(width: 58)
            .padding(.vertical, 7)
        }
        .buttonStyle(SharpPressStyle())
        .accessibilityLabel("Couleur \(preset.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func backgroundChoice(_ style: BirthdayBackgroundStyle) -> some View {
        let isSelected = selectedStyle == style.rawValue

        return Button {
            withAnimation(.snappy(duration: 0.25)) {
                selectedStyle = style.rawValue
            }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } label: {
            ZStack(alignment: .bottomLeading) {
                BirthdayBackgroundArtwork(
                    style: style,
                    isAnimated: false,
                    showsSeasonalContext: false
                )
                LinearGradient(
                    colors: [.clear, .black.opacity(0.72)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(style.title)
                            .font(.subheadline.weight(.bold))
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(BirthdayTheme.Palette.accent)
                        }
                    }
                    Text(style.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.68))
                }
                .foregroundStyle(.white)
                .padding(12)
            }
            .frame(height: 174)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        isSelected ? BirthdayTheme.Palette.accent : Color.white.opacity(0.10),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
            .shadow(color: isSelected ? BirthdayTheme.Palette.accent.opacity(0.16) : .clear, radius: 14, y: 5)
        }
        .buttonStyle(SharpPressStyle())
        .accessibilityLabel("Fond \(style.title), \(isSelected ? "sélectionné" : style.subtitle)")
    }

    private func styles(in category: BirthdayBackgroundCategory) -> [BirthdayBackgroundStyle] {
        BirthdayBackgroundStyle.selectableStyles.filter { $0.category == category }
    }

    private var visibleCategories: [BirthdayBackgroundCategory] {
        [.signatureStyles, .staticStyles, .animatedStyles]
    }

    private var contextualSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) {
                contextualToggle(
                    title: "Suivre les saisons",
                    subtitle: "Chaleur estivale, lumière givrée en hiver.",
                    icon: "leaf.fill",
                    isOn: $seasonalTintEnabled
                )
                Divider().overlay(BirthdayTheme.Palette.line)
                contextualToggle(
                    title: "Listes en cartes",
                    subtitle: "Les anniversaires sont regroupés sur des cartes détachées du fond.",
                    icon: "rectangle.stack",
                    isOn: $floatingCards
                )
                Divider().overlay(BirthdayTheme.Palette.line)
                contextualToggle(
                    title: "Teinte tirée de la photo",
                    subtitle: "La carte reprend la couleur dominante de la photo au lieu de la couleur d’accent.",
                    icon: "eyedropper.halffull",
                    isOn: $photoTintEnabled
                )
            }
            .background(BirthdayTheme.Palette.surface.opacity(0.88))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(BirthdayTheme.Palette.line, lineWidth: 1)
            }
        }
    }

    private func contextualToggle(
        title: String,
        subtitle: String,
        icon: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(BirthdayTheme.Palette.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(BirthdayTheme.Palette.secondaryText)
                }
            }
        }
        .tint(BirthdayTheme.Palette.accent)
        .padding(14)
    }
}
