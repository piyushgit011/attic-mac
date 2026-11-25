import Foundation
import CoreServices

/// Walks the user's folders and builds the in-memory file index. Runs off the main thread.
enum Scanner {
    static let keys: [URLResourceKey] = [
        .isRegularFileKey, .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey,
        .fileSizeKey, .totalFileAllocatedSizeKey,
        .creationDateKey, .contentModificationDateKey, .addedToDirectoryDateKey, .contentAccessDateKey,
        .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsUploadedKey,
    ]
    static let keySet = Set(keys)

    /// Folder names whose contents are build output or dependencies, not files a person manages.
    static let skipNames: Set<String> = [
        "node_modules", "Pods", "DerivedData", ".build", "__pycache__", "venv", ".venv",
        "bower_components", ".gradle", "Library", ".next", ".turbo", ".expo", "build", "dist",
        "target", ".dart_tool", "vendor", "site-packages",
    ]

    static func scan(roots: [URL], progress: @escaping (Int) -> Void, isCancelled: @escaping () -> Bool) -> [FileItem] {
        var out: [FileItem] = []
        out.reserveCapacity(50_000)
        var seen = Set<String>()
        let fm = FileManager.default

        for root in roots {
            guard let en = fm.enumerator(at: root, includingPropertiesForKeys: keys,
                                         options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                         errorHandler: { _, _ in true }) else { continue }
            for case let url as URL in en {
                if isCancelled() { return out }
                guard let rv = try? url.resourceValues(forKeys: keySet) else { continue }
                if rv.isSymbolicLink == true { continue }
                let isPackage = rv.isPackage == true
                if rv.isDirectory == true && !isPackage {
                    if skipNames.contains(url.lastPathComponent) { en.skipDescendants() }
                    continue
                }
                guard rv.isRegularFile == true || isPackage else { continue }
                if !seen.insert(url.path).inserted { continue }
                if let item = makeItem(url: url, rv: rv, isPackage: isPackage) {
                    out.append(item)
                    if out.count % 1000 == 0 { progress(out.count) }
                }
            }
        }

        // Size packages (.photoslibrary, .fcpbundle, .key …) now that the fast pass is done.
        for i in out.indices where out[i].isPackage {
            if isCancelled() { break }
            let s = directorySize(out[i].url)
            out[i].size = s.logical
            out[i].allocatedSize = s.allocated
        }
        progress(out.count)
        return out
    }

    static func makeItem(url: URL, rv: URLResourceValues, isPackage: Bool) -> FileItem? {
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        let info = TypeInfo.lookup(ext)
        let path = url.path
        let froms = whereFroms(path)
        let isCloudOnly = rv.isUbiquitousItem == true && rv.ubiquitousItemDownloadingStatus == .notDownloaded
        let isShot = info.category == .images && (hasXattr(path, "com.apple.metadata:kMDItemIsScreenCapture")
            || name.hasPrefix("Screenshot ") || name.hasPrefix("Screen Shot ") || name.hasPrefix("CleanShot "))
        var item = FileItem(
            url: url,
            name: name,
            lowerName: name.lowercased(),
            ext: ext,
            size: Int64(rv.fileSize ?? 0),
            allocatedSize: Int64(rv.totalFileAllocatedSize ?? rv.fileSize ?? 0),
            created: rv.creationDate ?? rv.contentModificationDate ?? .distantPast,
            modified: rv.contentModificationDate ?? .distantPast,
            added: rv.addedToDirectoryDate,
            accessed: rv.contentAccessDate,
            category: info.category,
            kind: info.kind,
            whereFroms: froms,
            source: DownloadSource.source(from: froms),
            isScreenshot: isShot,
            isCloudOnly: isCloudOnly,
            isPackage: isPackage
        )
        if rv.isUbiquitousItem == true && !isCloudOnly {
            item.isICloudDownloaded = true
            item.isICloudUploaded = rv.ubiquitousItemIsUploaded == true
        }
        return item
    }

    // MARK: Apps

    static func scanApps() -> [FileItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var bundles: [URL] = []
        for dir in [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")] {
            guard let children = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for child in children {
                if child.pathExtension == "app" {
                    bundles.append(child)
                } else if (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                          let nested = try? fm.contentsOfDirectory(at: child, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                    bundles += nested.filter { $0.pathExtension == "app" }
                }
            }
        }
        var out: [FileItem] = []
        for url in bundles {
            guard let rv = try? url.resourceValues(forKeys: keySet) else { continue }
            let s = directorySize(url)
            let lastUsed = mdDate(url, kMDItemLastUsedDate)
            let item = FileItem(
                url: url,
                name: url.deletingPathExtension().lastPathComponent,
                lowerName: url.deletingPathExtension().lastPathComponent.lowercased(),
                ext: "app",
                size: s.logical,
                allocatedSize: s.allocated,
                created: rv.creationDate ?? .distantPast,
                modified: rv.contentModificationDate ?? .distantPast,
                added: rv.addedToDirectoryDate,
                accessed: lastUsed,
                category: .apps,
                kind: "Application",
                whereFroms: [],
                source: nil,
                isScreenshot: false,
                isCloudOnly: false,
                isPackage: true,
                bundleID: Bundle(url: url)?.bundleIdentifier
            )
            out.append(item)
        }
        return out
    }

    // MARK: Helpers

    static func directorySize(_ url: URL) -> (logical: Int64, allocated: Int64) {
        var logical: Int64 = 0
        var allocated: Int64 = 0
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey]
        guard let en = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else {
            return (0, 0)
        }
        for case let f as URL in en {
            guard let rv = try? f.resourceValues(forKeys: Set(keys)), rv.isRegularFile == true else { continue }
            logical += Int64(rv.fileSize ?? 0)
            allocated += Int64(rv.totalFileAllocatedSize ?? rv.fileSize ?? 0)
        }
        return (logical, allocated)
    }

    static func whereFroms(_ path: String) -> [String] {
        let name = "com.apple.metadata:kMDItemWhereFroms"
        let len = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
        guard len > 0, len < 1_000_000 else { return [] }
        var data = Data(count: len)
        let read = data.withUnsafeMutableBytes { getxattr(path, name, $0.baseAddress, len, 0, XATTR_NOFOLLOW) }
        guard read > 0 else { return [] }
        let list = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String]
        return list?.filter { !$0.isEmpty } ?? []
    }

    static func hasXattr(_ path: String, _ name: String) -> Bool {
        getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW) >= 0
    }

    static func mdDate(_ url: URL, _ attr: CFString) -> Date? {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, attr) as? Date
    }
}

struct DiskStats: Equatable {
    var total: Int64 = 0
    var available: Int64 = 0
    var used: Int64 { max(0, total - available) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    static func current() -> DiskStats {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let rv = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        let available = rv?.volumeAvailableCapacityForImportantUsage ?? Int64(rv?.volumeAvailableCapacity ?? 0)
        return DiskStats(total: Int64(rv?.volumeTotalCapacity ?? 0), available: available)
    }
}
