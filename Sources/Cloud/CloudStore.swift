import Foundation
import AppKit
import Security
import Observation

// MARK: - Keychain

enum Keychain {
    static let service = "studio.versely.attic.r2"

    static func save(_ data: Data, account: String = "default") throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        add[kSecAttrLabel as String] = "Attic – Cloudflare R2"
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Couldn’t save to Keychain (\(status))"])
        }
    }

    static func load(account: String = "default") -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    static func delete(account: String = "default") {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Versely backend credentials

enum VerselyImport {
    static var defaultEnvURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Developer/versely/content-creation-backend/.env")
    }

    /// Reads the Cloudflare account + R2 keys the Versely backend already uses.
    static func credentials(from envURL: URL = defaultEnvURL) -> (accountId: String, accessKeyId: String, secret: String)? {
        guard let text = try? String(contentsOf: envURL, encoding: .utf8) else { return nil }
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<eq].trimmingCharacters(in: .whitespaces)
            var value = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            values[key] = value
        }
        guard let account = values["CF_ACCOUNT_ID"] ?? values["CLOUDFLARE_ACCOUNT_ID"], !account.isEmpty,
              let key = values["CF_R2_ACCESS_KEY_ID"] ?? values["R2_ACCESS_KEY_ID"], !key.isEmpty,
              let secret = values["CF_R2_SECRET_ACCESS_KEY"] ?? values["R2_SECRET_ACCESS_KEY"], !secret.isEmpty else { return nil }
        return (account, key, secret)
    }

    /// A bucket name unique to this Mac, e.g. "attic-piyushs-macbook-pro".
    static var suggestedBucket: String {
        let host = (Host.current().localizedName ?? ProcessInfo.processInfo.hostName).lowercased()
        let cleaned = host.map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let ascii = cleaned.unicodeScalars.filter { $0.isASCII }.map(String.init).joined()
        return String(("attic-" + (ascii.isEmpty ? "mac" : ascii)).prefix(63))
    }
}

// MARK: - Offload records

struct OffloadRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var originalPath: String
    var bucket: String
    var key: String
    var size: Int64
    var modified: Date
    var offloadedAt: Date
    var stubPath: String?
    /// nil = Cloudflare R2, "icloud" = moved into iCloud Drive, "icloud-inplace" = already in iCloud, download removed.
    var destination: String?
    /// iCloud only: the local copy is removed once iCloud finishes uploading.
    var pendingEvict: Bool?
    var isICloud: Bool { destination?.hasPrefix("icloud") == true }
    var whereLabel: String { isICloud ? "iCloud Drive" : "R2 · \(bucket)" }

    var name: String { (originalPath as NSString).lastPathComponent }
    var folder: String { Fmt.path((originalPath as NSString).deletingLastPathComponent) }
    var ext: String { (name as NSString).pathExtension.lowercased() }
}

struct StubFile: Codable {
    var app = "Attic"
    var version = 1
    var bucket: String
    var key: String
    var size: Int64
    var originalPath: String
    var offloadedAt: Date
    var note = "This file lives in Cloudflare R2. Double-click to download it back with Attic."
}

enum AfterUpload: String, CaseIterable, Identifiable {
    case trash, delete, keep
    var id: String { rawValue }
    var title: String {
        switch self {
        case .trash: return "Move the local copy to the Trash"
        case .delete: return "Delete the local copy (frees space now)"
        case .keep: return "Keep the local copy (backup only)"
        }
    }
}

// MARK: - Transfers

@MainActor @Observable
final class TransferCenter {
    struct Transfer: Identifiable {
        enum State: Equatable { case running, done, failed(String) }
        let id = UUID()
        let name: String
        let isUpload: Bool
        var total: Int64
        var done: Int64 = 0
        var state: State = .running
        var fraction: Double { total > 0 ? min(1, Double(done) / Double(total)) : 0 }
    }

    var transfers: [Transfer] = []
    var active: [Transfer] { transfers.filter { $0.state == .running } }
    var overallFraction: Double {
        let a = active
        let total = a.reduce(Int64(0)) { $0 + $1.total }
        return total > 0 ? Double(a.reduce(Int64(0)) { $0 + $1.done }) / Double(total) : 0
    }

    func start(_ name: String, upload: Bool, total: Int64) -> UUID {
        let t = Transfer(name: name, isUpload: upload, total: total)
        transfers.insert(t, at: 0)
        if transfers.count > 200 { transfers.removeLast(transfers.count - 200) }
        return t.id
    }

    func update(_ id: UUID, done: Int64, total: Int64) {
        guard let i = transfers.firstIndex(where: { $0.id == id }) else { return }
        transfers[i].done = done
        if total > 0 { transfers[i].total = total }
    }

    func finish(_ id: UUID, error: Error? = nil) {
        guard let i = transfers.firstIndex(where: { $0.id == id }) else { return }
        transfers[i].state = error.map { .failed($0.localizedDescription) } ?? .done
        if error == nil { transfers[i].done = transfers[i].total }
    }

    func clearFinished() { transfers.removeAll { $0.state != .running } }

    nonisolated func reporter(_ id: UUID) -> @Sendable (Int64, Int64) -> Void {
        { done, total in Task { @MainActor in self.update(id, done: done, total: total) } }
    }
}

// MARK: - Cloud store

@MainActor @Observable
final class CloudStore {
    var creds: R2Credentials?
    var client: R2Client?
    var buckets: [String] = []
    var bucket: String = ""
    var prefix: String = ""
    var listing = R2Listing()
    var isLoading = false
    var error: String?
    var records: [OffloadRecord] = []
    var bucketBytes: Int64?
    var bucketCount: Int?
    var offloadProgress: OffloadProgress?

    struct OffloadProgress: Equatable {
        var total: Int
        var done: Int
        var bytesTotal: Int64
        var bytesDone: Int64
        var current: String
        var freed: Int64 = 0
        var failures: [String] = []
        var finished = false
    }

    private let transfers: TransferCenter
    private let library: LibraryStore
    private var manifestURL: URL { AppPaths.support.appendingPathComponent("offloaded.json") }

    var isConnected: Bool { client != nil }
    var isHomeBucket: Bool { bucket == creds?.bucket }
    var canWrite: Bool { isHomeBucket || UserDefaults.standard.bool(forKey: Prefs.allowOtherBucketWrites) }
    var offloadedBytes: Int64 { records.reduce(0) { $0 + $1.size } }
    /// R2 standard storage: $0.015 per GB-month, no egress fees.
    var monthlyCost: Double { Double(bucketBytes ?? offloadedBytes) / 1_000_000_000 * 0.015 }

    init(transfers: TransferCenter, library: LibraryStore) {
        self.transfers = transfers
        self.library = library
        loadManifest()
        DispatchQueue.main.async { [weak self] in self?.startICloudWatcher() }
        if let data = Keychain.load(), let c = try? JSONDecoder().decode(R2Credentials.self, from: data) {
            apply(c)
        }
    }

    private func apply(_ c: R2Credentials) {
        creds = c
        client = R2Client(c)
        bucket = c.bucket
        prefix = ""
    }

    // MARK: Setup

    /// Uses the Versely backend's Cloudflare keys, creates this Mac's bucket if it doesn't exist, and saves everything to the Keychain.
    func connectWithVersely(envURL: URL, bucketName: String) async throws {
        guard let v = VerselyImport.credentials(from: envURL) else {
            throw NSError(domain: "Attic", code: 1, userInfo: [NSLocalizedDescriptionKey: "Couldn’t find CF_ACCOUNT_ID, CF_R2_ACCESS_KEY_ID and CF_R2_SECRET_ACCESS_KEY in \(Fmt.path(envURL))"])
        }
        try await connect(R2Credentials(accountId: v.accountId, accessKeyId: v.accessKeyId, secretAccessKey: v.secret,
                                        bucket: bucketName, source: "versely"), createIfMissing: true)
    }

    func connect(_ c: R2Credentials, createIfMissing: Bool) async throws {
        let name = c.bucket.trimmingCharacters(in: .whitespaces).lowercased()
        guard name.range(of: "^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", options: .regularExpression) != nil else {
            throw NSError(domain: "Attic", code: 2, userInfo: [NSLocalizedDescriptionKey: "Bucket names use 3–63 lowercase letters, numbers and hyphens."])
        }
        var c = c
        c.bucket = name
        let probe = R2Client(c)
        let existing = (try? await probe.listBuckets()) ?? []
        if !existing.contains(name) {
            if await probe.bucketExists(name) == false {
                guard createIfMissing else {
                    throw NSError(domain: "Attic", code: 3, userInfo: [NSLocalizedDescriptionKey: "Bucket “\(name)” doesn’t exist."])
                }
                try await probe.createBucket(name)
            }
        }
        _ = try await probe.list(prefix: "", delimiter: "/") // proves read access
        try Keychain.save(try JSONEncoder().encode(c))
        apply(c)
        buckets = existing.contains(name) ? existing : (existing + [name]).sorted()
        await refresh()
        await refreshBucketStats()
    }

    func disconnect() {
        Keychain.delete()
        creds = nil
        client = nil
        listing = R2Listing()
        buckets = []
    }

    // MARK: Browsing

    func refresh() async {
        guard let client else { return }
        isLoading = true
        error = nil
        do {
            listing = try await client.list(bucket: bucket, prefix: prefix)
            if buckets.isEmpty { buckets = (try? await client.listBuckets()) ?? [bucket] }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func refreshBucketStats() async {
        guard let client, let home = creds?.bucket else { return }
        if let all = try? await client.list(bucket: home, prefix: "", delimiter: nil) {
            bucketBytes = all.objects.reduce(0) { $0 + $1.size }
            bucketCount = all.objects.filter { !$0.isFolderMarker }.count
        }
    }

    func open(prefix p: String, record: Bool = true) async {
        if record && p != prefix { AppState.shared.nav.recordCloud(prefix: prefix) }
        prefix = p
        await refresh()
    }

    func switchBucket(_ b: String) async {
        bucket = b
        prefix = ""
        await refresh()
    }

    var breadcrumbs: [(name: String, prefix: String)] {
        var out: [(String, String)] = [(bucket, "")]
        var acc = ""
        for part in prefix.split(separator: "/") {
            acc += part + "/"
            out.append((String(part), acc))
        }
        return out
    }

    func createFolder(_ name: String) async {
        guard let client, canWrite else { return }
        let clean = name.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !clean.isEmpty else { return }
        do {
            try await client.putEmpty(key: prefix + clean + "/")
            await refresh()
        } catch { self.error = error.localizedDescription }
    }

    /// Uploads files and folders (recursively) into the current folder.
    func upload(_ urls: [URL]) async {
        guard let client, canWrite else { return }
        var work: [(URL, String)] = []
        for url in urls {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                let base = url.deletingLastPathComponent().path + "/"
                if let en = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                    for case let f as URL in en where (try? f.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                        work.append((f, prefix + String(f.path.dropFirst(base.count))))
                    }
                }
            } else {
                work.append((url, prefix + url.lastPathComponent))
            }
        }
        for (file, key) in work {
            let size = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            let id = transfers.start(file.lastPathComponent, upload: true, total: size)
            do {
                try await client.upload(file: file, key: key, bucket: bucket, progress: transfers.reporter(id))
                transfers.finish(id)
            } catch {
                transfers.finish(id, error: error)
            }
        }
        await refresh()
        await refreshBucketStats()
    }

    func download(_ objects: [R2Object], to folder: URL? = nil, reveal: Bool = true) async -> [URL] {
        guard let client else { return [] }
        let dir = folder ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        var done: [URL] = []
        for obj in objects where !obj.isFolderMarker {
            let dest = AppPaths.uniqueURL(for: dir.appendingPathComponent(obj.name))
            let id = transfers.start(obj.name, upload: false, total: obj.size)
            do {
                try await client.download(key: obj.key, bucket: bucket, to: dest, progress: transfers.reporter(id))
                transfers.finish(id)
                done.append(dest)
            } catch {
                transfers.finish(id, error: error)
            }
        }
        if reveal, !done.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(done) }
        return done
    }

    /// Downloads into a cache folder and opens it, for a quick look at a cloud file.
    func preview(_ obj: R2Object) async {
        guard let client else { return }
        let dest = AppPaths.caches.appendingPathComponent("preview", isDirectory: true)
            .appendingPathComponent(bucket).appendingPathComponent(obj.key)
        if !FileManager.default.fileExists(atPath: dest.path) {
            let id = transfers.start(obj.name, upload: false, total: obj.size)
            do {
                try await client.download(key: obj.key, bucket: bucket, to: dest, progress: transfers.reporter(id))
                transfers.finish(id)
            } catch {
                transfers.finish(id, error: error)
                self.error = error.localizedDescription
                return
            }
        }
        NSWorkspace.shared.open(dest)
    }

    func delete(objects: [R2Object], folders: [String]) async {
        guard let client, canWrite else { return }
        do {
            var keys = objects.map(\.key)
            for f in folders {
                let all = try await client.list(bucket: bucket, prefix: f, delimiter: nil)
                keys += all.objects.map(\.key) + [f]
            }
            try await client.delete(keys: keys, bucket: bucket)
            let deleted = Set(keys)
            records.removeAll { $0.bucket == bucket && deleted.contains($0.key) }
            saveManifest()
            await refresh()
            await refreshBucketStats()
        } catch { self.error = error.localizedDescription }
    }

    func copyLink(_ obj: R2Object) {
        guard let url = client?.presignedURL(key: obj.key, bucket: bucket) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        library.show(toast: "Copied a private link to \(obj.name), valid for 7 days")
    }

    func record(forKey key: String) -> OffloadRecord? {
        records.first { $0.key == key && $0.bucket == bucket }
    }

    // MARK: Offload

    static func key(for url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.standardizedFileURL.path
        if path.hasPrefix(home + "/") { return String(path.dropFirst(home.count + 1)) }
        return "_root" + path
    }

    /// Upload → verify size in R2 → record → remove the local copy → leave a tiny .attic placeholder.
    func offload(_ items: [FileItem], after: AfterUpload, leaveStubs: Bool) async {
        guard let client, let home = creds?.bucket else { return }
        let files = items.filter { !$0.isPackage && !$0.isCloudOnly && !$0.url.isAtticStub && $0.category != .apps }
        var progress = OffloadProgress(total: files.count, done: 0, bytesTotal: files.reduce(0) { $0 + $1.size },
                                       bytesDone: 0, current: "")
        offloadProgress = progress
        var removed = Set<URL>()
        var stubs: [URL] = []
        let skipped = items.count - files.count
        if skipped > 0 { progress.failures.append("Skipped \(skipped) apps, packages or iCloud-only items") }

        for item in files {
            progress.current = item.name
            offloadProgress = progress
            let key = CloudStore.key(for: item.url)
            let id = transfers.start(item.name, upload: true, total: item.size)
            do {
                let existing = try await client.head(key, bucket: home)
                if existing?.size != item.size {
                    let meta = ["attic-original-path": R2Client.metaEncode(item.path),
                                "attic-mtime": String(Int(item.modified.timeIntervalSince1970))]
                    let base = progress.bytesDone
                    let report = transfers.reporter(id)
                    try await client.upload(file: item.url, key: key, bucket: home, metadata: meta, progress: { [weak self] done, total in
                        report(done, total)
                        Task { @MainActor in self?.offloadProgress?.bytesDone = base + done }
                    })
                }
                guard let check = try await client.head(key, bucket: home) else { throw R2Error.verifyFailed("object missing after upload") }
                guard check.size == item.size else { throw R2Error.verifyFailed("size \(check.size) ≠ \(item.size)") }
                transfers.finish(id)

                var stubPath: String?
                switch after {
                case .keep: break
                case .trash: try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                case .delete: try FileManager.default.removeItem(at: item.url)
                }
                if after != .keep {
                    removed.insert(item.url)
                    progress.freed += item.spaceOnDisk
                    if leaveStubs {
                        let stubURL = AppPaths.uniqueURL(for: item.url.appendingPathExtension("attic"))
                        let stub = StubFile(bucket: home, key: key, size: item.size, originalPath: item.path, offloadedAt: Date())
                        let enc = JSONEncoder()
                        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                        enc.dateEncodingStrategy = .iso8601
                        if (try? enc.encode(stub).write(to: stubURL)) != nil {
                            try? FileManager.default.setAttributes([.modificationDate: item.modified], ofItemAtPath: stubURL.path)
                            stubPath = stubURL.path
                            stubs.append(stubURL)
                        }
                    }
                }
                records.removeAll { $0.key == key && $0.bucket == home }
                records.insert(OffloadRecord(originalPath: item.path, bucket: home, key: key, size: item.size,
                                             modified: item.modified, offloadedAt: Date(), stubPath: stubPath), at: 0)
                saveManifest()
            } catch {
                transfers.finish(id, error: error)
                progress.failures.append("\(item.name): \(error.localizedDescription)")
            }
            progress.done += 1
            progress.bytesDone = files.prefix(progress.done).reduce(0) { $0 + $1.size }
            offloadProgress = progress
        }
        progress.finished = true
        progress.current = ""
        offloadProgress = progress
        library.remove(urls: removed)
        if !stubs.isEmpty { library.scanStubs(stubs) }
        await refreshBucketStats()
        if bucket == home { await refresh() }
    }

    // MARK: Restore

    @discardableResult
    func restore(_ record: OffloadRecord, open: Bool = false, removeFromCloud: Bool = false, reveal: Bool = true) async -> URL? {
        if record.isICloud {
            await restoreICloud(record, open: open)
            return URL(fileURLWithPath: record.originalPath)
        }
        guard let client else { error = R2Error.notConfigured.localizedDescription; return nil }
        let original = URL(fileURLWithPath: record.originalPath)
        let dest = AppPaths.uniqueURL(for: original)
        let id = transfers.start(record.name, upload: false, total: record.size)
        do {
            try await client.download(key: record.key, bucket: record.bucket, to: dest, progress: transfers.reporter(id))
            transfers.finish(id)
            try? FileManager.default.setAttributes([.modificationDate: record.modified], ofItemAtPath: dest.path)
            if let stub = record.stubPath { try? FileManager.default.removeItem(atPath: stub) }
            if removeFromCloud { try? await client.delete(key: record.key, bucket: record.bucket) }
            records.removeAll { $0.id == record.id }
            saveManifest()
            library.show(toast: "Restored \(record.name) to \(Fmt.path(dest.deletingLastPathComponent()))")
            library.refreshDisk()
            if open { NSWorkspace.shared.open(dest) } else if reveal { NSWorkspace.shared.activateFileViewerSelecting([dest]) }
            if removeFromCloud { await refreshBucketStats() }
            return dest
        } catch {
            transfers.finish(id, error: error)
            self.error = error.localizedDescription
            library.show(toast: "Couldn’t restore \(record.name): \(error.localizedDescription)")
            return nil
        }
    }

    /// Called when someone double-clicks a .attic placeholder in Finder.
    func restoreStub(at url: URL, open: Bool = true, reveal: Bool = true) async {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url), let stub = try? dec.decode(StubFile.self, from: data) else {
            library.show(toast: "That .attic file couldn’t be read")
            return
        }
        var record = records.first { $0.key == stub.key && $0.bucket == stub.bucket }
            ?? OffloadRecord(originalPath: stub.originalPath, bucket: stub.bucket, key: stub.key, size: stub.size,
                             modified: Date(), offloadedAt: stub.offloadedAt, stubPath: url.path)
        // The placeholder may have been moved: restore next to it, under the original name.
        record.originalPath = url.deletingPathExtension().path
        record.stubPath = url.path
        await restore(record, open: open, reveal: reveal)
        library.remove(urls: [url])
    }

    // MARK: iCloud Drive

    static var iCloudDriveRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    }
    static var iCloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil || FileManager.default.fileExists(atPath: iCloudDriveRoot.path)
    }
    var iCloudPendingCount: Int { records.filter { $0.isICloud && $0.pendingEvict == true }.count }
    var iCloudStatus: String?
    private var evictTimer: Timer?

    /// Removes the local copy of files iCloud already has. They stay in place and download again when opened.
    @discardableResult
    func removeDownloads(_ items: [FileItem]) -> (count: Int, bytes: Int64) {
        var done = Set<URL>()
        var bytes: Int64 = 0
        var failed: [String] = []
        for it in items where it.isICloudDownloaded {
            do {
                try FileManager.default.evictUbiquitousItem(at: it.url)
                done.insert(it.url)
                bytes += it.spaceOnDisk
            } catch { failed.append(it.name) }
        }
        library.remove(urls: done)
        library.show(toast: failed.isEmpty
                     ? "Removed \(Fmt.bytes(bytes)) of downloads. The files stay in iCloud and download again when you open them."
                     : "Removed \(done.count). Not uploaded yet or busy: \(failed.prefix(3).joined(separator: ", "))")
        return (done.count, bytes)
    }

    /// Offload to iCloud Drive: files already in iCloud get their download removed; other files move into
    /// iCloud Drive ▸ Attic with a link left behind, and the local copy goes once iCloud has uploaded it.
    func offloadToICloud(_ items: [FileItem]) async {
        let files = items.filter { !$0.isCloudOnly && !$0.url.isAtticStub && $0.category != .apps }
        var progress = OffloadProgress(total: files.count, done: 0, bytesTotal: files.reduce(0) { $0 + $1.size }, bytesDone: 0, current: "")
        offloadProgress = progress
        var moved = Set<URL>()
        let fm = FileManager.default
        for item in files {
            progress.current = item.name
            offloadProgress = progress
            do {
                if item.isICloudDownloaded {
                    if item.isICloudUploaded {
                        try fm.evictUbiquitousItem(at: item.url)
                        progress.freed += item.spaceOnDisk
                        moved.insert(item.url)
                    } else {
                        records.insert(OffloadRecord(originalPath: item.path, bucket: "iCloud Drive", key: item.path, size: item.size,
                                                     modified: item.modified, offloadedAt: Date(), stubPath: nil,
                                                     destination: "icloud-inplace", pendingEvict: true), at: 0)
                    }
                } else {
                    let rel = CloudStore.key(for: item.url)
                    let dest = AppPaths.uniqueURL(for: CloudStore.iCloudDriveRoot.appendingPathComponent("Attic").appendingPathComponent(rel))
                    try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.setUbiquitous(true, itemAt: item.url, destinationURL: dest)
                    try? fm.createSymbolicLink(at: item.url, withDestinationURL: dest)
                    records.removeAll { $0.originalPath == item.path && $0.isICloud }
                    records.insert(OffloadRecord(originalPath: item.path, bucket: "iCloud Drive", key: dest.path, size: item.size,
                                                 modified: item.modified, offloadedAt: Date(), stubPath: item.path,
                                                 destination: "icloud", pendingEvict: true), at: 0)
                    moved.insert(item.url)
                }
            } catch {
                progress.failures.append("\(item.name): \(error.localizedDescription)")
            }
            progress.done += 1
            progress.bytesDone += item.size
            offloadProgress = progress
        }
        saveManifest()
        progress.finished = true
        progress.current = ""
        offloadProgress = progress
        library.remove(urls: moved)
        startICloudWatcher()
        checkICloudUploads()
    }

    func startICloudWatcher() {
        guard evictTimer == nil, iCloudPendingCount > 0 else { return }
        evictTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkICloudUploads() }
        }
    }

    /// Evicts iCloud files whose upload has finished.
    func checkICloudUploads() {
        var changed = false
        var waiting = 0
        var lastError: String?
        for i in records.indices where records[i].isICloud && records[i].pendingEvict == true {
            let url = URL(fileURLWithPath: records[i].key)
            let keys: Set<URLResourceKey> = [.ubiquitousItemIsUploadedKey, .ubiquitousItemUploadingErrorKey, .ubiquitousItemDownloadingStatusKey]
            guard let rv = try? url.resourceValues(forKeys: keys) else { continue }
            if rv.ubiquitousItemDownloadingStatus == .notDownloaded {
                records[i].pendingEvict = false; changed = true; continue
            }
            if rv.ubiquitousItemIsUploaded == true, (try? FileManager.default.evictUbiquitousItem(at: url)) != nil {
                records[i].pendingEvict = false
                changed = true
            } else {
                waiting += 1
                if let err = rv.ubiquitousItemUploadingError { lastError = err.localizedDescription }
            }
        }
        iCloudStatus = waiting == 0 ? nil : "Waiting for iCloud to upload \(Fmt.plural(waiting, "file"))" + (lastError.map { ": \($0)" } ?? "…")
        if changed { saveManifest(); library.refreshDisk() }
        if waiting == 0 { evictTimer?.invalidate(); evictTimer = nil }
    }

    /// Brings an iCloud-offloaded file back: downloads it and, if Attic moved it into iCloud Drive, moves it home.
    func restoreICloud(_ record: OffloadRecord, open: Bool) async {
        let fm = FileManager.default
        let icloudURL = URL(fileURLWithPath: record.key)
        do {
            try? fm.startDownloadingUbiquitousItem(at: icloudURL)
            if record.destination == "icloud" {
                library.show(toast: "Downloading \(record.name) from iCloud…")
                for _ in 0..<720 { // up to an hour
                    let st = (try? icloudURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?.ubiquitousItemDownloadingStatus
                    if st == .current || st == .downloaded { break }
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                }
                let original = URL(fileURLWithPath: record.originalPath)
                if (try? original.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true { try fm.removeItem(at: original) }
                let dest = AppPaths.uniqueURL(for: original)
                try fm.setUbiquitous(false, itemAt: icloudURL, destinationURL: dest)
                if open { NSWorkspace.shared.open(dest) } else { NSWorkspace.shared.activateFileViewerSelecting([dest]) }
            } else if open {
                NSWorkspace.shared.open(icloudURL)
            }
            records.removeAll { $0.id == record.id }
            saveManifest()
            library.show(toast: "\(record.name) is back on this Mac")
            library.refreshDisk()
        } catch {
            library.show(toast: "Couldn’t restore \(record.name): \(error.localizedDescription)")
        }
    }

    // MARK: Manifest

    private func loadManifest() {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: manifestURL), let list = try? dec.decode([OffloadRecord].self, from: data) else { return }
        records = list
    }

    private func saveManifest() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = .prettyPrinted
        if let data = try? enc.encode(records) { try? data.write(to: manifestURL, options: .atomic) }
    }
}
