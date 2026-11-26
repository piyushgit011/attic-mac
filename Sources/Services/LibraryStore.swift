import Foundation
import AppKit
import Observation

@MainActor @Observable
final class LibraryStore {
    var items: [FileItem] = []
    var isScanning = false
    var scanCount = 0
    var lastScan: Date?
    var disk = DiskStats.current()
    var totals: [FileCategory: CategoryTotal] = [:]
    var sources: [SourceGroup] = []
    var cleanupCards: [CleanupCard] = []
    var trashedBytes: Int64 = Int64(UserDefaults.standard.double(forKey: Prefs.trashedBytes))
    var toast: String?
    /// iCloud-only files macOS wouldn't move to the Trash; the UI asks before deleting them from iCloud.
    var pendingCloudDelete: [FileItem] = []

    private var scanTask: Task<Void, Never>?
    private var cancelFlag = CancelFlag()

    var hasScanned: Bool { lastScan != nil }
    /// Space across all Clean Up cards, counting a file once even if it shows on two cards.
    var cleanupTotal: Int64 {
        var seen = Set<URL>()
        var total: Int64 = 0
        for c in cleanupCards { for it in c.items where seen.insert(it.url).inserted { total += it.spaceOnDisk } }
        return total
    }

    func startIfNeeded() {
        if lastScan == nil && !isScanning { scan() }
    }

    func scan() {
        cancelFlag.cancelled = true
        let flag = CancelFlag()
        cancelFlag = flag
        isScanning = true
        scanCount = 0
        disk = DiskStats.current()
        let roots = Prefs.scanRootPaths.map { URL(fileURLWithPath: $0) }
        scanTask = Task.detached(priority: .userInitiated) { [weak self] in
            let files = Scanner.scan(roots: roots, progress: { n in
                Task { @MainActor in self?.scanCount = n }
            }, isCancelled: { flag.cancelled })
            if flag.cancelled { return }
            let apps = Scanner.scanApps()
            let all = DemoData.apply(files) + apps
            let index = LibraryStore.buildIndex(all)
            await MainActor.run {
                guard let self, !flag.cancelled else { return }
                self.items = all
                self.totals = index.totals
                self.sources = index.sources
                self.cleanupCards = CleanupEngine.cards(for: all)
                self.isScanning = false
                self.lastScan = Date()
                self.scanCount = all.count
                AppState.shared.ocr.indexInBackground(all)
                // Like Clean Up, duplicates are found in the background so Home can show what they'd free.
                let dupes = AppState.shared.dupes
                if !dupes.scanning { dupes.scan(all) }
            }
        }
    }

    nonisolated static func buildIndex(_ items: [FileItem]) -> (totals: [FileCategory: CategoryTotal], sources: [SourceGroup]) {
        var totals: [FileCategory: CategoryTotal] = [:]
        var bySource: [String: (Int, Int64, Date)] = [:]
        for it in items {
            totals[it.category, default: CategoryTotal()].count += 1
            totals[it.category, default: CategoryTotal()].bytes += it.spaceOnDisk
            if let s = it.source {
                let cur = bySource[s] ?? (0, 0, .distantPast)
                bySource[s] = (cur.0 + 1, cur.1 + it.size, max(cur.2, it.arrivalDate))
            }
        }
        let sources = bySource.map { SourceGroup(name: $0.key, count: $0.value.0, bytes: $0.value.1, latest: $0.value.2) }
            .sorted { $0.count > $1.count }
        return (totals, sources)
    }

    func refreshDisk() { disk = DiskStats.current() }

    // MARK: Lookups

    func items(in category: FileCategory) -> [FileItem] { items.filter { $0.category == category } }
    var recents: [FileItem] {
        Array(items.filter { $0.category != .apps }.sorted { $0.arrivalDate > $1.arrivalDate }.prefix(400))
    }
    var screenshots: [FileItem] { items.filter(\.isScreenshot) }
    var screenshotCount: Int { items.reduce(0) { $0 + ($1.isScreenshot ? 1 : 0) } }
    var largeFileCount: Int { items.reduce(0) { $0 + ($1.spaceOnDisk >= 100_000_000 && $1.category != .apps ? 1 : 0) } }
    var largeFiles: [FileItem] { items.filter { $0.spaceOnDisk >= 100_000_000 && $0.category != .apps }.sorted { $0.spaceOnDisk > $1.spaceOnDisk } }
    func items(from source: String) -> [FileItem] { items.filter { $0.source == source } }
    var latestDownloads: [FileItem] {
        Array(items.filter(\.isInDownloads).sorted { $0.arrivalDate > $1.arrivalDate }.prefix(10))
    }
    func item(for url: URL) -> FileItem? { items.first { $0.url == url } }

    var otherBytes: Int64 { totals[.other]?.bytes ?? 0 }
    var indexedBytes: Int64 { totals.values.reduce(0) { $0 + $1.bytes } }

    // MARK: Changes

    func remove(urls: Set<URL>) {
        guard !urls.isEmpty else { return }
        // Folders aren't in the index, but the files inside them are.
        let known = Set(items.map(\.url))
        let folders = urls.filter { !known.contains($0) }.map { $0.path + "/" }
        items.removeAll { item in urls.contains(item.url) || (!folders.isEmpty && folders.contains { item.path.hasPrefix($0) }) }
        let index = LibraryStore.buildIndex(items)
        totals = index.totals
        sources = index.sources
        cleanupCards = CleanupEngine.cards(for: items)
        refreshDisk()
        for u in urls { FolderSizeCache.shared.invalidate(u.deletingLastPathComponent().path) }
        FolderPeekCache.shared.clear()
        fsVersion += 1
    }

    /// Bumped whenever Attic changes files, so an open folder reloads right away.
    var fsVersion = 0

    /// Keeps the index right after a rename, move, copy, new folder or saved screenshot, without a full rescan.
    func filesChanged(moved: [(URL, URL)] = [], added: [URL] = []) {
        var gone = Set<URL>()
        var fresh = added
        var folderMoved = false
        for (from, to) in moved {
            gone.insert(from)
            fresh.append(to)
        }
        let roots = Prefs.scanRootPaths
        func indexed(_ u: URL) -> Bool { roots.contains { u.path.hasPrefix($0 + "/") } }
        if !gone.isEmpty { items.removeAll { gone.contains($0.url) } }
        var newItems: [FileItem] = []
        for u in fresh {
            guard let it = FileItem.load(u) else { continue }
            if it.isDirectory { folderMoved = true; continue }
            if indexed(u) && !items.contains(where: { $0.url == u }) { newItems.append(it) }
        }
        items += newItems
        let index = LibraryStore.buildIndex(items)
        totals = index.totals
        sources = index.sources
        cleanupCards = CleanupEngine.cards(for: items)
        for u in gone.union(fresh) { FolderSizeCache.shared.invalidate(u.deletingLastPathComponent().path) }
        FolderPeekCache.shared.clear()
        fsVersion += 1
        refreshDisk()
        if !newItems.isEmpty { AppState.shared.ocr.indexNow(newItems) }
        // A renamed or moved folder changes the path of everything inside it.
        if folderMoved && !gone.isEmpty { scan() }
    }

    /// Adds freshly written .attic placeholders to the index without a full rescan.
    func scanStubs(_ urls: [URL]) {
        let added = urls.compactMap { url -> FileItem? in
            guard let rv = try? url.resourceValues(forKeys: Scanner.keySet) else { return nil }
            return Scanner.makeItem(url: url, rv: rv, isPackage: false)
        }
        items += added
        let index = LibraryStore.buildIndex(items)
        totals = index.totals
        sources = index.sources
    }

    /// Moves files to the Trash (never deletes outright). Returns what was moved.
    @discardableResult
    func trash(_ targets: [FileItem]) async -> (count: Int, bytes: Int64, failed: [String]) {
        var moved = Set<URL>()
        var bytes: Int64 = 0
        var failed: [String] = []
        var needsWorkspace: [FileItem] = []
        for it in targets {
            do {
                try FileManager.default.trashItem(at: it.url, resultingItemURL: nil)
                moved.insert(it.url)
                bytes += it.spaceOnDisk
            } catch {
                needsWorkspace.append(it)
            }
        }
        // Root-owned items (some apps) need Finder's authorization prompt.
        var needsFinder: [FileItem] = []
        for it in needsWorkspace {
            do {
                _ = try await NSWorkspace.shared.recycle([it.url])
                moved.insert(it.url)
                bytes += it.spaceOnDisk
            } catch {
                needsFinder.append(it)
            }
        }
        // iCloud Drive items (Desktop & Documents in iCloud) live in a File Provider domain that only
        // Finder may trash from a non-sandboxed app, so hand those to Finder.
        // iCloud-only (dataless) files: macOS won't let a non-Finder app move them to the Trash without
        // downloading them first. Ask before deleting them from iCloud instead (iCloud.com keeps them 30 days).
        let cloudOnly = needsFinder.filter(\.isCloudOnly)
        if !cloudOnly.isEmpty { pendingCloudDelete = cloudOnly }
        let others = needsFinder.filter { !$0.isCloudOnly }
        if !others.isEmpty {
            let done = FinderTrash.trash(others.map(\.url))
            for it in others {
                if done.contains(it.url) { moved.insert(it.url); bytes += it.spaceOnDisk } else { failed.append(it.name) }
            }
        }
        if !cloudOnly.isEmpty && moved.isEmpty && failed.isEmpty { return (0, 0, []) }
        remove(urls: moved)
        trashedBytes += bytes
        UserDefaults.standard.set(Double(trashedBytes), forKey: Prefs.trashedBytes)
        show(toast: failed.isEmpty
             ? "Moved \(Fmt.plural(moved.count, "item")) (\(Fmt.bytes(bytes))) to the Trash"
             : "Moved \(moved.count) to the Trash. Couldn’t move: \(failed.prefix(3).joined(separator: ", "))")
        return (moved.count, bytes, failed)
    }

    /// Deletes iCloud-only files through iCloud (coordinated), without downloading them.
    func deleteFromICloud(_ targets: [FileItem]) {
        var gone = Set<URL>()
        var failed: [String] = []
        for it in targets {
            var coordErr: NSError?
            var inner: Error?
            NSFileCoordinator().coordinate(writingItemAt: it.url, options: .forDeleting, error: &coordErr) { u in
                do { try FileManager.default.removeItem(at: u) } catch { inner = error }
            }
            if coordErr == nil && inner == nil { gone.insert(it.url) } else { failed.append(it.name) }
        }
        pendingCloudDelete = []
        remove(urls: gone)
        show(toast: failed.isEmpty
             ? "Deleted \(Fmt.plural(gone.count, "file")) from iCloud. They’re in iCloud.com ▸ Recently Deleted for 30 days."
             : "Deleted \(gone.count). Couldn’t delete: \(failed.prefix(3).joined(separator: ", "))")
    }

    func trashURLs(_ urls: [URL], sizes: Int64) async -> Int {
        var moved = 0
        var leftovers: [URL] = []
        for url in urls {
            if (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil {
                moved += 1
            } else if (try? await NSWorkspace.shared.recycle([url])) != nil {
                moved += 1
            } else {
                leftovers.append(url)
            }
        }
        if !leftovers.isEmpty { moved += FinderTrash.trash(leftovers).count }
        trashedBytes += sizes
        UserDefaults.standard.set(Double(trashedBytes), forKey: Prefs.trashedBytes)
        refreshDisk()
        return moved
    }

    func show(toast message: String) {
        toast = message
        let current = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if self.toast == current { self.toast = nil }
        }
    }
}

/// Asks Finder to move items to the Trash. Finder can trash iCloud Drive (File Provider) items that
/// FileManager refuses with "no permission" (error 513). First use shows macOS's Automation prompt.
@MainActor
enum FinderTrash {
    static func trash(_ urls: [URL]) -> Set<URL> {
        guard !urls.isEmpty else { return [] }
        let list = urls.map { "POSIX file \"" + $0.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
            .joined(separator: ", ")
        let source = "tell application \"Finder\" to delete {\(list)}"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { NSLog("Attic: Finder trash failed: \(error)") }
        return Set(urls.filter { !FileManager.default.fileExists(atPath: $0.path) })
    }
}

final class CancelFlag: @unchecked Sendable {
    var cancelled = false
}

// MARK: - File actions shared by every view

@MainActor
enum FileActions {
    /// What a double-click does: folders open in Attic, songs play in Attic, everything else opens in its app.
    static func primary(_ item: FileItem, in list: [FileItem]) {
        if item.isDirectory {
            AppState.shared.nav.go(.folder(item.path))
        } else if item.category == .music && !item.url.isAtticStub && !item.isCloudOnly {
            AppState.shared.player.play(item, queue: list.filter { $0.category == .music })
        } else {
            open([item])
        }
    }

    static func open(_ items: [FileItem]) {
        if items.count == 1, let one = items.first, one.isDirectory {
            AppState.shared.nav.go(.folder(one.path))
            return
        }
        for it in items.prefix(20) {
            if it.url.isAtticStub {
                Task { await AppState.shared.cloud.restoreStub(at: it.url, open: true) }
            } else {
                NSWorkspace.shared.open(it.url)
            }
        }
    }

    static func reveal(_ items: [FileItem]) {
        NSWorkspace.shared.activateFileViewerSelecting(items.map(\.url))
    }

    static func copyPaths(_ items: [FileItem]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(items.map(\.path).joined(separator: "\n"), forType: .string)
        AppState.shared.library.show(toast: "Copied \(Fmt.plural(items.count, "path"))")
    }

    static func copyFiles(_ items: [FileItem]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(items.map { $0.url as NSURL })
        AppState.shared.library.show(toast: "Copied \(Fmt.plural(items.count, "file"))")
    }

    static func copyText(_ items: [FileItem]) {
        let images = items.filter { $0.category == .images || $0.ext == "pdf" }
        guard !images.isEmpty else { return }
        Task {
            let text = await AppState.shared.ocr.recognizeNow(images.map(\.url))
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            AppState.shared.library.show(toast: text.isEmpty ? "No text found" : "Copied text from \(Fmt.plural(images.count, "file"))")
        }
    }
}
