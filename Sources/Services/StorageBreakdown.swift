import Foundation
import SwiftUI
import Observation

/// Splits the disk into buckets a person can act on, instead of one big "System & other".
struct StorageBucket: Identifiable, Hashable {
    enum Kind: String, CaseIterable {
        case files, projects, appData, homeOther, caches, devTools, simulators, trash, swap, macOS, other
    }
    struct Entry: Hashable { let name: String; let path: String; let bytes: Int64 }

    let kind: Kind
    var bytes: Int64
    var top: [Entry] = []
    var id: String { kind.rawValue }

    var title: String {
        switch kind {
        case .files: return "Your files"
        case .projects: return "Projects (~/Developer)"
        case .appData: return "App data"
        case .homeOther: return "Other folders in your home"
        case .caches: return "Caches & temporary files"
        case .devTools: return "Developer tools"
        case .simulators: return "Simulators"
        case .trash: return "Trash"
        case .swap: return "Swap"
        case .macOS: return "macOS"
        case .other: return "Other system data"
        }
    }

    var detail: String {
        switch kind {
        case .files: return "Desktop, Documents, Downloads, Movies, Music, Pictures and apps. Browse them in the sidebar."
        case .projects: return "Code, worktrees, node_modules and build folders. Deep Clean finds the parts that rebuild themselves."
        case .appData: return "What apps keep in ~/Library: chat media, browser profiles, editor data. Clear it from inside each app."
        case .homeOther: return "Folders that aren't projects or app data, often tools' hidden folders like ~/.claude or ~/.codex."
        case .caches: return "Caches and temporary files that apps and tools recreate on their own."
        case .devTools: return "Homebrew, language toolchains and editor extensions."
        case .simulators: return "iOS and other simulator runtimes. Remove ones you don't need in Xcode ▸ Settings ▸ Components."
        case .trash: return "Still on your disk until you empty the Trash."
        case .swap: return "Memory macOS wrote to disk. Quitting heavy apps shrinks it."
        case .macOS: return "The system, Recovery, and what macOS downloads for itself (Apple Intelligence, Siri and speech models). Can't be reduced."
        case .other: return "Things macOS doesn't let apps measure directly: logs, Spotlight's index, temporary files and other users."
        }
    }

    var symbol: String {
        switch kind {
        case .files: return "person.crop.square"
        case .projects: return "chevron.left.forwardslash.chevron.right"
        case .appData: return "square.stack.3d.up"
        case .homeOther: return "house"
        case .caches: return "shippingbox"
        case .devTools: return "wrench.and.screwdriver"
        case .simulators: return "iphone"
        case .trash: return "trash"
        case .swap: return "memorychip"
        case .macOS: return "apple.logo"
        case .other: return "questionmark.folder"
        }
    }

    var tint: Color {
        switch kind {
        case .files: return .pink
        case .projects: return .indigo
        case .appData: return .teal
        case .homeOther: return .mint
        case .caches: return .orange
        case .devTools: return .green
        case .simulators: return .cyan
        case .trash: return .red
        case .swap: return .purple
        case .macOS: return .gray
        case .other: return Color.gray.opacity(0.55)
        }
    }
}

@MainActor @Observable
final class StorageBreakdownModel {
    var buckets: [StorageBucket] = []
    /// Without Full Disk Access, macOS hides other apps' private folders (WhatsApp media, Mail, Messages).
    var hasFullDiskAccess = StorageBreakdownModel.checkFullDiskAccess()
    var isMeasuring = false
    var current = ""
    var measuredAt: Date?

    var total: Int64 { buckets.reduce(0) { $0 + $1.bytes } }

    func measureIfStale() {
        if isMeasuring { return }
        if let m = measuredAt, Date().timeIntervalSince(m) < 15 * 60 { return }
        measure()
    }

    func measure() {
        guard !isMeasuring else { return }
        isMeasuring = true
        hasFullDiskAccess = StorageBreakdownModel.checkFullDiskAccess()
        let filesBytes = AppState.shared.library.indexedBytes
        let used = AppState.shared.library.disk.used
        Task.detached(priority: .utility) {
            let result = StorageBreakdownModel.compute(filesBytes: filesBytes, diskUsed: used) { p in
                Task { @MainActor in self.current = p }
            }
            await MainActor.run {
                self.buckets = result
                self.isMeasuring = false
                self.measuredAt = Date()
                self.current = ""
                FileManager.default.createFile(atPath: AppPaths.caches.appendingPathComponent("storage-measured").path, contents: Data())
            }
        }
    }

    /// The system's privacy database is readable only with Full Disk Access, so this checks without prompting.
    nonisolated static func checkFullDiskAccess() -> Bool {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db").path
        guard let f = fopen(path, "r") else { return false }
        fclose(f)
        return true
    }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) }
    }

    // MARK: Measuring

    nonisolated static func compute(filesBytes: Int64, diskUsed: Int64, progress: @escaping (String) -> Void) -> [StorageBucket] {
        if DemoData.root != nil { return demo(filesBytes: filesBytes, diskUsed: diskUsed) }
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        func size(_ url: URL) -> Int64 {
            guard fm.fileExists(atPath: url.path) else { return 0 }
            progress(Fmt.path(url))
            return Scanner.directorySize(url).allocated
        }
        /// Size of each child, biggest first, plus the total.
        func children(_ url: URL, skip: Set<String> = []) -> (total: Int64, top: [StorageBucket.Entry]) {
            guard let all = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: []) else { return (0, []) }
            let kids = all.filter { !skip.contains($0.lastPathComponent) }
            // Measure folders side by side; SSDs handle parallel reads well.
            var sizes = [Int64](repeating: 0, count: kids.count)
            let lock = NSLock()
            DispatchQueue.concurrentPerform(iterations: kids.count) { i in
                let s = size(kids[i])
                lock.lock(); sizes[i] = s; lock.unlock()
            }
            var entries: [StorageBucket.Entry] = []
            for (i, k) in kids.enumerated() where sizes[i] > 0 {
                entries.append(.init(name: DeepCleanScanner.friendlyName(k.lastPathComponent), path: k.path, bytes: sizes[i]))
            }
            entries.sort { $0.bytes > $1.bytes }
            return (entries.reduce(0) { $0 + $1.bytes }, Array(entries.prefix(8)))
        }

        let apfs = apfsVolumes()
        let macOS = apfs.filter { ["System", "Preboot", "Recovery", "Update", "Hardware", "xART"].contains($0.role) }.reduce(Int64(0)) { $0 + $1.used }
        let swap = apfs.filter { $0.role == "VM" }.reduce(Int64(0)) { $0 + $1.used }
        let simVolumes = apfs.filter { $0.role.isEmpty && $0.name.localizedCaseInsensitiveContains("simulator") }

        var files = filesBytes
        var fileEntries: [StorageBucket.Entry] = []
        for u in ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Applications"].map({ home.appendingPathComponent($0) })
            + [URL(fileURLWithPath: "/Applications")] {
            let s = size(u)
            if s > 0 { fileEntries.append(.init(name: Fmt.path(u), path: u.path, bytes: s)) }
        }
        files = max(files, fileEntries.reduce(0) { $0 + $1.bytes })
        fileEntries.sort { $0.bytes > $1.bytes }

        let projects = children(home.appendingPathComponent("Developer"))

        // Anything else in the home folder (hidden tool folders like ~/.claude, loose project folders)
        let knownHome: Set<String> = ["Developer", "Library", "Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Applications",
                                      "Public", ".Trash", ".cache", ".npm", ".bun", ".gradle", ".cocoapods", ".rustup", ".nvm", ".vscode",
                                      ".cursor", ".pyenv", ".local", ".cargo", ".docker", "go"]
        let homeOther = children(home, skip: knownHome)

        let library = home.appendingPathComponent("Library")
        var librarySkip: Set<String> = ["Caches", "Developer", "CloudStorage", "pnpm", "Python"]
        if !checkFullDiskAccess() { librarySkip.formUnion(["Group Containers", "Containers", "Mail", "Messages", "Safari", "Biome"]) }
        let libKids = children(library, skip: librarySkip)
        let libCaches = children(library.appendingPathComponent("Caches"))

        var cacheEntries = libCaches.top
        var cacheTotal = libCaches.total
        for rel in [".cache", ".npm", ".bun", ".gradle/caches", ".cocoapods", "Library/pnpm"] {
            let u = home.appendingPathComponent(rel)
            let s = size(u)
            if s > 0 { cacheTotal += s; cacheEntries.append(.init(name: "~/" + rel, path: u.path, bytes: s)) }
        }
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        for (name, u) in [("Temporary files", tmp), ("App caches outside ~/Library", tmp.deletingLastPathComponent().appendingPathComponent("C"))] {
            let s = size(u)
            if s > 0 { cacheTotal += s; cacheEntries.append(.init(name: name, path: u.path, bytes: s)) }
        }
        for c in DeepCleanScanner.codeSignClones(progress: progress) {
            cacheTotal += c.bytes
            cacheEntries.append(.init(name: c.title, path: c.url.path, bytes: c.bytes))
        }
        cacheEntries.sort { $0.bytes > $1.bytes }

        // macOS keeps downloaded assets (simulator runtimes, Siri and Apple Intelligence models) in AssetsV2.
        let assets = children(URL(fileURLWithPath: "/System/Library/AssetsV2"))
        let simAssets = assets.top.filter { $0.path.contains("SimulatorRuntime") }
        let osAssets = assets.total - simAssets.reduce(0) { $0 + $1.bytes }
        var simEntries: [StorageBucket.Entry] = simVolumes.map { .init(name: $0.name, path: "/Library/Developer/CoreSimulator/Volumes", bytes: $0.used) }
            + simAssets.map { .init(name: "Simulator runtimes", path: $0.path, bytes: $0.bytes) }
        var simTotal = simEntries.reduce(Int64(0)) { $0 + $1.bytes }
        let userSims = home.appendingPathComponent("Library/Developer/CoreSimulator")
        let userSimSize = size(userSims)
        if userSimSize > 0 { simTotal += userSimSize; simEntries.append(.init(name: "Simulator devices", path: userSims.path, bytes: userSimSize)) }
        let sysSims = children(URL(fileURLWithPath: "/Library/Developer/CoreSimulator"), skip: ["Volumes", "Images", "Cryptex"])
        if sysSims.total > 0 { simTotal += sysSims.total; simEntries += sysSims.top }

        var toolEntries: [StorageBucket.Entry] = []
        var toolTotal: Int64 = 0
        let devLib = home.appendingPathComponent("Library/Developer")
        let devLibSize = max(0, size(devLib) - size(home.appendingPathComponent("Library/Developer/CoreSimulator")))
        if devLibSize > 0 { toolTotal += devLibSize; toolEntries.append(.init(name: "~/Library/Developer (Xcode)", path: devLib.path, bytes: devLibSize)) }
        for p in ["/opt/homebrew", "/usr/local", "~/.rustup", "~/.nvm", "~/.vscode", "~/.cursor", "~/.pyenv", "~/.local", "~/.cargo", "~/.docker", "~/go", "~/Library/Python"] {
            let u = p.hasPrefix("~") ? home.appendingPathComponent(String(p.dropFirst(2))) : URL(fileURLWithPath: p)
            let s = size(u)
            if s > 50_000_000 { toolTotal += s; toolEntries.append(.init(name: p, path: u.path, bytes: s)) }
        }
        toolEntries.sort { $0.bytes > $1.bytes }

        let trash = size(home.appendingPathComponent(".Trash"))

        var buckets: [StorageBucket] = [
            .init(kind: .files, bytes: files, top: fileEntries),
            .init(kind: .projects, bytes: projects.total, top: projects.top),
            .init(kind: .appData, bytes: libKids.total, top: libKids.top),
            .init(kind: .homeOther, bytes: homeOther.total, top: homeOther.top),
            .init(kind: .caches, bytes: cacheTotal, top: Array(cacheEntries.prefix(8))),
            .init(kind: .devTools, bytes: toolTotal, top: toolEntries),
            .init(kind: .simulators, bytes: simTotal, top: simEntries),
            .init(kind: .trash, bytes: trash, top: trash > 0 ? [.init(name: "Trash", path: home.appendingPathComponent(".Trash").path, bytes: trash)] : []),
            .init(kind: .swap, bytes: swap),
            .init(kind: .macOS, bytes: macOS + osAssets,
                  top: [.init(name: "System, startup and Recovery", path: "", bytes: macOS)]
                      + assets.top.filter { !$0.path.contains("SimulatorRuntime") }.prefix(5)
                        .map { .init(name: $0.name.replacingOccurrences(of: "com_apple_MobileAsset_", with: "").replacingOccurrences(of: "_", with: " "), path: $0.path, bytes: $0.bytes) }),
        ]
        // Container usage includes the system, swap and simulator volumes; the Data volume figure doesn't.
        let containerUsed = max(diskUsed, apfs.reduce(Int64(0)) { $0 + $1.used })
        let known = buckets.reduce(Int64(0)) { $0 + $1.bytes }
        buckets.append(.init(kind: .other, bytes: max(0, containerUsed - known)))
        return buckets.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
    }

    struct APFSVolume { let name: String; let role: String; let used: Int64 }

    /// Volumes in the container that holds the startup disk, with how much each uses.
    nonisolated static func apfsVolumes() -> [APFSVolume] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        p.arguments = ["apfs", "list", "-plist"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let containers = plist["Containers"] as? [[String: Any]] else { return [] }
        let container = containers.first { c in
            ((c["Volumes"] as? [[String: Any]]) ?? []).contains { (($0["Roles"] as? [String]) ?? []).contains("System") }
        } ?? containers.first
        return ((container?["Volumes"] as? [[String: Any]]) ?? []).map {
            APFSVolume(name: $0["Name"] as? String ?? "",
                       role: (($0["Roles"] as? [String]) ?? []).first ?? "",
                       used: ($0["CapacityInUse"] as? NSNumber)?.int64Value ?? 0)
        }
    }

    nonisolated static func demo(filesBytes: Int64, diskUsed: Int64) -> [StorageBucket] {
        let GB: Int64 = 1_000_000_000
        let list: [StorageBucket] = [
            .init(kind: .files, bytes: filesBytes),
            .init(kind: .projects, bytes: 96 * GB, top: [.init(name: "ios-client", path: "", bytes: 31 * GB), .init(name: "storefront-web", path: "", bytes: 18 * GB),
                                                          .init(name: "ml-experiments", path: "", bytes: 14 * GB)]),
            .init(kind: .appData, bytes: 58 * GB, top: [.init(name: "WhatsApp media", path: "", bytes: 13 * GB), .init(name: "Slack", path: "", bytes: 6 * GB)]),
            .init(kind: .caches, bytes: 21 * GB),
            .init(kind: .simulators, bytes: 17 * GB),
            .init(kind: .devTools, bytes: 12 * GB),
            .init(kind: .swap, bytes: 10 * GB),
            .init(kind: .trash, bytes: 6 * GB),
            .init(kind: .macOS, bytes: 25 * GB),
        ]
        let known = list.reduce(Int64(0)) { $0 + $1.bytes }
        return (list + [.init(kind: .other, bytes: max(0, diskUsed - known))]).filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
    }
}
