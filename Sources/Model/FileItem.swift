import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Categories

enum FileCategory: String, CaseIterable, Identifiable, Codable, Hashable {
    case images, videos, music, documents, archives, apps, other

    var id: String { rawValue }

    static let library: [FileCategory] = [.images, .videos, .music, .documents, .archives, .apps]

    var title: String {
        switch self {
        case .images: return "Images"
        case .videos: return "Videos"
        case .music: return "Music"
        case .documents: return "Documents"
        case .archives: return "Archives"
        case .apps: return "Apps"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .images: return "photo.on.rectangle.angled"
        case .videos: return "film.stack"
        case .music: return "music.note"
        case .documents: return "doc.text"
        case .archives: return "archivebox"
        case .apps: return "square.grid.2x2"
        case .other: return "doc"
        }
    }

    var tint: Color {
        switch self {
        case .images: return .pink
        case .videos: return .purple
        case .music: return .orange
        case .documents: return .blue
        case .archives: return .brown
        case .apps: return .teal
        case .other: return .gray
        }
    }
}

// MARK: - Type lookup (cached per extension, thread safe)

struct TypeInfo {
    let category: FileCategory
    let kind: String

    private static var cache: [String: TypeInfo] = [:]
    private static let lock = NSLock()

    static let installerExts: Set<String> = ["dmg", "pkg", "mpkg", "iso", "xip"]
    static let archiveExts: Set<String> = installerExts.union(["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "zst", "jar", "sit", "sitx", "cab"])
    static let docExts: Set<String> = ["pdf", "doc", "docx", "pages", "numbers", "key", "odt", "ods", "odp", "rtf", "txt", "md", "csv", "tsv", "xls", "xlsx", "ppt", "pptx", "epub", "mobi"]

    static func lookup(_ ext: String) -> TypeInfo {
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[ext] { return hit }
        var type: UTType? = ext.isEmpty ? nil : UTType(filenameExtension: ext)
        if type?.isDynamic == true { type = nil }
        let kind = type?.localizedDescription ?? (ext.isEmpty ? "Document" : "\(ext.uppercased()) file")
        let info = TypeInfo(category: classify(type, ext: ext), kind: kind)
        cache[ext] = info
        return info
    }

    private static func classify(_ t: UTType?, ext: String) -> FileCategory {
        if archiveExts.contains(ext) { return .archives }
        if docExts.contains(ext) { return .documents }
        guard let t else { return .other }
        if t.conforms(to: .applicationBundle) || t.conforms(to: .application) { return .apps }
        if t.conforms(to: .image) { return .images }
        if t.conforms(to: .movie) || t.conforms(to: .video) { return .videos }
        if t.conforms(to: .audio) { return .music }
        if t.conforms(to: .archive) || t.conforms(to: .diskImage) { return .archives }
        if t.conforms(to: .pdf) || t.conforms(to: .presentation) || t.conforms(to: .spreadsheet)
            || t.conforms(to: .rtf) || t.conforms(to: .epub) { return .documents }
        if t.conforms(to: .plainText) && !t.conforms(to: .sourceCode) { return .documents }
        return .other
    }
}

// MARK: - File item

struct FileItem: Identifiable, Hashable {
    let url: URL
    let name: String
    let lowerName: String
    let ext: String
    var size: Int64
    var allocatedSize: Int64
    let created: Date
    let modified: Date
    let added: Date?
    let accessed: Date?
    let category: FileCategory
    let kind: String
    let whereFroms: [String]
    let source: String?
    let isScreenshot: Bool
    let isCloudOnly: Bool
    /// In iCloud Drive (Desktop & Documents, or iCloud Drive itself) with a full copy downloaded here.
    var isICloudDownloaded: Bool = false
    /// iCloud already holds the latest version, so the local copy can be removed safely.
    var isICloudUploaded: Bool = false
    let isPackage: Bool
    var bundleID: String? = nil

    var id: URL { url }
    var path: String { url.path }
    var folderName: String { url.deletingLastPathComponent().lastPathComponent }
    var sourceSort: String { source ?? "" }
    /// The date a person would think of as "when I got this file".
    var arrivalDate: Date { added ?? created }
    /// Best guess at the last time this file was used.
    var lastUsed: Date { max(accessed ?? modified, modified) }
    var isInstaller: Bool { TypeInfo.installerExts.contains(ext) }
    var isInDownloads: Bool { path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path + "/") }
    /// Bytes this file actually occupies on this Mac. iCloud-only (dataless) files use none.
    var spaceOnDisk: Int64 { isCloudOnly ? 0 : (allocatedSize > 0 ? allocatedSize : size) }
    var sizeLabel: String { isCloudOnly ? "\(Fmt.bytes(size)) in iCloud" : Fmt.bytes(spaceOnDisk) }

    static func == (a: FileItem, b: FileItem) -> Bool { a.url == b.url }
    func hash(into h: inout Hasher) { h.combine(url) }
}

// MARK: - Where a download came from

enum DownloadSource {
    static let known: [(name: String, hosts: [String])] = [
        ("Gmail", ["mail.google.com", "mail-attachment.googleusercontent.com"]),
        ("Google Drive", ["drive.google.com", "drive.usercontent.google.com", "docs.google.com", "googleusercontent.com"]),
        ("ChatGPT", ["chatgpt.com", "chat.openai.com", "oaiusercontent.com", "openai.com"]),
        ("Claude", ["claude.ai", "anthropic.com", "claudeusercontent.com"]),
        ("Canva", ["canva.com"]),
        ("X", ["x.com", "twitter.com", "twimg.com"]),
        ("Slack", ["slack.com", "slack-edge.com", "slack-files.com"]),
        ("WhatsApp", ["whatsapp.com", "whatsapp.net"]),
        ("GitHub", ["github.com", "githubusercontent.com"]),
        ("Telegram", ["telegram.org", "t.me"]),
        ("Discord", ["discord.com", "discordapp.com", "discordapp.net"]),
        ("Notion", ["notion.so", "notion.site", "notion-static.com", "notion.com"]),
        ("Figma", ["figma.com"]),
        ("Dropbox", ["dropbox.com", "dropboxusercontent.com"]),
        ("YouTube", ["youtube.com", "googlevideo.com"]),
        ("Instagram", ["instagram.com", "cdninstagram.com", "fbcdn.net"]),
        ("LinkedIn", ["linkedin.com", "licdn.com"]),
        ("Cloudflare R2", ["r2.cloudflarestorage.com", "r2.dev"]),
    ]

    static func source(from urls: [String]) -> String? {
        guard !urls.isEmpty else { return nil }
        for s in urls {
            let lower = s.lowercased()
            if lower.hasPrefix("chrome-extension://") || lower.hasPrefix("moz-extension://") || lower.hasPrefix("safari-web-extension://") {
                return "Extensions"
            }
            guard let host = URL(string: s)?.host?.lowercased() else { continue }
            for entry in known where entry.hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
                return entry.name
            }
        }
        let fallback = urls.count > 1 ? urls[1] : urls[0]
        if let host = URL(string: fallback)?.host?.lowercased(), !host.isEmpty {
            return registrableDomain(host)
        }
        return nil
    }

    static func registrableDomain(_ host: String) -> String {
        var labels = host.split(separator: ".").map(String.init)
        if labels.first == "www" { labels.removeFirst() }
        guard labels.count > 2 else { return labels.joined(separator: ".") }
        let secondLevel: Set<String> = ["co", "com", "org", "net", "ac", "gov", "edu"]
        if let tld = labels.last, tld.count == 2, secondLevel.contains(labels[labels.count - 2]) {
            return labels.suffix(3).joined(separator: ".")
        }
        return labels.suffix(2).joined(separator: ".")
    }

    static func symbol(for source: String) -> String {
        switch source {
        case "Gmail": return "envelope.fill"
        case "Google Drive": return "externaldrive.fill"
        case "ChatGPT", "Claude": return "sparkles"
        case "Canva": return "paintpalette.fill"
        case "X": return "at"
        case "Slack": return "number"
        case "WhatsApp", "Telegram", "Discord": return "bubble.left.and.bubble.right.fill"
        case "GitHub": return "chevron.left.forwardslash.chevron.right"
        case "Extensions": return "puzzlepiece.extension.fill"
        case "Notion": return "note.text"
        case "Figma": return "pencil.and.outline"
        case "Dropbox": return "shippingbox.fill"
        case "YouTube": return "play.rectangle.fill"
        case "Instagram": return "camera.fill"
        case "LinkedIn": return "person.2.fill"
        case "Cloudflare R2": return "cloud.fill"
        default: return "globe"
        }
    }
}

struct SourceGroup: Identifiable, Hashable {
    let name: String
    let count: Int
    let bytes: Int64
    var latest: Date = .distantPast
    var id: String { name }
}

struct CategoryTotal: Hashable {
    var count: Int = 0
    var bytes: Int64 = 0
}
