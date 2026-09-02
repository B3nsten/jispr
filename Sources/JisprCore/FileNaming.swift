import Foundation

/// Names for saved recordings and transcripts.
public enum FileNaming {
    /// `meeting_<seconds since 1970>_<yyMMdd_HHmm>`, for example `meeting_1788442330_260902_1432`.
    /// The number is exact and for calculations. The rest is local time (24-hour clock) for people.
    public static func meetingName(at date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = localFormatter(timeZone)
        return "meeting_\(Int(date.timeIntervalSince1970))_" + formatter.string(from: date)
    }

    /// When a `meeting_…` file was saved, and the time zone it was saved in.
    public struct SavedTime: Equatable {
        public let date: Date
        public let timeZone: TimeZone

        public init(date: Date, timeZone: TimeZone) {
            self.date = date
            self.timeZone = timeZone
        }
    }

    /// Reads the saved time back from a `meeting_…` name (suffixes like `-2` are fine). Nil for other names.
    ///
    /// - `meeting_1788442330_260902_1432`: the seconds give the exact moment. The local part tells the
    ///   time zone of the recording, so the transcript shows the clock as it was there, never UTC.
    /// - `meeting_260902_1432` (older files): the minute, in `timeZone`. The file's "last changed" time
    ///   adds the seconds when it falls inside that minute (a copied file may be way off).
    public static func savedTime(name: String, modified: Date?, timeZone: TimeZone = .current) -> SavedTime? {
        guard name.hasPrefix("meeting_") else { return nil }
        let parts = name.dropFirst("meeting_".count).split(separator: "_", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }

        if let seconds = Int(parts[0]), seconds > 0, let local = localDate(String(parts[1].prefix(11)), in: .gmt) {
            // Local time read as if it were UTC, minus the true UTC minute, is the zone's offset.
            let date = Date(timeIntervalSince1970: TimeInterval(seconds))
            let utcMinute = TimeInterval(seconds - seconds % 60)
            let offset = Int(local.timeIntervalSince1970 - utcMinute)
            guard let zone = TimeZone(secondsFromGMT: offset) else { return nil }
            return SavedTime(date: date, timeZone: zone)
        }

        guard let minute = localDate(String(name.dropFirst("meeting_".count).prefix(11)), in: timeZone) else { return nil }
        if let modified, modified >= minute, modified < minute.addingTimeInterval(60) {
            return SavedTime(date: modified, timeZone: timeZone)
        }
        return SavedTime(date: minute, timeZone: timeZone)
    }

    /// `base.ext`, or `base-2.ext`, `base-3.ext`, ... when the name is taken.
    public static func unique(base: String, ext: String, taken: (String) -> Bool) -> String {
        let first = "\(base).\(ext)"
        guard taken(first) else { return first }
        var n = 2
        while true {
            let candidate = "\(base)-\(n).\(ext)"
            if !taken(candidate) { return candidate }
            n += 1
        }
    }

    private static func localDate(_ stamp: String, in timeZone: TimeZone) -> Date? {
        localFormatter(timeZone).date(from: stamp)
    }

    private static func localFormatter(_ timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyMMdd_HHmm"
        return formatter
    }
}
