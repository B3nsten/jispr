import Foundation

/// Deterministic clean-up for speech-to-text output.
///
/// Rules, in order:
/// 1. Collapse whitespace.
/// 2. No space before `, . ! ? ; :`. One space after `, ; : ! ?` when a letter follows,
///    and after `.` when a lowercase letter precedes and a capital follows ("world.How").
/// 3. The pronoun "i" becomes "I" (also "i'm", "i'll", ...).
/// 4. Optional: shouted words (4+ capital letters, e.g. "JISPR") become names ("Jispr"),
///    unless they are known acronyms or in the caller's keep list.
/// 5. Capital letter at the start and after `. ! ?` (not after abbreviations like "U.S." or "e.g.").
/// 6. A final period when the text ends in a letter or digit (placed after closing quotes
///    and brackets). A trailing `, ; :` becomes a period.
public enum TextCleanup {
    /// Acronyms and brands that stay in capitals when `normalizeAllCaps` is on.
    /// Words of three letters or fewer (AI, API, USB, ...) are never touched.
    public static let defaultKeepCaps: Set<String> = [
        "NASA", "NATO", "UNESCO", "UNICEF", "FIFA", "UEFA", "WWDC", "NVIDIA", "OPENAI", "CUDA",
        "HTML", "HTTP", "HTTPS", "JSON", "YAML", "TOML", "REST", "GRPC", "UUID", "GUID", "ASCII",
        "HDMI", "WIFI", "WLAN", "IMAP", "SMTP", "SNMP", "LDAP", "SAML", "IBAN", "ISBN", "BIOS",
        "UEFI", "SATA", "NVME", "LLVM", "MIDI", "JPEG", "MPEG", "WEBP", "HEIC", "NAND", "RISC",
        "SIMD", "FPGA", "ASIC", "SCSI", "RAID", "OLED", "AMOLED", "GDPR", "HIPAA", "SWIFT",
    ]

    public static func clean(
        _ raw: String,
        normalizeAllCaps: Bool = false,
        keepCaps: Set<String> = []
    ) -> String {
        var text = collapseWhitespace(raw)
        guard !text.isEmpty else { return text }
        text = fixPunctuationSpacing(text)
        text = fixPronounI(text)
        if normalizeAllCaps {
            text = lowerShoutedWords(text, keep: defaultKeepCaps.union(keepCaps))
        }
        text = capitalizeSentences(text)
        text = ensureFinalPunctuation(text)
        return text
    }

    // MARK: - Rules

    static func collapseWhitespace(_ s: String) -> String {
        s.replacing(#/[ \t\r\n]+/#, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func fixPunctuationSpacing(_ s: String) -> String {
        var t = s.replacing(#/ +([,.!?;:])/#) { "\($0.1)" }
        t = t.replacing(#/([,;:!?])(?=[A-Za-z])/#) { "\($0.1) " }
        // "world.How" -> "world. How". Leaves "github.com", "U.S.", "3.5" alone.
        t = t.replacing(#/([a-z])\.(?=[A-Z])/#) { "\($0.1). " }
        return t
    }

    static func fixPronounI(_ s: String) -> String {
        // Simple word boundaries: Unicode rules treat "i'm" as one word.
        s.replacing(#/\bi\b/#.wordBoundaryKind(.simple), with: "I")
    }

    static func lowerShoutedWords(_ s: String, keep: Set<String>) -> String {
        s.replacing(#/\b[A-Z]{4,}\b/#.wordBoundaryKind(.simple)) { match in
            let word = String(match.0)
            if keep.contains(word) { return word }
            return String(word.prefix(1)) + word.dropFirst().lowercased()
        }
    }

    static func capitalizeSentences(_ s: String) -> String {
        var t = s
        if let first = t.first, first.isLowercase {
            t = first.uppercased() + t.dropFirst()
        }
        // word + end mark (+ optional closer) + spaces + lowercase letter
        return t.replacing(#/(\S+)([.!?]["')\]]?) +([a-z])/#) { match in
            let word = match.1
            let mark = match.2
            let letter = match.3
            // "U.S." / "e.g." / "a." are abbreviations, not sentence ends.
            let isAbbreviation = mark.first == "."
                && word.wholeMatch(of: #/(?:[A-Za-z]\.)*[A-Za-z]/#) != nil
            return "\(word)\(mark) \(isAbbreviation ? String(letter) : letter.uppercased())"
        }
    }

    static func ensureFinalPunctuation(_ s: String) -> String {
        // Closing quotes and brackets at the end stay; the period goes after them.
        let closers: Set<Character> = ["\"", "'", ")", "]", "\u{201D}", "\u{2019}"]
        var core = Substring(s)
        var tail = ""
        while let last = core.last, closers.contains(last) {
            tail.insert(last, at: tail.startIndex)
            core = core.dropLast()
        }
        guard let last = core.last else { return s }
        if last.isLetter || last.isNumber { return s + "." }
        if ",;:".contains(last) { return core.dropLast() + tail + "." }
        return s
    }
}
