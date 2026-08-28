import Foundation

/// Nettoyage des intitulés d'événements, partagé par les imports ICS et
/// Calendrier. Les deux avaient leur propre version : celle du calendrier
/// retirait le motif n'importe où dans le titre, y compris au milieu.
enum BirthdayNameFormatter {
    private static let prefixes = [
        "Anniversaire de ", "Anniversaire : ", "Anniversaire: ", "Birthday of "
    ]
    private static let suffixes = ["’s birthday", "'s birthday", " birthday"]

    static func personName(fromEventTitle title: String) -> String {
        var value = title.trimmingCharacters(in: .whitespacesAndNewlines)

        // Les motifs sont ancrés : sans cela, « Fête anniversaire de mariage »
        // perdrait des mots en plein milieu.
        for prefix in prefixes {
            if let range = value.range(
                of: prefix,
                options: [.anchored, .caseInsensitive, .diacriticInsensitive]
            ) {
                value.removeSubrange(range)
                break
            }
        }
        for suffix in suffixes {
            if let range = value.range(
                of: suffix,
                options: [.anchored, .backwards, .caseInsensitive]
            ) {
                value.removeSubrange(range)
                break
            }
        }
        return BirthdayLimits.clampedName(value)
    }
}
