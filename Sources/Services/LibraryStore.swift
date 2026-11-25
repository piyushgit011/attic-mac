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

    private var scanTask: Task<Void, Never>?
    private var cancelFlag = CancelFlag()

    var hasScanned: Bool { lastScan != nil }

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
            let all = files + apps
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
        items.removeAll { urls.contains($0.url) }
        let index = LibraryStore.buildIndex(items)
        totals = index.totals
        sources = index.sources
        cleanupCards = CleanupEngine.cards(for: items)
        refreshDisk()
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
        for it in needsWorkspace {
            do {
                _ = try await NSWorkspace.shared.recycle([it.url])
                moved.insert(it.url)
                bytes += it.spaceOnDisk
            } catch {
                failed.append(it.name)
            }
        }
        remove(urls: moved)
        trashedBytes += bytes
        UserDefaults.standard.set(Double(trashedBytes), forKey: Prefs.trashedBytes)
        show(toast: failed.isEmpty
             ? "Moved \(Fmt.plural(moved.count, "item")) (\(Fmt.bytes(bytes))) to the Trash"
             : "Moved \(moved.count) to the Trash. Couldn’t move: \(failed.prefix(3).joined(separator: ", "))")
        return (moved.count, bytes, failed)
    }

    func trashURLs(_ urls: [URL], sizes: Int64) async -> Int {
        var moved = 0
        for url in urls {
            if (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil {
                moved += 1
            } else if (try? await NSWorkspace.shared.recycle([url])) != nil {
                moved += 1
            }
        }
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

final class CancelFlag: @unchecked Sendable {
    var cancelled = false
}

// MARK: - File actions shared by every view

@MainActor
enum FileActions {
    static func open(_ items: [FileItem]) {
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
