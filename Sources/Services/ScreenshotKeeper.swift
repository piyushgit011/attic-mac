import AppKit
import ImageIO

/// macOS can send screenshots straight to the clipboard (⇧⌘5 ▸ Options ▸ Save to ▸ Clipboard). Then no file is
/// ever written, so they can't be found later. When "Keep screenshot history" is on, Attic saves each new
/// clipboard screenshot as a PNG in Pictures ▸ Screenshots, where search can read the text in it.
///
/// Only real screenshots are kept: macOS tags them with the EXIF comment "Screenshot". Images copied from a web
/// page, Preview or Photos don't have it and are left alone.
@MainActor @Observable
final class ScreenshotKeeper {
    static let shared = ScreenshotKeeper()

    var enabled: Bool = UserDefaults.standard.bool(forKey: Prefs.keepScreenshots) {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Prefs.keepScreenshots)
            if enabled { start(); check(includeCurrent: true) } else { stop() }
        }
    }
    private(set) var savedThisSession = 0
    private var timer: Timer?
    private var lastChange = NSPasteboard.general.changeCount
    private var lastSaved: Data?

    /// Where macOS puts screenshots: "clipboard", or a folder path.
    nonisolated static var macOSTarget: String {
        let d = UserDefaults(suiteName: "com.apple.screencapture")
        return d?.string(forKey: "target-screenshot") ?? d?.string(forKey: "target") ?? "file"
    }

    nonisolated static var macOSCopiesToClipboard: Bool { macOSTarget == "clipboard" }

    nonisolated static var folder: URL {
        if let custom = UserDefaults.standard.string(forKey: Prefs.screenshotFolder), !custom.isEmpty {
            return URL(fileURLWithPath: custom)
        }
        return Locations.home.appendingPathComponent("Pictures/Screenshots", isDirectory: true)
    }

    func start() {
        guard enabled, timer == nil else { return }
        lastChange = NSPasteboard.general.changeCount
        let t = Timer(timeInterval: 0.8, repeats: true) { _ in
            Task { @MainActor in ScreenshotKeeper.shared.check(includeCurrent: false) }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Looks at the clipboard. Reading the change count is free; the image is only read when something new arrived.
    func check(includeCurrent: Bool) {
        let pb = NSPasteboard.general
        guard includeCurrent || pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        guard enabled, let items = pb.pasteboardItems, items.count == 1 else { return }
        let types = Set(items[0].types)
        guard types.contains(.png), !types.contains(.fileURL), !types.contains(.html),
              let data = items[0].data(forType: .png), ScreenshotKeeper.isScreenshot(data) else { return }
        guard data != lastSaved else { return }
        lastSaved = data
        if let url = save(data) {
            savedThisSession += 1
            AppState.shared.library.filesChanged(added: [url])
        }
    }

    nonisolated static func isScreenshot(_ data: Data) -> Bool {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let comment = exif[kCGImagePropertyExifUserComment] as? String else { return false }
        return comment == "Screenshot"
    }

    private func save(_ data: Data) -> URL? {
        let dir = ScreenshotKeeper.folder
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let url = AppPaths.uniqueURL(for: dir.appendingPathComponent("Screenshot \(f.string(from: Date())).png"))
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("Attic: couldn't save screenshot: \(error)")
            return nil
        }
        // Mark it the way macOS marks its own screenshots, so Spotlight and Finder's smart folders agree.
        if let plist = try? PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0) {
            _ = plist.withUnsafeBytes { buf in
                setxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", buf.baseAddress, buf.count, 0, 0)
            }
        }
        return url
    }
}
