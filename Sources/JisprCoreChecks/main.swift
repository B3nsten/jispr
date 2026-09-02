// Checks for JisprCore. Run with `make check` (or `swift run JisprCoreChecks`).
// Plain asserts: the macOS Command Line Tools ship neither XCTest nor Swift Testing.
import Foundation
import JisprCore

var failures = 0
var count = 0

func check(_ actual: String, _ expected: String, _ note: String = "", line: Int = #line) {
    count += 1
    if actual != expected {
        failures += 1
        print("FAIL line \(line) \(note)\n  expected: \(expected)\n  actual:   \(actual)")
    }
}

func clean(_ s: String, caps: Bool = false, keep: Set<String> = []) -> String {
    TextCleanup.clean(s, normalizeAllCaps: caps, keepCaps: keep)
}

// Sentence case and final period
check(clean("hello world"), "Hello world.")
check(clean("one. two! three? four"), "One. Two! Three? Four.")

// Pronoun I
check(clean("i think i'm fine and i'll go"), "I think I'm fine and I'll go.")
check(clean("it is in"), "It is in.", "no false positives inside words")

// Spacing around punctuation
check(clean("hello ,world .How are you ?fine"), "Hello, world. How are you? Fine.")
check(clean("visit github.com and U.S. sites"), "Visit github.com and U.S. sites.", "periods inside words stay")
check(clean("it costs 1,000.50 dollars"), "It costs 1,000.50 dollars.", "numbers untouched")

// Endings
check(clean("see you soon,"), "See you soon.")
check(clean("really?"), "Really?")
check(clean("he said \"hi\""), "He said \"hi\".")

// Idempotent on good text
let good = "Hello, this is a test. It works! Does it? Yes."
check(clean(good), good)

// Empty
check(clean(""), "")
check(clean("   \n "), "")

// Shouted words
check(clean("the JISPR app", caps: true), "The Jispr app.")
check(clean("JISPR's menu", caps: true), "Jispr's menu.")
check(clean("the JISPR app"), "The JISPR app.", "off by default")
check(clean("NASA uses HTML and AI on a USB stick", caps: true), "NASA uses HTML and AI on a USB stick.")
check(clean("ARM64 and MP3", caps: true), "ARM64 and MP3.")
check(clean("built with FOOBAR", caps: true, keep: ["FOOBAR"]), "Built with FOOBAR.")

// Break commands
check(clean("hello there. new paragraph. this is the second part"), "Hello there.\n\nThis is the second part.")
check(clean("hello there, new paragraph this is the second part"), "Hello there.\n\nThis is the second part.", "comma before the command becomes a period")
check(clean("first line, new line second line"), "First line.\nSecond line.")
check(clean("Hello. New Line. Bye"), "Hello.\nBye.", "any case")
check(clean("I started a new paragraph in the essay"), "I started a new paragraph in the essay.", "inside a sentence: words stay")
check(clean("new lines are great"), "New lines are great.", "plural is not a command")
check(clean("new paragraph hello"), "\n\nHello.", "command at the start")
check(clean("done. new paragraph"), "Done.\n\n", "command at the end: no period added")
check(clean("one. new paragraph new paragraph two"), "One.\n\n\nTwo.", "repeated command")

// Real Parakeet output
check(
    clean("Hello, this is a test of the JISPR dictation app, it should insert this text where the cursor is", caps: true),
    "Hello, this is a test of the Jispr dictation app, it should insert this text where the cursor is.")

// File names for recordings
let berlin = TimeZone(identifier: "Europe/Berlin")!
let newYork = TimeZone(identifier: "America/New_York")!
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = berlin
let afternoon = calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 14, minute: 32))!
let morning = calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 9, minute: 5))!
let savedSecond = afternoon.addingTimeInterval(41)
let epoch = Int(savedSecond.timeIntervalSince1970)
check(FileNaming.meetingName(at: savedSecond, timeZone: berlin), "meeting_\(epoch)_260902_1432")
check(FileNaming.meetingName(at: morning, timeZone: berlin), "meeting_\(Int(morning.timeIntervalSince1970))_260902_0905", "leading zeros, 24-hour clock")
check(FileNaming.meetingName(at: savedSecond, timeZone: newYork), "meeting_\(epoch)_260902_0832", "same moment, local time of the recording")
check(FileNaming.unique(base: "meeting_1432", ext: "m4a") { _ in false }, "meeting_1432.m4a")
check(FileNaming.unique(base: "meeting_1432", ext: "m4a") { $0 == "meeting_1432.m4a" }, "meeting_1432-2.m4a", "name taken")
check(FileNaming.unique(base: "meeting_1432", ext: "txt") { ["meeting_1432.txt", "meeting_1432-2.txt"].contains($0) }, "meeting_1432-3.txt")

// Saved time from the file name
func saved(_ name: String, modified: Date? = nil, zone: TimeZone = berlin) -> String {
    guard let t = FileNaming.savedTime(name: name, modified: modified, timeZone: zone) else { return "nil" }
    return "\(Int(t.date.timeIntervalSince1970)) \(t.timeZone.secondsFromGMT(for: t.date) / 3600)h"
}
check(saved("meeting_\(epoch)_260902_1432"), "\(epoch) 2h", "exact second, zone of the recording (CEST)")
check(saved("meeting_\(epoch)_260902_1432-2"), "\(epoch) 2h", "suffix is fine")
check(saved("meeting_\(epoch)_260902_0832", zone: newYork), "\(epoch) -4h", "recorded in New York")
check(saved("meeting_\(epoch)_260902_0832", zone: berlin), "\(epoch) -4h", "read in Berlin: still New York time")
check(saved("meeting_\(epoch)_260902_1432", modified: afternoon.addingTimeInterval(3600)), "\(epoch) 2h", "file time is ignored when the seconds are in the name")
check(saved("meeting_260902_1432"), "\(Int(afternoon.timeIntervalSince1970)) 2h", "old name: the minute")
check(saved("meeting_260902_1432", modified: savedSecond), "\(epoch) 2h", "old name: file time inside the minute wins")
check(saved("meeting_260902_1432", modified: afternoon.addingTimeInterval(3600)), "\(Int(afternoon.timeIntervalSince1970)) 2h", "old name: file time off, the minute")
check(saved("interview"), "nil")
check(saved("meeting_2609"), "nil", "too short")
check(saved("meeting_abc_260902_1432"), "nil")

// Speaker turns
let twoSpeakers = [SpeakerSpan("S2", 0.0, 2.0), SpeakerSpan("S1", 2.5, 4.0), SpeakerSpan("S2", 4.0, 5.0)]
let words = [
    TimedWord("hello", 0.1, 0.5), TimedWord("there", 0.6, 1.0),
    TimedWord("hi", 2.6, 2.9), TimedWord("bob", 3.0, 3.4),
    TimedWord("bye", 4.2, 4.6),
]
let turns = SpeakerAlignment.turns(words: words, spans: twoSpeakers)
check(String(describing: turns.map { "\($0.speaker):\($0.text)" }), String(describing: ["1:hello there", "2:hi bob", "1:bye"]), "first voice is Person 1")
check(SpeakerAlignment.format(turns), "[0:00] Person 1: hello there\n\n[0:02] Person 2: hi bob\n\n[0:04] Person 1: bye", "no clock: times from the start of the file")
let clock = TranscriptClock(savedAt: calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 14, minute: 32, second: 10))!, duration: 5, timeZone: berlin)
check(SpeakerAlignment.format(turns, clock: clock), "Recorded 2026-09-02, 14:32–14:32\n\n[14:32:05] Person 1: hello there\n\n[14:32:07] Person 2: hi bob\n\n[14:32:09] Person 1: bye", "clock: saved at 14:32:10, 5 s long, so second 0 is 14:32:05")
let nyClock = TranscriptClock(savedAt: clock.start.addingTimeInterval(5), duration: 5, timeZone: TimeZone(secondsFromGMT: -4 * 3600)!)
check(SpeakerAlignment.format(turns, clock: nyClock), "Recorded 2026-09-02, 08:32–08:32\n\n[08:32:05] Person 1: hello there\n\n[08:32:07] Person 2: hi bob\n\n[08:32:09] Person 1: bye", "same moment shown in the zone of the recording")
let longClock = TranscriptClock(savedAt: afternoon, duration: 3600, timeZone: berlin)
check(SpeakerAlignment.format([SpeakerTurn(speaker: 1, start: 0, text: "Hello.")], clock: longClock), "Recorded 2026-09-02, 13:32–14:32\n\nHello.", "one speaker: header and plain text")
check(SpeakerAlignment.relative(3725), "1:02:05")
check(SpeakerAlignment.format([]), "")
check(SpeakerAlignment.format(SpeakerAlignment.turns(words: words, spans: [SpeakerSpan("S1", 0, 5)])), "hello there hi bob bye", "one speaker: plain text")
check(SpeakerAlignment.format(SpeakerAlignment.turns(words: words, spans: [])), "hello there hi bob bye", "no spans: plain text")
let gapWord = [TimedWord("um", 2.1, 2.3)]
check(SpeakerAlignment.turns(words: gapWord, spans: twoSpeakers).first?.text ?? "", "um")
check(String(SpeakerAlignment.turns(words: gapWord, spans: twoSpeakers).count), "1", "word in a gap goes to the nearest span")
let overlapWords = [TimedWord("hi", 2.6, 2.9), TimedWord("yes", 3.8, 4.4)]
check(SpeakerAlignment.turns(words: overlapWords, spans: twoSpeakers).map { "\($0.speaker)" }.joined(), "12", "most overlap wins (S2 4.0-4.4 > S1 3.8-4.0)")

if failures == 0 {
    print("OK: \(count) checks passed")
    exit(0)
} else {
    print("FAILED: \(failures) of \(count) checks")
    exit(1)
}
