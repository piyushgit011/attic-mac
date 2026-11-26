// Renders the Attic logo: app icon sizes, menu bar template, in-app mark, lockups and an SVG.
// The mark is a house-shaped folder with your files peeking out: an attic for everything on your Mac.
// Usage: swift branding/render-logo.swift <repo root>
import AppKit

let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let C: CGFloat = 1024 // design canvas, y-down like SVG

// MARK: Geometry (shared by PNG + SVG)

let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tileRadius: CGFloat = 186

/// The back of the folder is a gable: the attic.
let gable: [CGPoint] = [CGPoint(x: 254, y: 790), CGPoint(x: 254, y: 470), CGPoint(x: 512, y: 246),
                        CGPoint(x: 770, y: 470), CGPoint(x: 770, y: 790)]
let gableRound: CGFloat = 46
/// The round attic window.
let windowCenter = CGPoint(x: 512, y: 372)
let windowRadius: CGFloat = 42
/// Three files peeking out: (center, rotation in degrees, top color, bottom color).
let cards: [(CGPoint, CGFloat, UInt32, UInt32)] = [
    (CGPoint(x: 386, y: 600), -11, 0xC4B5FF, 0x8F7BFF),
    (CGPoint(x: 638, y: 600), 11, 0x8EEAD0, 0x34C39C),
    (CGPoint(x: 512, y: 578), 0, 0xFFFFFF, 0xF3F1F8),
]
let cardSize = CGSize(width: 196, height: 244)
let cardRadius: CGFloat = 24
/// The front of the folder.
let flap = CGRect(x: 222, y: 640, width: 580, height: 178)
let flapRadius: CGFloat = 50
let labelHolder = CGRect(x: 452, y: 672, width: 120, height: 16)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

func hex(_ v: UInt32) -> String { String(format: "#%06X", v) }

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let extend: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]

func gradient(_ stops: [(UInt32, CGFloat, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: stops.map { color($0.0, $0.1) } as CFArray, locations: stops.map { $0.2 })!
}

func makeContext(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

/// A polygon with rounded corners.
func roundedPolygon(_ pts: [CGPoint], radius: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let n = pts.count
    let mid = CGPoint(x: (pts[n - 1].x + pts[0].x) / 2, y: (pts[n - 1].y + pts[0].y) / 2)
    p.move(to: mid)
    for i in 0..<n {
        p.addArc(tangent1End: pts[i], tangent2End: pts[(i + 1) % n], radius: radius)
    }
    p.closeSubpath()
    return p
}

func gablePath() -> CGPath { roundedPolygon(gable, radius: gableRound) }
func flapPath() -> CGPath { CGPath(roundedRect: flap, cornerWidth: flapRadius, cornerHeight: flapRadius, transform: nil) }

func cardPath(_ c: (CGPoint, CGFloat, UInt32, UInt32)) -> CGPath {
    var t = CGAffineTransform(translationX: c.0.x, y: c.0.y).rotated(by: c.1 * .pi / 180)
    let r = CGRect(x: -cardSize.width / 2, y: -cardSize.height / 2, width: cardSize.width, height: cardSize.height)
    return CGPath(roundedRect: r, cornerWidth: cardRadius, cornerHeight: cardRadius, transform: &t)
}

/// Draws the full-colour icon into ctx (already scaled to the 1024 design canvas, y-down).
func drawIcon(_ ctx: CGContext, shadow: Bool = true) {
    let tilePath = CGPath(roundedRect: tile, cornerWidth: tileRadius, cornerHeight: tileRadius, transform: nil)
    if shadow {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 16), blur: 34, color: color(0x000000, 0.30))
        ctx.addPath(tilePath); ctx.setFillColor(color(0xFF7A45)); ctx.fillPath()
        ctx.restoreGState()
    }

    // Tile: warm sunset with light from the top left.
    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()
    ctx.drawLinearGradient(gradient([(0xFFC15E, 1, 0), (0xFF8048, 1, 0.48), (0xF2466F, 1, 0.86), (0xD9336F, 1, 1)]),
                           start: CGPoint(x: 260, y: 100), end: CGPoint(x: 764, y: 924), options: extend)
    ctx.drawRadialGradient(gradient([(0xFFFFFF, 0.42, 0), (0xFFFFFF, 0, 1)]),
                           startCenter: CGPoint(x: 300, y: 150), startRadius: 0, endCenter: CGPoint(x: 300, y: 150), endRadius: 620, options: [])
    ctx.drawLinearGradient(gradient([(0x6A0F33, 0, 0), (0x6A0F33, 0.26, 1)]),
                           start: CGPoint(x: 512, y: 620), end: CGPoint(x: 512, y: 924), options: extend)

    // The gable, like frosted glass.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 28, color: color(0x7A1238, 0.22))
    ctx.addPath(gablePath())
    ctx.setFillColor(color(0xFFFFFF, 0.36))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(gablePath()); ctx.clip()
    ctx.drawLinearGradient(gradient([(0xFFFFFF, 0.34, 0), (0xFFFFFF, 0.04, 1)]),
                           start: CGPoint(x: 512, y: 246), end: CGPoint(x: 512, y: 790), options: extend)
    ctx.restoreGState()
    ctx.addPath(gablePath())
    ctx.setStrokeColor(color(0xFFFFFF, 0.75)); ctx.setLineWidth(7); ctx.strokePath()

    // The round attic window.
    let win = CGRect(x: windowCenter.x - windowRadius, y: windowCenter.y - windowRadius, width: windowRadius * 2, height: windowRadius * 2)
    ctx.saveGState()
    ctx.addEllipse(in: win); ctx.clip()
    ctx.drawLinearGradient(gradient([(0xFFF6D6, 1, 0), (0xFFD08A, 1, 1)]), start: CGPoint(x: 512, y: win.minY), end: CGPoint(x: 512, y: win.maxY), options: extend)
    ctx.restoreGState()
    ctx.setStrokeColor(color(0xFFFFFF, 0.95)); ctx.setLineWidth(9)
    ctx.addEllipse(in: win); ctx.strokePath()
    ctx.setLineWidth(7)
    ctx.move(to: CGPoint(x: windowCenter.x, y: win.minY)); ctx.addLine(to: CGPoint(x: windowCenter.x, y: win.maxY))
    ctx.move(to: CGPoint(x: win.minX, y: windowCenter.y)); ctx.addLine(to: CGPoint(x: win.maxX, y: windowCenter.y))
    ctx.strokePath()

    // Files peeking out.
    for c in cards {
        let path = cardPath(c)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 8), blur: 18, color: color(0x5A0E2C, 0.28))
        ctx.addPath(path); ctx.setFillColor(color(c.3)); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        ctx.drawLinearGradient(gradient([(c.2, 1, 0), (c.3, 1, 1)]),
                               start: CGPoint(x: c.0.x, y: c.0.y - cardSize.height / 2), end: CGPoint(x: c.0.x, y: c.0.y + cardSize.height / 2), options: extend)
        if c.1 == 0 {
            // The middle file is a photo: sky, sun and hills.
            var t = CGAffineTransform(translationX: c.0.x, y: c.0.y)
            let photo = CGPath(roundedRect: CGRect(x: -74, y: -96, width: 148, height: 116), cornerWidth: 14, cornerHeight: 14, transform: &t)
            ctx.addPath(photo); ctx.clip()
            ctx.drawLinearGradient(gradient([(0x7CC4FF, 1, 0), (0xC9E7FF, 1, 1)]),
                                   start: CGPoint(x: c.0.x, y: c.0.y - 96), end: CGPoint(x: c.0.x, y: c.0.y + 20), options: extend)
            ctx.setFillColor(color(0xFFE08A)); ctx.fillEllipse(in: CGRect(x: c.0.x + 18, y: c.0.y - 78, width: 34, height: 34))
            let hill = CGMutablePath()
            hill.move(to: CGPoint(x: c.0.x - 80, y: c.0.y + 24))
            hill.addLine(to: CGPoint(x: c.0.x - 80, y: c.0.y - 10))
            hill.addQuadCurve(to: CGPoint(x: c.0.x - 10, y: c.0.y - 26), control: CGPoint(x: c.0.x - 48, y: c.0.y - 52))
            hill.addQuadCurve(to: CGPoint(x: c.0.x + 80, y: c.0.y - 18), control: CGPoint(x: c.0.x + 30, y: c.0.y - 2))
            hill.addLine(to: CGPoint(x: c.0.x + 80, y: c.0.y + 24))
            hill.closeSubpath()
            ctx.addPath(hill); ctx.setFillColor(color(0x3FBF8A)); ctx.fillPath()
        } else {
            // Lines of text on the side files.
            ctx.setFillColor(color(0xFFFFFF, 0.6))
            var t = CGAffineTransform(translationX: c.0.x, y: c.0.y).rotated(by: c.1 * .pi / 180)
            for (i, w) in [118.0, 92.0, 104.0].enumerated() {
                let line = CGPath(roundedRect: CGRect(x: -64, y: -82 + CGFloat(i) * 30, width: CGFloat(w), height: 14),
                                  cornerWidth: 7, cornerHeight: 7, transform: &t)
                ctx.addPath(line); ctx.fillPath()
            }
        }
        ctx.restoreGState()
    }

    // The front of the folder.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 22, color: color(0x6A0F33, 0.30))
    ctx.addPath(flapPath()); ctx.setFillColor(color(0xFFFFFF)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(flapPath()); ctx.clip()
    ctx.drawLinearGradient(gradient([(0xFFFFFF, 1, 0), (0xFFF0E6, 1, 0.7), (0xFFE2D2, 1, 1)]),
                           start: CGPoint(x: 512, y: flap.minY), end: CGPoint(x: 512, y: flap.maxY), options: extend)
    ctx.restoreGState()
    ctx.addPath(CGPath(roundedRect: labelHolder, cornerWidth: 9, cornerHeight: 9, transform: nil))
    ctx.setFillColor(color(0xF2466F, 0.28)); ctx.fillPath()

    // A thin light along the top edge of the tile.
    ctx.addPath(tilePath)
    ctx.setLineWidth(6)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(gradient([(0xFFFFFF, 0.55, 0), (0xFFFFFF, 0, 0.35)]),
                           start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: extend)
    ctx.restoreGState()
}

/// Monochrome mark for the menu bar (template image): the gable outline and the folder front.
func drawTemplate(_ ctx: CGContext) {
    ctx.setStrokeColor(color(0x000000))
    ctx.setLineWidth(58)
    ctx.setLineJoin(.round)
    ctx.addPath(roundedPolygon(gable, radius: 30))
    ctx.strokePath()
    ctx.setFillColor(color(0x000000))
    ctx.addPath(flapPath()); ctx.fillPath()
    ctx.fillEllipse(in: CGRect(x: windowCenter.x - 44, y: windowCenter.y - 44, width: 88, height: 88))
}

func png(_ px: Int, crop: CGRect = CGRect(x: 0, y: 0, width: C, height: C), draw: (CGContext) -> Void) -> Data {
    let scale = CGFloat(px) / crop.width
    let h = Int(crop.height * scale)
    let ctx = makeContext(px, h)
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: scale, y: -scale)
    ctx.translateBy(x: -crop.minX, y: -crop.minY)
    ctx.interpolationQuality = .high
    draw(ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

func write(_ data: Data, _ path: String) {
    let url = URL(fileURLWithPath: root + "/" + path)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! data.write(to: url)
}

// MARK: App icon
let iconSet = "Resources/Assets.xcassets/AppIcon.appiconset"
let sizes: [(String, Int)] = [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                              ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)]
var images: [[String: String]] = []
for (name, px) in sizes {
    let file = "icon_\(name).png"
    write(png(px) { drawIcon($0) }, "\(iconSet)/\(file)")
    let parts = name.split(separator: "@")
    images.append(["idiom": "mac", "size": String(parts[0]), "scale": parts.count > 1 ? "2x" : "1x", "filename": file])
}
write(try! JSONSerialization.data(withJSONObject: ["images": images, "info": ["version": 1, "author": "xcode"]], options: [.prettyPrinted, .sortedKeys]),
      "\(iconSet)/Contents.json")

// MARK: Menu bar template (18 pt)
let markBox = CGRect(x: 216, y: 228, width: 592, height: 592)
let tmpl = "Resources/Assets.xcassets/MenuBarMark.imageset"
write(png(18, crop: markBox) { drawTemplate($0) }, "\(tmpl)/menubar.png")
write(png(36, crop: markBox) { drawTemplate($0) }, "\(tmpl)/menubar@2x.png")
write(Data("""
{ "images": [ { "idiom": "universal", "filename": "menubar.png", "scale": "1x" }, { "idiom": "universal", "filename": "menubar@2x.png", "scale": "2x" } ],
  "info": { "version": 1, "author": "xcode" }, "properties": { "template-rendering-intent": "template" } }
""".utf8), "\(tmpl)/Contents.json")

// Logo mark for use inside the app
let inApp = "Resources/Assets.xcassets/LogoMark.imageset"
write(png(128) { drawIcon($0, shadow: false) }, "\(inApp)/logo.png")
write(png(256) { drawIcon($0, shadow: false) }, "\(inApp)/logo@2x.png")
write(Data("""
{ "images": [ { "idiom": "universal", "filename": "logo.png", "scale": "1x" }, { "idiom": "universal", "filename": "logo@2x.png", "scale": "2x" } ],
  "info": { "version": 1, "author": "xcode" } }
""".utf8), "\(inApp)/Contents.json")

// MARK: Brand files
write(png(1024) { drawIcon($0) }, "branding/attic-icon-1024.png")
write(png(512) { drawIcon($0) }, "docs/images/icon.png")

func lockup(dark: Bool) -> Data {
    let w = 1800, h = 520
    let ctx = makeContext(w, h)
    ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
    if dark { ctx.setFillColor(color(0x0B0B0D)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h)) }
    ctx.saveGState()
    ctx.translateBy(x: 40, y: 20)
    ctx.scaleBy(x: 480 / C, y: 480 / C)
    drawIcon(ctx)
    ctx.restoreGState()
    let font = NSFont.systemFont(ofSize: 230, weight: .bold)
    let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 230) } ?? font
    let attr = NSAttributedString(string: "Attic", attributes: [.font: rounded, .foregroundColor: NSColor(cgColor: dark ? color(0xFFFFFF) : color(0x1D1D1F))!, .kern: -4])
    let sub = NSAttributedString(string: "The Finder alternative that frees up your Mac.", attributes: [
        .font: NSFont.systemFont(ofSize: 50, weight: .medium), .foregroundColor: NSColor(cgColor: dark ? color(0xA1A1A6) : color(0x6E6E73))!])
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    attr.draw(at: NSPoint(x: 560, y: 70))
    sub.draw(at: NSPoint(x: 568, y: 345))
    NSGraphicsContext.restoreGraphicsState()
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}
write(lockup(dark: false), "branding/attic-logo-light.png")
write(lockup(dark: true), "branding/attic-logo-dark.png")

// MARK: SVG of the icon (same geometry, simplified light)
func svgPoints(_ pts: [CGPoint]) -> String { pts.map { "\(Int($0.x)),\(Int($0.y))" }.joined(separator: " ") }
let cardsSVG = cards.map { c in
    "<rect x=\"\(Int(-cardSize.width / 2))\" y=\"\(Int(-cardSize.height / 2))\" width=\"\(Int(cardSize.width))\" height=\"\(Int(cardSize.height))\" rx=\"\(Int(cardRadius))\" fill=\"\(hex(c.3))\" transform=\"translate(\(Int(c.0.x)) \(Int(c.0.y))) rotate(\(Int(c.1)))\"/>"
}.joined(separator: "\n    ")
let svg = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <title>Attic</title>
  <defs>
    <linearGradient id="bg" x1="260" y1="100" x2="764" y2="924" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#FFC15E"/><stop offset="0.48" stop-color="#FF8048"/><stop offset="0.86" stop-color="#F2466F"/><stop offset="1" stop-color="#D9336F"/>
    </linearGradient>
    <radialGradient id="glow" cx="300" cy="150" r="620" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.42"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="flap" x1="512" y1="612" x2="512" y2="808" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#FFE2D2"/>
    </linearGradient>
  </defs>
  <rect x="100" y="100" width="824" height="824" rx="186" fill="url(#bg)"/>
  <rect x="100" y="100" width="824" height="824" rx="186" fill="url(#glow)"/>
  <polygon points="\(svgPoints(gable))" fill="#FFFFFF" fill-opacity="0.3" stroke="#FFFFFF" stroke-opacity="0.55" stroke-width="5" stroke-linejoin="round"/>
  <circle cx="\(Int(windowCenter.x))" cy="\(Int(windowCenter.y))" r="\(Int(windowRadius))" fill="#FFE3A8" stroke="#FFFFFF" stroke-width="9"/>
  <path d="M512 330V414M470 372H554" stroke="#FFFFFF" stroke-width="7"/>
  <g>
    \(cardsSVG)
  </g>
  <rect x="\(Int(flap.minX))" y="\(Int(flap.minY))" width="\(Int(flap.width))" height="\(Int(flap.height))" rx="\(Int(flapRadius))" fill="url(#flap)"/>
  <rect x="\(Int(labelHolder.minX))" y="\(Int(labelHolder.minY))" width="\(Int(labelHolder.width))" height="\(Int(labelHolder.height))" rx="9" fill="#F2466F" fill-opacity="0.28"/>
</svg>
"""
write(Data(svg.utf8), "branding/attic-icon.svg")
print("rendered")
