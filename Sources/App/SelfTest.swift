import Foundation
import AppKit
import CryptoKit
import ImageIO

/// `Attic.app/Contents/MacOS/Attic --selftest [--r2]` runs the non-UI engine against real data and prints results.
enum SelfTest {
    static func runAndExit() -> Never {
        // Keep the main run loop alive so @MainActor code (CloudStore, offload/restore) can run in the test.
        Task { @MainActor in
            var failures = await run()
            if CommandLine.arguments.contains("--offload") { failures += await offloadTest() }
            if CommandLine.arguments.contains("--icloud") { failures += await iCloudTest() }
            if let i = CommandLine.arguments.firstIndex(of: "--deepclean"), i + 1 < CommandLine.arguments.count {
                // Writes what Deep Clean finds under a folder as JSON, for review before anything is moved.
                let root = URL(fileURLWithPath: CommandLine.arguments[i + 1])
                let out = i + 2 < CommandLine.arguments.count ? URL(fileURLWithPath: CommandLine.arguments[i + 2]) : nil
                let found = await Task.detached { DeepCleanScanner.scan(projectRoots: [root], progress: { _ in }, isCancelled: { false }) }.value
                let rows: [[String: Any]] = found.map { ["path": $0.url.path, "title": $0.title, "detail": $0.detail, "group": $0.group.rawValue,
                                                          "bytes": $0.bytes, "recommended": $0.recommended, "inUse": $0.inUse,
                                                          "lastUsedDaysAgo": $0.lastUsed.map { Int(-$0.timeIntervalSinceNow / 86_400) } ?? -1] }
                let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
                if let out, let data { try? data.write(to: out) }
                print("deep clean: \(found.count) items, \(Fmt.bytes(found.reduce(0) { $0 + $1.bytes }))")
            }
            if CommandLine.arguments.contains("--fdacheck") {
                let home = FileManager.default.homeDirectoryForCurrentUser
                print("Full Disk Access: \(StorageBreakdownModel.checkFullDiskAccess())")
                for rel in ["Library/Safari", "Library/Mail", "Library/Messages", "Library/Group Containers/group.net.whatsapp.WhatsApp.shared", "Library/Containers/com.apple.mail"] {
                    do {
                        let n = try FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent(rel).path).count
                        print("read \(rel): ok (\(n) items)")
                    } catch { print("read \(rel): \((error as NSError).code) \(error.localizedDescription)") }
                }
            }
            if CommandLine.arguments.contains("--storage") {
                print("— Storage breakdown (this Mac)")
                let disk = DiskStats.current()
                let buckets = await Task.detached { StorageBreakdownModel.compute(filesBytes: 0, diskUsed: disk.used, progress: { _ in }) }.value
                for b in buckets { print(String(format: "  %8.1f GB  %@", Double(b.bytes) / 1e9, b.title)) }
                print("    disk used \(Fmt.bytes(disk.used)) · files bucket skipped in this test")
                let clones = await Task.detached { DeepCleanScanner.codeSignClones(progress: { _ in }) }.value
                for c in clones { print("  leftover copies: \(c.title) → \(Fmt.bytes(c.bytes)) real (recommended: \(c.recommended))") }
            }
            if let i = CommandLine.arguments.firstIndex(of: "--icloudtest"), i + 2 < CommandLine.arguments.count {
                // arg1: a downloaded iCloud file to evict; arg2: a local file to move into iCloud Drive
                let evictURL = URL(fileURLWithPath: CommandLine.arguments[i + 1])
                do { try FileManager.default.evictUbiquitousItem(at: evictURL); print("evict OK") }
                catch { let e = error as NSError; print("evict FAILED \(e.domain) \(e.code) \(e.localizedDescription)") }
                let local = URL(fileURLWithPath: CommandLine.arguments[i + 2])
                let docs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Attic", isDirectory: true)
                do {
                    try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
                    let dest = docs.appendingPathComponent(local.lastPathComponent)
                    try FileManager.default.setUbiquitous(true, itemAt: local, destinationURL: dest)
                    print("setUbiquitous OK -> \(dest.path)")
                    try FileManager.default.createSymbolicLink(at: local, withDestinationURL: dest)
                    print("symlink OK")
                } catch { let e = error as NSError; print("move to iCloud FAILED \(e.domain) \(e.code) \(e.localizedDescription)") }
            }
            if let i = CommandLine.arguments.firstIndex(of: "--trashtest"), i + 1 < CommandLine.arguments.count {
                let url = URL(fileURLWithPath: CommandLine.arguments[i + 1])
                do {
                    var out: NSURL?
                    try FileManager.default.trashItem(at: url, resultingItemURL: &out)
                    print("trashItem OK -> \(out?.path ?? "?")")
                } catch {
                    let e = error as NSError
                    print("trashItem FAILED \(e.domain) \(e.code) \(e.localizedDescription) \((e.userInfo[NSUnderlyingErrorKey] as? NSError).map { "\($0.domain) \($0.code)" } ?? "")")
                    do {
                        _ = try await NSWorkspace.shared.recycle([url])
                        print("recycle OK")
                    } catch {
                        let e = error as NSError
                        print("recycle FAILED \(e.domain) \(e.code) \(e.localizedDescription)")
                        var coordErr: NSError?
                        var inner: Error?
                        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMoving, error: &coordErr) { u in
                            do { try FileManager.default.trashItem(at: u, resultingItemURL: nil) } catch { inner = error }
                        }
                        if coordErr == nil && inner == nil { print("coordinated trash OK") }
                        else {
                            print("coordinated trash FAILED \((inner as NSError?)?.code ?? coordErr?.code ?? 0)")
                            var delErr: NSError?
                            var delInner: Error?
                            NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &delErr) { u in
                                do { try FileManager.default.removeItem(at: u) } catch { delInner = error }
                            }
                            print(delErr == nil && delInner == nil ? "coordinated delete OK" : "coordinated delete FAILED \((delInner as NSError?)?.code ?? delErr?.code ?? 0) \((delInner as NSError?)?.localizedDescription ?? "")")
                        }
                    }
                }
            }
            print(failures == 0 ? "SELFTEST PASS" : "SELFTEST FAIL (\(failures))")
            exit(failures == 0 ? 0 : 1)
        }
        while true { _ = RunLoop.main.run(mode: .default, before: .distantFuture) }
    }

    static func check(_ ok: Bool, _ what: String, _ failures: inout Int) {
        print((ok ? "  ✓ " : "  ✗ ") + what)
        if !ok { failures += 1 }
    }

    static func run() async -> Int {
        var f = 0
        let args = CommandLine.arguments

        print("— Query parser")
        let now = Date()
        let q1 = QueryParser.parse("pdfs from last week over 5 mb", now: now)
        print("    " + q1.chips.map(\.label).joined(separator: " | "))
        check(q1.chips.contains(.exts("PDF", ["pdf"])), "pdf type", &f)
        check(q1.chips.contains(.minSize(5_000_000)), "over 5 MB", &f)
        check(q1.chips.contains { $0.kindKey == "date" }, "last week date", &f)
        let q2 = QueryParser.parse("zips bigger than 1gb older than 6 months", now: now)
        print("    " + q2.chips.map(\.label).joined(separator: " | "))
        check(q2.chips.contains(.minSize(1_000_000_000)) && q2.chips.contains { if case .olderThan = $0 { return true }; return false }, "zip size+age", &f)
        let q3 = QueryParser.parse("screenshots with wifi password", now: now)
        print("    " + q3.chips.map(\.label).joined(separator: " | "))
        check(q3.chips.contains(.screenshots) && q3.chips.contains(.text("wifi password")), "screenshot text", &f)
        let q4 = QueryParser.parse("pdfs from gmail", now: now)
        check(q4.chips.contains(.source("Gmail")), "gmail source", &f)
        let q5 = QueryParser.parse("videos from my iphone in august", now: now)
        print("    " + q5.chips.map(\.label).joined(separator: " | "))
        check(q5.chips.contains(.iphone) && q5.chips.contains(.category(.videos)), "iphone videos august", &f)

        print("— Apple Intelligence (on-device)")
        print("    " + LocalAI.statusText)
        if LocalAI.isAvailable {
            for q in ["the invoice my accountant emailed me", "that huge video of the drone flight from last year", "screenshot with the tracking number of my order"] {
                let rules = QueryParser.parse(q)
                let t0 = Date()
                let ai = await LocalAI.understand(q, rules: rules)
                print("    “\(q)” → \(ai?.chips.map(\.label).joined(separator: " | ") ?? "nil")  (\(String(format: "%.1f", Date().timeIntervalSince(t0)))s)")
                check(ai != nil && !(ai!.chips.isEmpty), "model answered", &f)
            }
        }

        print("— Scanner (Downloads)")
        let t0 = Date()
        let dl = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let items = Scanner.scan(roots: [dl], progress: { _ in }, isCancelled: { false })
        let total = items.reduce(Int64(0)) { $0 + $1.spaceOnDisk }
        print("    \(items.count) files, \(Fmt.bytes(total)) in \(String(format: "%.1f", Date().timeIntervalSince(t0)))s")
        let srcs = LibraryStore.buildIndex(items).sources.prefix(6).map { "\($0.name) \($0.count)" }
        print("    sources: " + srcs.joined(separator: ", "))
        check(!items.isEmpty || ProcessInfo.processInfo.environment["CI"] != nil, "found files in Downloads", &f)
        let cards = CleanupEngine.cards(for: items)
        print("    cleanup: " + cards.map { "\($0.title) \(Fmt.bytes($0.bytes))" }.joined(separator: ", "))
        let matches = items.filter { q1.matches($0, ocr: nil) }.count
        print("    “pdfs from last week over 5 mb” → \(matches) matches")

        print("— Folders (Finder actions in a temporary folder)")
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("attic-folders-\(UUID().uuidString.prefix(6))", isDirectory: true)
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
            try Data("hello".utf8).write(to: tmp.appendingPathComponent("note.txt"))
            try Data(repeating: 7, count: 4096).write(to: tmp.appendingPathComponent(".hidden"))
            let made = try FileOps.newFolder(in: tmp)
            check(made.lastPathComponent == "untitled folder", "new folder", &f)
            let renamed = try FileOps.rename(made, to: "Invoices")
            check(renamed.lastPathComponent == "Invoices" && fm.fileExists(atPath: renamed.path), "rename", &f)
            let moved = FileOps.transfer([tmp.appendingPathComponent("note.txt")], into: renamed, copy: false)
            check(moved.moved.count == 1 && fm.fileExists(atPath: renamed.appendingPathComponent("note.txt").path), "move into folder", &f)
            let intoItself = FileOps.transfer([renamed], into: renamed, copy: false)
            check(intoItself.moved.isEmpty && intoItself.failed.count == 1, "refuses moving a folder into itself", &f)
            let visible = FolderReader.read(tmp, showHidden: false)
            let all = FolderReader.read(tmp, showHidden: true)
            check(visible.folders.map(\.name) == ["Invoices"] && visible.files.isEmpty && all.files.count == 1, "read folder (hidden files)", &f)
            let size = FolderSizeCache.measure(tmp) { false } ?? 0
            check(size >= 4096, "folder size \(Fmt.bytes(size))", &f)
            let crumbs = Locations.crumbs(for: NSHomeDirectory() + "/Documents/Invoices/2026")
            print("    " + crumbs.map(\.title).joined(separator: " ▸ "))
            check(crumbs.count == 4 && crumbs.last?.title == "2026", "path crumbs", &f)
            check(FileItem.isAppLibrary(path: "/Users/x/Pictures/Photos Library.photoslibrary") && !FileItem.isAppLibrary(path: "/x/a.key"), "app libraries are protected", &f)
            try? fm.removeItem(at: tmp)
        } catch {
            check(false, "folder actions: \(error.localizedDescription)", &f)
        }

        print("— Screenshot history")
        let shot = NSImage(size: NSSize(width: 40, height: 30))
        shot.lockFocus(); NSColor.orange.setFill(); NSRect(x: 0, y: 0, width: 40, height: 30).fill(); shot.unlockFocus()
        func png(comment: String?) -> Data {
            let cg = shot.cgImage(forProposedRect: nil, context: nil, hints: nil)!
            let data = NSMutableData()
            let dest = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
            let props: [CFString: Any] = comment.map { [kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: $0]] } ?? [:]
            CGImageDestinationAddImage(dest, cg, props as CFDictionary)
            CGImageDestinationFinalize(dest)
            return data as Data
        }
        check(ScreenshotKeeper.isScreenshot(png(comment: "Screenshot")), "recognizes a macOS screenshot", &f)
        check(!ScreenshotKeeper.isScreenshot(png(comment: nil)), "ignores other copied images", &f)
        print("    macOS saves screenshots to: \(ScreenshotKeeper.macOSTarget)")

        print("— Memory & swap")
        let snap = MemoryMonitor.readSnapshot()
        print("    swap \(Fmt.bytes(Int64(snap.swapUsed))) / \(Fmt.bytes(Int64(snap.swapTotal))), files on disk \(snap.swapFileCount) = \(Fmt.bytes(Int64(snap.swapFilesOnDisk))), memory \(Fmt.bytes(Int64(snap.used))) / \(Fmt.bytes(Int64(snap.physical))), pressure \(snap.pressureLabel)")
        check(snap.physical > 0 && snap.used > 0, "memory stats", &f)
        let apps = MemoryMonitor.readApps(running: [])
        print("    top: " + apps.prefix(6).map { "\($0.name) \(Fmt.bytes(Int64($0.footprint)))" }.joined(separator: ", "))
        check(!apps.isEmpty, "per-app memory", &f)

        if args.contains("--r2") {
            f += await r2Test()
        }
        return f
    }

    static func r2Test() async -> Int {
        var f = 0
        print("— Cloudflare R2")
        guard let v = VerselyImport.credentials() else {
            check(false, "Versely .env has R2 keys", &f)
            return f
        }
        let bucket = VerselyImport.suggestedBucket
        let creds = R2Credentials(accountId: v.accountId, accessKeyId: v.accessKeyId, secretAccessKey: v.secret, bucket: bucket, source: "versely")
        let c = R2Client(creds)
        do {
            let buckets = try await c.listBuckets()
            check(!buckets.isEmpty, "list buckets (\(buckets.count))", &f)
            if !buckets.contains(bucket) {
                try await c.createBucket(bucket)
                print("    created bucket \(bucket)")
            }
            let exists = await c.bucketExists(bucket)
            check(exists, "bucket \(bucket) exists", &f)
            if CommandLine.arguments.contains("--connect") {
                try Keychain.save(try JSONEncoder().encode(creds))
                let back = Keychain.load().flatMap { try? JSONDecoder().decode(R2Credentials.self, from: $0) }
                check(back == creds, "saved to Keychain, app is now connected to \(bucket)", &f)
            }

            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("attic-selftest-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }

            // small file with a tricky name
            let small = dir.appendingPathComponent("héllo wörld (1)+&.txt")
            try Data("Attic self test \(Date())".utf8).write(to: small)
            let smallKey = "_selftest/" + small.lastPathComponent
            try await c.upload(file: small, key: smallKey, metadata: ["attic-original-path": R2Client.metaEncode(small.path)], progress: { _, _ in })
            let h = try await c.head(smallKey)
            let smallCount = try Data(contentsOf: small).count
            check(h?.size == Int64(smallCount), "small upload + head", &f)
            check(R2Client.metaDecode(h?.metadata["attic-original-path"] ?? "") == small.path, "metadata round trip", &f)

            // multipart (70 MB)
            let big = dir.appendingPathComponent("big.bin")
            var bytes = Data(count: 70 * 1024 * 1024)
            bytes.withUnsafeMutableBytes { p in
                let words = p.bindMemory(to: UInt64.self)
                var x: UInt64 = 0x9E3779B97F4A7C15
                for i in 0..<words.count { x ^= x << 13; x ^= x >> 7; x ^= x << 17; words[i] = x }
            }
            try bytes.write(to: big)
            let bigHash = SHA256.hash(data: bytes).description
            let bigKey = "_selftest/big.bin"
            let last = Counter()
            let t0 = Date()
            try await c.upload(file: big, key: bigKey, progress: { d, _ in _ = last.swap(d) })
            let secs = Date().timeIntervalSince(t0)
            print(String(format: "    multipart 70 MB in %.1fs (%.1f MB/s)", secs, 70 / secs))
            check(last.value == Int64(bytes.count), "multipart progress reached 100%", &f)
            let bh = try await c.head(bigKey)
            check(bh?.size == Int64(bytes.count), "multipart size verified", &f)

            // list
            let listing = try await c.list(prefix: "_selftest/")
            check(Set(listing.objects.map(\.key)) == [smallKey, bigKey], "list prefix", &f)
            let top = try await c.list(prefix: "")
            check(top.folders.contains("_selftest/"), "folders via delimiter", &f)

            // download + compare
            let back = dir.appendingPathComponent("back.bin")
            try await c.download(key: bigKey, to: back, progress: { _, _ in })
            let backData = try Data(contentsOf: back)
            check(SHA256.hash(data: backData).description == bigHash, "download matches byte-for-byte", &f)

            // presigned link
            if let url = c.presignedURL(key: smallKey) {
                let (data, resp) = try await URLSession.shared.data(from: url)
                let original = try Data(contentsOf: small)
                check((resp as? HTTPURLResponse)?.statusCode == 200 && data == original, "presigned link works", &f)
            } else { check(false, "presigned link", &f) }

            // batch delete
            try await c.delete(keys: [smallKey, bigKey])
            let after = try await c.list(prefix: "_selftest/")
            check(after.objects.isEmpty, "batch delete", &f)
            let gone = try await c.head(smallKey)
            check(gone == nil, "head 404 → nil", &f)
        } catch {
            check(false, "R2 error: \(error.localizedDescription)", &f)
        }
        return f
    }

    /// End to end: offload a real file with a placeholder, then double-click-restore it from the placeholder.
    @MainActor
    static func offloadTest() async -> Int {
        var f = 0
        print("— Offload & restore (CloudStore)")
        let cloud = AppState.shared.cloud
        guard cloud.isConnected, let home = cloud.creds?.bucket else {
            check(false, "app connected to R2 (run with --connect)", &f)
            return f
        }
        let dir = AppPaths.caches.appendingPathComponent("selftest", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("Holiday clip (test).mov")
        var data = Data(count: 9 * 1024 * 1024)
        data.withUnsafeMutableBytes { p in for i in stride(from: 0, to: p.count, by: 4096) { p[i] = UInt8(truncatingIfNeeded: i / 4096) } }
        try? data.write(to: file)
        let hash = SHA256.hash(data: data).description
        guard let rv = try? file.resourceValues(forKeys: Scanner.keySet), let item = Scanner.makeItem(url: file, rv: rv, isPackage: false) else {
            check(false, "make test file", &f)
            return f
        }
        await cloud.offload([item], after: .delete, leaveStubs: true)
        let stub = file.appendingPathExtension("attic")
        check(!FileManager.default.fileExists(atPath: file.path), "local copy removed after verified upload", &f)
        check(FileManager.default.fileExists(atPath: stub.path), "placeholder left: \(stub.lastPathComponent)", &f)
        let stubSize = (try? stub.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? -1
        print("    placeholder is \(stubSize) bytes, original was \(Fmt.bytes(Int64(data.count)))")
        let key = CloudStore.key(for: file)
        check(cloud.records.contains { $0.key == key }, "listed under Offloaded (key \(key))", &f)
        check(cloud.offloadProgress?.failures.isEmpty == true, "no offload errors", &f)

        await cloud.restoreStub(at: stub, open: false, reveal: false)
        let restored = (try? Data(contentsOf: file)).map { SHA256.hash(data: $0).description }
        check(restored == hash, "placeholder double-click restored the identical file", &f)
        check(!FileManager.default.fileExists(atPath: stub.path), "placeholder removed after restore", &f)
        check(!cloud.records.contains { $0.key == key }, "removed from Offloaded list", &f)

        try? await cloud.client?.delete(key: key, bucket: home)
        try? FileManager.default.removeItem(at: dir)
        return f
    }

    @MainActor
    static func iCloudTest() async -> Int {
        var f = 0
        print("— Offload to iCloud Drive & restore")
        let cloud = AppState.shared.cloud
        let dir = AppPaths.caches.appendingPathComponent("icloud-selftest", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("Trip photos (test).zip")
        var data = Data(count: 3 * 1024 * 1024)
        data.withUnsafeMutableBytes { p in for i in stride(from: 0, to: p.count, by: 512) { p[i] = UInt8(truncatingIfNeeded: i &* 31) } }
        try? data.write(to: file)
        let hash = SHA256.hash(data: data).description
        guard let rv = try? file.resourceValues(forKeys: Scanner.keySet), let item = Scanner.makeItem(url: file, rv: rv, isPackage: false) else {
            check(false, "make test file", &f); return f
        }
        await cloud.offloadToICloud([item])
        let isLink = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.type] as? FileAttributeType == .typeSymbolicLink
        check(isLink, "link left in the original folder", &f)
        guard let rec = cloud.records.first(where: { $0.originalPath == file.path && $0.isICloud }) else { check(false, "record", &f); return f }
        print("    now in \(Fmt.path(rec.key))")
        var evicted = false
        for _ in 0..<45 {
            cloud.checkICloudUploads()
            if cloud.records.first(where: { $0.id == rec.id })?.pendingEvict == false { evicted = true; break }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        check(evicted, "uploaded, then removed from this Mac", &f)
        let st = (try? URL(fileURLWithPath: rec.key).resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?.ubiquitousItemDownloadingStatus
        check(st == .notDownloaded, "iCloud copy is cloud-only (0 bytes here)", &f)
        let readable = (try? Data(contentsOf: file)).map { SHA256.hash(data: $0).description } == hash
        check(readable, "opening the link downloads the identical file", &f)
        if let r = cloud.records.first(where: { $0.id == rec.id }) { await cloud.restoreICloud(r, open: false) }
        let back = (try? Data(contentsOf: file)).map { SHA256.hash(data: $0).description }
        let stillLink = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.type] as? FileAttributeType == .typeSymbolicLink
        check(back == hash && !stillLink, "restored as a real file, identical", &f)
        check(!FileManager.default.fileExists(atPath: rec.key), "moved back out of iCloud Drive", &f)
        try? FileManager.default.removeItem(at: dir)
        return f
    }
}
