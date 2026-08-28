import Foundation

/// Bornes appliquées à toute donnée qui entre dans l'app. Les saisies manuelles
/// sont raisonnables par nature, mais un fichier ICS ou une sauvegarde peuvent
/// venir de n'importe où : sans limites, un champ démesuré casse la mise en
/// page, gonfle le stockage ou fait travailler l'app pour rien.
enum BirthdayLimits {
    /// Assez pour un nom composé, trop court pour un texte collé par erreur.
    static let name = 80
    static let note = 2_000
    /// Un ICS d'anniversaires reste minuscule ; au-delà, le fichier n'en est pas un.
    static let importFileBytes = 5 * 1_024 * 1_024
    static let importedEntries = 2_000
    /// Une sauvegarde contient des photos : la marge est plus large.
    static let backupFileBytes = 200 * 1_024 * 1_024

    static func clampedName(_ value: String) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(name))
    }

    static func clampedNote(_ value: String) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(note))
    }
}
