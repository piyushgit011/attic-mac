import SwiftUI

/// Browse any folder like Finder: folders as cards you can open, files as big thumbnails, a path you can click,
/// live updates when something changes, folder sizes measured in the background, and drag and drop to move.
struct FolderBrowserView: View {
    let path: String
    @Environment(NavigationModel.self) private var nav
    @Environment(LibraryStore.self) private var library
    @AppStorage("sort.folder") private var sortRaw = SortKey.name.rawValue
    @AppStorage("sort.folder.reversed") private var reversed = false
    @State private var contents = FolderContents()
    @State private var loaded = false
    @State private var sizes: [String: Int64] = [:]
    @State private var measuring = false
    @State private var filters = ListFilters()
    @State private var tableOrder: [KeyPathComparator<FileItem>] = []
    @State private var watcher: FolderWatcher?
    @State private var reloadToken = 0
    @State private var dropTargeted = false

    private var url: URL { URL(fileURLWithPath: path) }
    private var sort: SortKey { SortKey(rawValue: sortRaw) ?? .name }

    var body: some View {
        let folders = sortFolders(filters.apply(withSizes(contents.folders), byModified: true))
        let files = sort.sort(filters.apply(contents.files, byModified: true), reversed: reversed)
        let all = folders + files
        VStack(spacing: 0) {
            header(folders: folders, files: files)
            Divider()
            if !loaded {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = contents.error {
                VStack(spacing: 12) {
                    EmptyStateView(symbol: "lock.fill", title: "Can’t open “\(Locations.title(for: path))”", message: err)
                    Button("Open Full Disk Access Settings") { StorageBreakdownModel.openFullDiskAccessSettings() }
                    Spacer()
                }
            } else if all.isEmpty {
                EmptyStateView(symbol: filters.isActive ? "line.3.horizontal.decrease.circle" : "folder",
                               title: filters.isActive ? "Nothing matches these filters" : "This folder is empty",
                               message: filters.isActive ? "Try a different date, size or kind." : "Drop files here to move them in. Hold ⌥ to copy.")
            } else if nav.viewMode == .grid {
                grid(folders: folders, files: files, all: all)
            } else {
                FileTable(items: tableOrder.isEmpty ? all : all.sorted(using: tableOrder), order: $tableOrder, showFolder: false)
            }
        }
        .navigationTitle(Locations.title(for: path))
        .task(id: "\(path)|\(nav.showHidden)|\(library.fsVersion)|\(reloadToken)") { await load() }
        .onAppear { watch() }
        .onDisappear { watcher?.stop(); watcher = nil }
        .dropDestination(for: URL.self) { urls, _ in
            FolderDrop.handle(urls, into: url)
        } isTargeted: { dropTargeted = $0 }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, lineWidth: 3).padding(6).allowsHitTesting(false)
            }
        }
    }

    // MARK: Header

    @ViewBuilder
    private func header(folders: [FileItem], files: [FileItem]) -> some View {
        let fileBytes = files.reduce(Int64(0)) { $0 + $1.spaceOnDisk }
        let folderBytes = folders.reduce(Int64(0)) { $0 + $1.size }
        let selected = (folders + files).filter { nav.selection.contains($0.url) }
        let pinned = nav.pinned.contains(path)
        let standard = Locations.standard.contains { $0.path == path }
        VStack(alignment: .leading, spacing: 10) {
            Breadcrumbs(path: path)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(Locations.title(for: path)).font(.system(size: 26, weight: .regular)).lineLimit(1).truncationMode(.middle)
                        if !standard {
                            Button { pinned ? nav.unpin(path) : nav.pin(path) } label: { Image(systemName: pinned ? "pin.fill" : "pin") }
                                .buttonStyle(.borderless).help(pinned ? "Remove from the sidebar" : "Pin to the sidebar")
                        }
                    }
                    Text(summary(folders: folders.count, files: files.count, bytes: fileBytes + folderBytes))
                        .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
                .layoutPriority(1)
                Spacer(minLength: 12)
                SelectionActions(selected: selected)
                Button { nav.newFolder(in: url) } label: { Image(systemName: "folder.badge.plus") }
                    .buttonStyle(.borderless).help("New Folder (⇧⌘N)")
                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Image(systemName: "macwindow") }
                    .buttonStyle(.borderless).help("Show in Finder")
            }
            HStack(spacing: 8) {
                FilterBar(items: files, filters: $filters,
                          sort: Binding(get: { sort }, set: { sortRaw = $0.rawValue; tableOrder = [] }),
                          reversed: $reversed, dateLabel: "Modified")
                Spacer(minLength: 8)
                ViewModeToggle()
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private func summary(folders: Int, files: Int, bytes: Int64) -> String {
        var parts: [String] = []
        if folders > 0 { parts.append(Fmt.plural(folders, "folder")) }
        parts.append(Fmt.plural(files, "file"))
        if bytes > 0 { parts.append(Fmt.bytes(bytes) + (measuring ? " so far" : "")) }
        return parts.joined(separator: " · ")
    }

    // MARK: Grid

    private func grid(folders: [FileItem], files: [FileItem], all: [FileItem]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !folders.isEmpty {
                    ShelfTitle(title: "Folders", count: folders.count) {
                        if measuring {
                            ProgressView().controlSize(.mini)
                            Text("Measuring sizes…").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: max(180, nav.cardSize * 1.15), maximum: 320), spacing: 14)], spacing: 14) {
                        ForEach(folders) { f in
                            FolderTile(item: f, measured: sizes[f.path], selected: nav.selection.contains(f.url))
                                .onTapGesture { GridSelect.tap(f, in: all, nav: nav) }
                                .contextMenu { FileContextMenu(targets: GridSelect.targets(for: f, in: all, nav: nav), all: all) }
                                .onDrag { NSItemProvider(contentsOf: f.url) ?? NSItemProvider() }
                                .dropDestination(for: URL.self) { urls, _ in FolderDrop.handle(urls, into: f.url) }
                        }
                    }
                }
                if !files.isEmpty {
                    ShelfTitle(title: "Files", count: files.count).padding(.top, folders.isEmpty ? 0 : 10)
                    FileCardsGrid(items: files, all: all)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.001))
        .onTapGesture { nav.selection = [] }
        .gridKeys(items: all)
        .contextMenu {
            Button("New Folder") { nav.newFolder(in: url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("Copy Path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(path, forType: .string) }
            Divider()
            Button(nav.showHidden ? "Hide Hidden Files" : "Show Hidden Files") { nav.showHidden.toggle() }
        }
    }

    // MARK: Loading

    private func withSizes(_ f: [FileItem]) -> [FileItem] {
        f.map { item in
            guard let s = sizes[item.path] else { return item }
            var x = item
            x.size = s
            x.allocatedSize = s
            return x
        }
    }

    private func sortFolders(_ f: [FileItem]) -> [FileItem] {
        let base: [FileItem]
        switch sort {
        case .size: base = f.sorted { $0.size > $1.size }
        case .modified, .arrival: base = f.sorted { $0.modified > $1.modified }
        case .name, .kind: base = f.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        return reversed ? Array(base.reversed()) : base
    }

    private func load() async {
        let dir = url
        let hidden = nav.showHidden
        let result = await Task.detached(priority: .userInitiated) { FolderReader.read(dir, showHidden: hidden) }.value
        if Task.isCancelled { return }
        contents = result
        loaded = true
        var known: [String: Int64] = [:]
        for f in result.folders { if let b = FolderSizeCache.shared.bytes(for: f.path) { known[f.path] = b } }
        sizes = known
        await measure(result.folders.filter { known[$0.path] == nil })
    }

    /// Measures folder sizes one at a time, smallest work first, and stops as soon as you leave.
    private func measure(_ folders: [FileItem]) async {
        guard !folders.isEmpty else { return }
        measuring = true
        for f in folders {
            if Task.isCancelled { break }
            let flag = CancelFlag()
            let target = f.url
            let bytes = await withTaskCancellationHandler {
                await Task.detached(priority: .utility) { FolderSizeCache.measure(target) { flag.cancelled } }.value
            } onCancel: {
                flag.cancelled = true
            }
            guard let bytes, !Task.isCancelled else { break }
            FolderSizeCache.shared.set(f.path, bytes)
            sizes[f.path] = bytes
        }
        measuring = false
    }

    private func watch() {
        watcher?.stop()
        watcher = FolderWatcher(path: path) { reloadToken += 1 }
    }
}

// MARK: - Path bar

struct Breadcrumbs: View {
    let path: String
    @Environment(NavigationModel.self) private var nav

    var body: some View {
        let crumbs = Locations.crumbs(for: path)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(Array(crumbs.enumerated()), id: \.offset) { i, c in
                    if i > 0 {
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                    }
                    let last = i == crumbs.count - 1
                    Button { if !last { nav.go(.folder(c.path)) } } label: {
                        HStack(spacing: 4) {
                            if i == 0 { Image(systemName: c.path == "/" ? "internaldrive" : (c.path == "/Applications" ? "square.grid.2x2" : "house")) }
                            Text(c.title)
                        }
                        .foregroundStyle(last ? Color.primary : Color.secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .dropDestination(for: URL.self) { urls, _ in FolderDrop.handle(urls, into: URL(fileURLWithPath: c.path)) }
                }
            }
            .font(.callout)
        }
    }
}

// MARK: - Folder card

struct FolderTile: View {
    let item: FileItem
    let measured: Int64?
    let selected: Bool
    @AppStorage(Prefs.look) private var look = Look.playful.rawValue
    @State private var peek: (count: Int, sample: [URL])?

    var body: some View {
        Group {
            if look == Look.minimal.rawValue {
                VStack(spacing: 6) {
                    PeekFolderIcon(samples: peek?.sample ?? [], width: 92)
                        .padding(.top, 6)
                    Text(item.name).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(selected ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
            } else {
                PastelFolder(tint: Palette.folderBlue, selected: selected) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(item.name).font(.system(.callout, design: .monospaced).weight(.medium)).lineLimit(1).truncationMode(.middle)
                        Rectangle().fill(Palette.folderBlue.opacity(0.22)).frame(height: 1)
                        HStack(spacing: 6) {
                            AvatarStack(urls: peek?.sample ?? [], size: 22)
                            Spacer(minLength: 4)
                            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).monospacedDigit()
                        }
                        .frame(height: 24)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .help(Fmt.path(item.url))
        .task(id: item.path) {
            if let hit = FolderPeekCache.shared.get(item.path) { peek = hit; return }
            let url = item.url
            let p = await Task.detached(priority: .utility) { FolderReader.peek(url) }.value
            FolderPeekCache.shared.set(item.path, p)
            peek = p
        }
    }

    private var detail: String {
        var parts: [String] = []
        if let peek { parts.append(peek.count == 0 ? "Empty" : Fmt.plural(peek.count, "item")) }
        if let measured { parts.append(Fmt.bytes(measured)) }
        return parts.isEmpty ? " " : parts.joined(separator: " · ")
    }
}
