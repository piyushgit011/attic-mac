import SwiftUI

/// Where the whole disk goes, in buckets you can act on.
struct StorageView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(NavigationModel.self) private var nav
    @State private var expanded: Set<String> = [StorageBucket.Kind.projects.rawValue, StorageBucket.Kind.appData.rawValue]
    private var model: StorageBreakdownModel { AppState.shared.storage }

    var body: some View {
        let disk = library.disk
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom) {
                    SectionHeader(title: "Storage",
                                  subtitle: "Everything on Macintosh HD, including what macOS lumps into “System Data”.")
                    Spacer()
                    if model.isMeasuring {
                        ProgressView().controlSize(.small)
                        Text("Measuring \(model.current)").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).frame(maxWidth: 280, alignment: .trailing)
                    } else {
                        Button("Measure Again") { model.measure() }
                    }
                }
                bar(disk)
                if !model.hasFullDiskAccess {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "lock.shield").font(.title2).foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Some app data is hidden from Attic").font(.headline)
                            Text("macOS keeps other apps’ private folders (WhatsApp media, Mail, Messages) away from Attic, so that space shows up as “Other system data”. Give Attic Full Disk Access to see it, then Measure Again.")
                                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button("Open Settings") { StorageBreakdownModel.openFullDiskAccessSettings() }
                    }
                    .padding(14)
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
                if model.buckets.isEmpty {
                    HStack { ProgressView(); Text("Measuring your disk. This takes a minute the first time.").foregroundStyle(.secondary) }
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    VStack(spacing: 10) {
                        ForEach(model.buckets) { row($0, total: max(1, disk.total)) }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Storage")
        .onAppear { library.refreshDisk(); model.measureIfStale() }
    }

    private func bar(_ disk: DiskStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.bytes(disk.used)).font(.system(size: 30, weight: .bold, design: .rounded))
                Text("used of \(Fmt.bytes(disk.total)) · \(Fmt.bytes(disk.available)) free").foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(model.buckets) { b in
                        Rectangle().fill(b.tint.gradient)
                            .frame(width: max(2, geo.size.width * CGFloat(b.bytes) / CGFloat(max(1, disk.total))))
                            .help("\(b.title): \(Fmt.bytes(b.bytes))")
                    }
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(height: 18)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .card()
    }

    @ViewBuilder
    private func row(_ b: StorageBucket, total: Int64) -> some View {
        let open = expanded.contains(b.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: b.symbol).font(.title3).foregroundStyle(b.tint).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(b.title).font(.headline)
                    Text(b.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Fmt.bytes(b.bytes)).font(.headline).monospacedDigit()
                    Text("\(Int((Double(b.bytes) / Double(total) * 100).rounded()))% of disk").font(.caption).foregroundStyle(.secondary)
                }
                action(b)
                if !b.top.isEmpty {
                    Button { if open { expanded.remove(b.id) } else { expanded.insert(b.id) } } label: {
                        Image(systemName: "chevron.right").rotationEffect(.degrees(open ? 90 : 0))
                    }
                    .buttonStyle(.borderless)
                }
            }
            if open && !b.top.isEmpty {
                VStack(spacing: 4) {
                    ForEach(b.top, id: \.self) { e in
                        HStack {
                            Text(e.name).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(Fmt.bytes(e.bytes)).monospacedDigit().foregroundStyle(.secondary)
                            if !e.path.isEmpty {
                                Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: e.path)]) } label: { Image(systemName: "magnifyingglass") }
                                    .buttonStyle(.borderless).help("Show in Finder")
                            }
                        }
                        .font(.callout)
                        .padding(.leading, 42)
                    }
                }
            }
        }
        .card()
    }

    @ViewBuilder
    private func action(_ b: StorageBucket) -> some View {
        switch b.kind {
        case .files: Button("Clean Up") { nav.go(.cleanup) }
        case .projects, .caches: Button("Deep Clean") { nav.go(.deepClean) }
        case .swap: Button("See what to quit") { nav.go(.memory) }
        case .trash: Button("Empty…") { nav.go(.deepClean) }
        case .simulators:
            Button("Open Xcode") {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.dt.Xcode") { NSWorkspace.shared.open(url) }
            }
        default: EmptyView()
        }
    }
}
