import SwiftUI

struct CleanupCardView: View {
    let card: CleanupCard
    @Environment(NavigationModel.self) private var nav

    var body: some View {
        Button { nav.go(.cleanupCard(card.kind)) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: card.symbol).font(.title3).foregroundStyle(card.tint)
                    Spacer()
                    Text(Fmt.plural(card.items.count, "item")).font(.caption).foregroundStyle(.secondary)
                }
                Text(card.title).font(.headline)
                Text(Fmt.bytes(card.bytes)).font(.system(size: 24, weight: .bold, design: .rounded))
                Text(card.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .card()
        }
        .buttonStyle(.plain)
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14)], spacing: 14) {
                    ForEach(cards) { CleanupCardView(card: $0) }
                    deepCleanCard
                    duplicatesCard
                }
            }
            .padding(24)
        }
        .navigationTitle("Clean Up")
    }

    private var deepCleanCard: some View {
        Button { nav.go(.deepClean) } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "hammer").font(.title3).foregroundStyle(.indigo)
                Text("Deep Clean").font(.headline)
                Text("node_modules, Xcode builds, npm/pip caches, app caches").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .card()
        }.buttonStyle(.plain)
    }

    private var duplicatesCard: some View {
        Button { nav.go(.duplicates) } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "square.on.square").font(.title3).foregroundStyle(.green)
                Text("Duplicates").font(.headline)
                Text("Identical files found by SHA-256 fingerprint").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .card()
        }.buttonStyle(.plain)
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
                if card.kind != .unusedApps && card.kind != .oldInstallers {
                    Button { nav.offloadRequest = picked } label: { Label("Offload \(Fmt.bytes(pickedBytes)) to R2", systemImage: "icloud.and.arrow.up") }
                        .buttonStyle(.borderedProminent).disabled(picked.isEmpty)
                }
                if card.prefersOffload {
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
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Duplicates").font(.title2.weight(.semibold))
                    Text(m.scanned ? "\(Fmt.plural(m.groups.count, "set")) of identical files · \(Fmt.bytes(reclaim)) to get back"
                         : "Finds identical files by their contents (SHA-256). APFS clones are counted correctly.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if m.scanning {
                    ProgressView(value: m.progress).frame(width: 160)
                } else {
                    Button(m.scanned ? "Scan Again" : "Find Duplicates") { scan() }.disabled(library.isScanning)
                }
                SortMenu(key: $sort, reversed: $reversed)
                Button(role: .destructive) { trashAll() } label: { Label("Trash \(Fmt.bytes(reclaim)) of copies", systemImage: "trash") }
                    .buttonStyle(.borderedProminent).disabled(m.groups.isEmpty || m.scanning)
            }
            .padding(20)
            Divider()
            if m.groups.isEmpty {
                EmptyStateView(symbol: "square.on.square", title: m.scanned ? "No duplicates" : "Look for duplicates",
                               message: m.scanned ? "Every file is one of a kind." : "Checks files over 100 KB across your scan locations.")
            } else {
                List {
                    ForEach(orderedIDs(m.groups), id: \.self) { id in
                        if let i = m.groups.firstIndex(where: { $0.id == id }) {
                            DuplicateGroupRow(group: $m.groups[i])
                        }
                    }
                }
            }
        }
        .navigationTitle("Duplicates")
    }

    private func scan() {
        m.scanning = true
        m.progress = 0
        let items = library.items
        Task.detached(priority: .userInitiated) {
            let found = DuplicateFinder.find(in: items, progress: { p in Task { @MainActor in m.progress = p } }, isCancelled: { false })
            await MainActor.run {
                m.groups = found
                m.scanning = false
                m.scanned = true
            }
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(group.files.first?.name ?? "").font(.headline).lineLimit(1)
                Text("\(group.files.count) copies · \(Fmt.bytes(group.size)) each").foregroundStyle(.secondary)
                Spacer()
                Text(group.reclaimable > 0 ? "Frees \(Fmt.bytes(group.reclaimable))" : "Clones, frees nothing")
                    .font(.callout.weight(.medium)).foregroundStyle(group.reclaimable > 0 ? .green : .secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(group.files) { f in
                        let keep = f.url == group.keep
                        VStack(alignment: .leading, spacing: 4) {
                            ThumbView(url: f.url, side: 90).frame(width: 120, height: 80).clipShape(RoundedRectangle(cornerRadius: 8))
                            Text(Fmt.path(f.url.deletingLastPathComponent())).font(.caption).lineLimit(1).truncationMode(.head).frame(width: 120, alignment: .leading)
                            Text(keep ? "Keep" : "To Trash").font(.caption.weight(.semibold)).foregroundStyle(keep ? .green : .secondary)
                        }
                        .padding(6)
                        .background(keep ? Color.green.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(keep ? Color.green : .clear, lineWidth: 1.5))
                        .onTapGesture { group.keep = f.url }
                        .help("Click to keep this copy instead")
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}
