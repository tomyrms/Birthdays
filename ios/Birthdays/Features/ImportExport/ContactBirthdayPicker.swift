import Contacts
import ContactsUI
import SwiftUI

struct ContactBirthdayPicker: UIViewControllerRepresentable {
    let onImport: ([BirthdayEntry]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(onImport: onImport, dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [CNContactBirthdayKey, CNContactImageDataKey]
        picker.predicateForEnablingContact = NSPredicate(format: "birthday != nil")
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onImport: ([BirthdayEntry]) -> Void
        let dismiss: DismissAction

        init(onImport: @escaping ([BirthdayEntry]) -> Void, dismiss: DismissAction) {
            self.onImport = onImport
            self.dismiss = dismiss
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            let entries = contacts.compactMap(Self.entry(from:))
            onImport(entries)
            dismiss()
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            dismiss()
        }

        private static func entry(from contact: CNContact) -> BirthdayEntry? {
            guard let birthday = contact.birthday,
                  let month = birthday.month,
                  let day = birthday.day else { return nil }
            let formatted = CNContactFormatter.string(from: contact, style: .fullName)
            let name = formatted?.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = contact.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedName = (name?.isEmpty == false ? name! : fallback)
            guard !resolvedName.isEmpty else { return nil }

            return BirthdayEntry(
                name: resolvedName,
                month: month,
                day: day,
                birthYear: birthday.year,
                avatarStyle: contact.imageData == nil ? .initials : .photo,
                photoData: contact.imageData.flatMap { ImageProcessor.thumbnailData(from: $0) },
                source: .contacts,
                sourceIdentifier: contact.identifier
            )
        }
    }
}
