import SwiftUI
import AppKit
import Carbon.HIToolbox
import ServiceManagement

// MARK: - Settings

struct SettingsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(CloudStore.self) private var cloud
    @AppStorage(Prefs.menuBarEnabled) private var menuBar = true
    @AppStorage(Prefs.quickSearchEnabled) private var quickSearch = true
    @AppStorage(Prefs.ocrEnabled) private var ocr = true
    @AppStorage(Prefs.afterUpload) private var after = AfterUpload.trash.rawValue
    @AppStorage(Prefs.leaveStubs) private var stubs = true
    @AppStorage(Prefs.allowOtherBucketWrites) private var otherBuckets = false
    @AppStorage(Prefs.look) private var look = Look.playful.rawValue
    @AppStorage(Prefs.appearance) private var appearance = "system"
    @State private var roots = Prefs.scanRootPaths
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    private var keeper: ScreenshotKeeper { ScreenshotKeeper.shared }

    var body: some View {
        TabView {
            Form {
                Section("Look") {
                    Picker("Look", selection: $look) {
                        ForEach(Look.allCases) { Label($0.title, systemImage: $0.symbol).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    Text("Playful uses soft colour. Minimal is black, white and grey. Switch any time with ⌃⌘T or from the top bar.")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Appearance", selection: $appearance) {
                        Text("Same as my Mac").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    Toggle("Open Attic when you log in", isOn: Binding(get: { openAtLogin }, set: { on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            library.show(toast: "Couldn’t change login items: \(error.localizedDescription)")
                        }
                        openAtLogin = SMAppService.mainApp.status == .enabled
                    }))
                }
                Section("Screenshots") {
                    Toggle("Keep a history of screenshots", isOn: Binding(get: { keeper.enabled }, set: { keeper.enabled = $0 }))
                    LabeledContent("Saved to") {
                        HStack {
                            Text(Fmt.path(ScreenshotKeeper.folder)).foregroundStyle(.secondary)
                            Button("Choose…") { chooseScreenshotFolder() }.controlSize(.small)
                        }
                    }
                    Text(ScreenshotKeeper.macOSCopiesToClipboard
                         ? "Your Mac copies screenshots to the clipboard instead of saving them. With this on, Attic saves a copy of each new one (only real screenshots, not other images you copy) while it’s open, so you can find them and search their text."
                         : "Your Mac already saves screenshots as files. This also keeps the ones you copy to the clipboard with ⌃⇧⌘4.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Section("Scan locations") {
                    ForEach(roots, id: \.self) { r in
                        HStack {
                            Image(systemName: "folder")
                            Text(Fmt.path(r))
                            Spacer()
                            Button { roots.removeAll { $0 == r }; save() } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                        }
                    }
                    HStack {
                        Button("Add Folder…") { addFolder() }
                        Button("Reset") { roots = Prefs.defaultRoots(); save() }
                    }
                }
                Section {
                    Toggle("Show Attic in the menu bar (latest downloads)", isOn: $menuBar)
                    Toggle("Quick Search with ⇧⌘Space from any app", isOn: $quickSearch)
                        .onChange(of: quickSearch) { _, _ in QuickSearchController.shared.installHotKey() }
                    Toggle("Read text in screenshots and recent images (on this Mac)", isOn: $ocr)
                }
                Section("On-device intelligence") {
                    Label(LocalAI.statusText, systemImage: "apple.intelligence")
                    Text("Text recognition uses Apple Vision (the Live Text engine). Search help uses Apple’s on-device language model. Both run on this Mac; nothing is uploaded.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Siri and Shortcuts: “Find files in Attic”, “How much space is left in Attic”, “Free up space with Attic”.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                Section("Cloudflare R2") {
                    if let c = cloud.creds {
                        LabeledContent("Bucket", value: c.bucket)
                        LabeledContent("Account", value: String(c.accountId.prefix(8)) + "…")
                        LabeledContent("Keys from", value: c.source == "versely" ? "Versely backend" : "Entered by hand")
                        Button("Disconnect", role: .destructive) { cloud.disconnect() }
                    } else {
                        Text("Not connected. Open Cloud (R2) in the sidebar to set it up.").foregroundStyle(.secondary)
                    }
                }
                Section("When offloading") {
                    Picker("After a verified upload", selection: $after) {
                        ForEach(AfterUpload.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Toggle("Leave a .attic placeholder in the original folder", isOn: $stubs)
                }
                Section("Safety") {
                    Toggle("Allow uploads and deletes in other buckets on this account", isOn: $otherBuckets)
                    Text("Off by default so Versely’s production buckets stay read-only in Attic.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Cloud", systemImage: "cloud") }
        }
        .frame(width: 580, height: 620)
    }

    private func save() {
        Prefs.scanRootPaths = roots
        library.scan()
    }

    private func chooseScreenshotFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = ScreenshotKeeper.folder.deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url {
            UserDefaults.standard.set(url.path, forKey: Prefs.screenshotFolder)
            if !roots.contains(where: { url.path.hasPrefix($0 + "/") || url.path == $0 }) {
                roots.append(url.path)
                save()
            }
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            roots += panel.urls.map(\.path).filter { !roots.contains($0) }
            save()
        }
    }
}

// MARK: - Menu bar

struct MenuBarView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(MemoryMonitor.self) private var memory
    @Environment(CloudStore.self) private var cloud
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image("LogoMark").resizable().frame(width: 22, height: 22)
                Text("Attic").font(.headline)
                Spacer()
                Text("\(Fmt.bytes(library.disk.available)) free").font(.caption).foregroundStyle(.secondary)
            }
            ProgressView(value: library.disk.usedFraction)
            HStack {
                Label("Swap \(Fmt.bytes(Int64(memory.snapshot.swapUsed)))", systemImage: "memorychip")
                Spacer()
                if cloud.isConnected { Label("\(Fmt.bytes(cloud.offloadedBytes)) in R2", systemImage: "cloud") }
            }
            .font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Latest downloads").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if library.latestDownloads.isEmpty {
                Text(library.isScanning ? "Scanning…" : "Nothing yet").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(library.latestDownloads) { item in
                HStack(spacing: 8) {
                    ThumbView(url: item.url, side: 30).frame(width: 30, height: 30).clipShape(RoundedRectangle(cornerRadius: 5))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name).font(.callout).lineLimit(1).truncationMode(.middle)
                        Text("\(Fmt.bytes(item.size)) · \(Fmt.ago(item.arrivalDate))\(item.source.map { " · \($0)" } ?? "")")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture { NSWorkspace.shared.open(item.url) }
                .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
                .contextMenu {
                    Button("Show in Finder") { FileActions.reveal([item]) }
                    Button("Show in Attic") { show(item) }
                }
            }
            Divider()
            HStack {
                Button("Open Attic") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
                Button("Quick Search") { QuickSearchController.shared.show() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 340)
        .onAppear {
            library.startIfNeeded()
            library.refreshDisk()
            memory.refresh()
        }
    }

    private func show(_ item: FileItem) {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
        AppState.shared.nav.go(.downloadedFrom)
        AppState.shared.nav.selection = [item.url]
        AppState.shared.nav.focused = item.url
        AppState.shared.nav.showInspector = true
    }
}

// MARK: - Quick Search (⇧⌘Space)

@MainActor
final class QuickSearchController {
    static let shared = QuickSearchController()
    private var panel: NSPanel?
    let state = QuickSearchState()
    /// When set (tours), the panel opens over this frame instead of the top of the screen.
    var anchor: NSRect?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerInstalled = false

    func installHotKey() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
        guard UserDefaults.standard.object(forKey: Prefs.quickSearchEnabled) as? Bool ?? true else { return }
        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { QuickSearchController.shared.toggle() } }
                return noErr
            }, 1, &spec, nil, nil)
            handlerInstalled = true
        }
        let id = EventHotKeyID(signature: OSType(0x4154_5443), id: 1) // 'ATTC'
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(cmdKey | shiftKey), id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func toggle() {
        if panel?.isVisible == true { hide() } else { show() }
    }

    func show() {
        if Tour.isActive {
            state.text = ""
            state.inlineVisible = true
            return
        }
        if panel == nil {
            let p = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
                             styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                             backing: .buffered, defer: false)
            p.titleVisibility = .hidden
            p.titlebarAppearsTransparent = true
            p.isFloatingPanel = true
            p.level = .floating
            p.hidesOnDeactivate = false
            p.isMovableByWindowBackground = true
            p.standardWindowButton(.closeButton)?.isHidden = true
            p.standardWindowButton(.miniaturizeButton)?.isHidden = true
            p.standardWindowButton(.zoomButton)?.isHidden = true
            p.contentView = NSHostingView(rootView: QuickSearchView(close: { [weak self] in self?.hide() }).withAtticEnvironment())
            panel = p
        }
        guard let panel else { return }
        if let a = anchor {
            panel.setFrameOrigin(NSPoint(x: a.midX - 320, y: a.maxY - 140 - 420))
        } else if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - 320, y: f.maxY - f.height * 0.22 - 420))
        }
        AppState.shared.library.startIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .quickSearchShown, object: nil)
    }

    func hide() {
        state.inlineVisible = false
        panel?.orderOut(nil)
    }
}

@MainActor @Observable
final class QuickSearchState {
    var text = ""
    var index = 0
    var inlineVisible = false
}

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

extension Notification.Name {
    static let quickSearchShown = Notification.Name("AtticQuickSearchShown")
}

struct QuickSearchView: View {
    let close: () -> Void
    @Environment(LibraryStore.self) private var library
    @Environment(OCRIndex.self) private var ocr
    @Environment(\.openWindow) private var openWindow
    @Bindable private var state = QuickSearchController.shared.state
    private var text: String { state.text }
    private var index: Int { state.index }
    @FocusState private var focused: Bool

    private var results: [FileItem] {
        let q = QueryParser.parse(text)
        if q.isEmpty { return library.recents.prefix(12).map { $0 } }
        return Array(library.items.lazy.filter { q.matches($0, ocr: q.wantsOCR ? ocr.texts[$0.path] : nil) }.prefix(200))
            .sorted { $0.arrivalDate > $1.arrivalDate }.prefix(12).map { $0 }
    }

    var body: some View {
        let list = results
        let q = QueryParser.parse(text)
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.title2).foregroundStyle(.secondary)
                TextField("Search your Mac in plain English…", text: $state.text)
                    .textFieldStyle(.plain).font(.system(size: 22))
                    .focused($focused)
                    .onSubmit { activate(list) }
                    .onChange(of: state.text) { _, _ in state.index = 0 }
            }
            .padding(16)
            if !q.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(q.chips) { c in
                            Label(c.label, systemImage: c.symbol).font(.caption)
                                .padding(.horizontal, 8).padding(.vertical, 4).background(.quaternary, in: Capsule())
                        }
                    }.padding(.horizontal, 16)
                }.padding(.bottom, 8)
            }
            Divider()
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, item in
                        HStack(spacing: 10) {
                            ThumbView(url: item.url, side: 34).frame(width: 34, height: 34).clipShape(RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name).lineLimit(1).truncationMode(.middle)
                                Text("\(Fmt.path(item.url.deletingLastPathComponent())) · \(Fmt.bytes(item.size)) · \(Fmt.ago(item.arrivalDate))")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(i == index ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                        .onTapGesture { state.index = i; activate(list) }
                    }
                }
                .padding(8)
            }
            Divider()
            HStack(spacing: 14) {
                Text("↩ open").font(.caption)
                Text("⌥↩ show in Finder").font(.caption)
                Text("⌘↩ show in Attic").font(.caption)
                Spacer()
                Text("esc to close").font(.caption)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .frame(width: 640, height: 420)
        .background(.regularMaterial)
        .onKeyPress(.downArrow) { state.index = min(index + 1, max(0, list.count - 1)); return .handled }
        .onKeyPress(.upArrow) { state.index = max(0, index - 1); return .handled }
        .onKeyPress(.escape) { close(); return .handled }
        .onAppear { focused = true }
        .onReceive(NotificationCenter.default.publisher(for: .quickSearchShown)) { _ in focused = true; state.text = "" }
    }

    private func activate(_ list: [FileItem]) {
        guard list.indices.contains(index) else { return }
        let item = list[index]
        let mods = NSEvent.modifierFlags
        close()
        if mods.contains(.option) {
            FileActions.reveal([item])
        } else if mods.contains(.command) {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
            let nav = AppState.shared.nav
            nav.searchText = text
            nav.selection = [item.url]
            nav.focused = item.url
            nav.showInspector = true
        } else {
            FileActions.open([item])
        }
    }
}
