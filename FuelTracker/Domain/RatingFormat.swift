import Foundation

/// Dates and pence amounts as the ratings UI shows them: UK format, Europe/London time.
enum RatingFormat {
    private static let londonTimeZone = TimeZone(identifier: "Europe/London") ?? .current

    /// Parses the backend's ISO-8601 timestamps, with or without fractional seconds.
    static func parseDate(_ iso: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)
    }

    /// "1 Oct 2026"; falls back to the raw date part if the timestamp doesn't parse.
    static func ukDate(_ iso: String) -> String {
        guard let date = parseDate(iso) else { return String(iso.prefix(10)) }
        return string(from: date, format: "d MMM yyyy")
    }

    /// "14:05" in UK time, or `nil` if the timestamp doesn't parse.
    static func ukTime(_ iso: String) -> String? {
        parseDate(iso).map { string(from: $0, format: "HH:mm") }
    }

    private static func string(from date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = londonTimeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    /// "4" / "3.5": whole numbers without a decimal, anything else to one place.
    static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// "3.1p more than listed" / "2p less than listed".
    static func gapPhrase(_ gapPence: Double) -> String {
        if gapPence == 0 { return "the listed price" }
        let pence = "\(number(abs(gapPence)))p"
        return gapPence > 0 ? "\(pence) more than listed" : "\(pence) less than listed"
    }

    /// "+3.1p" / "−2p": the sign says whether drivers paid more or less than listed.
    static func signedPence(_ gapPence: Double) -> String {
        "\(gapPence > 0 ? "+" : "\u{2212}")\(number(abs(gapPence)))p"
    }
}
