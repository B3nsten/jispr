import Foundation

/// A word with its place in the audio, in seconds.
public struct TimedWord: Equatable {
    public let text: String
    public let start: Double
    public let end: Double

    public init(_ text: String, _ start: Double, _ end: Double) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// "Who spoke when", one span from the diarizer.
public struct SpeakerSpan: Equatable {
    public let speaker: String
    public let start: Double
    public let end: Double

    public init(_ speaker: String, _ start: Double, _ end: Double) {
        self.speaker = speaker
        self.start = start
        self.end = end
    }
}

/// Words in a row by the same speaker. Speakers are numbered from 1 in order of first appearance.
public struct SpeakerTurn: Equatable {
    public let speaker: Int
    /// Seconds into the audio when the turn starts.
    public let start: Double
    public var text: String

    public init(speaker: Int, start: Double, text: String) {
        self.speaker = speaker
        self.start = start
        self.text = text
    }
}

/// Real time of the audio: when second 0 was, and how long it runs.
public struct TranscriptClock: Equatable {
    public let start: Date
    public let duration: Double
    public let timeZone: TimeZone

    public init(start: Date, duration: Double, timeZone: TimeZone = .current) {
        self.start = start
        self.duration = duration
        self.timeZone = timeZone
    }

    /// Second 0 was `duration` seconds before the file was saved.
    public init(savedAt: Date, duration: Double, timeZone: TimeZone = .current) {
        self.init(start: savedAt.addingTimeInterval(-duration), duration: duration, timeZone: timeZone)
    }
}

/// Joins word times with speaker spans into turns.
public enum SpeakerAlignment {
    /// Gives every word to the span it overlaps most, or the nearest span when none overlaps.
    /// Then groups runs of words by the same speaker into turns.
    public static func turns(words: [TimedWord], spans: [SpeakerSpan]) -> [SpeakerTurn] {
        var numbers: [String: Int] = [:]
        var turns: [SpeakerTurn] = []
        for word in words {
            let label = speaker(of: word, in: spans)
            let number: Int
            if let known = numbers[label] {
                number = known
            } else {
                number = numbers.count + 1
                numbers[label] = number
            }
            if let last = turns.indices.last, turns[last].speaker == number {
                turns[last].text += " " + word.text
            } else {
                turns.append(SpeakerTurn(speaker: number, start: word.start, text: word.text))
            }
        }
        return turns
    }

    /// `[14:02:05] Person 1: …` paragraphs, one per turn, under a `Recorded …` line.
    /// Without a clock the times count from the start of the file: `[0:41] Person 2: …`.
    /// With one speaker only, the plain text (plus the `Recorded` line when the clock is known).
    public static func format(_ turns: [SpeakerTurn], clock: TranscriptClock? = nil) -> String {
        guard !turns.isEmpty else { return "" }
        var header = ""
        if let clock {
            let day = formatter("yyyy-MM-dd", clock.timeZone)
            let time = formatter("HH:mm", clock.timeZone)
            let end = clock.start.addingTimeInterval(clock.duration)
            header = "Recorded \(day.string(from: clock.start)), \(time.string(from: clock.start))–\(time.string(from: end))\n\n"
        }
        let speakers = Set(turns.map(\.speaker))
        if speakers.count <= 1 {
            return header + turns.map(\.text).joined(separator: " ")
        }
        let stamp: (Double) -> String
        if let clock {
            let time = formatter("HH:mm:ss", clock.timeZone)
            stamp = { time.string(from: clock.start.addingTimeInterval($0)) }
        } else {
            stamp = relative
        }
        return header + turns.map { "[\(stamp($0.start))] Person \($0.speaker): \($0.text)" }.joined(separator: "\n\n")
    }

    /// `m:ss`, or `h:mm:ss` from one hour on.
    public static func relative(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    private static func formatter(_ format: String, _ timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }

    private static func speaker(of word: TimedWord, in spans: [SpeakerSpan]) -> String {
        var best = ""
        var bestOverlap = 0.0
        var bestDistance = Double.infinity
        for span in spans {
            let overlap = min(word.end, span.end) - max(word.start, span.start)
            if overlap > 0 {
                if overlap > bestOverlap {
                    bestOverlap = overlap
                    best = span.speaker
                }
            } else if bestOverlap == 0 {
                let distance = max(span.start - word.end, word.start - span.end)
                if distance < bestDistance {
                    bestDistance = distance
                    best = span.speaker
                }
            }
        }
        return best
    }
}
