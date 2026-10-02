import Foundation

/// Display-casing for Gov Fuel Finder text, matching fuel-web's `lib/stationText.ts`.
///
/// The feed has no casing convention: most names are ALL CAPS, a few all lowercase, the rest
/// sensibly cased. Only a string with no case information of its own (entirely upper- or
/// lowercase) is restyled; anything already mixed ("BP Yarnton") was cased deliberately upstream
/// and is passed through untouched.
enum StationText {
    /// Initialisms that stay uppercase. Brands written as words (Asda, Esso, Tesco) are absent.
    private static let uppercaseTokens: Set<String> = [
        "BP", "EG", "MFG", "MRH", "MWSA", "NTS", "PFS", "PGG", "SF", "TGC", "UK", "JET",
        "LPG", "HGV", "MOT", "EV", "ATM", "WC", "DIY", "AM", "PM", "II", "III",
    ]

    /// Fragments that stay lowercase after a hyphen: "CO-OP" is "Co-op".
    private static let lowerAfterHyphen: Set<String> = ["op", "operative", "op's", "operatives"]

    /// Lowercase inside a title, unless first or last.
    private static let minorWords: Set<String> = [
        "a", "an", "and", "as", "at", "but", "by", "for", "from", "in", "nor", "of",
        "on", "or", "the", "to", "via", "with",
    ]

    private static let ordinal = try! NSRegularExpression(pattern: #"^\d+(?:ST|ND|RD|TH)$"#)
    private static let houseNumberSuffix = try! NSRegularExpression(pattern: #"^\d+[A-Z]$"#)
    private static let alwaysUpper = try! NSRegularExpression(pattern: #"^(?:[A-Z]{1,2}\d{1,4}[A-Z]?|\d[A-Z]{2})$"#)

    private static func matches(_ regex: NSRegularExpression, _ value: String) -> Bool {
        regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }

    /// Word separators, kept as they are: trade names run words together with dots and "&".
    private static let separators: Set<Character> = [" ", "\t", "\n", "-", "/", ".", "&", ",", "(", ")", "[", "]"]

    /// A station or place name as it should be displayed; also collapses runs of whitespace.
    static func displayName(_ value: String?) -> String {
        let trimmed = (value ?? "")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !trimmed.isEmpty else { return "" }
        return hasNoCaseIntent(trimmed) ? titleCase(trimmed) : trimmed
    }

    private static func hasNoCaseIntent(_ value: String) -> Bool {
        guard value.contains(where: { $0.isLetter }) else { return false }
        return value == value.uppercased() || value == value.lowercased()
    }

    private static func titleCase(_ input: String) -> String {
        // Alternating word and separator runs, so separators can be put back unchanged.
        var parts: [(text: String, isSeparator: Bool)] = []
        for character in input {
            let isSeparator = separators.contains(character)
            if let last = parts.last, last.isSeparator == isSeparator {
                parts[parts.count - 1].text.append(character)
            } else {
                parts.append((String(character), isSeparator))
            }
        }
        let wordIndices = parts.indices.filter { !parts[$0].isSeparator }
        let first = wordIndices.first
        let last = wordIndices.last
        return parts.indices.map { i in
            let part = parts[i]
            if part.isSeparator { return part.text }
            let afterHyphen = i > 0 && parts[i - 1].isSeparator && parts[i - 1].text.contains("-")
            return restyle(part.text, isFirst: i == first, isLast: i == last, afterHyphen: afterHyphen)
        }.joined()
    }

    private static func restyle(_ word: String, isFirst: Bool, isLast: Bool, afterHyphen: Bool) -> String {
        let upper = word.uppercased()
        // Before the code check, which would otherwise claim "1ST" and "2ND" as postcode halves.
        if matches(ordinal, upper) { return upper.lowercased() }
        if matches(houseNumberSuffix, upper) { return upper }
        // Road numbers (A34, M25) and postcode halves (OX33, 1RT) stay uppercase.
        if uppercaseTokens.contains(upper) || matches(alwaysUpper, upper) { return upper }

        let lower = word.lowercased()
        if afterHyphen && lowerAfterHyphen.contains(lower) { return lower }
        if !isFirst && !isLast && minorWords.contains(lower) { return lower }

        let letters = Array(lower)
        // "O'BRIEN" -> "O'Brien"; a possessive 's ("TOUT'S") never takes a capital.
        if letters.count > 2, letters[0] == "o", letters[1] == "'", letters[2].isLetter {
            return "O'" + String(letters[2]).uppercased() + String(letters.dropFirst(3))
        }
        // "MCDONALDS" -> "McDonalds"; left alone below 4 letters so "MCS" doesn't become "McS".
        if letters.count >= 4, letters[0] == "m", letters[1] == "c", letters.dropFirst(2).allSatisfy({ $0.isLetter }) {
            return "Mc" + String(letters[2]).uppercased() + String(letters.dropFirst(3))
        }
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }
}
