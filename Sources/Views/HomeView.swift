import SwiftUI

struct HomeView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(CloudStore.self) private var cloud
    @Environment(NavigationModel.self) private var nav
    @Environment(MemoryMonitor.self) private var memory
    @AppStorage(Prefs.look) private var look = Look.playful.rawValue

    var body: some View {
        let newest = HomeView.newest(library.items)
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                greeting
                librarySection(newest)
                if !library.cleanupCards.isEmpty || !AppState.shared.dupes.groups.isEmpty { cleanupSection }
                foldersSection
                screenshotsSection
                yourMacSection
                if !library.sources.isEmpty { downloadsSection }
                shelf("Latest downloads", library.latestDownloads, .downloadedFrom)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
        }
        .navigationTitle("Home")
        .onAppear { library.refreshDisk(); memory.refresh() }
    }

    // MARK: Greeting

    private var greeting: some View {
        let hour = Calendar.current.component(.hour, from: Date())
        let hello = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        let bytes = library.items.reduce(Int64(0)) { $0 + $1.spaceOnDisk }
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(hello).font(.system(size: 28, weight: .regular))
                Text(library.isScanning ? "Reading your files… \(Fmt.count(library.scanCount)) so far"
                     : "\(Fmt.count(library.items.count)) files · \(Fmt.bytes(bytes)) across your Mac")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button { library.scan() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .controlSize(.small).disabled(library.isScanning)
                .help("Read your folders again (⌘R)")
        }
    }

    // MARK: Library

    private func librarySection(_ newest: [FileCategory: [URL]]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ShelfTitle(title: "Library", count: FileCategory.library.count)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 360), spacing: 16)], spacing: 16) {
                ForEach(FileCategory.library) { c in
                    LibraryFolderCard(category: c, total: library.totals[c] ?? CategoryTotal(), samples: newest[c] ?? [])
                }
            }
        }
    }

    /// The three newest files of each kind, in one pass.
    static func newest(_ items: [FileItem]) -> [FileCategory: [URL]] {
        var out: [FileCategory: [(Date, URL)]] = [:]
        for it in items where !it.isCloudOnly {
            var cur = out[it.category, default: []]
            if cur.count < 3 || it.arrivalDate > cur[cur.count - 1].0 {
                cur.append((it.arrivalDate, it.url))
                cur.sort { $0.0 > $1.0 }
                if cur.count > 3 { cur.removeLast() }
                out[it.category] = cur
            }
        }
        return out.mapValues { $0.map(\.1) }
    }

    // MARK: Clean Up

    private var cleanupSection: some View {
        let dupes = AppState.shared.dupes
        let dupeBytes = dupes.groups.reduce(Int64(0)) { $0 + $1.reclaimable }
        let total = library.cleanupTotal + dupeBytes
        let cards = library.cleanupCards.sorted { $0.bytes > $1.bytes }
        return VStack(alignment: .leading, spacing: 12) {
            ShelfTitle(title: "Clean Up", seeAll: { nav.go(.cleanup) }) {
                if total > 0 { GoodPill(text: "Free up to \(Fmt.bytes(total))") }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                if dupeBytes > 0 { DuplicatesCardView() }
                ForEach(cards.prefix(dupeBytes > 0 ? 3 : 4)) { CleanupCardView(card: $0) }
            }
        }
    }

    // MARK: Your folders (Locations)

    private var foldersSection: some View {
        let locs = Locations.standard.filter { $0.path != "/Applications" && $0.path != Locations.home.path }
        let pinned = nav.pinned.map { FileItem.folder(URL(fileURLWithPath: $0), rv: nil) }
        let items = locs.map { FileItem.folder($0.url, rv: nil) } + pinned
        return VStack(alignment: .leading, spacing: 12) {
            ShelfTitle(title: "Folders", count: items.count, seeAll: { nav.go(.folder(Locations.home.path)) })
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 320), spacing: 14)], spacing: 14) {
                ForEach(items) { f in
                    FolderTile(item: f, measured: FolderSizeCache.shared.bytes(for: f.path), selected: false)
                        .onTapGesture { nav.go(.folder(f.path)) }
                        .dropDestination(for: URL.self) { urls, _ in FolderDrop.handle(urls, into: f.url) }
                        .contextMenu {
                            Button("Open") { nav.go(.folder(f.path)) }
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([f.url]) }
                            if nav.pinned.contains(f.path) { Button("Remove from Sidebar") { nav.unpin(f.path) } }
                        }
                }
            }
        }
    }

    // MARK: Screenshots

    @ViewBuilder
    private var screenshotsSection: some View {
        let shots = library.screenshots.sorted { $0.arrivalDate > $1.arrivalDate }
        let keeper = ScreenshotKeeper.shared
        if !shots.isEmpty || (ScreenshotKeeper.macOSCopiesToClipboard && !keeper.enabled) {
            VStack(alignment: .leading, spacing: 12) {
                ShelfTitle(title: "Recent screenshots", count: shots.isEmpty ? nil : shots.count, seeAll: { nav.go(.screenshots) })
                ScreenshotHistoryBanner(compact: true)
                if !shots.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(shots.prefix(12))) { item in shelfCard(item, in: Array(shots.prefix(12))) }
                        }
                        .padding(.bottom, 4)
                    }
                }
            }
        }
    }

    // MARK: Your Mac

    private var yourMacSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ShelfTitle(title: "Your Mac", seeAll: { nav.go(.storage) })
            StorageCard()
            HStack(alignment: .top, spacing: 14) {
                cloudCard
                swapCard
            }
        }
    }

    private var cloudCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                IconBubble(symbol: "cloud.fill", tint: FileCategory.music.pastel)
                Text("Cloudflare R2").font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
            }
            if cloud.isConnected {
                Text(Fmt.bytes(cloud.offloadedBytes)).font(.system(size: 26, weight: .semibold))
                Text("freed from this Mac · \(Fmt.plural(cloud.records.count, "file")) in “\(cloud.creds?.bucket ?? "")”")
                    .font(.callout).foregroundStyle(.secondary)
                Text(String(format: "Storage cost about $%.2f / month · no download fees", cloud.monthlyCost))
                    .font(.caption).foregroundStyle(.tertiary)
                HStack {
                    Button("Offload large files…") { nav.go(.largeFiles) }.buttonStyle(.borderedProminent)
                    Button("Open bucket") { nav.go(.cloud) }
                }
            } else {
                Text("Move big files to your own R2 bucket and keep a tiny placeholder here. Double-click it to bring the file back.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Connect Cloudflare R2") { nav.go(.cloud) }.buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(FileCategory.music.pastel, strong: false)
    }

    private var swapCard: some View {
        let s = memory.snapshot
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                IconBubble(symbol: "memorychip", tint: FileCategory.videos.pastel)
                Text("Memory & Swap").font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
            }
            Text(Fmt.bytes(Int64(s.swapUsed))).font(.system(size: 26, weight: .semibold))
            Text("of swap in use · \(s.swapFileCount) swap files take \(Fmt.bytes(Int64(s.swapFilesOnDisk))) of disk")
                .font(.callout).foregroundStyle(.secondary)
            Text("Memory \(Fmt.bytes(Int64(s.used))) of \(Fmt.bytes(Int64(s.physical))) · pressure \(s.pressureLabel)")
                .font(.caption).foregroundStyle(.tertiary)
            Button("See what to quit") { nav.go(.memory) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(FileCategory.videos.pastel, strong: false)
    }

    // MARK: Downloaded From

    private var downloadsSection: some View {
        let top = library.sources.sorted { $0.count > $1.count }.prefix(10)
        let samples = SourceCard.samples(library.items)
        return VStack(alignment: .leading, spacing: 12) {
            ShelfTitle(title: "Downloaded From", count: library.sources.count, seeAll: { nav.go(.downloadedFrom) })
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                ForEach(Array(top)) { s in SourceCard(source: s, samples: samples[s.name] ?? []) }
            }
        }
    }

    // MARK: Shelves

    @ViewBuilder
    private func shelf(_ title: String, _ items: [FileItem], _ target: SidebarItem) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ShelfTitle(title: title, seeAll: { nav.go(target) })
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(items) { item in shelfCard(item, in: items) }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
    }

    private func shelfCard(_ item: FileItem, in items: [FileItem]) -> some View {
        FileCard(item: item, side: 190, selected: false)
            .frame(width: 200)
            .onTapGesture {
                if NSApp.currentEvent?.clickCount == 2 { FileActions.primary(item, in: items) }
                else { nav.quickLook(item.url, in: items.map(\.url)) }
            }
            .contextMenu { FileContextMenu(targets: [item], all: items) }
            .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
    }
}

/// One of the six shelves (Images, Videos…) drawn as a folder.
struct LibraryFolderCard: View {
    let category: FileCategory
    let total: CategoryTotal
    let samples: [URL]
    @Environment(NavigationModel.self) private var nav
    @AppStorage(Prefs.look) private var look = Look.playful.rawValue

    var body: some View {
        Group {
            if look == Look.minimal.rawValue {
                VStack(spacing: 6) {
                    PeekFolderIcon(samples: samples, width: 112)
                    Text(category.title).font(.callout.weight(.semibold))
                    Text("\(Fmt.plural(total.count, "item")) · \(Fmt.bytes(total.bytes))").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                PastelFolder(tint: category.pastel) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(category.title).font(.system(.body, design: .monospaced).weight(.medium))
                            Spacer()
                            menu
                        }
                        Rectangle().fill(category.pastel.opacity(0.3)).frame(height: 1)
                        HStack(spacing: 6) {
                            AvatarStack(urls: samples, extra: max(0, total.count - samples.count), size: 24)
                            Spacer(minLength: 4)
                            Text("\(Fmt.count(total.count)) items · \(Fmt.bytes(total.bytes))")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).monospacedDigit()
                        }
                        .frame(height: 26)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { nav.go(.category(category)) }
        .help("Open \(category.title)")
    }

    private var menu: some View {
        Menu {
            Button("Open") { nav.go(.category(category)) }
            Button("Biggest first") {
                UserDefaults.standard.set(SortKey.size.rawValue, forKey: "sort.list.\(category.title)")
                UserDefaults.standard.set(false, forKey: "sort.list.\(category.title).reversed")
                nav.go(.category(category))
            }
            Button("Newest first") {
                UserDefaults.standard.set(SortKey.arrival.rawValue, forKey: "sort.list.\(category.title)")
                UserDefaults.standard.set(false, forKey: "sort.list.\(category.title).reversed")
                nav.go(.category(category))
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 18)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.9), in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct StorageCard: View {
    @Environment(LibraryStore.self) private var library
    @Environment(MemoryMonitor.self) private var memory
    @Environment(NavigationModel.self) private var nav
    private var breakdown: StorageBreakdownModel { AppState.shared.storage }

    var body: some View {
        let disk = library.disk
        let cats = FileCategory.allCases.filter { (library.totals[$0]?.bytes ?? 0) > 0 }
        let indexed = cats.reduce(Int64(0)) { $0 + (library.totals[$1]?.bytes ?? 0) }
        let swap = Int64(memory.snapshot.swapFilesOnDisk)
        let rest = breakdown.buckets.filter { $0.kind != .files }
        let unmeasured = max(0, disk.used - indexed - (rest.isEmpty ? swap : rest.reduce(0) { $0 + $1.bytes }))
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.bytes(disk.available)).font(.system(size: 34, weight: .bold, design: .rounded))
                Text("free of \(Fmt.bytes(disk.total))").foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(disk.usedFraction * 100))% full").font(.headline)
                    .foregroundStyle(disk.usedFraction > 0.9 ? .red : disk.usedFraction > 0.8 ? .orange : .secondary)
            }
            GeometryReader { geo in
                let w = { (b: Int64) in max(2, geo.size.width * CGFloat(b) / CGFloat(max(1, disk.total))) }
                HStack(spacing: 2) {
                    ForEach(cats) { c in Rectangle().fill(c.tint.gradient).frame(width: w(library.totals[c]?.bytes ?? 0)) }
                    if rest.isEmpty {
                        if swap > 0 { Rectangle().fill(Color.purple.gradient).frame(width: w(swap)) }
                    } else {
                        ForEach(rest) { b in Rectangle().fill(b.tint.gradient).frame(width: w(b.bytes)) }
                    }
                    if unmeasured > 0 && rest.isEmpty { Rectangle().fill(Color.gray.opacity(0.5)).frame(width: w(unmeasured)) }
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(height: 16)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .onTapGesture { nav.go(.storage) }
            FlowLegend {
                ForEach(cats) { c in legend(c.title, c.tint, library.totals[c]?.bytes ?? 0) }
                if rest.isEmpty {
                    if swap > 0 { legend("Swap", .purple, swap) }
                    Button { nav.go(.storage) } label: {
                        HStack(spacing: 5) {
                            Circle().fill(Color.gray).frame(width: 8, height: 8)
                            Text(breakdown.isMeasuring ? "System & other: measuring…" : "System & other").foregroundStyle(.secondary)
                            Text(Fmt.bytes(unmeasured)).monospacedDigit()
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain).help("See what’s inside")
                } else {
                    ForEach(rest) { b in
                        Button { nav.go(.storage) } label: { legend(b.title, b.tint, b.bytes) }.buttonStyle(.plain)
                    }
                }
            }
            .font(.caption)
        }
        .softCard(.gray, strong: false)
        .onAppear { breakdown.measureIfStale() }
    }

    private func legend(_ title: String, _ color: Color, _ bytes: Int64) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).foregroundStyle(.secondary)
            Text(Fmt.bytes(bytes)).monospacedDigit()
        }
        .lineLimit(1)
    }
}

/// Lays legend items out in rows that wrap, so nothing gets truncated.
struct FlowLegend: Layout {
    var spacing: CGFloat = 14
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW { y += lineH + lineSpacing; x = 0; lineH = 0 }
            x += s.width + spacing
            lineH = max(lineH, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxW), height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { y += lineH + lineSpacing; x = bounds.minX; lineH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
    }
}
