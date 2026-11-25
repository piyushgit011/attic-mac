import SwiftUI
import UniformTypeIdentifiers

struct CloudView: View {
    @Environment(CloudStore.self) private var cloud

    var body: some View {
        if cloud.isConnected { CloudBrowser() } else { CloudSetupView() }
    }
}

// MARK: - Setup

struct CloudSetupView: View {
    @Environment(CloudStore.self) private var cloud
    @State private var envPath = VerselyImport.defaultEnvURL.path
    @State private var bucket = VerselyImport.suggestedBucket
    @State private var busy = false
    @State private var error: String?
    @State private var manual = R2Credentials(accountId: "", accessKeyId: "", secretAccessKey: "", bucket: VerselyImport.suggestedBucket)
    @State private var createManual = true

    var body: some View {
        let found = VerselyImport.credentials(from: URL(fileURLWithPath: envPath))
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Free up space with Cloudflare R2").font(.largeTitle.weight(.bold))
                    Text("Big files move to a private bucket. A tiny placeholder stays in the same folder, and double-clicking it brings the file back. R2 has no download fees, and storage costs about $0.015 per GB a month.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label("Use Versely’s Cloudflare account", systemImage: "bolt.horizontal.circle.fill").font(.title3.weight(.semibold)).foregroundStyle(.orange)
                    Text("Reads the R2 keys the Versely backend already uses, creates a separate bucket just for this Mac, and stores the keys in your Keychain.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        TextField("Versely backend .env", text: $envPath).textFieldStyle(.roundedBorder)
                        Button("Choose…") { pickEnv() }
                    }
                    if let found {
                        Label("Found Cloudflare account \(String(found.accountId.prefix(6)))… and R2 keys", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green).font(.callout)
                    } else {
                        Label("No CF_ACCOUNT_ID / CF_R2_ACCESS_KEY_ID / CF_R2_SECRET_ACCESS_KEY in that file", systemImage: "xmark.circle")
                            .foregroundStyle(.orange).font(.callout)
                    }
                    HStack {
                        Text("Bucket for this Mac")
                        TextField("bucket", text: $bucket).textFieldStyle(.roundedBorder).frame(width: 280)
                    }
                    Button {
                        run { try await cloud.connectWithVersely(envURL: URL(fileURLWithPath: envPath), bucketName: bucket) }
                    } label: {
                        Label(busy ? "Connecting…" : "Create bucket & connect", systemImage: "cloud.fill")
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(found == nil || busy)
                }
                .card()

                DisclosureGroup("Or enter R2 keys yourself") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Account ID", text: $manual.accountId)
                        TextField("Access key ID", text: $manual.accessKeyId)
                        SecureField("Secret access key", text: $manual.secretAccessKey)
                        TextField("Bucket", text: $manual.bucket)
                        Toggle("Create the bucket if it doesn’t exist", isOn: $createManual)
                        Button("Connect") { run { try await cloud.connect(manual, createIfMissing: createManual) } }
                            .disabled(manual.accountId.isEmpty || manual.accessKeyId.isEmpty || manual.secretAccessKey.isEmpty || busy)
                    }
                    .textFieldStyle(.roundedBorder)
                    .padding(.top, 8)
                }
                .card()

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).textSelection(.enabled)
                }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .navigationTitle("Cloudflare R2")
    }

    private func run(_ op: @escaping () async throws -> Void) {
        busy = true
        error = nil
        Task {
            do { try await op() } catch { self.error = error.localizedDescription }
            busy = false
        }
    }

    private func pickEnv() {
        let panel = NSOpenPanel()
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: envPath).deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url { envPath = url.path }
    }
}

// MARK: - Browser

struct CloudBrowser: View {
    @Environment(CloudStore.self) private var cloud
    @Environment(NavigationModel.self) private var nav
    @State private var selection = Set<String>()
    @State private var newFolder = ""
    @State private var askFolder = false
    @State private var confirmDelete = false
    @State private var dropTargeted = false
    @State private var filter = ""
    @State private var order: [KeyPathComparator<CloudRow>] = [KeyPathComparator(\.name)]

    private var objects: [R2Object] {
        cloud.listing.objects.filter { !$0.isFolderMarker && (filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter)) }
    }
    private var folders: [String] {
        cloud.listing.folders.filter { filter.isEmpty || $0.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            breadcrumbBar
            Divider()
            content
        }
        .navigationTitle(cloud.bucket)
        .task { if cloud.listing.objects.isEmpty && cloud.listing.folders.isEmpty { await cloud.refresh(); await cloud.refreshBucketStats() } }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard cloud.canWrite else { return false }
            Task {
                var urls: [URL] = []
                for p in providers {
                    if let url = try? await p.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data,
                       let u = URL(dataRepresentation: url, relativeTo: nil) { urls.append(u) }
                }
                await cloud.upload(urls)
            }
            return true
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 16).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .background(Color.accentColor.opacity(0.06)).padding(10)
                    .overlay(Label("Drop to upload to \(cloud.prefix.isEmpty ? cloud.bucket : cloud.prefix)", systemImage: "icloud.and.arrow.up").font(.title2))
            }
        }
        .alert("New folder", isPresented: $askFolder) {
            TextField("Name", text: $newFolder)
            Button("Create") { Task { await cloud.createFolder(newFolder); newFolder = "" } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete \(Fmt.plural(selection.count, "item")) from R2?", isPresented: $confirmDelete) {
            Button("Delete permanently", role: .destructive) {
                let objs = cloud.listing.objects.filter { selection.contains($0.key) }
                let fs = cloud.listing.folders.filter { selection.contains($0) }
                Task { await cloud.delete(objects: objs, folders: fs); selection = [] }
            }
        } message: {
            Text("Cloud files can’t be recovered once deleted. Offloaded files will no longer be restorable.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "cloud.fill").font(.title).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Menu(cloud.bucket) {
                        ForEach(cloud.buckets, id: \.self) { b in
                            Button(b == cloud.creds?.bucket ? "\(b) (this Mac)" : b) { Task { await cloud.switchBucket(b) } }
                        }
                    }
                    .menuStyle(.borderlessButton).fixedSize().font(.title2.weight(.semibold))
                    if !cloud.canWrite {
                        Label("Read only", systemImage: "lock.fill").font(.caption).foregroundStyle(.secondary)
                            .help("Other Versely buckets are read-only here. Turn on changes in Settings if you really need them.")
                    }
                }
                if cloud.isHomeBucket {
                    Text("\(cloud.bucketCount.map { Fmt.plural($0, "file") } ?? "…") · \(cloud.bucketBytes.map(Fmt.bytes) ?? "…") · \(String(format: "≈ $%.2f/month", cloud.monthlyCost))")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            TextField("Filter", text: $filter).textFieldStyle(.roundedBorder).frame(width: 160)
            Button { Task { await cloud.refresh() } } label: { Image(systemName: "arrow.clockwise") }.help("Refresh")
            Button { askFolder = true } label: { Label("New Folder", systemImage: "folder.badge.plus") }.disabled(!cloud.canWrite)
            Button { pickUpload() } label: { Label("Upload", systemImage: "arrow.up.circle.fill") }
                .buttonStyle(.borderedProminent).disabled(!cloud.canWrite)
        }
        .padding(20)
    }

    private var breadcrumbBar: some View {
        HStack(spacing: 4) {
            Button {
                let parts = cloud.prefix.split(separator: "/").dropLast()
                Task { await cloud.open(prefix: parts.isEmpty ? "" : parts.joined(separator: "/") + "/") }
            } label: { Image(systemName: "arrow.turn.left.up") }
                .buttonStyle(.borderless).disabled(cloud.prefix.isEmpty).help("Enclosing folder")
                .padding(.trailing, 6)
            ForEach(Array(cloud.breadcrumbs.enumerated()), id: \.offset) { i, crumb in
                if i > 0 { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
                Button(crumb.name) { Task { await cloud.open(prefix: crumb.prefix) } }.buttonStyle(.link)
            }
            Spacer()
            if !selection.isEmpty {
                let objs = cloud.listing.objects.filter { selection.contains($0.key) }
                Text("\(selection.count) selected").foregroundStyle(.secondary)
                Button("Download") { Task { _ = await cloud.download(objs) } }.disabled(objs.isEmpty)
                Button("Delete…", role: .destructive) { confirmDelete = true }.disabled(!cloud.canWrite)
            }
            if cloud.isLoading { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if let err = cloud.error {
            EmptyStateView(symbol: "exclamationmark.icloud", title: "Couldn’t load the bucket", message: err)
        } else if objects.isEmpty && folders.isEmpty && !cloud.isLoading {
            EmptyStateView(symbol: "icloud", title: "Empty folder", message: cloud.canWrite ? "Drop files here, or offload big files from Large Files or Clean Up." : "Nothing here.")
        } else {
            let folderRows = folders.map { CloudRow(id: $0, name: String($0.dropFirst(cloud.prefix.count).dropLast()), object: nil) }.sorted(using: order)
            let fileRows = objects.map { CloudRow(id: $0.key, name: $0.name, object: $0) }.sorted(using: order)
            Table(of: CloudRow.self, selection: $selection, sortOrder: $order) {
                TableColumn("Name", value: \.name) { row in
                    HStack(spacing: 8) {
                        if row.isFolder {
                            Image(systemName: "folder.fill").foregroundStyle(.blue)
                        } else {
                            Image(nsImage: NSWorkspace.shared.icon(for: UTType(filenameExtension: (row.name as NSString).pathExtension) ?? .data))
                                .resizable().frame(width: 18, height: 18)
                        }
                        Text(row.name).lineLimit(1).truncationMode(.middle)
                        if let rec = row.object.flatMap({ cloud.record(forKey: $0.key) }) {
                            Text("from \(rec.folder)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .width(min: 240, ideal: 420)
                TableColumn("Size", value: \.sizeSort) { row in Text(row.object.map { Fmt.bytes($0.size) } ?? "—").monospacedDigit() }.width(90)
                TableColumn("Modified", value: \.modifiedSort) { row in Text(row.object?.lastModified.map(Fmt.shortDate) ?? "") }.width(120)
            } rows: {
                ForEach(folderRows) { TableRow($0) }
                ForEach(fileRows) { TableRow($0) }
            }
            .contextMenu(forSelectionType: String.self) { ids in
                menu(for: ids)
            } primaryAction: { ids in
                guard let id = ids.first else { return }
                if id.hasSuffix("/") { Task { await cloud.open(prefix: id) } }
                else if let obj = cloud.listing.objects.first(where: { $0.key == id }) { Task { await cloud.preview(obj) } }
            }
        }
    }

    @ViewBuilder
    private func menu(for ids: Set<String>) -> some View {
        let objs = cloud.listing.objects.filter { ids.contains($0.key) }
        if let obj = objs.first, objs.count == 1 {
            Button("Open") { Task { await cloud.preview(obj) } }
            if let rec = cloud.record(forKey: obj.key) {
                Button("Restore to \(rec.folder)") { Task { await cloud.restore(rec) } }
            }
            Button("Copy Private Link (7 days)") { cloud.copyLink(obj) }
        }
        if !objs.isEmpty {
            Button("Download to Downloads") { Task { _ = await cloud.download(objs) } }
        }
        Divider()
        Button("Delete…", role: .destructive) { selection = ids; confirmDelete = true }.disabled(!cloud.canWrite)
    }

    private func pickUpload() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        if panel.runModal() == .OK { Task { await cloud.upload(panel.urls) } }
    }
}

struct CloudRow: Identifiable, Hashable {
    let id: String
    let name: String
    let object: R2Object?
    var isFolder: Bool { object == nil }
    var sizeSort: Int64 { object?.size ?? -1 }
    var modifiedSort: Date { object?.lastModified ?? .distantPast }
}

// MARK: - Offload sheet

struct OffloadSheet: View {
    let items: [FileItem]
    @Environment(CloudStore.self) private var cloud
    @Environment(NavigationModel.self) private var nav
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.afterUpload) private var after = AfterUpload.trash.rawValue
    @AppStorage(Prefs.leaveStubs) private var leaveStubs = true
    @AppStorage("offloadDestination") private var destination = "r2"
    @State private var started = false

    private var toICloud: Bool { destination == "icloud" }

    var body: some View {
        let eligible = items.filter { !$0.isCloudOnly && !$0.url.isAtticStub && $0.category != .apps && (toICloud || !$0.isPackage) }
        let bytes = eligible.reduce(Int64(0)) { $0 + $1.size }
        let alreadyInICloud = eligible.filter(\.isICloudDownloaded).count
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: toICloud ? "icloud.and.arrow.up.fill" : "cloud.fill").font(.system(size: 34))
                    .foregroundStyle(toICloud ? Color.cyan : Color.orange)
                VStack(alignment: .leading) {
                    Text("Free up space").font(.title2.weight(.semibold))
                    Text("\(Fmt.plural(eligible.count, "file")) · \(Fmt.bytes(bytes))").foregroundStyle(.secondary)
                }
            }
            if !started {
                Picker("Move to", selection: $destination) {
                    Label("Cloudflare R2", systemImage: "cloud").tag("r2")
                    Label("iCloud Drive", systemImage: "icloud").tag("icloud")
                }
                .pickerStyle(.segmented)
            }
            if started, let p = cloud.offloadProgress {
                progressView(p)
            } else if !toICloud && !cloud.isConnected {
                Text("Connect your R2 bucket first. It takes one click with Versely’s Cloudflare account.").foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                    Button("Set up R2") { dismiss(); nav.go(.cloud) }.buttonStyle(.borderedProminent)
                }
            } else if toICloud && !CloudStore.iCloudAvailable {
                Text("iCloud Drive isn’t turned on for this Mac. Turn it on in System Settings ▸ Apple Account ▸ iCloud.").foregroundStyle(.secondary)
                HStack { Spacer(); Button("Cancel") { dismiss() } }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(eligible.prefix(5)) { Text("• \($0.name) (\(Fmt.bytes($0.size)))").lineLimit(1).truncationMode(.middle) }
                    if eligible.count > 5 { Text("and \(eligible.count - 5) more").foregroundStyle(.secondary) }
                    if eligible.count < items.count {
                        Text("\(items.count - eligible.count) apps, packages or iCloud-only items will be skipped.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if toICloud {
                    Text(alreadyInICloud > 0
                         ? "\(alreadyInICloud) of these are already in iCloud Drive: they stay where they are and stop taking space here. The rest move to iCloud Drive ▸ Attic with a link left in their folder, and the copy on this Mac goes as soon as iCloud has uploaded it."
                         : "Files move to iCloud Drive ▸ Attic and a link stays in their folder, so they still open from there. The copy on this Mac goes as soon as iCloud has uploaded it. They count toward your iCloud storage.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Each file is uploaded to “\(cloud.creds?.bucket ?? "")”, checked byte-for-byte in R2, and only then removed from this Mac.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Picker("After a verified upload", selection: $after) {
                        ForEach(AfterUpload.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.radioGroup)
                    Toggle("Leave a small .attic placeholder where each file was (double-click to bring it back)", isOn: $leaveStubs)
                        .disabled(after == AfterUpload.keep.rawValue)
                }
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button(toICloud ? "Move \(Fmt.bytes(bytes)) to iCloud" : "Offload \(Fmt.bytes(bytes)) to R2") {
                        started = true
                        if toICloud {
                            Task { await cloud.offloadToICloud(eligible) }
                        } else {
                            Task { await cloud.offload(eligible, after: AfterUpload(rawValue: after) ?? .trash, leaveStubs: leaveStubs) }
                        }
                    }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(eligible.isEmpty)
                }
            }
        }
        .padding(24)
        .frame(width: 540)
        .onAppear {
            if nav.autoStartOffload {
                nav.autoStartOffload = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    started = true
                    if toICloud { Task { await cloud.offloadToICloud(eligible) } }
                    else { Task { await cloud.offload(eligible, after: .delete, leaveStubs: true) } }
                }
            }
        }
    }

    @ViewBuilder
    private func progressView(_ p: CloudStore.OffloadProgress) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView(value: Double(p.bytesDone), total: Double(max(1, p.bytesTotal)))
            Text(p.finished ? "Done: \(p.done) of \(p.total) files" : "\(toICloud ? "Moving" : "Uploading") \(p.current) (\(min(p.done + 1, p.total)) of \(p.total))")
                .lineLimit(1).truncationMode(.middle)
            if toICloud {
                Text(cloud.iCloudPendingCount > 0
                     ? "\(Fmt.bytes(p.freed)) freed now. The rest is freed as iCloud finishes uploading (\(Fmt.plural(cloud.iCloudPendingCount, "file")) waiting). Attic keeps checking while it’s open."
                     : "\(Fmt.bytes(p.freed)) freed on this Mac. Everything is in iCloud Drive.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("\(Fmt.bytes(p.bytesDone)) of \(Fmt.bytes(p.bytesTotal)) uploaded · \(Fmt.bytes(p.freed)) freed on this Mac")
                    .font(.callout).foregroundStyle(.secondary)
                if after == AfterUpload.trash.rawValue && p.finished && p.freed > 0 {
                    Text("The local copies are in the Trash. Empty it to get the \(Fmt.bytes(p.freed)) back.").font(.callout).foregroundStyle(.orange)
                }
            }
            if !p.failures.isEmpty {
                ScrollView {
                    VStack(alignment: .leading) {
                        ForEach(p.failures, id: \.self) { Text($0).font(.caption).foregroundStyle(.red) }
                    }
                }.frame(maxHeight: 100)
            }
            HStack {
                Spacer()
                Button(p.finished ? "Done" : "Hide") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
    }
}

// MARK: - Offloaded list

struct OffloadedView: View {
    @Environment(CloudStore.self) private var cloud
    @Environment(NavigationModel.self) private var nav
    @State private var selection = Set<UUID>()
    @State private var filter = ""
    @State private var order: [KeyPathComparator<OffloadRecord>] = [KeyPathComparator(\.offloadedAt, order: .reverse)]

    var body: some View {
        let rows = cloud.records.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) || $0.folder.localizedCaseInsensitiveContains(filter) }
            .sorted(using: order)
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Offloaded").font(.title2.weight(.semibold))
                    Text("\(Fmt.plural(cloud.records.count, "file")) · \(Fmt.bytes(cloud.offloadedBytes)) moved off this Mac" + (cloud.iCloudStatus.map { " · \($0)" } ?? ""))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TextField("Filter", text: $filter).textFieldStyle(.roundedBorder).frame(width: 180)
                Button { restore(open: false) } label: { Label("Restore", systemImage: "arrow.down.circle") }
                    .buttonStyle(.borderedProminent).disabled(selection.isEmpty || !cloud.isConnected)
            }
            .padding(20)
            Divider()
            if cloud.records.isEmpty {
                EmptyStateView(symbol: "icloud.and.arrow.up", title: "Nothing offloaded yet",
                               message: "Select big files anywhere in Attic and choose Offload to R2. They show up here, ready to bring back.")
            } else {
                Table(rows, selection: $selection, sortOrder: $order) {
                    TableColumn("Name", value: \.name) { r in
                        HStack {
                            Image(nsImage: NSWorkspace.shared.icon(for: UTType(filenameExtension: r.ext) ?? .data)).resizable().frame(width: 18, height: 18)
                            Text(r.name).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    TableColumn("Was in", value: \.folder) { Text($0.folder).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head) }
                    TableColumn("Now in", value: \.whereLabel) { r in
                        HStack(spacing: 5) {
                            Image(systemName: r.isICloud ? "icloud" : "cloud").foregroundStyle(r.isICloud ? Color.cyan : Color.orange)
                            Text(r.pendingEvict == true ? "iCloud (uploading…)" : r.whereLabel).lineLimit(1)
                        }
                    }.width(min: 110, ideal: 170)
                    TableColumn("Size", value: \.size) { Text(Fmt.bytes($0.size)).monospacedDigit() }.width(90)
                    TableColumn("Offloaded", value: \.offloadedAt) { Text(Fmt.ago($0.offloadedAt)) }.width(110)
                }
                .contextMenu(forSelectionType: UUID.self) { ids in
                    Button("Restore") { selection = ids; restore(open: false) }
                    Button("Restore & Open") { selection = ids; restore(open: true) }
                    Button("Restore & Remove from R2") { selection = ids; restore(open: false, remove: true) }
                    if ids.count == 1, let r = cloud.records.first(where: { ids.contains($0.id) }), let stub = r.stubPath {
                        Button("Show Placeholder in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: stub)]) }
                    }
                } primaryAction: { ids in
                    selection = ids
                    restore(open: true)
                }
            }
        }
        .navigationTitle("Offloaded")
    }

    private func restore(open: Bool, remove: Bool = false) {
        let recs = cloud.records.filter { selection.contains($0.id) }
        Task {
            for r in recs { await cloud.restore(r, open: open && recs.count == 1, removeFromCloud: remove) }
            selection = []
        }
    }
}
