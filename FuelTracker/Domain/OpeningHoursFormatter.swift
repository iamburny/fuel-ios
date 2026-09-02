import Foundation

/// Direct port of `DetailScreen.kt`'s `formatOpeningTime` / fuel-web's `formatOpeningTime`.
enum OpeningHoursFormatter {
    private static let timeWithSecondsRegex = try! NSRegularExpression(pattern: #"^\d{1,2}:\d{2}:\d{2}$"#)

    /// Strips a trailing :SS from an "HH:MM:SS" opening-hours time for display; free text some
    /// stations report instead of a real time (e.g. "24 hrs") is returned unchanged.
    static func format(_ value: String?) -> String {
        guard let value else { return "" }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard timeWithSecondsRegex.firstMatch(in: value, range: range) != nil else { return value }
        return String(value.dropLast(3))
    }
}
