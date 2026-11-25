import SwiftUI
import QuickLook

struct ContentView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(NavigationModel.self) private var nav
    @Environment(TransferCenter.self) private var transfers
    @Environment(CloudStore.self) private var cloud

    var body: some View {
        @Bindable var nav = nav
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 236, max: 300)
        } detail: {
            DetailRouter()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .inspector(isPresented: $nav.showInspector) {
                    InspectorView()
                        .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
                }
        }
        .searchable(text: $nav.searchText, placement: .toolbar, prompt: "Search, or try “pdfs from last week over 5 mb”")
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { nav.goBack() } label: { Label("Back", systemImage: "chevron.left") }
                    .disabled(!nav.canGoBack).help("Back (⌘[)")
                Button { nav.goForward() } label: { Label("Forward", systemImage: "chevron.right") }
                    .disabled(!nav.canGoForward).help("Forward (⌘])")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if !transfers.active.isEmpty { TransfersButton() }
                Button { nav.showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.right") }
                    .help("Show details (⌘I)")
            }
        }
        .overlay(alignment: .bottom) { ToastView() }
        .sheet(item: Binding(get: { nav.offloadRequest.map(OffloadRequest.init) }, set: { nav.offloadRequest = $0?.items })) { req in
            OffloadSheet(items: req.items)
        }
        .quickLookPreview($nav.quickLookURL, in: nav.quickLookList)
        .confirmationDialog(cloudDeleteTitle, isPresented: Binding(get: { !library.pendingCloudDelete.isEmpty },
                                                                  set: { if !$0 { library.pendingCloudDelete = [] } })) {
            Button("Delete from iCloud", role: .destructive) { library.deleteFromICloud(library.pendingCloudDelete) }
            Button("Cancel", role: .cancel) { library.pendingCloudDelete = [] }
        } message: {
            Text("\(library.pendingCloudDelete.prefix(3).map(\.name).joined(separator: ", "))\(library.pendingCloudDelete.count > 3 ? " and \(library.pendingCloudDelete.count - 3) more" : "") \(library.pendingCloudDelete.count == 1 ? "is" : "are") only in iCloud and use no space on this Mac. macOS won’t move iCloud-only files to the Trash without downloading them first, so Attic can delete them from iCloud instead. You can recover them from iCloud.com ▸ Drive ▸ Recently Deleted for 30 days.")
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

struct DetailRouter: View {
    @Environment(LibraryStore.self) private var library
    @Environment(NavigationModel.self) private var nav

    var body: some View {
        if !nav.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            SearchResultsView()
        } else {
            switch nav.sidebar ?? .home {
            case .home: HomeView()
            case .recents: FileBrowserView(title: "Recents", subtitle: "Newest arrivals first", items: library.recents, defaultSort: .arrival)
            case .downloadedFrom: DownloadedFromView()
            case .source(let s): FileBrowserView(title: s, subtitle: "Downloaded from \(s)", items: library.items(from: s), defaultSort: .arrival)
            case .category(let c): FileBrowserView(title: c.title, subtitle: nil, items: library.items(in: c), defaultSort: c == .apps ? .size : .arrival)
            case .largeFiles: FileBrowserView(title: "Large Files", subtitle: "Over 100 MB, biggest first", items: library.largeFiles, defaultSort: .size)
            case .screenshots: FileBrowserView(title: "Screenshots", subtitle: "Search finds the text inside them", items: library.screenshots, defaultSort: .arrival)
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

    var body: some View {
        @Bindable var nav = nav
        List(selection: $nav.sidebar) {
            Section("Discover") {
                row(.home, "Home", "house")
                row(.recents, "Recents", "clock")
                row(.downloadedFrom, "Downloaded From", "arrow.down.circle", count: library.sources.count)
            }
            Section("Library") {
                ForEach(FileCategory.library) { c in
                    row(.category(c), c.title, c.symbol, count: library.totals[c]?.count, tint: c.tint)
                }
            }
            Section("Smart Folders") {
                row(.largeFiles, "Large Files", "scalemass")
                row(.screenshots, "Screenshots", "camera.viewfinder")
            }
            Section("Free Up Space") {
                row(.cleanup, "Clean Up", "sparkles", badge: library.cleanupCards.reduce(0) { $0 + $1.bytes })
                row(.duplicates, "Duplicates", "square.on.square")
                row(.deepClean, "Deep Clean", "hammer")
                row(.memory, "Memory & Swap", "memorychip", badge: Int64(memory.snapshot.swapUsed))
            }
            Section("Cloudflare R2") {
                row(.cloud, cloud.isConnected ? (cloud.creds?.bucket ?? "Bucket") : "Connect R2", "cloud")
                row(.offloaded, "Offloaded", "icloud.and.arrow.up", count: cloud.records.isEmpty ? nil : cloud.records.count)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { DiskMeter().padding(12) }
        .onAppear { memory.refresh() }
    }

    @ViewBuilder
    private func row(_ item: SidebarItem, _ title: String, _ symbol: String, count: Int? = nil, badge: Int64? = nil, tint: Color? = nil) -> some View {
        Label {
            HStack {
                Text(title).lineLimit(1)
                Spacer()
                if let count, count > 0 {
                    Text(Fmt.count(count)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                } else if let badge, badge > 0 {
                    Text(Fmt.bytes(badge)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint ?? .accentColor)
        }
        .tag(item)
    }
}

struct DiskMeter: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "internaldrive")
                Text("Macintosh HD").font(.caption.weight(.semibold))
                Spacer()
                if library.isScanning {
                    ProgressView().controlSize(.mini)
                }
            }
            ProgressView(value: library.disk.usedFraction)
                .tint(library.disk.usedFraction > 0.9 ? .red : library.disk.usedFraction > 0.8 ? .orange : .accentColor)
            Text(library.isScanning ? "Scanning… \(Fmt.count(library.scanCount)) files"
                 : "\(Fmt.bytes(library.disk.available)) free of \(Fmt.bytes(library.disk.total))")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
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
            Text(title).font(.title3.weight(.semibold))
            if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
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
