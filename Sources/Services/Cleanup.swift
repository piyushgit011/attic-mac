import Foundation
import SwiftUI
import CryptoKit

// MARK: - Clean Up cards

struct CleanupCard: Identifiable, Hashable {
    enum Kind: String, CaseIterable {
        case forgottenDownloads, oldInstallers, oldScreenshots, bigOldVideos, largeFiles, unusedApps, alreadyInICloud
    }
    let kind: Kind
    let items: [FileItem]
    var id: String { kind.rawValue }
    var bytes: Int64 { items.reduce(0) { $0 + $1.spaceOnDisk } }

    var title: String {
        switch kind {
        case .forgottenDownloads: return "Forgotten downloads"
        case .oldInstallers: return "Old installers"
        case .oldScreenshots: return "Old screenshots"
        case .bigOldVideos: return "Big old videos"
        case .largeFiles: return "Large files"
        case .unusedApps: return "Unused apps"
        case .alreadyInICloud: return "Already in iCloud"
        }
    }

    var detail: String {
        switch kind {
        case .forgottenDownloads: return "In Downloads for over a month and not opened since"
        case .oldInstallers: return ".dmg and .pkg files older than a week"
        case .oldScreenshots: return "Screenshots older than 30 days"
        case .bigOldVideos: return "Videos over 200 MB not touched in 6 months"
        case .largeFiles: return "Anything over 500 MB, good candidates for the cloud"
        case .unusedApps: return "Apps you haven’t opened in 90 days"
        case .alreadyInICloud: return "Safe in iCloud Drive. Remove the copy on this Mac; it downloads again when you open it"
        }
    }

    var symbol: String {
        switch kind {
        case .forgottenDownloads: return "arrow.down.circle"
        case .oldInstallers: return "shippingbox"
        case .oldScreenshots: return "camera.viewfinder"
        case .bigOldVideos: return "film"
        case .largeFiles: return "scalemass"
        case .unusedApps: return "app.dashed"
        case .alreadyInICloud: return "icloud.and.arrow.down"
        }
    }

    var tint: Color {
        switch kind {
        case .forgottenDownloads: return FileCategory.documents.pastel
        case .oldInstallers: return FileCategory.archives.pastel
        case .oldScreenshots: return FileCategory.images.pastel
        case .bigOldVideos: return FileCategory.videos.pastel
        case .largeFiles: return FileCategory.music.pastel
        case .unusedApps: return FileCategory.apps.pastel
        case .alreadyInICloud: return Color(red: 0.2, green: 0.7, blue: 0.95)
        }
    }

    /// Whether moving to the cloud makes more sense than throwing away.
    var prefersOffload: Bool { kind == .bigOldVideos || kind == .largeFiles }
}

enum CleanupEngine {
    static func cards(for items: [FileItem], now: Date = Date()) -> [CleanupCard] {
        let day: TimeInterval = 86_400
        let files = items.filter { !$0.isCloudOnly && !$0.url.isAtticStub }
        var cards: [CleanupCard] = []

        let forgotten = files.filter {
            $0.isInDownloads && $0.arrivalDate < now - 30 * day && $0.lastUsed < now - 30 * day && $0.category != .apps
        }
        let installers = files.filter { $0.isInstaller && $0.arrivalDate < now - 7 * day }
        let shots = files.filter { $0.isScreenshot && $0.arrivalDate < now - 30 * day }
        let videos = files.filter { $0.category == .videos && $0.spaceOnDisk > 200_000_000 && $0.modified < now - 180 * day && $0.lastUsed < now - 90 * day }
        let large = files.filter { $0.category != .apps && !$0.isAppLibrary && $0.spaceOnDisk > 500_000_000 }
        let apps = files.filter {
            $0.category == .apps && !($0.bundleID ?? "").hasPrefix("com.apple.")
                && ($0.accessed ?? $0.added ?? $0.created) < now - 90 * day
        }

        let inICloud = files.filter { $0.isICloudDownloaded && $0.isICloudUploaded && $0.spaceOnDisk > 5_000_000 && !$0.isPackage }
        for (kind, list) in [(CleanupCard.Kind.forgottenDownloads, forgotten), (.oldInstallers, installers), (.oldScreenshots, shots),
                             (.bigOldVideos, videos), (.largeFiles, large), (.unusedApps, apps), (.alreadyInICloud, inICloud)] where !list.isEmpty {
            cards.append(CleanupCard(kind: kind, items: list.sorted { $0.spaceOnDisk > $1.spaceOnDisk }))
        }
        return cards.sorted { $0.bytes > $1.bytes }
    }
}

// MARK: - Duplicates

struct DuplicateGroup: Identifiable, Hashable {
    let id = UUID()
    let size: Int64
    var files: [FileItem]
    var keep: URL
    /// Files that are APFS clones of each other already share their blocks, so trashing them frees nothing.
    var cloneOffsets: [URL: Int64] = [:]

    var reclaimable: Int64 {
        let keepOffset = cloneOffsets[keep]
        var seen = Set<Int64>()
        if let keepOffset { seen.insert(keepOffset) }
        var total: Int64 = 0
        for f in files where f.url != keep {
            if let off = cloneOffsets[f.url] {
                if seen.contains(off) { continue }
                seen.insert(off)
            }
            total += f.spaceOnDisk
        }
        return total
    }
}

enum DuplicateFinder {
    static func find(in items: [FileItem], minSize: Int64 = 100_000,
                     progress: @escaping (Double) -> Void, isCancelled: @escaping () -> Bool) -> [DuplicateGroup] {
        let candidates = items.filter { !$0.isPackage && !$0.isCloudOnly && $0.size >= minSize && $0.category != .apps && !$0.url.isAtticStub }
        let bySize = Dictionary(grouping: candidates, by: \.size).filter { $0.value.count > 1 }
        let total = max(1, bySize.values.reduce(0) { $0 + $1.count })
        var done = 0
        var groups: [DuplicateGroup] = []

        for (size, sameSize) in bySize {
            if isCancelled() { break }
            // Cheap pass: first and last 64 KB.
            let byQuick = Dictionary(grouping: sameSize) { quickHash($0.url, size: size) ?? UUID().uuidString }
            for (_, quick) in byQuick where quick.count > 1 {
                let byFull = Dictionary(grouping: quick) { fullHash($0.url) ?? UUID().uuidString }
                for (_, same) in byFull where same.count > 1 {
                    var offsets: [URL: Int64] = [:]
                    for f in same { if let off = physicalOffset(f.path) { offsets[f.url] = off } }
                    let keep = pickKeeper(same)
                    groups.append(DuplicateGroup(size: size, files: same, keep: keep.url, cloneOffsets: offsets))
                }
            }
            done += sameSize.count
            progress(Double(done) / Double(total))
        }
        return groups.sorted { $0.reclaimable > $1.reclaimable }
    }

    static func pickKeeper(_ files: [FileItem]) -> FileItem {
        files.sorted { a, b in
            if a.isInDownloads != b.isInDownloads { return !a.isInDownloads }
            if a.created != b.created { return a.created < b.created }
            return a.path.count < b.path.count
        }[0]
    }

    static func quickHash(_ url: URL, size: Int64) -> String? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        var hasher = SHA256()
        let chunk = 64 * 1024
        if let head = try? fh.read(upToCount: chunk) { hasher.update(data: head) }
        if size > Int64(chunk * 2) {
            try? fh.seek(toOffset: UInt64(size) - UInt64(chunk))
            if let tail = try? fh.read(upToCount: chunk) { hasher.update(data: tail) }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func fullHash(_ url: URL) -> String? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        var hasher = SHA256()
        while true {
            let more: Bool = autoreleasepool {
                guard let data = try? fh.read(upToCount: 4 * 1024 * 1024), !data.isEmpty else { return false }
                hasher.update(data: data)
                return true
            }
            if !more { break }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Physical location of the file's first block. Two files with the same value are APFS clones.
    static func physicalOffset(_ path: String) -> Int64? {
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var l2p = log2phys()
        l2p.l2p_contigbytes = 1
        l2p.l2p_devoffset = 0
        guard fcntl(fd, F_LOG2PHYS_EXT, &l2p) != -1 else { return nil }
        return l2p.l2p_devoffset
    }
}
