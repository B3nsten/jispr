import Foundation
import JisprCore

/// What a double tap of Right Option starts.
enum Mode: String, CaseIterable {
    case dictate
    case record

    var title: String {
        switch self {
        case .dictate: return "Dictate (paste text)"
        case .record: return "Record to file"
        }
    }

    var hint: String {
        switch self {
        case .dictate: return "Double-tap Right ⌥ to dictate · tap ⌥ to paste · Esc to abort · triple-tap ⌥ to record"
        case .record: return "Double-tap Right ⌥ to record · tap ⌥ to save · Esc to abort · triple-tap ⌥ to dictate"
        }
    }

    /// The other mode.
    var other: Mode { self == .dictate ? .record : .dictate }

    private static let defaultsKey = "mode"

    static var selected: Mode {
        get {
            UserDefaults.standard.string(forKey: defaultsKey)
                .flatMap(Mode.init(rawValue:)) ?? .dictate
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }
}

/// Where recordings and transcripts go.
enum Recordings {
    static var downloads: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }

    /// When a `meeting_…` file was saved, and in which time zone. Nil for other files.
    static func savedTime(of url: URL) -> FileNaming.SavedTime? {
        let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        return FileNaming.savedTime(name: url.deletingPathExtension().lastPathComponent, modified: modified)
    }

    /// `<dir>/<base>.<ext>`, with `-2`, `-3`, ... added when the name is taken.
    static func freeURL(in dir: URL, base: String, ext: String) -> URL {
        let name = FileNaming.unique(base: base, ext: ext) { candidate in
            FileManager.default.fileExists(atPath: dir.appendingPathComponent(candidate).path)
        }
        return dir.appendingPathComponent(name)
    }
}
