import Foundation
import os

enum Log {
    static let subsystem = Bundle.main.bundleIdentifier ?? "io.github.b3nsten.jispr"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let speech = Logger(subsystem: subsystem, category: "speech")
    static let insert = Logger(subsystem: subsystem, category: "insert")
}

enum JisprError: LocalizedError {
    case microphoneDenied
    case accessibilityDenied

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: return "Microphone access denied"
        case .accessibilityDenied: return "Accessibility access denied"
        }
    }
}
