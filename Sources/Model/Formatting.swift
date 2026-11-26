import Foundation
import AppKit

enum Fmt {
    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return f
    }()

    static func bytes(_ n: Int64) -> String {
        n <= 0 ? "Zero KB" : byteFormatter.string(fromByteCount: n)
    }

    static func gb(_ n: Int64) -> String {
        String(format: "%.1f GB", Double(n) / 1_000_000_000)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    static func ago(_ d: Date) -> String {
        if abs(d.timeIntervalSinceNow) < 60 { return "just now" }
        return relativeFormatter.localizedString(for: d, relativeTo: Date())
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private static let shortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    static func date(_ d: Date) -> String { dateFormatter.string(from: d) }
    static func shortDate(_ d: Date) -> String { shortFormatter.string(from: d) }

    static func count(_ n: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: n), number: .decimal)
    }

    static func path(_ url: URL) -> String { path(url.path) }

    static func path(_ p: String) -> String {
        let home = NSHomeDirectory()
        return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }

    static func plural(_ n: Int, _ word: String) -> String {
        "\(count(n)) \(word)\(n == 1 ? "" : "s")"
    }
}

enum Prefs {
    static let menuBarEnabled = "menuBarEnabled"
    static let quickSearchEnabled = "quickSearchEnabled"
    static let ocrEnabled = "ocrEnabled"
    static let afterUpload = "afterUpload"
    static let leaveStubs = "leaveStubs"
    static let allowOtherBucketWrites = "allowOtherBucketWrites"
    static let scanRoots = "scanRoots"
    static let cardSize = "cardSize"
    static let trashedBytes = "trashedBytes"
    static let look = "look"
    static let appearance = "appearance"
    static let keepScreenshots = "keepScreenshots"
    static let screenshotFolder = "screenshotFolder"
    static let pinnedFolders = "pinnedFolders"
    static let savedSearches = "savedSearches"
    static let showHidden = "showHidden"

    static func defaultRoots() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures"].map { home.appendingPathComponent($0).path }
    }

    /// Where Deep Clean looks for node_modules and build output: the library folders plus ~/Developer.
    static var projectRootPaths: [String] {
        if let demo = DemoData.root { return [demo.appendingPathComponent("Developer").path] }
        var roots = scanRootPaths
        let dev = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Developer").path
        if FileManager.default.fileExists(atPath: dev), !roots.contains(where: { dev.hasPrefix($0) }) { roots.append(dev) }
        return roots
    }

    static var scanRootPaths: [String] {
        get {
            if let demo = DemoData.root {
                return ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures"].map { demo.appendingPathComponent($0).path }
            }
            return UserDefaults.standard.stringArray(forKey: scanRoots) ?? defaultRoots()
        }
        set { UserDefaults.standard.set(newValue, forKey: scanRoots) }
    }
}

extension URL {
    var isAtticStub: Bool { pathExtension.lowercased() == "attic" }
}

enum AppPaths {
    static var support: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Attic", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var caches: URL {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("studio.versely.attic", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func uniqueURL(for url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        for i in 2...999 {
            let candidate = dir.appendingPathComponent(ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return dir.appendingPathComponent(UUID().uuidString + (ext.isEmpty ? "" : ".\(ext)"))
    }
}
