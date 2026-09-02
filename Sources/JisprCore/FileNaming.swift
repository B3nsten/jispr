import Foundation

/// Names for saved recordings and transcripts.
public enum FileNaming {
    /// `meeting_yyMMdd_HHmm` for the given time (24-hour clock), for example `meeting_260902_1432`.
    public static func meetingName(at date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyMMdd_HHmm"
        return "meeting_" + formatter.string(from: date)
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
