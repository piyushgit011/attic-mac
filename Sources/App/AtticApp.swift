import SwiftUI
import AppKit

@main
struct AtticApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(Prefs.menuBarEnabled) private var menuBarEnabled = true

    init() {
        if CommandLine.arguments.contains("--selftest") {
            SelfTest.runAndExit()
        }
    }

    var body: some Scene {
        Window("Attic", id: "main") {
            ContentView()
                .withAtticEnvironment()
                .frame(minWidth: 960, minHeight: 600)
        }
        .defaultSize(width: 1280, height: 820)
        .commands { AtticCommands() }

        Settings {
            SettingsView()
                .withAtticEnvironment()
        }

        MenuBarExtra(isInserted: $menuBarEnabled) {
            MenuBarView()
                .withAtticEnvironment()
        } label: {
            Image("MenuBarMark")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppState {
    static let shared = AppState()
    let library = LibraryStore()
    let transfers = TransferCenter()
    let nav = NavigationModel()
    let ocr = OCRIndex()
    let memory = MemoryMonitor()
    let deepClean = DeepCleanModel()
    let dupes = DuplicatesModel()
    let storage = StorageBreakdownModel()
    let cloud: CloudStore

    private init() {
        cloud = CloudStore(transfers: transfers, library: library)
        let starts: [String: SidebarItem] = ["storage": .storage, "cloud": .cloud, "deepClean": .deepClean, "memory": .memory, "cleanup": .cleanup,
                                             "duplicates": .duplicates, "offloaded": .offloaded, "downloads": .downloadedFrom,
                                             "large": .largeFiles, "images": .category(.images)]
        if let s = UserDefaults.standard.string(forKey: "AtticStart"), let item = starts[s] { nav.setInitial(item) }
        if let q = UserDefaults.standard.string(forKey: "AtticSearch") { nav.searchText = q }
    }
}

extension View {
    @MainActor
    func withAtticEnvironment() -> some View {
        let s = AppState.shared
        return self
            .environment(s.library)
            .environment(s.cloud)
            .environment(s.nav)
            .environment(s.transfers)
            .environment(s.ocr)
            .environment(s.memory)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        QuickSearchController.shared.installHotKey()
        Tour.startIfRequested()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.isAtticStub {
            Task { await AppState.shared.cloud.restoreStub(at: url, open: true) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

// MARK: - Navigation

enum SidebarItem: Hashable {
    case home, recents, downloadedFrom, source(String)
    case category(FileCategory)
    case largeFiles, screenshots
    case storage, cleanup, cleanupCard(CleanupCard.Kind), duplicates, deepClean, memory
    case cloud, offloaded
}

enum ViewMode: String { case grid, list }

@MainActor @Observable
final class NavigationModel {
    var sidebar: SidebarItem? = .home {
        didSet {
            guard !restoring, oldValue != sidebar else { return }
            // Sidebar clicks: remember where we were, and leave any search.
            record(NavEntry(sidebar: oldValue ?? .home, search: searchText,
                            cloudPrefix: oldValue == .cloud ? AppState.shared.cloud.prefix : nil))
            if !searchText.isEmpty {
                restoring = true
                searchText = ""
                query = SearchQuery()
                restoring = false
            }
            selection = []
        }
    }
    var searchText = "" {
        didSet {
            scheduleParse()
            if !restoring && oldValue.isEmpty && !searchText.isEmpty {
                record(NavEntry(sidebar: sidebar ?? .home, search: "", cloudPrefix: sidebar == .cloud ? AppState.shared.cloud.prefix : nil))
            }
        }
    }

    // Back / forward history, like Finder.
    struct NavEntry: Equatable {
        var sidebar: SidebarItem
        var search: String
        var cloudPrefix: String?
    }
    var backStack: [NavEntry] = []
    var forwardStack: [NavEntry] = []
    private(set) var restoring = false
    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    private func snapshot() -> NavEntry {
        NavEntry(sidebar: sidebar ?? .home, search: searchText, cloudPrefix: sidebar == .cloud ? AppState.shared.cloud.prefix : nil)
    }

    private func record(_ e: NavEntry) {
        if backStack.last != e { backStack.append(e) }
        if backStack.count > 100 { backStack.removeFirst() }
        forwardStack.removeAll()
    }

    /// Called by the cloud browser when you open a folder, so Back goes to the parent.
    func recordCloud(prefix: String) {
        guard !restoring else { return }
        record(NavEntry(sidebar: .cloud, search: "", cloudPrefix: prefix))
    }

    func setInitial(_ item: SidebarItem) {
        restoring = true
        sidebar = item
        restoring = false
    }

    func goBack() {
        guard let e = backStack.popLast() else { return }
        forwardStack.append(snapshot())
        restore(e)
    }

    func goForward() {
        guard let e = forwardStack.popLast() else { return }
        backStack.append(snapshot())
        restore(e)
    }

    private func restore(_ e: NavEntry) {
        restoring = true
        sidebar = e.sidebar
        searchText = e.search
        query = QueryParser.parse(e.search)
        selection = []
        restoring = false
        if e.sidebar == .cloud, let p = e.cloudPrefix, AppState.shared.cloud.prefix != p {
            Task { await AppState.shared.cloud.open(prefix: p, record: false) }
        }
    }
    var query = SearchQuery()
    var aiThinking = false
    var selection = Set<URL>()
    var focused: URL?
    var showInspector = false
    var viewMode: ViewMode = .grid
    var cardSize: Double = UserDefaults.standard.object(forKey: Prefs.cardSize) as? Double ?? 150 {
        didSet { UserDefaults.standard.set(cardSize, forKey: Prefs.cardSize) }
    }
    var offloadRequest: [FileItem]?
    var autoStartOffload = false
    var quickLookURL: URL?
    var quickLookList: [URL] = []

    private var parseTask: Task<Void, Never>?

    private func scheduleParse() {
        parseTask?.cancel()
        let text = searchText
        parseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            let rules = QueryParser.parse(text)
            self.query = rules
            // Words the rules couldn't place go to Apple's on-device model (never leaves this Mac).
            guard LocalAI.shouldAsk(rules) else { self.aiThinking = false; return }
            self.aiThinking = true
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled, self.searchText == text else { return }
            let ai = await LocalAI.understand(text, rules: rules)
            guard !Task.isCancelled, self.searchText == text else { return }
            if let ai, !ai.isEmpty { self.query = ai }
            self.aiThinking = false
        }
    }

    func remove(chip: SearchChip) {
        query = query.removing(chip)
        // Keep the text field honest: rebuild it from the remaining chips.
        searchText = query.chips.map { chip -> String in
            switch chip {
            case .text(let t): return t
            case .category(let c): return c.title.lowercased()
            case .exts(let l, _): return l.lowercased()
            case .screenshots: return "screenshots"
            case .iphone: return "from iphone"
            case .source(let s): return "from \(s.lowercased())"
            case .minSize(let n): return "over \(n / 1_000_000)mb"
            case .maxSize(let n): return "under \(max(1, n / 1_000_000))mb"
            case .dateRange(let l, _, _), .olderThan(let l, _): return l.lowercased()
            }
        }.joined(separator: " ")
    }

    func go(_ item: SidebarItem) {
        guard item != sidebar || !searchText.isEmpty else { return }
        let before = snapshot()
        restoring = true
        searchText = ""
        query = SearchQuery()
        sidebar = item
        selection = []
        restoring = false
        record(before)
    }

    func selectedItems(in library: LibraryStore) -> [FileItem] {
        library.items.filter { selection.contains($0.url) }
    }

    func quickLook(_ url: URL, in list: [URL]) {
        quickLookList = list
        quickLookURL = url
    }
}

struct AtticCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button("Grid") { AppState.shared.nav.viewMode = .grid }.keyboardShortcut("1")
            Button("List") { AppState.shared.nav.viewMode = .list }.keyboardShortcut("2")
            Button("Bigger Cards") { AppState.shared.nav.cardSize = min(320, AppState.shared.nav.cardSize + 30) }.keyboardShortcut("+")
            Button("Smaller Cards") { AppState.shared.nav.cardSize = max(90, AppState.shared.nav.cardSize - 30) }.keyboardShortcut("-")
            Button("Show Inspector") { AppState.shared.nav.showInspector.toggle() }.keyboardShortcut("i")
            Divider()
            Button("Rescan") { AppState.shared.library.scan() }.keyboardShortcut("r")
        }
        CommandMenu("Go") {
            Button("Back") { AppState.shared.nav.goBack() }.keyboardShortcut("[")
            Button("Forward") { AppState.shared.nav.goForward() }.keyboardShortcut("]")
            Divider()
            Button("Home") { AppState.shared.nav.go(.home) }.keyboardShortcut("h", modifiers: [.command, .shift])
            Button("Downloaded From") { AppState.shared.nav.go(.downloadedFrom) }.keyboardShortcut("j", modifiers: [.command, .shift])
            Button("Storage") { AppState.shared.nav.go(.storage) }.keyboardShortcut("s", modifiers: [.command, .shift])
            Button("Clean Up") { AppState.shared.nav.go(.cleanup) }.keyboardShortcut("k", modifiers: [.command, .shift])
            Button("Duplicates") { AppState.shared.nav.go(.duplicates) }.keyboardShortcut("d", modifiers: [.command, .shift])
            Button("Deep Clean") { AppState.shared.nav.go(.deepClean) }.keyboardShortcut("e", modifiers: [.command, .shift])
            Button("Memory & Swap") { AppState.shared.nav.go(.memory) }.keyboardShortcut("m", modifiers: [.command, .shift])
            Button("Cloud (R2)") { AppState.shared.nav.go(.cloud) }.keyboardShortcut("u", modifiers: [.command, .shift])
            Button("Offloaded Files") { AppState.shared.nav.go(.offloaded) }.keyboardShortcut("o", modifiers: [.command, .shift])
            Divider()
            Button("Quick Search") { QuickSearchController.shared.toggle() }.keyboardShortcut(.space, modifiers: [.command, .shift])
        }
        CommandMenu("Files") {
            Button("Copy Text from Images") {
                let s = AppState.shared
                FileActions.copyText(s.nav.selectedItems(in: s.library))
            }.keyboardShortcut("c", modifiers: [.command, .shift])
            Button("Offload to R2 or iCloud…") {
                let s = AppState.shared
                let sel = s.nav.selectedItems(in: s.library)
                if !sel.isEmpty { s.nav.offloadRequest = sel }
            }.keyboardShortcut("u", modifiers: [.command, .option])
            Button("Move to Trash") {
                let s = AppState.shared
                let sel = s.nav.selectedItems(in: s.library)
                if !sel.isEmpty { Task { await s.library.trash(sel) } }
            }
        }
    }
}


/// Results kept across navigation so switching screens doesn't throw away a long scan.
@MainActor @Observable
final class DeepCleanModel {
    var items: [JunkItem] = []
    var checked = Set<URL>()
    var scanning = false
    var current = ""
    var scanned = false
    var trashSize: Int64?
}

@MainActor @Observable
final class DuplicatesModel {
    var groups: [DuplicateGroup] = []
    var scanning = false
    var progress = 0.0
    var scanned = false

    func scan(_ items: [FileItem]) {
        scanning = true
        progress = 0
        Task.detached(priority: .userInitiated) {
            let found = DuplicateFinder.find(in: items, progress: { p in Task { @MainActor in self.progress = p } }, isCancelled: { false })
            await MainActor.run {
                self.groups = found
                self.scanning = false
                self.scanned = true
            }
        }
    }
}
