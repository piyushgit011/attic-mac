import SwiftUI

struct CleanupCardView: View {
    let card: CleanupCard
    @Environment(NavigationModel.self) private var nav

    var body: some View {
        Button { nav.go(.cleanupCard(card.kind)) } label: {
            SoftStatCard(symbol: card.symbol, tint: card.tint, title: card.title, value: Fmt.bytes(card.bytes),
                         footnote: Fmt.plural(card.items.count, "item"), samples: card.items.prefix(3).map(\.url))
        }
        .buttonStyle(.plain)
        .help(card.detail)
    }
}

/// Duplicates as a Clean Up card, once a scan has found some.
struct DuplicatesCardView: View {
    @Environment(NavigationModel.self) private var nav

    var body: some View {
        let groups = AppState.shared.dupes.groups
        let extra = groups.reduce(0) { $0 + $1.files.count - 1 }
        Button { nav.go(.duplicates) } label: {
            SoftStatCard(symbol: "square.on.square", tint: Color(red: 0.95, green: 0.38, blue: 0.40), title: "Duplicates",
                         value: Fmt.bytes(groups.reduce(0) { $0 + $1.reclaimable }),
                         footnote: "\(Fmt.count(extra)) extra \(extra == 1 ? "copy" : "copies")",
                         samples: groups.prefix(3).compactMap { $0.files.first?.url })
        }
        .buttonStyle(.plain)
        .help("Identical files, found by their contents")
    }
}

/// Icon, little thumbnails, a label, a big number and "N items ›".
struct SoftStatCard: View {
    let symbol: String
    let tint: Color
    let title: String
    let value: String
    let footnote: String
    var samples: [URL] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                IconBubble(symbol: symbol, tint: tint)
                Spacer()
                AvatarStack(urls: samples, size: 22)
            }
            Spacer(minLength: 16)
            Text(title).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
            HStack(alignment: .firstTextBaseline) {
                Text(value).font(.system(size: 24, weight: .semibold)).monospacedDigit().lineLimit(1)
                Spacer(minLength: 4)
                HStack(spacing: 2) {
                    Text(footnote)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .softCard(tint)
        .contentShape(Rectangle())
    }
}

/// Shown where screenshots should be when macOS sends them to the clipboard instead of saving them.
struct ScreenshotHistoryBanner: View {
    var compact = false
    private var keeper: ScreenshotKeeper { ScreenshotKeeper.shared }

    var body: some View {
        if !keeper.enabled && ScreenshotKeeper.macOSCopiesToClipboard {
            HStack(alignment: .center, spacing: 12) {
                IconBubble(symbol: "camera.viewfinder", tint: FileCategory.images.pastel, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your screenshots go to the clipboard, so none are saved").font(.headline)
                    Text("Your Mac copies each screenshot instead of saving it, so there’s nothing here to find later. Attic can keep a copy of every new screenshot in Pictures ▸ Screenshots, where search reads the text in them. Only real screenshots are kept, not images you copy.")
                        .font(.callout).foregroundStyle(.secondary).lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("Keep Screenshot History") { keeper.enabled = true }
                    .buttonStyle(.borderedProminent)
            }
            .softCard(FileCategory.images.pastel)
        } else if keeper.enabled && !compact {
            Label("Screenshot history is on. Screenshots you take are saved to \(Fmt.path(ScreenshotKeeper.folder)) while Attic is open.",
                  systemImage: "checkmark.circle.fill")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

/// Large Files leaves out app libraries (Photos, Music, iMovie…): their app manages them, and trashing or moving one
/// can damage it. This note says what was left out, how big it is, and how to shrink it from inside its app.
struct AppLibraryNote: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        let libs = library.largeAppLibraries
        if let lib = libs.first {
            let total = libs.reduce(Int64(0)) { $0 + $1.spaceOnDisk }
            let app = NSWorkspace.shared.urlForApplication(toOpen: lib.url)
            HStack(alignment: .center, spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: lib.path))
                    .resizable().interpolation(.high).frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(libs.count == 1 ? "\(lib.name) isn’t listed · \(Fmt.bytes(total))"
                         : "\(lib.name) and \(libs.count - 1) more app \(libs.count == 2 ? "library" : "libraries") aren’t listed · \(Fmt.bytes(total))")
                        .font(.headline)
                    Text(AppLibraryNote.advice(for: lib.ext))
                        .font(.callout).foregroundStyle(.secondary).lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let app {
                    Button("Open \(app.deletingPathExtension().lastPathComponent)") {
                        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
                    }
                }
            }
            .softCard(FileCategory.images.pastel)
        }
    }

    static func advice(for ext: String) -> String {
        switch ext {
        case "photoslibrary", "photolibrary", "migratedphotolibrary", "aplibrary":
            return "Photos manages it, and trashing or moving it can damage your library. To free space, turn on iCloud Photos with Optimize Mac Storage in Photos ▸ Settings ▸ iCloud."
        case "musiclibrary", "tvlibrary":
            return "Its app manages it, so Attic won’t trash or move it. To free space, remove downloaded songs and videos in the Music or TV app."
        case "imovielibrary":
            return "iMovie manages it, so Attic won’t trash or move it. To free space, delete render files in iMovie ▸ Settings."
        case "fcpbundle":
            return "Final Cut Pro manages it, so Attic won’t trash or move it. To free space, choose File ▸ Delete Generated Library Files in Final Cut Pro."
        default:
            return "Its app manages it, and trashing or moving it can damage it, so Attic leaves it alone."
        }
    }
}

struct CleanupOverview: View {
    @Environment(LibraryStore.self) private var library
    @Environment(NavigationModel.self) private var nav
    @AppStorage("sort.cleanup") private var sort: CardSort = .size
    @AppStorage("sort.cleanup.reversed") private var reversed = false

    private var cards: [CleanupCard] {
        switch sort {
        case .size: return library.cleanupCards.sorted(by: { $0.bytes }, descending: !reversed)
        case .count: return library.cleanupCards.sorted(by: { $0.items.count }, descending: !reversed)
        case .name: return library.cleanupCards.sorted(by: { $0.title }, descending: reversed)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom) {
                    SectionHeader(title: "Clean Up",
                                  subtitle: "Smart cards for things you probably don’t need. Each opens a review page. Files go to the Trash or to R2, never deleted outright.")
                    Spacer()
                    SortMenu(key: $sort, reversed: $reversed)
                }
                if library.isScanning && library.cleanupCards.isEmpty {
                    ProgressView("Scanning…")
                } else if library.cleanupCards.isEmpty {
                    EmptyStateView(symbol: "checkmark.seal", title: "Nothing to clean", message: "Your files look tidy.")
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                    duplicatesCard
                    ForEach(cards) { CleanupCardView(card: $0) }
                    deepCleanCard
                }
                Label("Nothing is deleted without asking. Files go to the Trash, so you can always put them back.", systemImage: "checkmark.shield")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .navigationTitle("Clean Up")
    }

    private var deepCleanCard: some View {
        Button { nav.go(.deepClean) } label: {
            SoftStatCard(symbol: "hammer", tint: FileCategory.videos.pastel, title: "Deep Clean",
                         value: AppState.shared.deepClean.scanned ? Fmt.bytes(AppState.shared.deepClean.items.reduce(0) { $0 + $1.bytes }) : "Scan",
                         footnote: "node_modules, builds, caches")
        }.buttonStyle(.plain)
    }

    private var duplicatesCard: some View {
        Group {
            if AppState.shared.dupes.groups.isEmpty {
                Button { nav.go(.duplicates) } label: {
                    SoftStatCard(symbol: "square.on.square", tint: Color(red: 0.95, green: 0.38, blue: 0.40), title: "Duplicates",
                                 value: AppState.shared.dupes.scanning ? "Scanning…" : (AppState.shared.dupes.scanned ? "None" : "Scan"),
                                 footnote: "SHA-256 fingerprints")
                }.buttonStyle(.plain)
            } else {
                DuplicatesCardView()
            }
        }
    }
}

struct CleanupReviewView: View {
    let card: CleanupCard
    @Environment(LibraryStore.self) private var library
    @Environment(NavigationModel.self) private var nav
    @State private var checked = Set<URL>()
    @State private var order: [KeyPathComparator<FileItem>] = [KeyPathComparator(\.spaceOnDisk, order: .reverse)]

    var body: some View {
        let items = card.items.sorted(using: order)
        let picked = items.filter { checked.contains($0.url) }
        let pickedBytes = picked.reduce(Int64(0)) { $0 + $1.spaceOnDisk }
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Image(systemName: card.symbol).font(.title).foregroundStyle(card.tint)
                VStack(alignment: .leading) {
                    Text(card.title).font(.title2.weight(.semibold))
                    Text("\(card.detail) · \(Fmt.plural(items.count, "item")) · \(Fmt.bytes(card.bytes))").foregroundStyle(.secondary)
                }
                Spacer()
                Button(checked.count == items.count ? "Select None" : "Select All") {
                    checked = checked.count == items.count ? [] : Set(items.map(\.url))
                }
                if card.kind == .alreadyInICloud {
                    Button {
                        AppState.shared.cloud.removeDownloads(picked)
                        checked = []
                    } label: { Label("Remove \(Fmt.bytes(pickedBytes)) of downloads", systemImage: "icloud.and.arrow.down") }
                        .buttonStyle(.borderedProminent).disabled(picked.isEmpty)
                } else if card.kind != .unusedApps && card.kind != .oldInstallers {
                    Button { nav.offloadRequest = picked } label: { Label("Offload \(Fmt.bytes(pickedBytes))…", systemImage: "icloud.and.arrow.up") }
                        .buttonStyle(.borderedProminent).disabled(picked.isEmpty)
                }
                if card.kind == .alreadyInICloud {
                    EmptyView()
                } else if card.prefersOffload {
                    Button(role: .destructive) {
                        Task { await library.trash(picked); checked = [] }
                    } label: { Label("Trash Selected", systemImage: "trash") }
                        .disabled(picked.isEmpty)
                } else {
                    Button(role: .destructive) {
                        Task { await library.trash(picked); checked = [] }
                    } label: { Label("Trash Selected", systemImage: "trash") }
                        .buttonStyle(.borderedProminent)
                        .disabled(picked.isEmpty)
                }
            }
            .padding(20)
            Divider()
            Table(items, sortOrder: $order) {
                TableColumn("") { item in
                    Toggle("", isOn: Binding(get: { checked.contains(item.url) }, set: { on in
                        if on { checked.insert(item.url) } else { checked.remove(item.url) }
                    })).labelsHidden()
                }.width(28)
                TableColumn("Name", value: \.name) { item in
                    HStack {
                        ThumbView(url: item.url, side: 24).frame(width: 24, height: 24).clipShape(RoundedRectangle(cornerRadius: 4))
                        Text(item.name).lineLimit(1).truncationMode(.middle)
                    }
                    .contextMenu { FileContextMenu(targets: [item], all: items) }
                }
                TableColumn("Size", value: \.spaceOnDisk) { Text(Fmt.bytes($0.spaceOnDisk)).monospacedDigit() }.width(90)
                TableColumn("Last used", value: \.lastUsed) { Text(Fmt.ago($0.lastUsed)) }.width(110)
                TableColumn("Location", value: \.folderName) { Text(Fmt.path($0.url.deletingLastPathComponent())).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head) }
            }
        }
        .navigationTitle(card.title)
        .onAppear { checked = Set(card.items.map(\.url)) }
    }
}

// MARK: - Duplicates

struct DuplicatesView: View {
    @Environment(LibraryStore.self) private var library
    @AppStorage("sort.dupes") private var sort: DupeSort = .reclaim
    @AppStorage("sort.dupes.reversed") private var reversed = false
    private var m: DuplicatesModel { AppState.shared.dupes }

    var body: some View {
        @Bindable var m = AppState.shared.dupes
        let reclaim = m.groups.reduce(Int64(0)) { $0 + $1.reclaimable }
        let extra = m.groups.reduce(0) { $0 + $1.files.count - 1 }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom) {
                    SectionHeader(title: "Duplicates", subtitle: "Identical copies across your folders, found by their contents (SHA-256). APFS clones are counted correctly.")
                    Spacer()
                    SortMenu(key: $sort, reversed: $reversed)
                }
                banner(reclaim: reclaim, extra: extra)
                if m.groups.isEmpty {
                    EmptyStateView(symbol: "square.on.square", title: m.scanned ? "No duplicates" : (m.scanning ? "Looking for duplicates…" : "Look for duplicates"),
                                   message: m.scanned ? "Every file is one of a kind." : "Checks files over 100 KB across your scan locations.")
                        .frame(minHeight: 240)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(orderedIDs(m.groups), id: \.self) { id in
                            if let i = m.groups.firstIndex(where: { $0.id == id }) {
                                DuplicateGroupRow(group: $m.groups[i])
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Duplicates")
    }

    private func banner(reclaim: Int64, extra: Int) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "square.on.square").font(.system(size: 22, weight: .medium)).foregroundStyle(.white)
                .frame(width: 54, height: 54).background(.white.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(m.scanned ? "Free up \(Fmt.bytes(reclaim))" : (m.scanning ? "Looking for duplicates…" : "Find duplicate files"))
                    .font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
                Text(m.scanned ? "\(Fmt.count(extra)) extra \(extra == 1 ? "copy" : "copies") in \(Fmt.plural(m.groups.count, "group"))"
                     : "Attic keeps one copy of each and moves the rest to the Trash. You pick which one stays.")
                    .foregroundStyle(.white.opacity(0.7))
                if m.scanning { ProgressView(value: m.progress).tint(.white).frame(width: 220) }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Button { trashAll() } label: {
                    Label("Trash All Extras", systemImage: "trash").font(.callout.weight(.semibold)).foregroundStyle(.red)
                        .padding(.horizontal, 14).padding(.vertical, 7).background(.white, in: Capsule())
                }
                .buttonStyle(.plain).disabled(m.groups.isEmpty || m.scanning).opacity(m.groups.isEmpty ? 0.5 : 1)
                Button { scan() } label: {
                    Label(m.scanned ? "Scan Again" : "Find Duplicates", systemImage: "arrow.clockwise").font(.callout).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6).background(.white.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain).disabled(library.isScanning || m.scanning)
            }
        }
        .padding(22)
        .background(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.09)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func scan() {
        m.scan(library.items)
    }

    private func orderedIDs(_ groups: [DuplicateGroup]) -> [UUID] {
        let sorted: [DuplicateGroup]
        switch sort {
        case .reclaim: sorted = groups.sorted(by: { $0.reclaimable }, descending: !reversed)
        case .copies: sorted = groups.sorted(by: { $0.files.count }, descending: !reversed)
        case .size: sorted = groups.sorted(by: { $0.size }, descending: !reversed)
        case .name: sorted = groups.sorted(by: { $0.files.first?.name.lowercased() ?? "" }, descending: reversed)
        }
        return sorted.map(\.id)
    }

    private func trashAll() {
        let victims = m.groups.flatMap { g in g.files.filter { $0.url != g.keep } }
        Task {
            await library.trash(victims)
            m.groups = []
        }
    }
}

struct DuplicateGroupRow: View {
    @Binding var group: DuplicateGroup
    @Environment(LibraryStore.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.files.first?.name ?? "").font(.system(.callout, design: .monospaced).weight(.medium)).lineLimit(1)
                    Text("\(group.files.count) identical copies · \(group.reclaimable > 0 ? "\(Fmt.bytes(group.reclaimable)) can be freed" : "APFS clones, freeing them saves nothing")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    let victims = group.files.filter { $0.url != group.keep }
                    Task {
                        await library.trash(victims)
                        AppState.shared.dupes.groups.removeAll { $0.id == group.id }
                    }
                } label: { Label("Keep 1, Trash \(group.files.count - 1)", systemImage: "trash") }
                    .controlSize(.small)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(group.files) { f in
                        let keep = f.url == group.keep
                        VStack(alignment: .leading, spacing: 4) {
                            ThumbView(url: f.url, side: 120, plain: true, fill: true)
                                .frame(width: 150, height: 96).clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(alignment: .topLeading) {
                                    Text(keep ? "Keep" : "Trash").font(.caption2.weight(.bold)).foregroundStyle(.white)
                                        .padding(.horizontal, 7).padding(.vertical, 2)
                                        .background(keep ? Palette.good : Color.red, in: Capsule()).padding(6)
                                }
                            Text(Fmt.path(f.url.deletingLastPathComponent())).font(.caption).lineLimit(1).truncationMode(.head)
                            Text("\(Fmt.bytes(f.spaceOnDisk)) · \(Fmt.ago(f.arrivalDate))").font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(width: 150)
                        .padding(8)
                        .background(keep ? Palette.good.opacity(0.08) : Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(keep ? Palette.good : Color.primary.opacity(0.08), lineWidth: keep ? 1.5 : 1))
                        .onTapGesture { group.keep = f.url }
                        .contextMenu { FileContextMenu(targets: [f], all: group.files) }
                        .help(keep ? "This copy stays" : "Click to keep this copy instead")
                    }
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}
