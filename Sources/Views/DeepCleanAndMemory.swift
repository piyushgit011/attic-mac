import SwiftUI

// MARK: - Deep Clean

struct DeepCleanView: View {
    @Environment(LibraryStore.self) private var library
    @State private var confirmEmpty = false
    @State private var confirmTrash = false
    private var m: DeepCleanModel { AppState.shared.deepClean }
    @AppStorage("sort.junk") private var sort: JunkSort = .size
    @AppStorage("sort.junk.reversed") private var reversed = false

    private func ordered(_ rows: [JunkItem]) -> [JunkItem] {
        switch sort {
        case .size: return rows.sorted(by: { $0.bytes }, descending: !reversed)
        case .lastUsed: return rows.sorted(by: { $0.lastUsed ?? .distantPast }, descending: reversed)
        case .name: return rows.sorted(by: { $0.title.lowercased() }, descending: reversed)
        }
    }

    var body: some View {
        let picked = m.items.filter { m.checked.contains($0.url) && $0.group.canTrash }
        let pickedBytes = picked.reduce(Int64(0)) { $0 + $1.bytes }
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Deep Clean").font(.title2.weight(.semibold))
                    Text(m.scanning ? "Measuring \(m.current)" : m.scanned
                         ? "\(Fmt.bytes(m.items.filter { $0.group.canTrash }.reduce(0) { $0 + $1.bytes })) of rebuildable space found"
                         : "Dependency folders, build output and caches that tools recreate on their own.")
                        .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                if m.scanning { ProgressView().controlSize(.small) }
                SortMenu(key: $sort, reversed: $reversed)
                Button(m.scanned ? "Scan Again" : "Scan") { scan() }.disabled(m.scanning)
                Button(role: .destructive) { confirmTrash = true } label: { Label("Move \(Fmt.bytes(pickedBytes)) to Trash", systemImage: "trash") }
                    .buttonStyle(.borderedProminent).disabled(picked.isEmpty || m.scanning)
            }
            .padding(20)
            if let ts = AppState.shared.deepClean.trashSize, ts > 50_000_000 {
                HStack {
                    Image(systemName: "trash.fill").foregroundStyle(.red)
                    Text("Your Trash holds \(Fmt.bytes(ts)). That space comes back only when you empty it.")
                    Spacer()
                    Button("Empty Trash…") { confirmEmpty = true }
                }
                .padding(12)
                .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 20).padding(.bottom, 12)
            }
            Divider()
            if m.items.isEmpty {
                EmptyStateView(symbol: "hammer", title: m.scanned ? "Nothing big found" : "Find rebuildable space",
                               message: "Looks inside your scan locations (including ~/Developer) for node_modules, Xcode builds, Python environments, and in ~/Library and ~/.cache for caches.")
            } else {
                List {
                    ForEach(JunkItem.Group.allCases, id: \.self) { group in
                        let rows = ordered(m.items.filter { $0.group == group })
                        if !rows.isEmpty {
                            Section {
                                ForEach(rows) { row($0) }
                            } header: {
                                HStack {
                                    Label(group.rawValue, systemImage: group.symbol).foregroundStyle(group.tint)
                                    Spacer()
                                    Text(Fmt.bytes(rows.reduce(0) { $0 + $1.bytes })).monospacedDigit()
                                    if group.canTrash {
                                        Button("Select recommended") {
                                            for r in rows where r.recommended && !r.inUse { m.checked.insert(r.url) }
                                        }.buttonStyle(.link).font(.caption)
                                    }
                                }
                            } footer: {
                                Text(group.note).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Deep Clean")
        .onAppear {
            refreshTrash()
            if !m.scanned && !m.scanning { scan() }
        }
        .confirmationDialog("Move \(Fmt.plural(picked.count, "folder")) (\(Fmt.bytes(pickedBytes))) to the Trash?", isPresented: $confirmTrash) {
            Button("Move to Trash", role: .destructive) {
                Task {
                    _ = await library.trashURLs(picked.map(\.url), sizes: pickedBytes)
                    m.items.removeAll { picked.map(\.url).contains($0.url) }
                    m.checked.subtract(picked.map(\.url))
                    library.show(toast: "Moved \(Fmt.bytes(pickedBytes)) to the Trash. Empty it to get the space back.")
                    refreshTrash()
                }
            }
        } message: {
            Text("These are rebuildable: npm install, pip install or a fresh build recreates them. You can still put them back from the Trash.")
        }
        .confirmationDialog("Empty the Trash?", isPresented: $confirmEmpty) {
            Button("Empty Trash", role: .destructive) {
                if let err = DeepCleanScanner.emptyTrash() { library.show(toast: err) }
                else { library.show(toast: "Trash emptied"); library.refreshDisk() }
                refreshTrash()
            }
        } message: {
            Text("This permanently deletes everything in the Trash (\(Fmt.bytes(m.trashSize ?? 0))). It can’t be undone.")
        }
    }

    private func row(_ it: JunkItem) -> some View {
        HStack(spacing: 10) {
            if it.group.canTrash {
                Toggle("", isOn: Binding(get: { m.checked.contains(it.url) }, set: { on in
                    if on { m.checked.insert(it.url) } else { m.checked.remove(it.url) }
                })).labelsHidden()
            } else {
                Image(systemName: "info.circle").foregroundStyle(.secondary).frame(width: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(it.title).lineLimit(1)
                    if it.inUse {
                        Text("In use right now").font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.orange.opacity(0.15), in: Capsule()).foregroundStyle(.orange)
                            .help("An app or process is running from this project. Quit it before cleaning.")
                    } else if it.recommended && it.group.canTrash {
                        Text("Safe to remove").font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.green.opacity(0.15), in: Capsule()).foregroundStyle(.green)
                    }
                }
                Text(it.detail + (it.lastUsed.map { " · last touched \(Fmt.ago($0))" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(Fmt.bytes(it.bytes)).monospacedDigit().font(.callout.weight(.medium))
            Button { NSWorkspace.shared.activateFileViewerSelecting([it.url]) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless).help("Show in Finder")
        }
        .padding(.vertical, 3)
    }

    private func scan() {
        m.scanning = true
        let roots = Prefs.projectRootPaths.map { URL(fileURLWithPath: $0) }
        Task.detached(priority: .userInitiated) {
            let found = DemoData.root != nil ? DemoData.junk() : DeepCleanScanner.scan(projectRoots: roots, progress: { p in
                Task { @MainActor in m.current = p }
            }, isCancelled: { false })
            await MainActor.run {
                m.items = found
                m.checked = []
                m.scanning = false
                m.scanned = true
            }
        }
    }

    private func refreshTrash() {
        Task.detached(priority: .utility) {
            let s = DeepCleanScanner.trashSize()
            await MainActor.run { m.trashSize = s }
        }
    }
}

// MARK: - Memory & Swap

struct MemoryView: View {
    @Environment(MemoryMonitor.self) private var memory
    @State private var confirmForce: AppMemory?
    @AppStorage("sort.apps") private var sort: AppSort = .memory
    @AppStorage("sort.apps.reversed") private var reversed = false

    private var apps: [AppMemory] {
        switch sort {
        case .memory: return memory.apps.sorted(by: { $0.footprint }, descending: !reversed)
        case .processes: return memory.apps.sorted(by: { $0.processCount }, descending: !reversed)
        case .name: return memory.apps.sorted(by: { $0.name.lowercased() }, descending: reversed)
        }
    }

    var body: some View {
        let s = memory.snapshot
        let suggestions = memory.apps.filter { $0.suggestion != nil }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeader(title: "Memory & Swap",
                              subtitle: "When memory runs short, macOS writes it to swap files on your disk. Quitting heavy apps lets macOS shrink swap and hand that disk space back.")
                HStack(alignment: .top, spacing: 14) {
                    stat("Swap in use", Fmt.bytes(Int64(s.swapUsed)), "of \(Fmt.bytes(Int64(s.swapTotal))) allocated", .indigo,
                         fraction: s.swapTotal > 0 ? Double(s.swapUsed) / Double(s.swapTotal) : 0)
                    stat("Swap files on disk", Fmt.bytes(Int64(s.swapFilesOnDisk)), "\(s.swapFileCount) files in /System/Volumes/VM", .purple, fraction: nil)
                    stat("Memory used", Fmt.bytes(Int64(s.used)), "of \(Fmt.bytes(Int64(s.physical))) · compressed \(Fmt.bytes(Int64(s.compressed)))", .blue,
                         fraction: Double(s.used) / Double(max(1, s.physical)))
                    stat("Pressure", s.pressureLabel, "App memory \(Fmt.bytes(Int64(s.appMemory)))",
                         s.pressure >= 4 ? .red : s.pressure >= 2 ? .orange : .green, fraction: nil)
                }
                if s.swapUsed > 2_000_000_000 {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lightbulb.fill").foregroundStyle(.yellow)
                        Text("Swap files stay on disk until macOS no longer needs them. After you quit a few heavy apps, the space usually comes back within minutes. A restart clears all \(Fmt.bytes(Int64(s.swapFilesOnDisk))) at once.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }
                if !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quitting these would release \(Fmt.bytes(Int64(suggestions.reduce(UInt64(0)) { $0 + $1.footprint })))")
                            .font(.title3.weight(.semibold))
                        Text("Memory figures match Activity Monitor and include memory already pushed out to swap, so freeing it also lets macOS shrink the swap files on your disk.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        ForEach(suggestions) { appRow($0, highlight: true) }
                    }
                    .card()
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Everything you’re running").font(.title3.weight(.semibold))
                        Spacer()
                        if memory.isRefreshing { ProgressView().controlSize(.small) }
                        SortMenu(key: $sort, reversed: $reversed)
                        Button("Refresh") { memory.refresh() }
                    }
                    ForEach(apps) { appRow($0, highlight: false) }
                }
                .card()
            }
            .padding(24)
        }
        .navigationTitle("Memory & Swap")
        .onAppear { memory.start() }
        .onDisappear { memory.stop() }
        .confirmationDialog("Force quit \(confirmForce?.name ?? "")?", isPresented: Binding(get: { confirmForce != nil }, set: { if !$0 { confirmForce = nil } })) {
            Button("Force Quit", role: .destructive) { if let a = confirmForce { memory.forceQuit(a) }; confirmForce = nil }
        } message: {
            Text("Unsaved work in \(confirmForce?.name ?? "the app") will be lost.")
        }
    }

    private func stat(_ title: String, _ value: String, _ sub: String, _ tint: Color, fraction: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(tint)
            Text(value).font(.system(size: 24, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
            if let fraction { ProgressView(value: min(1, fraction)).tint(tint) }
            Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func appRow(_ app: AppMemory, highlight: Bool) -> some View {
        HStack(spacing: 10) {
            if let url = app.bundleURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 26, height: 26)
            } else {
                Image(systemName: "terminal").frame(width: 26, height: 26).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(app.name).lineLimit(1)
                    if app.isActive { Text("in use").font(.caption2).foregroundStyle(.secondary) }
                    if let s = app.suggestion, highlight {
                        Text(s).font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.orange.opacity(0.15), in: Capsule()).foregroundStyle(.orange)
                    }
                }
                Text(app.processCount > 1 ? "\(app.processCount) processes" : "1 process").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Fmt.bytes(Int64(app.footprint))).monospacedDigit().font(.callout.weight(.medium))
                .frame(width: 90, alignment: .trailing)
            if app.isSelf || app.isAppleSystem {
                Text(app.isSelf ? "This app" : "macOS").font(.caption).foregroundStyle(.tertiary).frame(width: 128)
            } else {
                Button("Quit") { memory.quit(app) }.frame(width: 56)
                Button("Force") { confirmForce = app }.frame(width: 64).help("Force quit if it doesn’t respond")
            }
        }
        .padding(.vertical, 2)
    }
}
