import Foundation
import AppKit
import Vision
import QuickLookThumbnailing
import PDFKit
import Observation

/// Reads the text inside screenshots and recent images on this Mac (Apple Vision), cached by path + modified date.
@MainActor @Observable
final class OCRIndex {
    var texts: [String: String] = [:]
    var isIndexing = false
    var indexed = 0
    var pending = 0

    private var mtimes: [String: Double] = [:]
    private var task: Task<Void, Never>?
    private var cacheURL: URL { AppPaths.support.appendingPathComponent("ocr-index.json") }

    private struct Entry: Codable { let m: Double; let t: String }

    init() { load() }

    func text(for url: URL) -> String? { texts[url.path] }

    func indexInBackground(_ items: [FileItem]) {
        guard UserDefaults.standard.object(forKey: Prefs.ocrEnabled) as? Bool ?? true else { return }
        let cutoff = Date().addingTimeInterval(-365 * 86_400)
        let candidates = items
            .filter { $0.category == .images && !$0.isCloudOnly && $0.size < 25_000_000 && ($0.isScreenshot || $0.arrivalDate > cutoff) }
            .filter { mtimes[$0.path] != $0.modified.timeIntervalSince1970 }
            .sorted { $0.arrivalDate > $1.arrivalDate }
            .prefix(3000)
        let work = Array(candidates)
        guard !work.isEmpty else { return }
        task?.cancel()
        isIndexing = true
        pending = work.count
        indexed = 0
        task = Task.detached(priority: .background) { [weak self] in
            var batch: [(String, Double, String)] = []
            for (n, item) in work.enumerated() {
                if Task.isCancelled { break }
                let text = OCRIndex.recognize(item.url, fast: false) ?? ""
                batch.append((item.path, item.modified.timeIntervalSince1970, text.lowercased()))
                if batch.count >= 25 || n == work.count - 1 {
                    let flush = batch
                    batch.removeAll()
                    await MainActor.run {
                        guard let self else { return }
                        for (p, m, t) in flush { self.texts[p] = t; self.mtimes[p] = m }
                        self.indexed = n + 1
                    }
                }
            }
            await MainActor.run {
                self?.isIndexing = false
                self?.save()
            }
        }
    }

    /// Recognizes text right now (for Copy Text), keeping line breaks.
    func recognizeNow(_ urls: [URL]) async -> String {
        await Task.detached(priority: .userInitiated) {
            urls.compactMap { url -> String? in
                if url.pathExtension.lowercased() == "pdf", let doc = PDFDocument(url: url), let s = doc.string, !s.isEmpty { return s }
                return OCRIndex.recognize(url, fast: false)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        }.value
    }

    nonisolated static func recognize(_ url: URL, fast: Bool) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = fast ? .fast : .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(url: url, options: [:])
        do { try handler.perform([request]) } catch { return nil }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }

    private func load() {
        guard let data = try? Data(contentsOf: cacheURL),
              let dict = try? JSONDecoder().decode([String: Entry].self, from: data) else { return }
        for (k, v) in dict { texts[k] = v.t; mtimes[k] = v.m }
    }

    private func save() {
        var dict: [String: Entry] = [:]
        for (k, t) in texts { dict[k] = Entry(m: mtimes[k] ?? 0, t: t) }
        if let data = try? JSONEncoder().encode(dict) { try? data.write(to: cacheURL, options: .atomic) }
    }
}

// MARK: - Thumbnails

final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    init() { cache.countLimit = 1500 }

    func cached(_ url: URL, side: CGFloat) -> NSImage? {
        cache.object(forKey: key(url, side))
    }

    func thumbnail(for url: URL, side: CGFloat) async -> NSImage {
        let k = key(url, side)
        if let hit = cache.object(forKey: k) { return hit }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side),
                                                   scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        let image: NSImage
        if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            image = rep.nsImage
        } else {
            image = NSWorkspace.shared.icon(forFile: url.path)
        }
        cache.setObject(image, forKey: k)
        return image
    }

    private func key(_ url: URL, _ side: CGFloat) -> NSString {
        "\(url.path)#\(Int(side / 64))" as NSString
    }
}
