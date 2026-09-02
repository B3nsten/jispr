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
    public var text: String

    public init(speaker: Int, text: String) {
        self.speaker = speaker
        self.text = text
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
                turns.append(SpeakerTurn(speaker: number, text: word.text))
            }
        }
        return turns
    }

    /// `Person 1: …` paragraphs. With one speaker only, the plain text.
    public static func format(_ turns: [SpeakerTurn]) -> String {
        let speakers = Set(turns.map(\.speaker))
        if speakers.count <= 1 {
            return turns.map(\.text).joined(separator: " ")
        }
        return turns.map { "Person \($0.speaker): \($0.text)" }.joined(separator: "\n\n")
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
