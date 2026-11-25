// Renders the Attic logo: app icon sizes, menu bar template, lockups and an SVG of the mark.
// Usage: swift branding/render-logo.swift <repo root>
import AppKit

let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let C: CGFloat = 1024 // design canvas, y-down like SVG

// MARK: Geometry (shared by PNG + SVG)
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tileRadius: CGFloat = 186
let roof: [CGPoint] = [CGPoint(x: 268, y: 506), CGPoint(x: 512, y: 290), CGPoint(x: 756, y: 506)]
let roofWidth: CGFloat = 86
let cloudCircles: [(CGPoint, CGFloat)] = [
    (CGPoint(x: 404, y: 622), 86),
    (CGPoint(x: 548, y: 584), 118),
    (CGPoint(x: 660, y: 640), 66),
]
let cloudBase = CGRect(x: 296, y: 622, width: 432, height: 140)
let cloudRadius: CGFloat = 70
/// Up arrow cut into the cloud: "move it up to the attic".
let arrowStem = (CGPoint(x: 530, y: 716), CGPoint(x: 530, y: 566))
let arrowHead: [CGPoint] = [CGPoint(x: 474, y: 620), CGPoint(x: 530, y: 564), CGPoint(x: 586, y: 620)]
let arrowWidth: CGFloat = 36

func cloudPath() -> CGPath {
    let p = CGMutablePath()
    for (c, r) in cloudCircles { p.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)) }
    p.addRoundedRect(in: cloudBase, cornerWidth: cloudRadius, cornerHeight: cloudRadius)
    return p
}

func roofPath() -> CGPath {
    let p = CGMutablePath()
    p.addLines(between: roof)
    return p.copy(strokingWithWidth: roofWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)
}

func arrowPath() -> CGPath {
    let p = CGMutablePath()
    p.move(to: arrowStem.0); p.addLine(to: arrowStem.1)
    p.addLines(between: arrowHead)
    return p.copy(strokingWithWidth: arrowWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)
}

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func makeContext(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

/// Draws the full-color icon into ctx (already scaled to the 1024 design canvas, y-down).
func drawIcon(_ ctx: CGContext, shadow: Bool = true) {
    let tilePath = CGPath(roundedRect: tile, cornerWidth: tileRadius, cornerHeight: tileRadius, transform: nil)
    if shadow {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 30, color: color(0x000000, 0.28))
        ctx.addPath(tilePath); ctx.setFillColor(color(0xFF7A45)); ctx.fillPath()
        ctx.restoreGState()
    }
    // Background gradient
    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()
    let bg = CGGradient(colorsSpace: space, colors: [color(0xFFC04D), color(0xFF7E45), color(0xEE4472)] as CFArray, locations: [0, 0.52, 1])!
    let extend: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    ctx.drawLinearGradient(bg, start: CGPoint(x: 300, y: 100), end: CGPoint(x: 724, y: 924), options: extend)
    // Soft top light
    let glow = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.38), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 330, y: 170), startRadius: 0, endCenter: CGPoint(x: 330, y: 170), endRadius: 560, options: [])
    // Subtle bottom depth
    let depth = CGGradient(colorsSpace: space, colors: [color(0x7A1238, 0), color(0x7A1238, 0.22)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(depth, start: CGPoint(x: 512, y: 640), end: CGPoint(x: 512, y: 924), options: extend)
    // Mark with a soft shadow
    ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 26, color: color(0x8A1E2E, 0.35))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    let mark = CGMutablePath()
    mark.addPath(roofPath())
    mark.addPath(cloudPath())
    ctx.addPath(mark)
    ctx.clip(using: .winding)
    let white = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF), color(0xFFEFE4)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(white, start: CGPoint(x: 512, y: 280), end: CGPoint(x: 512, y: 780), options: extend)
    ctx.resetClip()
    // knock the arrow out of the cloud so the tile shows through
    ctx.setBlendMode(.clear)
    ctx.addPath(arrowPath())
    ctx.fillPath()
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

/// Monochrome mark for the menu bar (template image).
func drawTemplate(_ ctx: CGContext) {
    let mark = CGMutablePath()
    mark.addPath(roofPath())
    mark.addPath(cloudPath())
    ctx.addPath(mark)
    ctx.setFillColor(color(0x000000))
    ctx.fillPath(using: .winding)
    ctx.setBlendMode(.clear)
    ctx.addPath(arrowPath())
    ctx.fillPath()
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
let markBox = CGRect(x: 218, y: 236, width: 588, height: 588)
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

func lockup(dark: Bool) -> Data {
    let w = 1600, h = 520
    let ctx = makeContext(w, h)
    ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
    if dark { ctx.setFillColor(color(0x141416)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h)) }
    ctx.saveGState()
    ctx.translateBy(x: 40, y: 20)
    ctx.scaleBy(x: 480 / C, y: 480 / C)
    drawIcon(ctx)
    ctx.restoreGState()
    // Wordmark
    let font = NSFont.systemFont(ofSize: 230, weight: .bold)
    let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 230) } ?? font
    let attr = NSAttributedString(string: "Attic", attributes: [.font: rounded, .foregroundColor: NSColor(cgColor: dark ? color(0xFFFFFF) : color(0x1D1D1F))!, .kern: -4])
    let sub = NSAttributedString(string: "Free up your Mac. Keep everything.", attributes: [
        .font: NSFont.systemFont(ofSize: 54, weight: .medium), .foregroundColor: NSColor(cgColor: dark ? color(0xA1A1A6) : color(0x6E6E73))!])
    NSGraphicsContext.saveGraphicsState()
    let g = NSGraphicsContext(cgContext: ctx, flipped: true)
    NSGraphicsContext.current = g
    attr.draw(at: NSPoint(x: 560, y: 70))
    sub.draw(at: NSPoint(x: 568, y: 345))
    NSGraphicsContext.restoreGraphicsState()
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}
write(lockup(dark: false), "branding/attic-logo-light.png")
write(lockup(dark: true), "branding/attic-logo-dark.png")

// MARK: SVG of the icon (same geometry)
let circles = cloudCircles.map { "<circle cx=\"\(Int($0.0.x))\" cy=\"\(Int($0.0.y))\" r=\"\(Int($0.1))\"/>" }.joined(separator: "\n      ")
let svg = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <title>Attic</title>
  <defs>
    <linearGradient id="bg" x1="300" y1="100" x2="724" y2="924" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#FFC04D"/><stop offset="0.52" stop-color="#FF7E45"/><stop offset="1" stop-color="#EE4472"/>
    </linearGradient>
    <radialGradient id="glow" cx="330" cy="170" r="560" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.38"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="depth" x1="512" y1="640" x2="512" y2="924" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#7A1238" stop-opacity="0"/><stop offset="1" stop-color="#7A1238" stop-opacity="0.22"/>
    </linearGradient>
    <linearGradient id="mark" x1="512" y1="300" x2="512" y2="780" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#FFEFE4"/>
    </linearGradient>
    <mask id="arrowCut" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024">
      <rect width="1024" height="1024" fill="#fff"/>
      <path d="M\(Int(arrowStem.0.x)) \(Int(arrowStem.0.y))V\(Int(arrowStem.1.y))M\(arrowHead.map { "\(Int($0.x)) \(Int($0.y))" }.joined(separator: "L"))" fill="none" stroke="#000" stroke-width="\(Int(arrowWidth))" stroke-linecap="round" stroke-linejoin="round"/>
    </mask>
    <filter id="tileShadow" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="14" stdDeviation="15" flood-color="#000" flood-opacity="0.28"/></filter>
    <filter id="markShadow" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="12" stdDeviation="13" flood-color="#8A1E2E" flood-opacity="0.35"/></filter>
  </defs>
  <g filter="url(#tileShadow)"><rect x="100" y="100" width="824" height="824" rx="186" fill="url(#bg)"/></g>
  <rect x="100" y="100" width="824" height="824" rx="186" fill="url(#glow)"/>
  <rect x="100" y="100" width="824" height="824" rx="186" fill="url(#depth)"/>
  <g filter="url(#markShadow)" fill="url(#mark)" mask="url(#arrowCut)">
    <polyline points="\(roof.map { "\(Int($0.x)),\(Int($0.y))" }.joined(separator: " "))" fill="none" stroke="url(#mark)" stroke-width="\(Int(roofWidth))" stroke-linecap="round" stroke-linejoin="round"/>
    <g>
      \(circles)
      <rect x="\(Int(cloudBase.minX))" y="\(Int(cloudBase.minY))" width="\(Int(cloudBase.width))" height="\(Int(cloudBase.height))" rx="\(Int(cloudRadius))"/>
    </g>
  </g>
</svg>
"""
write(Data(svg.utf8), "branding/attic-icon.svg")
print("rendered")
