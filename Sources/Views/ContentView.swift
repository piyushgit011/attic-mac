import SwiftUI
import QuickLook

struct ContentView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(NavigationModel.self) private var nav
    @Environment(TransferCenter.self) private var transfers
    @Environment(CloudStore.self) private var cloud
    @Environment(MusicPlayer.self) private var player

    var body: some View {
        @Bindable var nav = nav
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            DetailRouter()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .inspector(isPresented: $nav.showInspector) {
                    InspectorView()
                        .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
                }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { nav.goBack() } label: { Label("Back", systemImage: "chevron.left") }
                    .disabled(!nav.canGoBack).help("Back (⌘[)")
                Button { nav.goForward() } label: { Label("Forward", systemImage: "chevron.right") }
                    .disabled(!nav.canGoForward).help("Forward (⌘])")
            }
            ToolbarItem(placement: .navigation) {
                TopSearchField()
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if player.current != nil { MiniPlayer() }
                if !transfers.active.isEmpty { TransfersButton() }
                FreeSpaceButton()
                LookSwitcher()
                Button { nav.showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.right") }
                    .help("Show details (⌘I)")
            }
        }
        .overlay(alignment: .bottom) { ToastView() }
        .sheet(item: Binding(get: { Tour.isActive ? nil : nav.offloadRequest.map(OffloadRequest.init) }, set: { nav.offloadRequest = $0?.items })) { req in
            OffloadSheet(items: req.items)
        }
        .overlay {
            // Tours film one window, so pop-ups are drawn inside it instead of in their own windows.
            if Tour.isActive {
                ZStack {
                    if let items = nav.offloadRequest {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        OffloadSheet(items: items)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
                            .frame(maxHeight: .infinity, alignment: .top).padding(.top, 70)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if QuickSearchController.shared.state.inlineVisible {
                        Color.black.opacity(0.2).ignoresSafeArea()
                        QuickSearchView(close: { QuickSearchController.shared.hide() })
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
                            .frame(maxHeight: .infinity, alignment: .top).padding(.top, 60)
                            .transition(.scale(scale: 0.96).combined(with: .opacity))
                    }
                }
                .animation(.spring(duration: 0.35), value: nav.offloadRequest != nil)
                .animation(.spring(duration: 0.3), value: QuickSearchController.shared.state.inlineVisible)
            }
        }
        .modifier(TourActiveLook())
        .quickLookPreview($nav.quickLookURL, in: nav.quickLookList)
        .confirmationDialog(cloudDeleteTitle, isPresented: Binding(get: { !library.pendingCloudDelete.isEmpty },
                                                                  set: { if !$0 { library.pendingCloudDelete = [] } })) {
            Button("Delete from iCloud", role: .destructive) { library.deleteFromICloud(library.pendingCloudDelete) }
            Button("Cancel", role: .cancel) { library.pendingCloudDelete = [] }
        } message: {
            Text("\(library.pendingCloudDelete.prefix(3).map(\.name).joined(separator: ", "))\(library.pendingCloudDelete.count > 3 ? " and \(library.pendingCloudDelete.count - 3) more" : "") \(library.pendingCloudDelete.count == 1 ? "is" : "are") only in iCloud and use no space on this Mac. macOS won’t move iCloud-only files to the Trash without downloading them first, so Attic can delete them from iCloud instead. You can recover them from iCloud.com ▸ Drive ▸ Recently Deleted for 30 days.")
        }
        .alert("Rename “\(nav.renameTarget?.name ?? "")”", isPresented: Binding(get: { nav.renameTarget != nil }, set: { if !$0 { nav.renameTarget = nil } })) {
            TextField("Name", text: $nav.renameText)
            Button("Rename") { nav.commitRename() }
            Button("Cancel", role: .cancel) { nav.renameTarget = nil }
        }
        .alert("Go to Folder", isPresented: $nav.showGoToFolder) {
            TextField("~/Downloads", text: $nav.goToText)
            Button("Go") { nav.goToFolder() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Type a folder’s path, like ~/Documents/Invoices or /Applications.")
        }
        .onAppear { library.startIfNeeded() }
    }
}

extension ContentView {
    var cloudDeleteTitle: String {
        let n = library.pendingCloudDelete.count
        let total = library.pendingCloudDelete.reduce(Int64(0)) { $0 + $1.size }
        return "Delete \(Fmt.plural(n, "iCloud file")) (\(Fmt.bytes(total))) from iCloud?"
    }
}

struct OffloadRequest: Identifiable {
    let id = UUID()
    let items: [FileItem]
}

/// The search field on the left of the top bar. ⌘F jumps to it.
struct TopSearchField: View {
    @Environment(NavigationModel.self) private var nav
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var nav = nav
        let glass: Bool = { if #available(macOS 26, *) { return true } else { return false } }()
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search, or try “pdfs from last week”…", text: $nav.searchText)
                .textFieldStyle(.plain)
                .focused($focused)
                .onExitCommand { nav.searchText = ""; focused = false }
            if nav.searchText.isEmpty {
                HStack(spacing: 2) { KeyCap("⌘"); KeyCap("F") }
            } else {
                Button { nav.searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).help("Clear search")
            }
        }
        .padding(.horizontal, glass ? 6 : 9)
        .frame(width: 380, height: 28)
        .background {
            if !glass {
                RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.14), lineWidth: focused ? 2 : 1))
            }
        }
        .onChange(of: nav.focusSearchToken) { _, _ in focused = true }
    }
}

/// "95.9 GB free" in the top bar. Opens Storage.
struct FreeSpaceButton: View {
    @Environment(LibraryStore.self) private var library
    @Environment(NavigationModel.self) private var nav

    var body: some View {
        let disk = library.disk
        Button { nav.go(.storage) } label: {
            HStack(spacing: 5) {
                if library.isScanning { ProgressView().controlSize(.mini) }
                Text("Free").foregroundStyle(.secondary)
                Text(Fmt.bytes(disk.available)).fontWeight(.semibold).monospacedDigit()
                    .foregroundStyle(disk.usedFraction > 0.9 ? Color.red : disk.usedFraction > 0.8 ? Color.orange : Color.primary)
            }
            .font(.callout)
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .help(library.isScanning ? "Scanning… \(Fmt.count(library.scanCount)) files" : "\(Fmt.bytes(disk.available)) free of \(Fmt.bytes(disk.total)). Click for the full breakdown.")
    }
}

struct DetailRouter: View {
    @Environment(LibraryStore.self) private var library
    @Environment(NavigationModel.self) private var nav

    var body: some View {
        if !nav.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            SearchResultsView()
        } else {
            switch nav.sidebar ?? .home {
            case .home: HomeView()
            case .recents: FileBrowserView(title: "Recents", subtitle: "Newest arrivals first", items: library.recents, defaultSort: .arrival).id("recents")
            case .downloadedFrom: DownloadedFromView()
            case .source(let s): FileBrowserView(title: s, subtitle: "Downloaded from \(s)", items: library.items(from: s), defaultSort: .arrival).id("source-\(s)")
            case .category(let c): FileBrowserView(title: c.title, subtitle: nil, items: library.items(in: c), defaultSort: c == .apps ? .size : .arrival).id("cat-\(c.rawValue)")
            case .largeFiles:
                FileBrowserView(title: "Large Files", subtitle: "Over 100 MB", items: library.largeFiles, defaultSort: .size,
                                banner: AnyView(AppLibraryNote()), emptyTitle: "Nothing big on this Mac",
                                emptyMessage: library.largeFilesEmptyMessage).id("large")
            case .screenshots:
                FileBrowserView(title: "Screenshots", subtitle: "Search finds the text inside them", items: library.screenshots, defaultSort: .arrival,
                                banner: AnyView(ScreenshotHistoryBanner())).id("shots")
            case .folder(let p): FolderBrowserView(path: p).id("folder-\(p)")
            case .saved(let q): SavedSearchView(text: q).id("saved-\(q)")
            case .storage: StorageView()
            case .cleanup: CleanupOverview()
            case .cleanupCard(let kind):
                if let card = library.cleanupCards.first(where: { $0.kind == kind }) { CleanupReviewView(card: card) }
                else { EmptyStateView(symbol: "checkmark.seal", title: "All clear", message: "Nothing left in this card.") }
            case .duplicates: DuplicatesView()
            case .deepClean: DeepCleanView()
            case .memory: MemoryView()
            case .cloud: CloudView()
            case .offloaded: OffloadedView()
            }
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(NavigationModel.self) private var nav
    @Environment(CloudStore.self) private var cloud
    @Environment(MemoryMonitor.self) private var memory
    @AppStorage(Prefs.look) private var look = Look.playful.rawValue

    var body: some View {
        @Bindable var nav = nav
        let dupes = AppState.shared.dupes
        let dupeBytes = dupes.groups.reduce(Int64(0)) { $0 + $1.reclaimable }
        List(selection: $nav.sidebar) {
            Section {
                HStack(spacing: 8) {
                    Image("LogoMark").resizable().frame(width: 22, height: 22)
                    Text("Attic").font(.system(size: 15, weight: .semibold))
                }
                .padding(.vertical, 2)
                .selectionDisabled()
                row(.home, "Home", "house")
                row(.recents, "Recents", "clock")
                ForEach(FileCategory.library) { c in
                    row(.category(c), c.title, c.symbol, count: library.totals[c]?.count)
                }
            }
            Section {
                row(.largeFiles, "Large Files", "scalemass", badge: library.largeFileCount)
                row(.screenshots, "Screenshots", "camera.viewfinder", count: library.screenshotCount)
                row(.duplicates, "Duplicates", "square.on.square", good: dupeBytes)
                row(.cleanup, "Clean Up", "sparkles", good: library.cleanupTotal)
                row(.downloadedFrom, "Downloaded From", "arrow.down.circle", count: library.sources.count)
            }
            Section("Locations") {
                ForEach(Locations.standard) { loc in
                    folderRow(loc.title, loc.path, special: loc.symbol)
                        .contextMenu { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([loc.url]) } }
                }
            }
            if !nav.pinned.isEmpty {
                Section("Pinned") {
                    ForEach(nav.pinned, id: \.self) { p in
                        folderRow(Locations.title(for: p), p, special: nil)
                            .contextMenu {
                                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) }
                                Button("Remove from Sidebar") { nav.unpin(p) }
                            }
                    }
                    .onMove { from, to in nav.movePinned(from: from, to: to) }
                }
            }
            if !nav.savedSearches.isEmpty {
                Section("Saved Searches") {
                    ForEach(nav.savedSearches, id: \.self) { q in
                        row(.saved(q), q, "bookmark")
                            .contextMenu { Button("Remove from Sidebar") { nav.unsave(q) } }
                    }
                }
            }
            Section("Free Up Space") {
                row(.storage, "Storage", "chart.bar.xaxis", detail: library.disk.used)
                row(.deepClean, "Deep Clean", "hammer")
                row(.memory, "Memory & Swap", "memorychip", detail: Int64(memory.snapshot.swapUsed))
            }
            Section("Cloud") {
                row(.cloud, cloud.isConnected ? (cloud.creds?.bucket ?? "Bucket") : "Connect R2", "cloud")
                row(.offloaded, "Offloaded", "icloud.and.arrow.up", count: cloud.records.isEmpty ? nil : cloud.records.count)
                    .help(cloud.iCloudStatus ?? "Files moved to R2 or iCloud Drive")
            }
        }
        .listStyle(.sidebar)
        .onAppear { memory.refresh() }
    }

    @ViewBuilder
    private func row(_ item: SidebarItem, _ title: String, _ symbol: String, count: Int? = nil, badge: Int? = nil,
                     good: Int64? = nil, detail: Int64? = nil) -> some View {
        Label {
            HStack {
                Text(title).lineLimit(1)
                Spacer()
                if let badge, badge > 0 {
                    Text(Fmt.count(badge)).font(.caption2.weight(.bold)).monospacedDigit()
                        .foregroundStyle(look == Look.minimal.rawValue ? Color(nsColor: .windowBackgroundColor) : .white)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(look == Look.minimal.rawValue ? Color.primary : Color.red, in: Capsule())
                } else if let good, good > 0 {
                    Text(Fmt.bytes(good)).font(.caption.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(look == Look.minimal.rawValue ? Color.primary : Palette.good)
                } else if let count, count > 0 {
                    Text(Fmt.count(count)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                } else if let detail, detail > 0 {
                    Text(Fmt.bytes(detail)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(.secondary)
        }
        .tag(item)
    }

    private func folderRow(_ title: String, _ path: String, special: String?) -> some View {
        Label {
            Text(title).lineLimit(1)
        } icon: {
            if look == Look.minimal.rawValue {
                Image(systemName: special ?? "folder").foregroundStyle(.secondary)
            } else {
                Image(systemName: special.map { $0 == "house" ? "house.fill" : "folder.fill" } ?? "folder.fill")
                    .foregroundStyle(Palette.folderBlue)
            }
        }
        .tag(SidebarItem.folder(path))
        .dropDestination(for: URL.self) { urls, _ in
            FolderDrop.handle(urls, into: URL(fileURLWithPath: path))
        }
    }
}

/// Drop files on a folder (in the sidebar, on a folder card, or into an open folder) to move them there. ⌥ copies.
@MainActor
enum FolderDrop {
    static func handle(_ urls: [URL], into dir: URL) -> Bool {
        let copy = NSEvent.modifierFlags.contains(.option)
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { return false }
        let library = AppState.shared.library
        let result = FileOps.transfer(files, into: dir, copy: copy)
        if !result.moved.isEmpty {
            if copy { library.filesChanged(added: result.moved.map(\.1)) } else { library.filesChanged(moved: result.moved) }
            library.show(toast: "\(copy ? "Copied" : "Moved") \(Fmt.plural(result.moved.count, "item")) to \(Locations.title(for: dir.path))")
        } else if !result.failed.isEmpty {
            library.show(toast: "Couldn’t move \(result.failed.prefix(3).joined(separator: ", "))")
        }
        return !result.moved.isEmpty
    }
}

/// Song controls in the top bar while something plays.
struct MiniPlayer: View {
    @Environment(MusicPlayer.self) private var player

    var body: some View {
        if let cur = player.current {
            HStack(spacing: 8) {
                Button { player.previous() } label: { Image(systemName: "backward.fill") }.buttonStyle(.borderless).help("Previous (⌥⌘←)")
                Button { player.togglePlay() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill") }
                    .buttonStyle(.borderless).help("Play or pause (⌥⌘P)")
                Button { player.next() } label: { Image(systemName: "forward.fill") }.buttonStyle(.borderless).help("Next (⌥⌘→)")
                VStack(alignment: .leading, spacing: 3) {
                    Text(cur.name).font(.caption).lineLimit(1).truncationMode(.middle)
                    ProgressView(value: player.progress).progressViewStyle(.linear).controlSize(.mini)
                }
                .frame(width: 150)
                Button { player.stop() } label: { Image(systemName: "xmark") }.buttonStyle(.borderless).help("Stop")
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Small shared views

struct ToastView: View {
    @Environment(LibraryStore.self) private var library
    var body: some View {
        if let t = library.toast {
            Text(t)
                .font(.callout)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .shadow(radius: 8, y: 2)
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(duration: 0.3), value: library.toast)
        }
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(message))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct TransfersButton: View {
    @Environment(TransferCenter.self) private var transfers
    @State private var show = false
    var body: some View {
        Button { show.toggle() } label: {
            HStack(spacing: 6) {
                ProgressView(value: transfers.overallFraction).progressViewStyle(.circular).controlSize(.small)
                Text("\(transfers.active.count)").monospacedDigit()
            }
        }
        .help("Transfers")
        .popover(isPresented: $show, arrowEdge: .bottom) { TransfersList().frame(width: 360, height: 320) }
    }
}

struct TransfersList: View {
    @Environment(TransferCenter.self) private var transfers
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Transfers").font(.headline)
                Spacer()
                Button("Clear Finished") { transfers.clearFinished() }.controlSize(.small)
            }.padding(12)
            Divider()
            if transfers.transfers.isEmpty {
                Spacer(); Text("Nothing yet").foregroundStyle(.secondary); Spacer()
            } else {
                List(transfers.transfers) { t in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: t.isUpload ? "arrow.up.circle" : "arrow.down.circle")
                            Text(t.name).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            switch t.state {
                            case .running: Text("\(Int(t.fraction * 100))%").monospacedDigit().foregroundStyle(.secondary)
                            case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            }
                        }
                        if t.state == .running { ProgressView(value: t.fraction) }
                        if case .failed(let why) = t.state { Text(why).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                        Text("\(Fmt.bytes(t.done)) of \(Fmt.bytes(t.total))").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}

/// The same Sort menu on every screen: pick a key, optionally reverse it. Choices are remembered per screen.
struct SortMenu<K: Hashable & CaseIterable & RawRepresentable>: View where K.RawValue == String, K.AllCases: RandomAccessCollection {
    @Binding var key: K
    @Binding var reversed: Bool

    var body: some View {
        Menu {
            Picker("Sort by", selection: $key) {
                ForEach(Array(K.allCases), id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.inline)
            Toggle("Reverse order", isOn: $reversed)
        } label: {
            Label("Sort: \(key.rawValue)", systemImage: "arrow.up.arrow.down")
        }
        .fixedSize()
        .help("Sort")
    }
}

extension Array {
    func sorted<V: Comparable>(by key: (Element) -> V, descending: Bool) -> [Element] {
        sorted { descending ? key($0) > key($1) : key($0) < key($1) }
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 26, weight: .regular))
            if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(2) }
        }
    }
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator.opacity(0.5)))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}


/// During tours the app usually isn't frontmost; render controls with their active colors anyway.
struct TourActiveLook: ViewModifier {
    func body(content: Content) -> some View {
        if Tour.isActive { content.environment(\.controlActiveState, .key) } else { content }
    }
}
