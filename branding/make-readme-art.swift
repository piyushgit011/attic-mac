// Composes the README artwork from the demo screenshots (build/shots, made by branding/demo/run-tour.sh stills).
// Usage: swift branding/make-readme-art.swift <repo root>
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let shots = root.appendingPathComponent("build/shots")
let out = root.appendingPathComponent("docs/images")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
func load(_ url: URL) -> CGImage { NSImage(contentsOf: url)!.cgImage(forProposedRect: nil, context: nil, hints: nil)! }
func canvas(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
func write(_ ctx: CGContext, _ name: String) {
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
    print("  docs/images/\(name)")
}

/// Warm dark backdrop with soft brand glows.
func backdrop(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
    ctx.setFillColor(color(0x110B0F)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    for (x, y, r, c, a) in [(0.12, 0.85, 0.55, 0xFFC04D, 0.38), (0.92, 0.1, 0.65, 0xEE4472, 0.36), (0.75, 0.95, 0.45, 0xFF7E45, 0.30)] as [(CGFloat, CGFloat, CGFloat, UInt32, CGFloat)] {
        let g = CGGradient(colorsSpace: space, colors: [color(c, a), color(c, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: x * w, y: y * h), startRadius: 0, endCenter: CGPoint(x: x * w, y: y * h), endRadius: r * max(w, h), options: [])
    }
}

/// Draws a window screenshot with rounded corners, hairline border and a deep shadow.
func window(_ ctx: CGContext, _ img: CGImage, _ rect: CGRect, radius: CGFloat) {
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -rect.width * 0.025), blur: rect.width * 0.06, color: color(0x000000, 0.55))
    ctx.addPath(path); ctx.setFillColor(color(0x1D1D1F)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(img, in: rect)
    ctx.restoreGState()
    ctx.addPath(path); ctx.setStrokeColor(color(0xFFFFFF, 0.12)); ctx.setLineWidth(2); ctx.strokePath()
}

func text(_ ctx: CGContext, _ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ weight: NSFont.Weight, _ c: NSColor, rounded: Bool = false, kern: CGFloat = 0) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    var font = NSFont.systemFont(ofSize: size, weight: weight)
    if rounded, let d = font.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: size) { font = f }
    NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: c, .kern: kern]).draw(at: NSPoint(x: x, y: y))
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: Banner (2400 x 1260)
if let homeURL = shotURL("home") {
    let W: CGFloat = 2400, H: CGFloat = 1260
    let ctx = canvas(Int(W), Int(H))
    backdrop(ctx, W, H)
    let icon = load(root.appendingPathComponent("branding/attic-icon-1024.png"))
    ctx.draw(icon, in: CGRect(x: 110, y: H - 150 - 260, width: 260, height: 260))
    text(ctx, "Attic", 140, H - 600, 190, .bold, .white, rounded: true, kern: -4)
    text(ctx, "Free up your Mac.", 146, H - 700, 64, .semibold, NSColor(white: 1, alpha: 0.92))
    text(ctx, "Keep everything.", 146, H - 780, 64, .semibold, NSColor(srgbRed: 1, green: 0.72, blue: 0.52, alpha: 1))
    let bullets = ["Plain-English search, even inside screenshots", "Clean Up, Duplicates and Deep Clean", "Memory & Swap: see what to quit",
                   "Offload to Cloudflare R2 or iCloud Drive"]
    for (i, b) in bullets.enumerated() {
        ctx.setFillColor(color(0xFF9A5A)); ctx.fillEllipse(in: CGRect(x: 150, y: H - 885 - CGFloat(i) * 62, width: 14, height: 14))
        text(ctx, b, 184, H - 906 - CGFloat(i) * 62, 36, .medium, NSColor(white: 1, alpha: 0.72))
    }
    let home = load(homeURL)
    let ww: CGFloat = 1300
    let wh = ww * CGFloat(home.height) / CGFloat(home.width)
    window(ctx, home, CGRect(x: W - ww - 90, y: (H - wh) / 2 - 10, width: ww, height: wh), radius: 22)
    write(ctx, "banner.png")
}

// MARK: Framed screenshots (1800 wide)
// Shots are matched by label (the number prefix can shift when tours change).
let framed: [(String, String)] = [
    ("home", "home"), ("search", "search"), ("ai-search", "ai-search"), ("images", "library"), ("downloaded-from", "downloaded-from"),
    ("cleanup", "cleanup"), ("cleanup-review", "cleanup-review"), ("duplicates", "duplicates"), ("deep-clean", "deep-clean"),
    ("memory", "memory"), ("large-files", "large-files"), ("offload-sheet-icloud", "offload-icloud"),
    ("offload-sheet-r2", "offload-r2"), ("cloud", "cloud"), ("offloaded", "offloaded"), ("quick-search", "quick-search"),
]
func shotURL(_ label: String) -> URL? {
    let files = (try? FileManager.default.contentsOfDirectory(atPath: shots.path)) ?? []
    return files.first { $0.hasSuffix("-\(label).png") && $0.dropFirst(3) == "\(label).png" }.map { shots.appendingPathComponent($0) }
}
for (src, name) in framed {
    guard let url = shotURL(src) else { continue }
    let img = load(url)
    let W: CGFloat = 1800
    let pad: CGFloat = 90
    let ww = W - pad * 2
    let wh = ww * CGFloat(img.height) / CGFloat(img.width)
    let H = wh + pad * 2
    let ctx = canvas(Int(W), Int(H))
    backdrop(ctx, W, H)
    window(ctx, img, CGRect(x: pad, y: pad, width: ww, height: wh), radius: 18)
    write(ctx, "\(name).png")
}
