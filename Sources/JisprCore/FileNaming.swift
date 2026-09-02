import Foundation

/// Names for saved recordings and transcripts.
public enum FileNaming {
    private static let localFormat = "yyMMdd_HHmm"

    /// `meeting_<seconds since 1970>_<yyMMdd_HHmm>`, for example `meeting_1788442330_260902_1432`.
    /// The number is exact and for calculations. The rest is local time (24-hour clock) for people.
    public static func meetingName(at date: Date, timeZone: TimeZone = .current) -> String {
        let local = DateFormatter.posix(localFormat, in: timeZone).string(from: date)
        return "meeting_\(Int(date.timeIntervalSince1970))_\(local)"
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
    ///   When the two parts do not agree (a typo in the name), there is no clock.
    /// - `meeting_260902_1432` (older files): the minute, in `timeZone`. The file's "last changed" time
    ///   adds the seconds when it falls inside that minute (a copied file may be way off).
    public static func savedTime(name: String, modified: Date?, timeZone: TimeZone = .current) -> SavedTime? {
        guard let match = name.wholeMatch(of: #/meeting_(?:(\d{9,})_)?(\d{6}_\d{4})(?:-\d+)?/#) else { return nil }
        let local = String(match.2)

        if let secondsText = match.1 {
            guard let seconds = Int(secondsText),
                  let localAsUTC = DateFormatter.posix(localFormat, in: .gmt).date(from: local)
            else { return nil }
            // Local time read as if it were UTC, minus the true UTC minute, is the zone's offset.
            let utcMinute = TimeInterval(seconds - seconds % 60)
            let offset = Int(localAsUTC.timeIntervalSince1970 - utcMinute)
            // Real zones are whole quarter hours within 18 hours of UTC. Anything else is a typo.
            guard offset % 900 == 0, abs(offset) <= 18 * 3600, let zone = TimeZone(secondsFromGMT: offset) else { return nil }
            return SavedTime(date: Date(timeIntervalSince1970: TimeInterval(seconds)), timeZone: zone)
        }

        guard let minute = DateFormatter.posix(localFormat, in: timeZone).date(from: local) else { return nil }
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
}
