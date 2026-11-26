import SwiftUI
import UniformTypeIdentifiers

enum SortKey: String, CaseIterable, Identifiable, Hashable {
    case arrival = "Date Added", modified = "Date Modified", size = "Size", name = "Name", kind = "Kind"
    var id: String { rawValue }

    func sort(_ items: [FileItem], reversed: Bool) -> [FileItem] {
        let base: [FileItem]
        switch self {
        case .arrival: base = items.sorted { $0.arrivalDate > $1.arrivalDate }
        case .modified: base = items.sorted { $0.modified > $1.modified }
        case .size: base = items.sorted { $0.spaceOnDisk > $1.spaceOnDisk }
        case .name: base = items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .kind: base = items.sorted { ($0.kind, $0.lowerName) < ($1.kind, $1.lowerName) }
        }
        return reversed ? Array(base.reversed()) : base
    }
}

// MARK: - Filters shared by every list

enum DateFilter: String, CaseIterable, Identifiable {
    case any = "Any", today = "Today", week = "Last 7 days", month = "Last 30 days", year = "Last 12 months", older = "Over a year ago"
    var id: String { rawValue }

    func matches(_ d: Date) -> Bool {
        let age = -d.timeIntervalSinceNow
        switch self {
        case .any: return true
        case .today: return Calendar.current.isDateInToday(d)
        case .week: return age <= 7 * 86_400
        case .month: return age <= 30 * 86_400
        case .year: return age <= 365 * 86_400
        case .older: return age > 365 * 86_400
        }
    }
}

enum SizeFilter: String, CaseIterable, Identifiable {
    case any = "Any", small = "Under 1 MB", medium = "1 MB to 100 MB", large = "Over 100 MB", huge = "Over 1 GB"
    var id: String { rawValue }

    func matches(_ n: Int64) -> Bool {
        switch self {
        case .any: return true
        case .small: return n < 1_000_000
        case .medium: return n >= 1_000_000 && n < 100_000_000
        case .large: return n >= 100_000_000
        case .huge: return n >= 1_000_000_000
        }
    }
}

struct ListFilters: Equatable {
    var kind: FileCategory?
    var from: String?
    var date: DateFilter = .any
    var size: SizeFilter = .any

    var isActive: Bool { kind != nil || from != nil || date != .any || size != .any }

    func apply(_ items: [FileItem], byModified: Bool = false) -> [FileItem] {
        guard isActive else { return items }
        return items.filter { it in
            (kind == nil || (!it.isDirectory && it.category == kind))
                && (from == nil || it.source == from)
                && date.matches(byModified ? it.modified : it.arrivalDate)
                && (size == .any || (!it.isDirectory && size.matches(it.spaceOnDisk)))
        }
    }
}

/// From · Kind · Date · Size · Sort, as small rounded menus.
struct FilterBar: View {
    let items: [FileItem]
    @Binding var filters: ListFilters
    @Binding var sort: SortKey
    @Binding var reversed: Bool
    var dateLabel = "Date"

    var body: some View {
        HStack(spacing: 8) {
            let sources = Array(Set(items.compactMap(\.source))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            if !sources.isEmpty {
                FilterPill(label: "From", value: filters.from ?? "Anywhere", active: filters.from != nil) {
                    Button("Anywhere") { filters.from = nil }
                    Divider()
                    ForEach(sources.prefix(60), id: \.self) { s in Button(s) { filters.from = s } }
                }
            }
            let kinds = FileCategory.allCases.filter { c in items.contains { !$0.isDirectory && $0.category == c } }
            if kinds.count > 1 || filters.kind != nil {
                FilterPill(label: "Kind", value: filters.kind?.title ?? "All", active: filters.kind != nil) {
                    Button("All") { filters.kind = nil }
                    Divider()
                    ForEach(kinds) { c in Button(c.title) { filters.kind = c } }
                }
            }
            FilterPill(label: dateLabel, value: filters.date.rawValue, active: filters.date != .any) {
                ForEach(DateFilter.allCases) { d in Button(d.rawValue) { filters.date = d } }
            }
            FilterPill(label: "Size", value: filters.size.rawValue, active: filters.size != .any) {
                ForEach(SizeFilter.allCases) { s in Button(s.rawValue) { filters.size = s } }
            }
            FilterPill(label: "Sort", value: sort.rawValue) {
                Picker("Sort by", selection: $sort) {
                    ForEach(SortKey.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
                Toggle("Reverse order", isOn: $reversed)
            }
        }
    }
}

struct ViewModeToggle: View {
    @Environment(NavigationModel.self) private var nav
    var body: some View {
        @Bindable var nav = nav
        Picker("View", selection: $nav.viewMode) {
            Image(systemName: "square.grid.2x2").help("Grid (⌘1)").tag(ViewMode.grid)
            Image(systemName: "list.bullet").help("List (⌘2)").tag(ViewMode.list)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}

/// "3 selected · 1.2 GB  [Offload…] [Trash]"
struct SelectionActions: View {
    let selected: [FileItem]
    @Environment(NavigationModel.self) private var nav
    @Environment(LibraryStore.self) private var library

    var body: some View {
        if !selected.isEmpty {
            HStack(spacing: 8) {
                Text("\(selected.count) selected · \(Fmt.bytes(selected.reduce(0) { $0 + $1.spaceOnDisk }))")
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                if selected.contains(where: { $0.category != .apps && !$0.isPackage && !$0.isDirectory && !$0.url.isAtticStub }) {
                    Button { nav.offloadRequest = selected.filter { !$0.isDirectory } } label: { Label("Offload…", systemImage: "icloud.and.arrow.up") }
                        .help("Move to Cloudflare R2 or iCloud Drive and free the space on this Mac")
                }
                Button(role: .destructive) { Task { await library.trash(selected) } } label: { Label("Trash", systemImage: "trash") }
            }
        }
    }
}

// MARK: - A list of files (library shelves, smart folders, search results)

struct FileBrowserView: View {
    let title: String
    let subtitle: String?
    let items: [FileItem]
    var defaultSort: SortKey = .arrival
    var chips: AnyView? = nil
    var banner: AnyView? = nil
    var actions: AnyView? = nil

    @Environment(NavigationModel.self) private var nav
    @Environment(LibraryStore.self) private var library
    @AppStorage private var sortRaw: String
    @AppStorage private var reversed: Bool
    @State private var filters = ListFilters()
    @State private var tableOrder: [KeyPathComparator<FileItem>] = []

    init(title: String, subtitle: String?, items: [FileItem], defaultSort: SortKey = .arrival, storageKey: String? = nil,
         chips: AnyView? = nil, banner: AnyView? = nil, actions: AnyView? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.items = items
        self.defaultSort = defaultSort
        self.chips = chips
        self.banner = banner
        self.actions = actions
        let key = "sort.list.\(storageKey ?? title)"
        _sortRaw = AppStorage(wrappedValue: "", key)
        _reversed = AppStorage(wrappedValue: false, key + ".reversed")
    }

    private var activeSort: SortKey { SortKey(rawValue: sortRaw) ?? defaultSort }

    var body: some View {
        let filtered = filters.apply(items)
        let sorted = activeSort.sort(filtered, reversed: reversed)
        let list = tableOrder.isEmpty || nav.viewMode == .grid ? sorted : sorted.sorted(using: tableOrder)
        VStack(spacing: 0) {
            header(list)
            if let chips { chips }
            if let banner { banner.padding(.horizontal, 24).padding(.bottom, 12) }
            Divider()
            if library.isScanning && items.isEmpty {
                ProgressView("Reading your files… \(Fmt.count(library.scanCount))").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if list.isEmpty {
                EmptyStateView(symbol: filters.isActive ? "line.3.horizontal.decrease.circle" : "tray",
                               title: filters.isActive ? "Nothing matches these filters" : "Nothing here",
                               message: filters.isActive ? "Try a different date, size or kind." : "No files match.")
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
        let total = list.reduce(Int64(0)) { $0 + $1.spaceOnDisk }
        let selected = list.filter { nav.selection.contains($0.url) }
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title).font(.system(size: 26, weight: .regular)).lineLimit(1).truncationMode(.tail)
                        if let actions { actions }
                    }
                    Text([Fmt.plural(list.count, "item"), Fmt.bytes(total), subtitle].compactMap { $0 }.joined(separator: " · "))
                        .font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                }
                .layoutPriority(1)
                Spacer(minLength: 12)
                SelectionActions(selected: selected)
            }
            HStack(spacing: 8) {
                FilterBar(items: items, filters: $filters,
                          sort: Binding(get: { activeSort }, set: { sortRaw = $0.rawValue; tableOrder = [] }),
                          reversed: $reversed)
                Spacer(minLength: 8)
                ViewModeToggle()
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
}

// MARK: - Selection in grids

@MainActor
enum GridSelect {
    /// Click selects, ⌘-click adds, ⇧-click selects a range, double-click opens.
    static func tap(_ item: FileItem, in items: [FileItem], nav: NavigationModel) {
        if NSApp.currentEvent?.clickCount == 2 {
            FileActions.primary(item, in: items)
            return
        }
        let mods = NSEvent.modifierFlags
        if mods.contains(.command) {
            if nav.selection.contains(item.url) { nav.selection.remove(item.url) } else { nav.selection.insert(item.url) }
            nav.anchor = item.url
        } else if mods.contains(.shift), let anchor = nav.anchor, let a = items.firstIndex(where: { $0.url == anchor }),
                  let b = items.firstIndex(where: { $0.url == item.url }) {
            nav.selection = Set(items[min(a, b)...max(a, b)].map(\.url))
        } else {
            nav.selection = [item.url]
            nav.anchor = item.url
        }
        nav.focused = item.url
    }

    static func targets(for item: FileItem, in items: [FileItem], nav: NavigationModel) -> [FileItem] {
        nav.selection.contains(item.url) ? items.filter { nav.selection.contains($0.url) } : [item]
    }
}

// MARK: - Grid

struct FileGrid: View {
    let items: [FileItem]
    var title = "Files"
    @Environment(NavigationModel.self) private var nav

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ShelfTitle(title: title, count: items.count)
                FileCardsGrid(items: items, all: items)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.001))
        .onTapGesture { nav.selection = [] }
        .gridKeys(items: items)
    }
}

/// The cards themselves, without scrolling, so a folder can show folders and files in one scroll view.
struct FileCardsGrid: View {
    let items: [FileItem]
    let all: [FileItem]
    @Environment(NavigationModel.self) private var nav

    var body: some View {
        let side = nav.cardSize
        LazyVGrid(columns: [GridItem(.adaptive(minimum: side, maximum: side * 1.7), spacing: 14)], spacing: 14) {
            ForEach(items) { item in
                FileCard(item: item, side: side, selected: nav.selection.contains(item.url))
                    .onTapGesture { GridSelect.tap(item, in: all, nav: nav) }
                    .contextMenu { FileContextMenu(targets: GridSelect.targets(for: item, in: all, nav: nav), all: all) }
                    .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
            }
        }
    }
}

extension View {
    /// Space for Quick Look, Return to open, like Finder.
    func gridKeys(items: [FileItem]) -> some View { modifier(GridKeys(items: items)) }
}

struct GridKeys: ViewModifier {
    let items: [FileItem]
    @Environment(NavigationModel.self) private var nav

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.space) {
                guard let url = nav.focused ?? nav.selection.first else { return .ignored }
                nav.quickLook(url, in: items.filter { !$0.isDirectory }.map(\.url))
                return .handled
            }
            .onKeyPress(.return) {
                let picked = items.filter { nav.selection.contains($0.url) }
                if picked.count == 1, let one = picked.first { FileActions.primary(one, in: items) } else { FileActions.open(picked) }
                return .handled
            }
    }
}

struct KindPill: View {
    let item: FileItem
    @AppStorage(Prefs.look) private var look = Look.playful.rawValue

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(look == Look.minimal.rawValue ? Color.secondary : item.category.pastel).frame(width: 6, height: 6)
            Text(label).lineLimit(1)
        }
        .font(.system(size: 10, weight: .medium))
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.94), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
    }

    private var label: String {
        if item.isDirectory { return "Folder" }
        let kind = item.category == .apps ? "App" : (item.ext.isEmpty ? item.kind : item.ext.uppercased())
        if item.url.isAtticStub { return "In R2" }
        return "\(kind) · \(item.isCloudOnly ? "iCloud" : Fmt.bytes(item.spaceOnDisk))"
    }
}

struct FileCard: View {
    let item: FileItem
    let side: CGFloat
    let selected: Bool
    @State private var hover = false
    @Environment(MusicPlayer.self) private var player

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ThumbView(url: item.url, side: side, plain: true)
                .frame(maxWidth: .infinity)
                .frame(height: side * 0.62)
                .shadow(color: .black.opacity(0.14), radius: 3, y: 1.5)
                .padding(.horizontal, 14)
                .padding(.top, 30)
                .padding(.bottom, 8)
                .overlay(alignment: .topLeading) { KindPill(item: item).padding(8) }
                .overlay(alignment: .topTrailing) { badge.padding(8) }
                .overlay(alignment: .bottomTrailing) {
                    if hover && item.category == .images && !item.isCloudOnly {
                        Button { FileActions.copyText([item]) } label: { Label("Copy Text", systemImage: "text.viewfinder").font(.caption) }
                            .buttonStyle(.borderedProminent).controlSize(.small).padding(6)
                    } else if item.category == .music && !item.url.isAtticStub {
                        Button { player.toggle(item, queue: [item]) } label: {
                            Image(systemName: player.current?.url == item.url && player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 11, weight: .bold)).frame(width: 26, height: 26)
                                .background(.thinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain).padding(6).opacity(hover || player.current?.url == item.url ? 1 : 0)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 11)
        }
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(hover ? 0.075 : 0.045)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.07), lineWidth: selected ? 2 : 1))
        .background(selected ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .help(Fmt.path(item.url))
    }

    @ViewBuilder
    private var badge: some View {
        if item.url.isAtticStub {
            Image(systemName: "icloud.fill").font(.caption).padding(5).background(.thinMaterial, in: Circle())
                .help("In Cloudflare R2. Double-click to bring it back.")
        } else if item.isCloudOnly {
            Image(systemName: "icloud").font(.caption).padding(5).background(.thinMaterial, in: Circle())
                .help("Only in iCloud. Uses no space on this Mac.")
        }
    }

    private var subtitle: String {
        if item.isDirectory { return Fmt.date(item.modified) }
        if item.category == .apps { return item.accessed.map { "Opened \(Fmt.ago($0))" } ?? "Never opened" }
        return Fmt.date(item.arrivalDate)
    }
}

struct ThumbView: View {
    let url: URL
    let side: CGFloat
    var plain = false
    var fill = false
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if !plain { Rectangle().fill(.quaternary.opacity(0.35)) }
            if let image {
                if fill {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        .padding(image.size.width < side * 0.6 ? side * 0.12 : 0)
                }
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().aspectRatio(contentMode: .fit)
                    .padding(fill ? 0 : side * 0.12).opacity(0.7)
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
    var showFolder = true
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
            TableColumn("Size", value: \.spaceOnDisk) { item in
                Text(item.isDirectory ? (item.size > 0 ? Fmt.bytes(item.size) : "--") : item.sizeLabel)
                    .monospacedDigit().foregroundStyle(item.isCloudOnly || item.isDirectory ? .secondary : .primary)
            }
            .width(min: 80, ideal: 110)
            TableColumn("Kind", value: \.kind) { Text($0.kind).lineLimit(1) }.width(min: 90, ideal: 130)
            TableColumn(showFolder ? "Added" : "Modified", value: showFolder ? \.arrivalDate : \.modified) { item in
                Text(Fmt.shortDate(showFolder ? item.arrivalDate : item.modified))
            }
            .width(100)
            TableColumn("From", value: \.sourceSort) { Text($0.source ?? "").foregroundStyle(.secondary) }.width(min: 70, ideal: 100)
            TableColumn("Folder", value: \.folderName) { Text($0.folderName).foregroundStyle(.secondary).lineLimit(1) }
                .width(min: 80, ideal: showFolder ? 120 : 80)
        }
        .contextMenu(forSelectionType: URL.self) { urls in
            FileContextMenu(targets: items.filter { urls.contains($0.url) }, all: items)
        } primaryAction: { urls in
            let picked = items.filter { urls.contains($0.url) }
            if picked.count == 1, let one = picked.first { FileActions.primary(one, in: items) } else { FileActions.open(picked) }
        }
        .onChange(of: nav.selection) { _, new in nav.focused = new.first }
        .onKeyPress(.space) {
            guard let url = nav.selection.first else { return .ignored }
            nav.quickLook(url, in: items.filter { !$0.isDirectory }.map(\.url))
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
            if first.isDirectory && targets.count == 1 {
                Button("Open") { FileActions.primary(first, in: all) }
                Button("Show in Finder") { FileActions.reveal(targets) }
                Divider()
                if Locations.pinned.contains(first.path) {
                    Button("Remove from Sidebar") { nav.unpin(first.path) }
                } else if !Locations.standard.contains(where: { $0.path == first.path }) {
                    Button("Pin to Sidebar") { nav.pin(first.path) }
                }
                Button("Copy Path") { FileActions.copyPaths(targets) }
                Button("Rename…") { nav.beginRename(first) }
                Button("Get Info") { nav.selection = [first.url]; nav.focused = first.url; nav.showInspector = true }
                Divider()
                Button("Move to Trash", role: .destructive) { Task { await library.trash(targets) } }
            } else {
                Button(first.url.isAtticStub ? "Download from R2 & Open" : "Open") { FileActions.open(targets) }
                if first.category == .music && !first.url.isAtticStub {
                    Button("Play in Attic") { AppState.shared.player.play(first, queue: all.filter { $0.category == .music }) }
                }
                Button("Quick Look") { nav.quickLook(first.url, in: all.filter { !$0.isDirectory }.map(\.url)) }
                Button("Show in Finder") { FileActions.reveal(targets) }
                if targets.count == 1, !(nav.sidebar == .folder(first.url.deletingLastPathComponent().path) && nav.searchText.isEmpty) {
                    Button("Show in Enclosing Folder") {
                        nav.go(.folder(first.url.deletingLastPathComponent().path))
                        nav.selection = [first.url]
                        nav.focused = first.url
                    }
                }
                Divider()
                if targets.contains(where: { $0.category == .images || $0.ext == "pdf" }) {
                    Button("Copy Text") { FileActions.copyText(targets) }
                }
                Button("Copy") { FileActions.copyFiles(targets) }
                Button("Copy Path") { FileActions.copyPaths(targets) }
                if targets.count == 1 { Button("Rename…") { nav.beginRename(first) } }
                Button("Get Info") { nav.selection = Set(targets.map(\.url)); nav.focused = first.url; nav.showInspector = true }
                Divider()
                if targets.contains(where: { $0.category != .apps && !$0.isPackage && !$0.isDirectory && !$0.url.isAtticStub }) {
                    Button("Offload to R2 or iCloud…") { nav.offloadRequest = targets.filter { !$0.isDirectory } }
                }
                if targets.contains(where: \.isICloudDownloaded) {
                    Button("Remove Download (keep in iCloud)") { AppState.shared.cloud.removeDownloads(targets.filter(\.isICloudDownloaded)) }
                }
                Button("Move to Trash", role: .destructive) { Task { await library.trash(targets) } }
            }
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
        let text = nav.searchText.trimmingCharacters(in: .whitespaces)
        let saved = nav.savedSearches.contains(text)
        FileBrowserView(title: "Results for “\(text)”",
                        subtitle: ocr.isIndexing ? "Reading text in images \(ocr.indexed)/\(ocr.pending)" : "in your home folders",
                        items: results, defaultSort: .arrival, storageKey: "Search",
                        chips: AnyView(ChipsBar(query: q)),
                        actions: AnyView(
                            Button { saved ? nav.unsave(text) : nav.save(text) } label: {
                                Image(systemName: saved ? "bookmark.fill" : "bookmark")
                            }
                            .buttonStyle(.borderless)
                            .help(saved ? "Remove from Saved Searches" : "Save this search to the sidebar. It always shows what matches right now.")
                        ))
    }
}

/// A search saved to the sidebar. It runs again every time, so it always shows what matches now.
struct SavedSearchView: View {
    let text: String
    @Environment(LibraryStore.self) private var library
    @Environment(OCRIndex.self) private var ocr
    @Environment(NavigationModel.self) private var nav

    var body: some View {
        let q = QueryParser.parse(text)
        let results = q.isEmpty ? [] : library.items.filter { q.matches($0, ocr: q.wantsOCR ? ocr.texts[$0.path] : nil) }
        FileBrowserView(title: text, subtitle: "Saved search", items: results, defaultSort: .arrival, storageKey: "Saved.\(text)",
                        chips: AnyView(ChipsBar(query: q, editable: false)),
                        actions: AnyView(
                            Button { nav.unsave(text) } label: { Image(systemName: "bookmark.slash") }
                                .buttonStyle(.borderless).help("Remove from Saved Searches")
                        ))
    }
}

struct ChipsBar: View {
    let query: SearchQuery
    var editable = true
    @Environment(NavigationModel.self) private var nav

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if nav.aiThinking && editable {
                    ProgressView().controlSize(.mini)
                    Text("Asking Apple Intelligence, on this Mac…").font(.caption).foregroundStyle(.secondary)
                } else if query.byAI {
                    Label("Apple Intelligence · on this Mac", systemImage: "apple.intelligence")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LinearGradient(colors: [.orange, .pink, .purple], startPoint: .leading, endPoint: .trailing))
                        .help("Understood by Apple’s on-device model. Nothing was sent anywhere.")
                } else {
                    Label("Understood as", systemImage: "sparkle").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(query.chips) { chip in
                    HStack(spacing: 5) {
                        Image(systemName: chip.symbol).font(.caption)
                        Text(chip.label).font(.callout)
                        if editable {
                            Button { nav.remove(chip: chip) } label: { Image(systemName: "xmark.circle.fill").font(.caption) }
                                .buttonStyle(.plain).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(color(chip).opacity(0.13), in: Capsule())
                    .overlay(Capsule().strokeBorder(color(chip).opacity(0.3)))
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 12)
        }
    }

    private func color(_ c: SearchChip) -> Color {
        if Look.current == .minimal { return .secondary }
        switch c.kindKey {
        case "type": return FileCategory.documents.pastel
        case "date": return FileCategory.music.pastel
        case "size": return FileCategory.videos.pastel
        case "source": return FileCategory.apps.pastel
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
        let samples = SourceCard.samples(library.items)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Downloaded From").font(.system(size: 26, weight: .regular))
                        Text("\(Fmt.count(library.sources.reduce(0) { $0 + $1.count })) downloaded files from \(Fmt.plural(library.sources.count, "source"))")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    SortMenu(key: $sort, reversed: $reversed)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                    ForEach(sorted) { s in SourceCard(source: s, samples: samples[s.name] ?? []) }
                }
            }
            .padding(24)
        }
        .navigationTitle("Downloaded From")
    }
}

struct SourceCard: View {
    let source: SourceGroup
    let samples: [URL]
    @Environment(NavigationModel.self) private var nav

    var body: some View {
        Button { nav.go(.source(source.name)) } label: {
            HStack(spacing: 10) {
                IconBubble(symbol: DownloadSource.symbol(for: source.name), tint: Palette.tint(for: source.name), size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name).font(.callout.weight(.semibold)).lineLimit(1).truncationMode(.tail)
                    Text("\(Fmt.plural(source.count, "file")) · \(Fmt.bytes(source.bytes))").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                AvatarStack(urls: samples, size: 22)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The newest two files from each source, for the little thumbnails.
    static func samples(_ items: [FileItem]) -> [String: [URL]] {
        var out: [String: [(Date, URL)]] = [:]
        for it in items {
            guard let s = it.source else { continue }
            var cur = out[s, default: []]
            cur.append((it.arrivalDate, it.url))
            if cur.count > 2 { cur.sort { $0.0 > $1.0 }; cur.removeLast() }
            out[s] = cur
        }
        return out.mapValues { $0.sorted { $0.0 > $1.0 }.map(\.1) }
    }
}
