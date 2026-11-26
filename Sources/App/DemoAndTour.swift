import Foundation
import AppKit

/// Demo mode: `open Attic.app --args -AtticDemo /path/to/demo` scans a sample library instead of your files,
/// with sizes, dates and download sources taken from demo.json. Used for screenshots and recordings.
enum DemoData {
    static let root: URL? = UserDefaults.standard.string(forKey: "AtticDemo").map { URL(fileURLWithPath: $0) }

    static var downloadsPath: String {
        (root ?? FileManager.default.homeDirectoryForCurrentUser).appendingPathComponent("Downloads").path
    }

    struct FileOverride: Decodable {
        var size: Int64?
        var addedDaysAgo: Double?
        var modifiedDaysAgo: Double?
        var accessedDaysAgo: Double?
        var from: [String]?
        var screenshot: Bool?
    }

    struct Junk: Decodable {
        var path: String
        var title: String
        var detail: String
        var group: String
        var bytes: Int64
        var lastUsedDaysAgo: Double?
        var recommended: Bool
    }

    struct Manifest: Decodable {
        var files: [String: FileOverride]
        var junk: [Junk]
    }

    static let manifest: Manifest? = root.flatMap {
        try? JSONDecoder().decode(Manifest.self, from: Data(contentsOf: $0.appendingPathComponent("demo.json")))
    }

    static func apply(_ items: [FileItem]) -> [FileItem] {
        guard let root, let m = manifest else { return items }
        let now = Date()
        func ago(_ d: Double?) -> Date? { d.map { now.addingTimeInterval(-$0 * 86_400) } }
        return items.map { it in
            let rel = String(it.path.dropFirst(root.path.count + 1))
            guard let o = m.files[rel] else { return it }
            let modified = ago(o.modifiedDaysAgo) ?? it.modified
            let added = ago(o.addedDaysAgo) ?? modified
            let froms = o.from ?? it.whereFroms
            var copy = FileItem(
                url: it.url, name: it.name, lowerName: it.lowerName, ext: it.ext,
                size: o.size ?? it.size, allocatedSize: o.size ?? it.allocatedSize,
                created: min(added, modified), modified: modified, added: added,
                accessed: ago(o.accessedDaysAgo) ?? modified,
                category: it.category, kind: it.kind, whereFroms: froms,
                source: DownloadSource.source(from: froms),
                isScreenshot: o.screenshot ?? it.isScreenshot,
                isCloudOnly: it.isCloudOnly, isPackage: it.isPackage)
            copy.isICloudDownloaded = it.isICloudDownloaded
            copy.isICloudUploaded = it.isICloudUploaded
            return copy
        }
    }

    static func junk() -> [JunkItem] {
        guard let root, let m = manifest else { return [] }
        let groups: [String: JunkItem.Group] = ["projects": .projects, "devCaches": .devCaches, "appCaches": .appCaches, "appData": .appData]
        return m.junk.map {
            JunkItem(url: root.appendingPathComponent($0.path), title: $0.title, detail: $0.detail,
                     group: groups[$0.group] ?? .devCaches, bytes: $0.bytes,
                     lastUsed: $0.lastUsedDaysAgo.map { Date().addingTimeInterval(-$0 * 86_400) }, recommended: $0.recommended)
        }
        .sorted { $0.bytes > $1.bytes }
    }
}

/// Scripted walkthroughs: `open Attic.app --args -AtticDemo … -AtticTour search`. A recorder outside the app
/// films the window; the tour writes `<caches>/tour/done` when it finishes. The "stills" tour pauses at each
/// screen until `<caches>/tour/next-<n>` exists, so a script can screenshot every screen.
@MainActor
enum Tour {
    static let isActive = UserDefaults.standard.string(forKey: "AtticTour") != nil

    static var dir: URL {
        let d = AppPaths.caches.appendingPathComponent("tour", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func startIfRequested() {
        guard let name = UserDefaults.standard.string(forKey: "AtticTour") else { return }
        try? FileManager.default.removeItem(at: dir)
        Task { @MainActor in
            await waitFor { NSApp.windows.contains { $0.isVisible && $0.frame.width > 800 } }
            placeWindow()
            await waitFor(timeout: 120) { AppState.shared.library.hasScanned && !AppState.shared.library.isScanning }
            await waitFor(timeout: 120) { !AppState.shared.ocr.isIndexing }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            mark("ready")
            await waitFor(timeout: 30) { FileManager.default.fileExists(atPath: dir.appendingPathComponent("go").path) }
            await run(name)
            mark("done")
        }
    }

    static var mainWindow: NSWindow? {
        NSApp.windows.filter { $0.isVisible && $0.frame.width > 800 && $0.frame.height > 300 && !($0 is NSPanel) }.max { $0.frame.width < $1.frame.width }
    }

    static func placeWindow() {
        guard let w = mainWindow, let screen = w.screen ?? NSScreen.main else { return }
        let size = NSSize(width: 1280, height: 800)
        let f = screen.visibleFrame
        if UserDefaults.standard.bool(forKey: "AtticQuiet") {
            // Quiet mode: film the window off to the side without taking focus from whatever you're doing.
            w.setFrame(NSRect(x: screen.frame.maxX + 400, y: f.minY, width: size.width, height: size.height), display: true, animate: false)
            w.orderBack(nil)
        } else {
            w.setFrame(NSRect(x: f.midX - size.width / 2, y: f.midY - size.height / 2, width: size.width, height: size.height), display: true, animate: false)
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
        }
        QuickSearchController.shared.anchor = w.frame
    }

    static func mark(_ name: String) {
        FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data())
    }

    static func waitFor(timeout: Double = 60, _ cond: () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !cond() && Date() < end { try? await Task.sleep(nanoseconds: 150_000_000) }
    }

    static func pause(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }

    static func type(_ text: String, into set: (String) -> Void, speed: Double = 0.055) async {
        var acc = ""
        for ch in text {
            acc.append(ch)
            set(acc)
            await pause(speed)
        }
    }

    static var nav: NavigationModel { AppState.shared.nav }
    static var library: LibraryStore { AppState.shared.library }
    static var cloud: CloudStore { AppState.shared.cloud }

    static func search(_ q: String) async {
        nav.searchText = ""
        await pause(0.4)
        await type(q) { nav.searchText = $0 }
        await pause(0.4)
    }

    static func demoItems(_ names: [String]) -> [FileItem] {
        library.items.filter { names.contains($0.name) }
    }

    static func run(_ name: String) async {
        switch name {
        case "home":
            nav.go(.home); await pause(5)
        case "search":
            nav.go(.home); await pause(1.2)
            await search("screenshots with wifi password"); await pause(1.6)
            if let first = library.items.first(where: { nav.query.matches($0, ocr: AppState.shared.ocr.texts[$0.path]) }) {
                nav.selection = [first.url]; nav.focused = first.url; nav.showInspector = true
            }
            await pause(3.2)
            nav.showInspector = false
            await search("videos over 1 gb older than 6 months"); await pause(2.8)
            await search("pdfs from gmail"); await pause(2.6)
            nav.searchText = ""; await pause(0.6)
        case "downloads":
            nav.go(.downloadedFrom); await pause(2.6)
            nav.go(.source("Gmail")); await pause(2.4)
            nav.goBack(); await pause(1.6)
        case "cleanup":
            nav.go(.cleanup); await pause(2.6)
            nav.go(.cleanupCard(.forgottenDownloads)); await pause(3)
            nav.go(.duplicates); await pause(0.8)
            AppState.shared.dupes.scan(library.items)
            await waitFor { !AppState.shared.dupes.scanning }
            await pause(2.6)
            nav.go(.deepClean)
            await waitFor { AppState.shared.deepClean.scanned && !AppState.shared.deepClean.scanning }
            await pause(1)
            for r in AppState.shared.deepClean.items where r.recommended && r.group.canTrash {
                AppState.shared.deepClean.checked.insert(r.url); await pause(0.12)
            }
            await pause(2.4)
        case "memory":
            nav.go(.memory); await pause(6)
        case "folders":
            let home = Locations.home
            nav.go(.home); await pause(1.4)
            nav.go(.folder(home.path)); await pause(2.6)
            let downloads = home.appendingPathComponent("Downloads")
            nav.go(.folder(downloads.path)); await pause(2.4)
            let pdf = ((try? FileManager.default.contentsOfDirectory(at: downloads, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "pdf" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.first
            if let pdf {
                nav.selection = [pdf]; nav.focused = pdf; await pause(0.8)
                nav.showInspector = true; await pause(2.6)
                nav.showInspector = false; await pause(0.6)
            }
            nav.viewMode = .list; await pause(2.2)
            nav.viewMode = .grid; await pause(0.8)
            nav.go(.folder(home.appendingPathComponent("Pictures").path)); await pause(2.4)
            nav.goBack(); await pause(1.2)
            nav.goBack(); await pause(1.8)
        case "looks":
            nav.go(.home); await pause(2.4)
            UserDefaults.standard.set(Look.minimal.rawValue, forKey: Prefs.look); await pause(3)
            nav.go(.folder(Locations.home.path)); await pause(2.4)
            UserDefaults.standard.set(Look.playful.rawValue, forKey: Prefs.look); await pause(2.6)
            nav.go(.home); await pause(1.6)
        case "quicksearch":
            nav.go(.home); await pause(1)
            QuickSearchController.shared.show(); await pause(0.8)
            await type("invoice from gmail") { QuickSearchController.shared.state.text = $0 }
            await pause(1.4)
            QuickSearchController.shared.state.index = 1; await pause(0.9)
            QuickSearchController.shared.state.index = 0; await pause(1)
            await type("big videos") { QuickSearchController.shared.state.text = $0 }
            await pause(2)
            QuickSearchController.shared.hide(); await pause(0.6)
        case "offload":
            nav.go(.category(.videos)); await pause(1.6)
            let picks = demoItems(["Lisbon trip.mp4", "Studio session raw.mov"])
            nav.selection = Set(picks.map(\.url)); await pause(1.4)
            UserDefaults.standard.set("r2", forKey: "offloadDestination")
            nav.autoStartOffload = true
            nav.offloadRequest = picks
            await waitFor(timeout: 300) { cloud.offloadProgress?.finished == true }
            await pause(2.2)
            nav.offloadRequest = nil; await pause(0.8)
            nav.go(.offloaded); await pause(2.6)
            nav.go(.cloud); await cloud.open(prefix: "", record: false); await pause(2.8)
            nav.go(.offloaded); await pause(1)
            for r in cloud.records where !r.isICloud && r.originalPath.hasPrefix(DemoData.root?.path ?? "/nonexistent") {
                await cloud.restore(r, open: false, removeFromCloud: true, reveal: false)
            }
            await pause(2.4)
        case "ai":
            nav.go(.home); await pause(1)
            nav.searchText = ""
            await type("the invoice my accountant emailed me") { nav.searchText = $0 }
            await waitFor(timeout: 20) { !nav.aiThinking && nav.query.byAI }
            await pause(1.2)
            if let first = library.items.first(where: { nav.query.matches($0, ocr: AppState.shared.ocr.texts[$0.path]) }) {
                nav.selection = [first.url]; nav.focused = first.url; nav.showInspector = true
            }
            await pause(2.6)
            nav.showInspector = false
            nav.searchText = ""
            nav.go(.screenshots); await pause(1.2)
            if let shot = library.items.first(where: { $0.name.contains("09.41.12") }) {
                nav.selection = [shot.url]; nav.focused = shot.url; await pause(0.8)
                nav.showInspector = true; await pause(1.4)
                FileActions.copyText([shot])
                await pause(3)
            }
            nav.showInspector = false; await pause(0.5)
        case "stills":
            await stills()
        default:
            break
        }
    }

    /// Pauses on every screen until the capture script says it has taken the screenshot.
    static func stills() async {
        var n = 0
        func shot(_ label: String) async {
            n += 1
            await pause(1.4)
            mark("shot-\(n)-\(label)")
            await waitFor(timeout: 60) { FileManager.default.fileExists(atPath: dir.appendingPathComponent("next-\(n)").path) }
        }
        // Put two real clips in R2 first, so the bucket, Offloaded list and Home card have something to show.
        let clips = demoItems(["Lisbon trip.mp4", "Studio session raw.mov"])
        await cloud.offload(clips, after: .delete, leaveStubs: true)
        nav.go(.home); await shot("home")
        UserDefaults.standard.set(Look.minimal.rawValue, forKey: Prefs.look); await shot("home-minimal")
        UserDefaults.standard.set(Look.playful.rawValue, forKey: Prefs.look)
        nav.go(.folder(Locations.home.path)); await shot("folder-home")
        nav.go(.folder(Locations.home.appendingPathComponent("Downloads").path)); await shot("folder-downloads")
        nav.go(.screenshots); await shot("screenshots")
        nav.searchText = "screenshots with wifi password"
        await waitFor { !nav.query.isEmpty }
        if let first = library.items.first(where: { nav.query.matches($0, ocr: AppState.shared.ocr.texts[$0.path]) }) {
            nav.selection = [first.url]; nav.focused = first.url; nav.showInspector = true
        }
        await shot("search")
        nav.showInspector = false
        nav.searchText = "the invoice my accountant emailed me"
        await waitFor(timeout: 20) { !nav.aiThinking && nav.query.byAI }
        if let first = library.items.first(where: { nav.query.matches($0, ocr: AppState.shared.ocr.texts[$0.path]) }) {
            nav.selection = [first.url]; nav.focused = first.url; nav.showInspector = true
        }
        await shot("ai-search")
        nav.showInspector = false
        nav.go(.category(.images)); await shot("images")
        nav.go(.downloadedFrom); await shot("downloaded-from")
        nav.go(.cleanup); await shot("cleanup")
        nav.go(.cleanupCard(.forgottenDownloads)); await shot("cleanup-review")
        nav.go(.duplicates)
        AppState.shared.dupes.scan(library.items)
        await waitFor { !AppState.shared.dupes.scanning }
        await shot("duplicates")
        nav.go(.deepClean)
        await waitFor { AppState.shared.deepClean.scanned && !AppState.shared.deepClean.scanning }
        for r in AppState.shared.deepClean.items where r.recommended && r.group.canTrash { AppState.shared.deepClean.checked.insert(r.url) }
        await shot("deep-clean")
        nav.go(.memory); await pause(1); await shot("memory")
        nav.go(.largeFiles); nav.viewMode = .list; await shot("large-files")
        nav.viewMode = .grid
        let picks = demoItems(["Drone - Coast 4K.mov", "Kyoto timelapse.mov", "Wedding film final.mov"])
        UserDefaults.standard.set("icloud", forKey: "offloadDestination")
        nav.go(.category(.videos)); nav.selection = Set(picks.map(\.url))
        nav.offloadRequest = picks; await shot("offload-sheet-icloud")
        nav.offloadRequest = nil; await pause(0.6)
        UserDefaults.standard.set("r2", forKey: "offloadDestination")
        nav.offloadRequest = picks; await shot("offload-sheet-r2")
        nav.offloadRequest = nil
        nav.selection = []
        nav.go(.cloud); await cloud.open(prefix: "Attic Demo/Movies/", record: false); await shot("cloud")
        nav.go(.offloaded); await shot("offloaded")
        nav.go(.home)
        QuickSearchController.shared.show()
        QuickSearchController.shared.state.text = "invoice from gmail"
        await shot("quick-search")
        QuickSearchController.shared.hide()
        // Put the demo clips back
        for r in cloud.records where !r.isICloud && r.originalPath.hasPrefix(DemoData.root?.path ?? "/nonexistent") {
            await cloud.restore(r, open: false, removeFromCloud: true, reveal: false)
        }
    }
}
