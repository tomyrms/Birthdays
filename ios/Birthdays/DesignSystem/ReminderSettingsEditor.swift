import SwiftUI

struct ReminderSettingsEditor: View {
    @Binding var settings: BirthdayReminderSettings

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Heure")
                        .font(.birthdayName)
                    Text("Heure commune aux rappels activés")
                        .font(.birthdayMeta)
                        .foregroundStyle(BirthdayTheme.Palette.secondaryText)
                }
                Spacer()
                DatePicker("Heure", selection: timeBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            .padding(.vertical, 13)

            Divider().overlay(BirthdayTheme.Palette.line)
            ForEach(BirthdayReminderSettings.availableOffsets, id: \.self) { offset in
                reminderToggle(
                    BirthdayReminderSettings.label(forOffset: offset),
                    isOn: Binding(
                        get: { settings.offsets.contains(offset) },
                        set: { _ in settings.toggle(offset: offset) }
                    )
                )
                Divider().overlay(BirthdayTheme.Palette.line)
            }

            Toggle(isOn: $settings.timeSensitive) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sensible au temps")
                        .font(.birthdayName)
                    Text("Peut traverser le résumé programmé et certains modes Concentration.")
                        .font(.birthdayMeta)
                        .foregroundStyle(BirthdayTheme.Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 13)
        }
    }

    private func reminderToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .font(.birthdayBody)
            .padding(.vertical, 13)
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    from: DateComponents(hour: settings.hour, minute: settings.minute)
                ) ?? .now
            },
            set: { date in
                settings.hour = Calendar.current.component(.hour, from: date)
                settings.minute = Calendar.current.component(.minute, from: date)
            }
        )
    }
}
