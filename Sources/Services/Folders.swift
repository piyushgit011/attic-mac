import Foundation
import AppKit

// MARK: - Locations (the Finder part of the sidebar)

struct Location: Identifiable, Hashable {
    let title: String
    let path: String
    let symbol: String
    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
}

enum Locations {
    /// The folder that stands in for your home folder. In demo mode it's the sample library.
    static var home: URL { DemoData.root ?? FileManager.default.homeDirectoryForCurrentUser }

    static var standard: [Location] {
        let fm = FileManager.default
        let h = home
        var out = [Location(title: DemoData.root == nil ? NSUserName() : "Attic Demo", path: h.path, symbol: "house")]
        let named: [(String, String)] = [("Desktop", "menubar.dock.rectangle"), ("Documents", "doc"), ("Downloads", "arrow.down.circle"),
                                         ("Pictures", "photo"), ("Movies", "film"), ("Music", "music.note")]
        for (name, symbol) in named {
            let p = h.appendingPathComponent(name).path
            if fm.fileExists(atPath: p) { out.append(Location(title: name, path: p, symbol: symbol)) }
        }
        if DemoData.root == nil {
            let dev = h.appendingPathComponent("Developer").path
            if fm.fileExists(atPath: dev) { out.append(Location(title: "Developer", path: dev, symbol: "hammer")) }
            let icloud = h.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs").path
            if fm.fileExists(atPath: icloud) { out.append(Location(title: "iCloud Drive", path: icloud, symbol: "icloud")) }
            out.append(Location(title: "Applications", path: "/Applications", symbol: "square.grid.2x2"))
        } else {
            let dev = h.appendingPathComponent("Developer").path
            if fm.fileExists(atPath: dev) { out.append(Location(title: "Developer", path: dev, symbol: "hammer")) }
        }
        return out
    }

    static var pinned: [String] {
        get { UserDefaults.standard.stringArray(forKey: Prefs.pinnedFolders) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: Prefs.pinnedFolders) }
    }

    static func isPinned(_ path: String) -> Bool { pinned.contains(path) || standard.contains { $0.path == path } }

    /// A friendly name for any folder: "Desktop", "attic-mac", or your user name for home.
    static func title(for path: String) -> String {
        if let loc = standard.first(where: { $0.path == path }) { return loc.title }
        if path == "/" { return "Macintosh HD" }
        return FileManager.default.displayName(atPath: path)
    }

    /// Breadcrumbs from the nearest location (or /) down to `path`.
    static func crumbs(for path: String) -> [(title: String, path: String)] {
        let homePath = home.path
        var root = "/"
        if path == homePath || path.hasPrefix(homePath + "/") { root = homePath }
        else if path.hasPrefix("/Applications") { root = "/Applications" }
        var out: [(String, String)] = [(title(for: root), root)]
        guard path != root else { return out }
        let rest = path.dropFirst(root == "/" ? 1 : root.count + 1)
        var cur = root == "/" ? "" : root
        for part in rest.split(separator: "/") {
            cur += "/" + part
            out.append((title(for: cur), cur))
        }
        return out
    }
}

// MARK: - Reading one folder

struct FolderContents {
    var folders: [FileItem] = []
    var files: [FileItem] = []
    var error: String?
}

enum FolderReader {
    static func read(_ dir: URL, showHidden: Bool) -> FolderContents {
        let fm = FileManager.default
        var opts: FileManager.DirectoryEnumerationOptions = []
        if !showHidden { opts.insert(.skipsHiddenFiles) }
        let urls: [URL]
        do {
            urls = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: Scanner.keys, options: opts)
        } catch {
            let ns = error as NSError
            let denied = ns.code == NSFileReadNoPermissionError || (ns.underlyingErrors.first as NSError?)?.code == 1
            return FolderContents(error: denied ? "Attic doesn’t have permission to look inside this folder." : ns.localizedDescription)
        }
        var out = FolderContents()
        for url in urls where !(DemoData.root != nil && url.lastPathComponent == "demo.json") {
            guard var rv = try? url.resourceValues(forKeys: Scanner.keySet) else { continue }
            var target = url
            if rv.isSymbolicLink == true {
                let resolved = url.resolvingSymlinksInPath()
                guard let r = try? resolved.resourceValues(forKeys: Scanner.keySet) else { continue }
                rv = r
                target = resolved
            }
            if rv.isDirectory == true && rv.isPackage != true {
                out.folders.append(.folder(url, rv: rv))
            } else if var item = Scanner.makeItem(url: url, rv: rv, isPackage: rv.isPackage == true) {
                if rv.isPackage == true, let cached = FolderSizeCache.shared.bytes(for: target.path) {
                    item.size = cached; item.allocatedSize = cached
                }
                out.files.append(item)
            }
        }
        if DemoData.root != nil { out.files = DemoData.apply(out.files) }
        return out
    }

    /// A few files inside a folder, newest first, for the "files peeking out" look, plus how many items it holds.
    static func peek(_ dir: URL) -> (count: Int, sample: [URL]) {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey, .isPackageKey],
                                                                       options: [.skipsHiddenFiles]) else { return (0, []) }
        let files = urls.compactMap { u -> (URL, Date)? in
            guard let rv = try? u.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey, .isPackageKey]) else { return nil }
            if rv.isDirectory == true && rv.isPackage != true { return nil }
            return (u, rv.contentModificationDate ?? .distantPast)
        }
        let visual = files.filter { [.images, .videos, .documents, .apps].contains(TypeInfo.lookup($0.0.pathExtension.lowercased()).category) }
        let pick = (visual.isEmpty ? files : visual).sorted { $0.1 > $1.1 }.prefix(3).map(\.0)
        return (urls.count, Array(pick))
    }
}

/// Peeks are cheap but folders get drawn often, so keep them for a minute.
@MainActor
final class FolderPeekCache {
    static let shared = FolderPeekCache()
    private var store: [String: (count: Int, sample: [URL], at: Date)] = [:]

    func get(_ path: String) -> (count: Int, sample: [URL])? {
        guard let hit = store[path], hit.at.timeIntervalSinceNow > -60 else { return nil }
        return (hit.count, hit.sample)
    }

    func set(_ path: String, _ v: (count: Int, sample: [URL])) { store[path] = (v.count, v.sample, Date()) }
    func clear() { store.removeAll() }
}

// MARK: - Folder sizes, measured in the background like Finder's "Calculate all sizes"

final class FolderSizeCache: @unchecked Sendable {
    static let shared = FolderSizeCache()
    private var store: [String: (bytes: Int64, at: Date)] = [:]
    private let lock = NSLock()

    func bytes(for path: String) -> Int64? {
        lock.lock(); defer { lock.unlock() }
        guard let hit = store[path], hit.at.timeIntervalSinceNow > -900 else { return nil }
        return hit.bytes
    }

    func set(_ path: String, _ bytes: Int64) {
        lock.lock(); store[path] = (bytes, Date()); lock.unlock()
    }

    /// Anything inside a changed folder (and the folders above it) needs measuring again.
    func invalidate(_ path: String) {
        lock.lock()
        store = store.filter { !(path.hasPrefix($0.key + "/") || $0.key == path || $0.key.hasPrefix(path + "/")) }
        lock.unlock()
    }

    /// Space a folder takes on disk. Checks `cancelled` as it goes, so leaving a folder stops the work.
    static func measure(_ url: URL, cancelled: () -> Bool) -> Int64? {
        guard let en = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey],
                                                      options: [], errorHandler: { _, _ in true }) else { return nil }
        var total: Int64 = 0
        var n = 0
        for case let u as URL in en {
            n += 1
            if n % 2000 == 0 && cancelled() { return nil }
            guard let rv = try? u.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]), rv.isRegularFile == true else { continue }
            total += Int64(rv.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}

// MARK: - Watching a folder for changes (new downloads, renames in Finder…)

final class FolderWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1

    init?(path: String, onChange: @escaping () -> Void) {
        fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend], queue: .main)
        var pending: DispatchWorkItem?
        src.setEventHandler {
            // Coalesce bursts (a download writes many times).
            pending?.cancel()
            let work = DispatchWorkItem(block: onChange)
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
        let fd = self.fd
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    deinit { stop() }
}

// MARK: - File operations Finder does: rename, new folder, move and copy

enum FileOps {
    static func rename(_ url: URL, to newName: String) throws -> URL {
        let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: ":")
        guard !clean.isEmpty else { throw CocoaError(.fileWriteInvalidFileName) }
        let dest = url.deletingLastPathComponent().appendingPathComponent(clean)
        guard dest.path != url.path else { return url }
        if FileManager.default.fileExists(atPath: dest.path), dest.path.lowercased() != url.path.lowercased() {
            throw NSError(domain: "Attic", code: 1, userInfo: [NSLocalizedDescriptionKey: "There’s already an item named “\(clean)” here."])
        }
        try FileManager.default.moveItem(at: url, to: dest)
        return dest
    }

    static func newFolder(in dir: URL) throws -> URL {
        let url = AppPaths.uniqueURL(for: dir.appendingPathComponent("untitled folder"))
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    /// Moves (or copies) items into a folder. Skips items already there and folders dropped into themselves.
    static func transfer(_ urls: [URL], into dir: URL, copy: Bool) -> (moved: [(URL, URL)], failed: [String]) {
        var moved: [(URL, URL)] = []
        var failed: [String] = []
        for src in urls {
            if src.deletingLastPathComponent().standardizedFileURL.path == dir.standardizedFileURL.path && !copy { continue }
            if dir.standardizedFileURL.path == src.standardizedFileURL.path || dir.standardizedFileURL.path.hasPrefix(src.standardizedFileURL.path + "/") {
                failed.append(src.lastPathComponent); continue
            }
            let dest = AppPaths.uniqueURL(for: dir.appendingPathComponent(src.lastPathComponent))
            do {
                if copy { try FileManager.default.copyItem(at: src, to: dest) } else { try FileManager.default.moveItem(at: src, to: dest) }
                moved.append((src, dest))
            } catch {
                failed.append(src.lastPathComponent)
            }
        }
        return (moved, failed)
    }
}
