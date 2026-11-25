import SwiftUI

struct HomeView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(CloudStore.self) private var cloud
    @Environment(NavigationModel.self) private var nav
    @Environment(MemoryMonitor.self) private var memory

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                greeting
                StorageCard()
                HStack(alignment: .top, spacing: 16) {
                    cloudCard
                    swapCard
                }
                categoryTiles
                if !library.cleanupCards.isEmpty { cleanupRow }
                shelf("Latest downloads", library.latestDownloads, .downloadedFrom)
                shelf("Recent images", Array(library.items(in: .images).sorted { $0.arrivalDate > $1.arrivalDate }.prefix(14)), .category(.images))
                shelf("Recent videos", Array(library.items(in: .videos).sorted { $0.arrivalDate > $1.arrivalDate }.prefix(14)), .category(.videos))
                shelf("Recent documents", Array(library.items(in: .documents).sorted { $0.arrivalDate > $1.arrivalDate }.prefix(14)), .category(.documents))
            }
            .padding(24)
        }
        .navigationTitle("Home")
        .onAppear { library.refreshDisk(); memory.refresh() }
    }

    private var greeting: some View {
        let hour = Calendar.current.component(.hour, from: Date())
        let hello = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        return HStack(spacing: 14) {
            Image("LogoMark").resizable().frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
            Text(hello).font(.largeTitle.weight(.bold))
            Text(library.isScanning ? "Reading your files… \(Fmt.count(library.scanCount)) so far"
                 : "\(Fmt.count(library.items.count)) files indexed\(library.lastScan.map { " · updated \(Fmt.ago($0))" } ?? "")")
                .foregroundStyle(.secondary)
            }
        }
    }

    private var cloudCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Cloudflare R2", systemImage: "cloud.fill").font(.headline).foregroundStyle(.orange)
            if cloud.isConnected {
                Text(Fmt.bytes(cloud.offloadedBytes)).font(.system(size: 30, weight: .bold, design: .rounded))
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
                Button("Connect with Versely’s Cloudflare") { nav.go(.cloud) }.buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var swapCard: some View {
        let s = memory.snapshot
        return VStack(alignment: .leading, spacing: 10) {
            Label("Memory & Swap", systemImage: "memorychip").font(.headline).foregroundStyle(.indigo)
            Text(Fmt.bytes(Int64(s.swapUsed))).font(.system(size: 30, weight: .bold, design: .rounded))
            Text("of swap in use · \(s.swapFileCount) swap files take \(Fmt.bytes(Int64(s.swapFilesOnDisk))) of disk")
                .font(.callout).foregroundStyle(.secondary)
            Text("Memory \(Fmt.bytes(Int64(s.used))) of \(Fmt.bytes(Int64(s.physical))) · pressure \(s.pressureLabel)")
                .font(.caption).foregroundStyle(.tertiary)
            Button("See what to quit") { nav.go(.memory) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var categoryTiles: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            ForEach(FileCategory.library) { c in
                let t = library.totals[c] ?? CategoryTotal()
                Button { nav.go(.category(c)) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: c.symbol).font(.title2).foregroundStyle(c.tint)
                        Text(c.title).font(.headline)
                        Text("\(Fmt.count(t.count)) · \(Fmt.bytes(t.bytes))").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var cleanupRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Clean Up", subtitle: "Up to \(Fmt.bytes(library.cleanupCards.reduce(0) { $0 + $1.bytes })) you could get back. You review everything first.")
                Spacer()
                Button("See all") { nav.go(.cleanup) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(library.cleanupCards) { card in
                        CleanupCardView(card: card).frame(width: 240)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func shelf(_ title: String, _ items: [FileItem], _ target: SidebarItem) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(title).font(.title3.weight(.semibold))
                    Spacer()
                    Button("Show all") { nav.go(target) }.buttonStyle(.link)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(items) { item in
                            FileCard(item: item, side: 130, selected: false)
                                .onTapGesture { if NSApp.currentEvent?.clickCount == 2 { FileActions.open([item]) } else { nav.quickLook(item.url, in: items.map(\.url)) } }
                                .contextMenu { FileContextMenu(targets: [item], all: items) }
                                .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
                        }
                    }
                }
            }
        }
    }
}

struct StorageCard: View {
    @Environment(LibraryStore.self) private var library
    @Environment(MemoryMonitor.self) private var memory

    var body: some View {
        let disk = library.disk
        let cats = FileCategory.allCases.filter { (library.totals[$0]?.bytes ?? 0) > 0 }
        let indexed = cats.reduce(Int64(0)) { $0 + (library.totals[$1]?.bytes ?? 0) }
        let swap = Int64(memory.snapshot.swapFilesOnDisk)
        let systemAndOther = max(0, disk.used - indexed - swap)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.bytes(disk.available)).font(.system(size: 34, weight: .bold, design: .rounded))
                Text("free of \(Fmt.bytes(disk.total))").foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(disk.usedFraction * 100))% full").font(.headline)
                    .foregroundStyle(disk.usedFraction > 0.9 ? .red : disk.usedFraction > 0.8 ? .orange : .secondary)
            }
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(cats) { c in
                        let b = library.totals[c]?.bytes ?? 0
                        Rectangle().fill(c.tint.gradient).frame(width: max(2, geo.size.width * CGFloat(b) / CGFloat(max(1, disk.total))))
                    }
                    if swap > 0 {
                        Rectangle().fill(Color.indigo.gradient).frame(width: max(2, geo.size.width * CGFloat(swap) / CGFloat(max(1, disk.total))))
                    }
                    Rectangle().fill(Color.gray.opacity(0.5)).frame(width: max(0, geo.size.width * CGFloat(systemAndOther) / CGFloat(max(1, disk.total))))
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(height: 16)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            HStack(spacing: 14) {
                ForEach(cats) { c in legend(c.title, c.tint, library.totals[c]?.bytes ?? 0) }
                if swap > 0 { legend("Swap", .indigo, swap) }
                legend("System, apps’ data & other", .gray, systemAndOther)
            }
            .font(.caption)
        }
        .card()
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
