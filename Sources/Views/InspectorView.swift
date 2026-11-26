import SwiftUI
import AVFoundation
import ImageIO

struct InspectorView: View {
    @Environment(NavigationModel.self) private var nav
    @Environment(LibraryStore.self) private var library
    @Environment(OCRIndex.self) private var ocr
    @State private var details: [(String, String)] = []
    @State private var folderBytes: Int64?

    var body: some View {
        if let url = nav.focused ?? nav.selection.first, let item = library.item(for: url) ?? FileItem.load(url) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ThumbView(url: item.url, side: 280, plain: true)
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .onTapGesture { if !item.isDirectory { nav.quickLook(item.url, in: [item.url]) } }
                    Text(item.name).font(.headline).textSelection(.enabled)
                    Text(item.kind).foregroundStyle(.secondary)
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                        if item.isDirectory {
                            row("Size", folderBytes.map { Fmt.bytes($0) } ?? "Measuring…")
                        } else {
                            row("Size", item.isCloudOnly ? "\(Fmt.bytes(item.size)) in iCloud, none on this Mac"
                                : Fmt.bytes(item.size) + (item.allocatedSize != item.size ? " (\(Fmt.bytes(item.allocatedSize)) on disk)" : ""))
                        }
                        ForEach(Array(details.enumerated()), id: \.offset) { _, d in row(d.0, d.1) }
                        if !item.isDirectory { row("Added", Fmt.date(item.arrivalDate)) }
                        row("Modified", Fmt.date(item.modified))
                        if let a = item.accessed { row("Last opened", Fmt.date(a)) }
                        if let s = item.source { row("From", s) }
                        row("Where", Fmt.path(item.url.deletingLastPathComponent()))
                    }
                    .font(.callout)
                    if let link = item.whereFroms.first, let u = URL(string: link) {
                        Link(destination: u) { Label(u.host ?? link, systemImage: "link") }.font(.callout)
                    }
                    if let text = ocr.text(for: item.url), !text.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Text in image").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Spacer()
                                Button("Copy Text") { FileActions.copyText([item]) }.controlSize(.small)
                            }
                            Text(text.components(separatedBy: "\n").dropLast().joined(separator: "\n")).font(.callout).textSelection(.enabled).lineLimit(12)
                        }
                    }
                    HStack {
                        Button(item.isDirectory ? "Open" : "Open") { FileActions.primary(item, in: [item]) }
                        Button("Show in Finder") { FileActions.reveal([item]) }
                    }
                    if !item.url.isAtticStub && !item.isDirectory && item.category != .apps {
                        Button { nav.offloadRequest = [item] } label: { Label("Offload to R2 or iCloud…", systemImage: "icloud.and.arrow.up") }
                    }
                }
                .padding(16)
            }
            .task(id: item.url) {
                details = []
                folderBytes = nil
                if item.isDirectory {
                    if let cached = FolderSizeCache.shared.bytes(for: item.path) { folderBytes = cached; return }
                    let url = item.url
                    let flag = CancelFlag()
                    let b = await withTaskCancellationHandler {
                        await Task.detached(priority: .utility) { FolderSizeCache.measure(url) { flag.cancelled } }.value
                    } onCancel: { flag.cancelled = true }
                    if let b { FolderSizeCache.shared.set(item.path, b); folderBytes = b }
                } else if !item.isCloudOnly {
                    details = await MediaInfo.details(item.url, category: item.category)
                }
            }
        } else {
            EmptyStateView(symbol: "sidebar.right", title: "No selection", message: "Select a file to see its details.")
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        GridRow {
            Text(k).foregroundStyle(.secondary)
            Text(v).textSelection(.enabled).lineLimit(3)
        }
    }
}

/// Dimensions, duration and camera details, read on this Mac.
enum MediaInfo {
    static func details(_ url: URL, category: FileCategory) async -> [(String, String)] {
        switch category {
        case .images:
            return await Task.detached(priority: .utility) { imageDetails(url) }.value
        case .videos, .music:
            var out: [(String, String)] = []
            let asset = AVURLAsset(url: url)
            if let d = try? await asset.load(.duration), d.seconds.isFinite, d.seconds > 0 { out.append(("Duration", duration(d.seconds))) }
            if category == .videos, let track = try? await asset.loadTracks(withMediaType: .video).first,
               let size = try? await track.load(.naturalSize) {
                out.append(("Dimensions", "\(Int(abs(size.width))) × \(Int(abs(size.height)))"))
                if let fps = try? await track.load(.nominalFrameRate), fps > 0 { out.append(("Frame rate", String(format: "%.0f fps", fps))) }
            }
            if category == .music, let meta = try? await asset.load(.commonMetadata) {
                for (key, label) in [(AVMetadataKey.commonKeyArtist, "Artist"), (.commonKeyAlbumName, "Album")] {
                    if let it = AVMetadataItem.metadataItems(from: meta, withKey: key, keySpace: .common).first,
                       let v = try? await it.load(.stringValue), !v.isEmpty { out.append((label, v)) }
                }
            }
            return out
        default:
            return []
        }
    }

    static func imageDetails(_ url: URL) -> [(String, String)] {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return [] }
        var out: [(String, String)] = []
        if let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int { out.append(("Dimensions", "\(w) × \(h)")) }
        let tiff = p[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let exif = p[kCGImagePropertyExifDictionary] as? [CFString: Any]
        if let make = tiff?[kCGImagePropertyTIFFMake] as? String, let model = tiff?[kCGImagePropertyTIFFModel] as? String {
            out.append(("Camera", model.hasPrefix(make) ? model : "\(make) \(model)"))
        } else if let model = tiff?[kCGImagePropertyTIFFModel] as? String {
            out.append(("Camera", model))
        }
        if let lens = exif?[kCGImagePropertyExifLensModel] as? String { out.append(("Lens", lens)) }
        if let taken = exif?[kCGImagePropertyExifDateTimeOriginal] as? String { out.append(("Taken", taken)) }
        if (exif?[kCGImagePropertyExifUserComment] as? String) == "Screenshot" { out.append(("Type", "Screenshot")) }
        return out
    }

    static func duration(_ s: Double) -> String {
        let t = Int(s.rounded())
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }
}
