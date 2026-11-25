import Foundation
import SwiftUI

/// Rebuildable or app-owned space outside the normal file library: dependency folders, build output, caches.
struct JunkItem: Identifiable, Hashable {
    enum Group: String, CaseIterable {
        case projects = "Project dependencies & builds"
        case devCaches = "Developer caches"
        case appCaches = "App caches"
        case appData = "Large app data (review in the app)"

        var symbol: String {
            switch self {
            case .projects: return "hammer"
            case .devCaches: return "terminal"
            case .appCaches: return "internaldrive"
            case .appData: return "folder.badge.person.crop"
            }
        }
        var tint: Color {
            switch self {
            case .projects: return .indigo
            case .devCaches: return .green
            case .appCaches: return .orange
            case .appData: return .gray
            }
        }
        var note: String {
            switch self {
            case .projects: return "Rebuilt by npm install, pip install or a fresh build when you next work on the project."
            case .devCaches: return "Package-manager and build caches. Tools download them again when needed."
            case .appCaches: return "Apps recreate caches on their own. Quit the app first for best results."
            case .appData: return "Owned by the app. Clear it from inside the app (for example WhatsApp ▸ Settings ▸ Storage)."
            }
        }
        var canTrash: Bool { self != .appData }
    }

    let url: URL
    let title: String
    let detail: String
    let group: Group
    let bytes: Int64
    let lastUsed: Date?
    let recommended: Bool
    /// A running app or process lives in (or runs from) this project; moving it now would break that.
    var inUse = false
    var id: URL { url }
}

enum DeepCleanScanner {
    static func scan(projectRoots: [URL], progress: @escaping (String) -> Void, isCancelled: @escaping () -> Bool) -> [JunkItem] {
        var out: [JunkItem] = []
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        let busy = pathsInUse()

        // 1. Project folders: node_modules, Python envs, Xcode/SwiftPM build output, Next.js caches.
        for root in projectRoots {
            if isCancelled() { break }
            guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .contentModificationDateKey],
                                         options: [.skipsPackageDescendants], errorHandler: { _, _ in true }) else { continue }
            for case let url as URL in en {
                if isCancelled() { break }
                let name = url.lastPathComponent
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
                if name == ".git" || name == "Library" || name == ".Trash" { en.skipDescendants(); continue }
                guard let kind = projectJunkKind(url) else {
                    if name.hasPrefix(".") && name != ".build" && name != ".next" && name != ".venv" { en.skipDescendants() }
                    continue
                }
                en.skipDescendants()
                progress(Fmt.path(url))
                let size = Scanner.directorySize(url).allocated
                guard size > 20_000_000 else { continue }
                let last = lastActivity(of: url)
                let project = url.deletingLastPathComponent()
                let inUse = busy.contains { $0.hasPrefix(project.path + "/") }
                // Build caches are always safe to drop; dependencies only once the project has been idle a week.
                let isCache = kind.contains("build") || kind.contains("cache")
                var item = JunkItem(url: url, title: "\(project.lastPathComponent) ▸ \(name)",
                                    detail: "\(kind) · \(Fmt.path(project))", group: .projects, bytes: size,
                                    lastUsed: last, recommended: !inUse && (isCache || (last ?? .distantPast) < weekAgo))
                item.inUse = inUse
                out.append(item)
            }
        }

        // 2. Well-known developer caches.
        let devCaches: [(String, String, Bool)] = [
            ("Library/Developer/Xcode/DerivedData", "Xcode build cache", true),
            ("Library/Developer/Xcode/iOS DeviceSupport", "Xcode device symbols", true),
            ("Library/Developer/CoreSimulator/Caches", "Simulator caches", true),
            (".npm/_cacache", "npm cache", true),
            ("Library/Caches/Yarn", "Yarn cache", true),
            ("Library/pnpm/store", "pnpm store", true),
            (".bun/install/cache", "Bun cache", true),
            ("Library/Caches/Homebrew", "Homebrew downloads", true),
            ("Library/Caches/pip", "pip cache", true),
            (".cache/uv", "uv cache", true),
            (".cache/pip", "pip cache", true),
            (".gradle/caches", "Gradle cache", true),
            ("Library/Caches/ms-playwright", "Playwright browsers", false),
            (".cache/puppeteer", "Puppeteer browsers", false),
            (".cache/huggingface", "Hugging Face models (re-download when used)", false),
            ("Library/Caches/CocoaPods", "CocoaPods cache", true),
            (".cocoapods/repos", "CocoaPods specs", false),
        ]
        var covered = Set<String>()
        for (rel, title, rec) in devCaches {
            if isCancelled() { break }
            let url = home.appendingPathComponent(rel)
            guard fm.fileExists(atPath: url.path) else { continue }
            progress(Fmt.path(url))
            let size = Scanner.directorySize(url).allocated
            covered.insert(url.path)
            guard size > 20_000_000 else { continue }
            out.append(JunkItem(url: url, title: title, detail: Fmt.path(url), group: .devCaches, bytes: size, lastUsed: nil, recommended: rec))
        }

        // Anything else big in ~/.cache
        out += bigChildren(of: home.appendingPathComponent(".cache"), group: .devCaches, minBytes: 300_000_000,
                           skip: covered, recommended: false, progress: progress, isCancelled: isCancelled)

        // 3. App caches in ~/Library/Caches
        out += bigChildren(of: home.appendingPathComponent("Library/Caches"), group: .appCaches, minBytes: 100_000_000,
                           skip: covered, recommended: true, progress: progress, isCancelled: isCancelled)

        // 3b. Copies some apps (Chrome, Teams) make of themselves at launch and never clean up
        out += codeSignClones(progress: progress)

        // 4. Large app data, review only
        for dir in ["Library/Application Support", "Library/Group Containers", "Library/Containers"] {
            out += bigChildren(of: home.appendingPathComponent(dir), group: .appData, minBytes: 1_000_000_000,
                               skip: covered, recommended: false, progress: progress, isCancelled: isCancelled)
        }
        return out.sorted { $0.bytes > $1.bytes }
    }

    static func projectJunkKind(_ url: URL) -> String? {
        let fm = FileManager.default
        switch url.lastPathComponent {
        case "node_modules": return "npm dependencies"
        case ".next": return "Next.js build cache"
        case ".venv", "venv":
            return fm.fileExists(atPath: url.appendingPathComponent("pyvenv.cfg").path) ? "Python environment" : nil
        case ".build":
            return fm.fileExists(atPath: url.deletingLastPathComponent().appendingPathComponent("Package.swift").path) ? "Swift build output" : nil
        case "DerivedData": return "Xcode build output"
        case "build":
            // Xcode -derivedDataPath folders (build/<x>/Build/Products) or build/Build/Products
            if fm.fileExists(atPath: url.appendingPathComponent("Build/Products").path) { return "Xcode build output" }
            if let kids = try? fm.contentsOfDirectory(atPath: url.path),
               kids.contains(where: { fm.fileExists(atPath: url.appendingPathComponent($0).appendingPathComponent("Build/Products").path) }) {
                return "Xcode build output"
            }
            return nil
        case "target":
            return fm.fileExists(atPath: url.appendingPathComponent("CACHEDIR.TAG").path) ? "Rust build output" : nil
        default: return nil
        }
    }

    /// When someone last really worked on the project: the last commit or checkout, or a change to its dependencies.
    /// (Not `.git/index`: editors rewrite it all the time just to show git status, which made every project look busy.)
    static func lastActivity(of url: URL) -> Date? {
        let project = url.deletingLastPathComponent()
        let fm = FileManager.default
        func mtime(_ u: URL) -> Date? { try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
        var dates: [Date] = []
        for name in ["package.json", "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "bun.lockb", "Package.swift",
                     "Package.resolved", "requirements.txt", "pyproject.toml", "poetry.lock", "project.yml", "Podfile.lock"] {
            if let d = mtime(project.appendingPathComponent(name)) { dates.append(d) }
        }
        // Git's reflog moves on commits and checkouts. Worktrees keep it in the main repo's .git/worktrees/<name>.
        var gitDir = project.appendingPathComponent(".git")
        if let text = try? String(contentsOf: gitDir, encoding: .utf8), text.hasPrefix("gitdir:") {
            gitDir = URL(fileURLWithPath: text.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if fm.fileExists(atPath: gitDir.path), let d = mtime(gitDir.appendingPathComponent("logs/HEAD")) { dates.append(d) }
        return dates.max()
    }

    /// Executables and working folders of this user's running processes, so Deep Clean never pulls a folder out from under one.
    static func pathsInUse() -> [String] {
        let uid = getuid()
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        var out: [String] = []
        for pid in pids.prefix(Int(max(0, n))) where pid > 0 {
            var info = proc_bsdinfo()
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == Int32(MemoryLayout<proc_bsdinfo>.size),
                  info.pbi_uid == uid else { continue }
            var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
            if proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 { out.append(String(cString: buf)) }
            var vinfo = proc_vnodepathinfo()
            if proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vinfo, Int32(MemoryLayout<proc_vnodepathinfo>.size)) > 0 {
                let cwd = withUnsafeBytes(of: &vinfo.pvi_cdir.vip_path) { raw in String(cString: raw.bindMemory(to: CChar.self).baseAddress!) }
                if !cwd.isEmpty { out.append(cwd) }
            }
        }
        return out
    }

    static func bigChildren(of dir: URL, group: JunkItem.Group, minBytes: Int64, skip: Set<String>, recommended: Bool,
                            progress: (String) -> Void, isCancelled: () -> Bool) -> [JunkItem] {
        guard let kids = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: []) else { return [] }
        var out: [JunkItem] = []
        for url in kids {
            if isCancelled() { break }
            if skip.contains(url.path) || skip.contains(where: { $0.hasPrefix(url.path + "/") }) && group == .devCaches { continue }
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            progress(Fmt.path(url))
            let size = Scanner.directorySize(url).allocated
            guard size >= minBytes else { continue }
            out.append(JunkItem(url: url, title: friendlyName(url.lastPathComponent), detail: Fmt.path(url), group: group,
                                bytes: size, lastUsed: nil, recommended: recommended))
        }
        return out
    }

    static func friendlyName(_ name: String) -> String {
        let known: [String: String] = [
            "group.net.whatsapp.WhatsApp.shared": "WhatsApp media",
            "Claude": "Claude app data",
            "Arc": "Arc browser profiles",
            "Code": "VS Code data",
            "Google": "Google Chrome profiles",
            "com.spotify.client": "Spotify cache",
            "com.apple.Safari": "Safari",
            "group.com.apple.UserNotifications": "Notification attachments",
        ]
        if let k = known[name] { return k }
        if name.contains(".") && !name.contains(" ") {
            // reverse-DNS bundle id → last component
            return name.split(separator: ".").last.map { String($0).capitalized } ?? name
        }
        return name
    }

    /// `/var/folders/…/X/<bundle id>.code_sign_clone` holds a full copy of the app for every launch that wasn't cleaned up.
    /// Copies of the same version share disk blocks (APFS clones), so the space is estimated as one copy per version.
    static func codeSignClones(progress: (String) -> Void) -> [JunkItem] {
        let fm = FileManager.default
        let x = URL(fileURLWithPath: NSTemporaryDirectory()).deletingLastPathComponent().appendingPathComponent("X")
        guard let dirs = try? fm.contentsOfDirectory(at: x, includingPropertiesForKeys: nil, options: []) else { return [] }
        var out: [JunkItem] = []
        for dir in dirs where dir.lastPathComponent.hasSuffix(".code_sign_clone") {
            guard let clones = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: []),
                  !clones.isEmpty else { continue }
            progress(Fmt.path(dir))
            let bundleID = String(dir.lastPathComponent.dropLast(".code_sign_clone".count))
            let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            let appName = appURL.map { $0.deletingPathExtension().lastPathComponent } ?? bundleID
            let running = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
            var versionSets = Set<String>()
            var bytes: Int64 = 0
            var newest = Date.distantPast
            for c in clones {
                if let d = (try? c.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate { newest = max(newest, d) }
                let versions = (try? fm.subpathsOfDirectory(atPath: c.path))?
                    .filter { $0.contains(".framework/Versions/") && $0.split(separator: "/").count == 6 && !$0.hasSuffix("Current") }
                    .map { String($0.split(separator: "/").last!) }.sorted().joined(separator: ",") ?? ""
                if versionSets.insert(versions).inserted { bytes += Scanner.directorySize(c).allocated }
            }
            guard bytes > 50_000_000 else { continue }
            out.append(JunkItem(url: dir, title: "\(appName)’s leftover copies (\(clones.count))",
                                detail: running ? "Quit \(appName) first · \(Fmt.path(dir))" : "Safe while \(appName) is closed · \(Fmt.path(dir))",
                                group: .appCaches, bytes: bytes, lastUsed: newest, recommended: !running))
        }
        return out
    }

    // MARK: Trash

    static func trashSize() -> Int64? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        guard (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil else { return nil }
        return Scanner.directorySize(url).allocated
    }

    static func emptyTrash() -> String? {
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"Finder\" to empty trash")?.executeAndReturnError(&error)
        if let error { return (error[NSAppleScript.errorMessage] as? String) ?? "Finder couldn’t empty the Trash" }
        return nil
    }
}
