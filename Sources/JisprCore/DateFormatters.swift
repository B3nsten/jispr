import Foundation

extension DateFormatter {
    /// A fixed-format formatter (POSIX locale) in the given time zone.
    static func posix(_ format: String, in timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }
}
