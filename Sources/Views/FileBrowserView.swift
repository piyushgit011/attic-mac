import SwiftUI
import UniformTypeIdentifiers

enum SortKey: String, CaseIterable, Identifiable, Hashable {
    case arrival = "Date Added", modified = "Date Modified", size = "Size", name = "Name", kind = "Kind"
    var id: String { rawValue }
}

struct FileBrowserView: View {
    let title: String
    let subtitle: String?
    let items: [FileItem]
    var defaultSort: SortKey = .arrival
    var chips: AnyView? = nil

    @Environment(NavigationModel.self) private var nav
    @Environment(LibraryStore.self) private var library
    @Environment(CloudStore.self) private var cloud
    @State private var sort: SortKey?
    @State private var ascending = false
    @State private var tableOrder: [KeyPathComparator<FileItem>] = []

    private var activeSort: SortKey { sort ?? defaultSort }

    private var sorted: [FileItem] {
        let base: [FileItem]
        switch activeSort {
        case .arrival: base = items.sorted { $0.arrivalDate > $1.arrivalDate }
        case .modified: base = items.sorted { $0.modified > $1.modified }
        case .size: base = items.sorted { $0.spaceOnDisk > $1.spaceOnDisk }
        case .name: base = items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .kind: base = items.sorted { $0.kind < $1.kind }
        }
        let ordered = ascending ? Array(base.reversed()) : base
        return tableOrder.isEmpty ? ordered : ordered.sorted(using: tableOrder)
    }

    var body: some View {
        let list = sorted
        VStack(spacing: 0) {
            header(list)
            if let chips { chips }
            Divider()
            if library.isScanning && items.isEmpty {
                ProgressView("Reading your files… \(Fmt.count(library.scanCount))").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if list.isEmpty {
                EmptyStateView(symbol: "tray", title: "Nothing here", message: "No files match.")
            } else if nav.viewMode == .grid {
                FileGrid(items: list)
            } else {
                FileTable(items: list, order: $tableOrder)
            }
        }
        .navigationTitle(title)
    }

    @ViewBuilder
    private func header(_ list: [FileItem]) -> some View {
        @Bindable var nav = nav
        let total = list.reduce(Int64(0)) { $0 + $1.spaceOnDisk }
        let selected = list.filter { nav.selection.contains($0.url) }
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.weight(.semibold))
                Text([Fmt.plural(list.count, "item"), Fmt.bytes(total), subtitle].compactMap { $0 }.joined(separator: " · "))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if !selected.isEmpty {
                Text("\(selected.count) selected · \(Fmt.bytes(selected.reduce(0) { $0 + $1.spaceOnDisk }))")
                    .font(.callout).foregroundStyle(.secondary)
                if selected.contains(where: { $0.category != .apps && !$0.isPackage && !$0.url.isAtticStub }) {
                    Button { nav.offloadRequest = selected } label: { Label("Offload…", systemImage: "icloud.and.arrow.up") }
                        .help("Move to Cloudflare R2 or iCloud Drive and free the space on this Mac")
                }
                Button(role: .destructive) { Task { await library.trash(selected) } } label: { Label("Trash", systemImage: "trash") }
            }
            Picker("View", selection: $nav.viewMode) {
                Image(systemName: "square.grid.2x2").tag(ViewMode.grid)
                Image(systemName: "list.bullet").tag(ViewMode.list)
            }
            .pickerStyle(.segmented)
            .frame(width: 80)
            .labelsHidden()
            SortMenu(key: Binding(get: { activeSort }, set: { sort = $0; tableOrder = [] }), reversed: $ascending)
            if nav.viewMode == .grid {
                Slider(value: $nav.cardSize, in: 90...320).frame(width: 90).help("Card size (⌘+ / ⌘−)")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - Grid

struct FileGrid: View {
    let items: [FileItem]
    @Environment(NavigationModel.self) private var nav
    @State private var anchor: URL?

    var body: some View {
        let side = nav.cardSize
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: side, maximum: side * 1.35), spacing: 14)], spacing: 16) {
                ForEach(items) { item in
                    FileCard(item: item, side: side, selected: nav.selection.contains(item.url))
                        .onTapGesture { tap(item) }
                        .contextMenu { FileContextMenu(targets: targets(for: item), all: items) }
                        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.001))
        .onTapGesture { nav.selection = [] }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) {
            guard let url = nav.focused ?? nav.selection.first else { return .ignored }
            nav.quickLook(url, in: items.map(\.url))
            return .handled
        }
        .onKeyPress(.return) {
            FileActions.open(items.filter { nav.selection.contains($0.url) })
            return .handled
        }
    }

    private func targets(for item: FileItem) -> [FileItem] {
        nav.selection.contains(item.url) ? items.filter { nav.selection.contains($0.url) } : [item]
    }

    private func tap(_ item: FileItem) {
        let event = NSApp.currentEvent
        if event?.clickCount == 2 {
            FileActions.open([item])
            return
        }
        let mods = NSEvent.modifierFlags
        if mods.contains(.command) {
            if nav.selection.contains(item.url) { nav.selection.remove(item.url) } else { nav.selection.insert(item.url) }
            anchor = item.url
        } else if mods.contains(.shift), let anchor, let a = items.firstIndex(where: { $0.url == anchor }),
                  let b = items.firstIndex(where: { $0.url == item.url }) {
            nav.selection = Set(items[min(a, b)...max(a, b)].map(\.url))
        } else {
            nav.selection = [item.url]
            anchor = item.url
        }
        nav.focused = item.url
    }
}

struct FileCard: View {
    let item: FileItem
    let side: CGFloat
    let selected: Bool
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                ThumbView(url: item.url, side: side)
                    .frame(width: side, height: side * 0.78)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                if item.url.isAtticStub {
                    Image(systemName: "icloud.fill").padding(6).background(.thinMaterial, in: Circle()).padding(6)
                        .help("In Cloudflare R2. Double-click to bring it back.")
                } else if item.isCloudOnly {
                    Image(systemName: "icloud").padding(6).background(.thinMaterial, in: Circle()).padding(6)
                }
                if hover && item.category == .images {
                    Button { FileActions.copyText([item]) } label: { Label("Copy Text", systemImage: "text.viewfinder").font(.caption) }
                        .buttonStyle(.borderedProminent).controlSize(.small).padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            .frame(width: side, height: side * 0.78)
            Text(item.name).font(.callout).lineLimit(1).truncationMode(.middle)
            Text(item.category == .apps
                 ? "\(Fmt.bytes(item.spaceOnDisk)) · \(item.accessed.map { "opened \(Fmt.ago($0))" } ?? "never opened")"
                 : "\(item.sizeLabel) · \(Fmt.ago(item.arrivalDate))")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(8)
        .background(selected ? Color.accentColor.opacity(0.18) : (hover ? Color.primary.opacity(0.05) : .clear),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .help(Fmt.path(item.url))
    }
}

struct ThumbView: View {
    let url: URL
    let side: CGFloat
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary.opacity(0.35))
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).padding(image.size.width < side * 0.6 ? side * 0.12 : 0)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().aspectRatio(contentMode: .fit).padding(side * 0.18).opacity(0.6)
            }
        }
        .task(id: "\(url.path)#\(Int(side / 64))") {
            if let hit = ThumbnailCache.shared.cached(url, side: side) { image = hit; return }
            image = await ThumbnailCache.shared.thumbnail(for: url, side: side)
        }
    }
}

// MARK: - List

struct FileTable: View {
    let items: [FileItem]
    @Binding var order: [KeyPathComparator<FileItem>]
    @Environment(NavigationModel.self) private var nav

    var body: some View {
        @Bindable var nav = nav
        Table(items, selection: $nav.selection, sortOrder: $order) {
            TableColumn("Name", value: \.name) { item in
                HStack(spacing: 8) {
                    ThumbView(url: item.url, side: 22).frame(width: 22, height: 22).clipShape(RoundedRectangle(cornerRadius: 4))
                    Text(item.name).lineLimit(1).truncationMode(.middle)
                    if item.url.isAtticStub { Image(systemName: "icloud.fill").foregroundStyle(.secondary) }
                }
                .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
            }
            .width(min: 220, ideal: 340)
            TableColumn("Size", value: \.spaceOnDisk) { Text($0.sizeLabel).monospacedDigit().foregroundStyle($0.isCloudOnly ? .secondary : .primary) }.width(min: 80, ideal: 110)
            TableColumn("Kind", value: \.kind) { Text($0.kind).lineLimit(1) }.width(min: 90, ideal: 130)
            TableColumn("Added", value: \.arrivalDate) { Text(Fmt.shortDate($0.arrivalDate)) }.width(100)
            TableColumn("From", value: \.sourceSort) { Text($0.source ?? "").foregroundStyle(.secondary) }.width(min: 70, ideal: 100)
            TableColumn("Folder", value: \.folderName) { Text($0.folderName).foregroundStyle(.secondary).lineLimit(1) }.width(min: 80, ideal: 120)
        }
        .contextMenu(forSelectionType: URL.self) { urls in
            FileContextMenu(targets: items.filter { urls.contains($0.url) }, all: items)
        } primaryAction: { urls in
            FileActions.open(items.filter { urls.contains($0.url) })
        }
        .onChange(of: nav.selection) { _, new in nav.focused = new.first }
        .onKeyPress(.space) {
            guard let url = nav.selection.first else { return .ignored }
            nav.quickLook(url, in: items.map(\.url))
            return .handled
        }
    }
}

// MARK: - Context menu

struct FileContextMenu: View {
    let targets: [FileItem]
    let all: [FileItem]
    @Environment(NavigationModel.self) private var nav
    @Environment(LibraryStore.self) private var library

    var body: some View {
        if let first = targets.first {
            Button(first.url.isAtticStub ? "Download from R2 & Open" : "Open") { FileActions.open(targets) }
            Button("Quick Look") { nav.quickLook(first.url, in: all.map(\.url)) }
            Button("Show in Finder") { FileActions.reveal(targets) }
            Divider()
            if targets.contains(where: { $0.category == .images || $0.ext == "pdf" }) {
                Button("Copy Text") { FileActions.copyText(targets) }
            }
            Button("Copy") { FileActions.copyFiles(targets) }
            Button("Copy Path") { FileActions.copyPaths(targets) }
            Button("Show Details") { nav.selection = Set(targets.map(\.url)); nav.focused = first.url; nav.showInspector = true }
            Divider()
            if targets.contains(where: { $0.category != .apps && !$0.isPackage && !$0.url.isAtticStub }) {
                Button("Offload to R2 or iCloud…") { nav.offloadRequest = targets }
            }
            if targets.contains(where: \.isICloudDownloaded) {
                Button("Remove Download (keep in iCloud)") { AppState.shared.cloud.removeDownloads(targets.filter(\.isICloudDownloaded)) }
            }
            Button("Move to Trash", role: .destructive) { Task { await library.trash(targets) } }
        }
    }
}

// MARK: - Search

struct SearchResultsView: View {
    @Environment(NavigationModel.self) private var nav
    @Environment(LibraryStore.self) private var library
    @Environment(OCRIndex.self) private var ocr

    var body: some View {
        let q = nav.query
        let results = q.isEmpty ? [] : library.items.filter { q.matches($0, ocr: q.wantsOCR ? ocr.texts[$0.path] : nil) }
        FileBrowserView(title: "Search", subtitle: ocr.isIndexing ? "Reading text in images \(ocr.indexed)/\(ocr.pending)" : nil,
                        items: results, defaultSort: .arrival, chips: AnyView(ChipsBar(query: q)))
    }
}

struct ChipsBar: View {
    let query: SearchQuery
    @Environment(NavigationModel.self) private var nav

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("Understood as").font(.caption).foregroundStyle(.secondary)
                ForEach(query.chips) { chip in
                    HStack(spacing: 5) {
                        Image(systemName: chip.symbol).font(.caption)
                        Text(chip.label).font(.callout)
                        Button { nav.remove(chip: chip) } label: { Image(systemName: "xmark.circle.fill").font(.caption) }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(color(chip).opacity(0.15), in: Capsule())
                    .overlay(Capsule().strokeBorder(color(chip).opacity(0.35)))
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 10)
        }
    }

    private func color(_ c: SearchChip) -> Color {
        switch c.kindKey {
        case "type": return .blue
        case "date": return .orange
        case "size": return .purple
        case "source": return .green
        default: return .gray
        }
    }
}

// MARK: - Downloaded From

struct DownloadedFromView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(NavigationModel.self) private var nav
    @AppStorage("sort.sources") private var sort: SourceSort = .files
    @AppStorage("sort.sources.reversed") private var reversed = false

    private var sorted: [SourceGroup] {
        switch sort {
        case .files: return library.sources.sorted(by: { $0.count }, descending: !reversed)
        case .size: return library.sources.sorted(by: { $0.bytes }, descending: !reversed)
        case .recent: return library.sources.sorted(by: { $0.latest }, descending: !reversed)
        case .name: return library.sources.sorted(by: { $0.name.lowercased() }, descending: reversed)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .bottom) {
                    SectionHeader(title: "Downloaded From",
                                  subtitle: "\(Fmt.count(library.sources.reduce(0) { $0 + $1.count })) files · \(Fmt.plural(library.sources.count, "source"))")
                    Spacer()
                    SortMenu(key: $sort, reversed: $reversed)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                    ForEach(sorted) { s in
                        Button { nav.go(.source(s.name)) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: DownloadSource.symbol(for: s.name))
                                    .font(.title3).frame(width: 40, height: 40)
                                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.name).font(.headline).lineLimit(1)
                                    Text("\(Fmt.plural(s.count, "file")) · \(Fmt.bytes(s.bytes)) · \(Fmt.ago(s.latest))").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                            }
                            .card()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Downloaded From")
    }
}
