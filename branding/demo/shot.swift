// Screenshot of one app's windows only (ScreenCaptureKit), transparent around the window.
// Usage: swift shot.swift <bundle id> <out.png> [margin points]
import Foundation
import ScreenCaptureKit
import AppKit
import UniformTypeIdentifiers

let args = CommandLine.arguments
let bundleID = args[1], out = URL(fileURLWithPath: args[2])
let margin = args.count > 3 ? CGFloat(Double(args[3])!) : 0
_ = NSApplication.shared // connects to the window server (needed for window captures)
let sem = DispatchSemaphore(value: 0)
Task {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let app = content.applications.first(where: { $0.bundleIdentifier == bundleID }),
              let win = content.windows.filter({ $0.owningApplication?.bundleIdentifier == bundleID && $0.frame.width > 800 && $0.frame.height > 300 })
                .max(by: { $0.frame.width < $1.frame.width }) else { print("no window"); exit(1) }
        let display = content.displays.first { $0.frame.contains(CGPoint(x: win.frame.midX, y: win.frame.midY)) } ?? content.displays[0]
        print("window \(win.windowID) \(win.frame) onScreen=\(win.isOnScreen)")
        if true { // single-window capture: robust to other desktops and overlapping apps
            // Window is on another Space: capture each Attic window on its own and stack them.
            let scale: CGFloat = 2
            let all = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false).windows
                .filter { $0.windowID == win.windowID }
                .sorted { $0.windowID == win.windowID ? true : ($1.windowID == win.windowID ? false : $0.windowID < $1.windowID) }
            let ctx = CGContext(data: nil, width: Int(win.frame.width * scale), height: Int(win.frame.height * scale), bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            for w in all {
                let c = SCStreamConfiguration()
                c.width = Int(w.frame.width * scale); c.height = Int(w.frame.height * scale); c.showsCursor = false
                c.backgroundColor = CGColor.clear
                let img = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: w), configuration: c)
                let x = (w.frame.minX - win.frame.minX) * scale
                let y = (win.frame.maxY - w.frame.maxY) * scale
                ctx.draw(img, in: CGRect(x: x, y: y, width: w.frame.width * scale, height: w.frame.height * scale))
            }
            let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
            CGImageDestinationFinalize(dest)
            print("saved \(out.lastPathComponent) (off-screen fallback, \(all.count) windows)")
            sem.signal()
            return
        }
        let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
        let scale = CGFloat(filter.pointPixelScale)
        let cfg = SCStreamConfiguration()
        let r = win.frame.insetBy(dx: -margin, dy: -margin).offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        cfg.sourceRect = r
        cfg.width = Int(r.width * scale); cfg.height = Int(r.height * scale)
        cfg.showsCursor = false
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.backgroundColor = CGColor.clear
        let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
        let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
        print("saved \(out.lastPathComponent) \(img.width)x\(img.height)")
    } catch { print("error: \(error)") }
    sem.signal()
}
sem.wait()
