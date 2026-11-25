// Builds a made-up sample library for screenshots and recordings, so nothing personal is ever shown.
// Usage: swift branding/demo/make-demo.swift "<demo root>"   (then run make-media.sh for videos/audio)
import AppKit
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let fm = FileManager.default
for d in ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Developer", ".frames"] {
    try? fm.createDirectory(at: root.appendingPathComponent(d), withIntermediateDirectories: true)
}
var overrides: [String: [String: Any]] = [:]
func meta(_ rel: String, size: Int64? = nil, added: Double? = nil, modified: Double? = nil, accessed: Double? = nil,
          from: [String]? = nil, screenshot: Bool? = nil) {
    var m: [String: Any] = [:]
    if let size { m["size"] = size }
    if let added { m["addedDaysAgo"] = added }
    if let modified { m["modifiedDaysAgo"] = modified }
    if let accessed { m["accessedDaysAgo"] = accessed }
    if let from { m["from"] = from }
    if let screenshot { m["screenshot"] = screenshot }
    overrides[rel] = m
}
let MB: Int64 = 1_000_000, GB: Int64 = 1_000_000_000
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

struct RNG { var s: UInt64; mutating func next() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) } }

// MARK: Landscapes

struct Palette { let sky: [UInt32]; let sun: UInt32; let hills: [UInt32]; let water: Bool; let stars: Bool }
let palettes: [String: Palette] = [
    "sunset": Palette(sky: [0x2B1B4F, 0xC2477D, 0xFF9A5A], sun: 0xFFE3A3, hills: [0x8E3B6B, 0x5E2A5C, 0x3A1D45, 0x1E1030], water: false, stars: false),
    "coast": Palette(sky: [0x5FB3E8, 0xA9DDF5, 0xFFE6C7], sun: 0xFFF6DA, hills: [0x6C9FB8, 0x3F7B97, 0x24566F, 0x10354A], water: true, stars: false),
    "alpine": Palette(sky: [0x1D3A6E, 0x5C8FD0, 0xC9E3FF], sun: 0xFFFFFF, hills: [0xB9CDE6, 0x7E9CC4, 0x45658F, 0x22385A], water: false, stars: false),
    "desert": Palette(sky: [0xF6B26B, 0xFAD5A5, 0xFFF1DD], sun: 0xFFF8E7, hills: [0xE39A5C, 0xC97543, 0xA2552E, 0x6E361C], water: false, stars: false),
    "night": Palette(sky: [0x070B24, 0x1B2559, 0x4B3C8F], sun: 0xF2F0FF, hills: [0x2B2E6B, 0x1C1E4D, 0x111232, 0x080919], water: true, stars: true),
    "forest": Palette(sky: [0x9ED8C9, 0xD8F0DF, 0xFFF7E0], sun: 0xFFFDF0, hills: [0x7DB894, 0x4F9672, 0x2D6E52, 0x163F30], water: false, stars: false),
    "dawn": Palette(sky: [0x7B8CDE, 0xF3A7C1, 0xFFD9B8], sun: 0xFFF0E0, hills: [0xB48EC4, 0x8467A8, 0x5A4683, 0x33285A], water: true, stars: false),
]

func landscape(_ p: Palette, seed: UInt64, w: Int = 2400, h: Int = 1600) -> CGImage {
    var r = RNG(s: seed)
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let W = CGFloat(w), H = CGFloat(h)
    let sky = CGGradient(colorsSpace: space, colors: p.sky.map { color($0) } as CFArray, locations: [0, 0.6, 1])!
    ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: H * 0.3), options: [.drawsAfterEndLocation])
    if p.stars {
        for _ in 0..<260 {
            ctx.setFillColor(color(0xFFFFFF, CGFloat(0.3 + r.next() * 0.7)))
            let s = CGFloat(1 + r.next() * 3)
            ctx.fillEllipse(in: CGRect(x: r.next() * W, y: H * 0.45 + r.next() * H * 0.55, width: s, height: s))
        }
    }
    let sunX = W * CGFloat(0.25 + r.next() * 0.5), sunY = H * CGFloat(0.55 + r.next() * 0.15), sunR = H * 0.09
    let glow = CGGradient(colorsSpace: space, colors: [color(p.sun, 0.55), color(p.sun, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: sunX, y: sunY), startRadius: sunR * 0.8, endCenter: CGPoint(x: sunX, y: sunY), endRadius: sunR * 5, options: [])
    ctx.setFillColor(color(p.sun)); ctx.fillEllipse(in: CGRect(x: sunX - sunR, y: sunY - sunR, width: sunR * 2, height: sunR * 2))
    for (i, hc) in p.hills.enumerated() {
        let base = H * (0.62 - CGFloat(i) * 0.12)
        let amp = H * (0.16 - CGFloat(i) * 0.025)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        var y = base + amp * CGFloat(r.next() - 0.5)
        var x: CGFloat = 0
        path.addLine(to: CGPoint(x: 0, y: y))
        let step = W / CGFloat(18 + i * 6)
        while x < W + step {
            x += step
            let ny = base + amp * CGFloat(r.next() - 0.5) * 1.6
            path.addQuadCurve(to: CGPoint(x: x, y: ny), control: CGPoint(x: x - step / 2, y: (y + ny) / 2 + amp * CGFloat(r.next() - 0.3) * 0.8))
            y = ny
        }
        path.addLine(to: CGPoint(x: W, y: 0)); path.closeSubpath()
        ctx.addPath(path); ctx.setFillColor(color(hc)); ctx.fillPath()
        if p.water && i == p.hills.count - 2 {
            let water = CGGradient(colorsSpace: space, colors: [color(p.sky[1], 0.85), color(p.sky[0], 0.95)] as CFArray, locations: [0, 1])!
            ctx.saveGState(); ctx.clip(to: CGRect(x: 0, y: 0, width: W, height: H * 0.22))
            ctx.drawLinearGradient(water, start: CGPoint(x: 0, y: H * 0.22), end: .zero, options: [])
            ctx.setFillColor(color(p.sun, 0.35))
            for k in 0..<14 { ctx.fill(CGRect(x: sunX - CGFloat(60 + k * 9), y: H * 0.2 - CGFloat(k) * H * 0.014, width: CGFloat(120 + k * 18), height: 5)) }
            ctx.restoreGState()
        }
    }
    return ctx.makeImage()!
}

func save(_ img: CGImage, _ rel: String, type: UTType = .jpeg) {
    let url = root.appendingPathComponent(rel)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary)
    CGImageDestinationFinalize(dest)
}

let photos: [(String, String, UInt64, Double, UTType)] = [
    ("Pictures/Lisbon sunset.jpg", "sunset", 11, 40, .jpeg), ("Pictures/Kyoto morning.jpg", "dawn", 12, 400, .jpeg),
    ("Pictures/Big Sur coast.jpg", "coast", 13, 95, .jpeg), ("Pictures/Dolomites hike.jpg", "alpine", 14, 210, .jpeg),
    ("Pictures/Sahara camp.jpg", "desert", 15, 330, .jpeg), ("Pictures/Northern sky.jpg", "night", 16, 150, .jpeg),
    ("Pictures/Black Forest trail.jpg", "forest", 17, 18, .jpeg), ("Pictures/IMG_4821.HEIC", "coast", 21, 6, .heic),
    ("Pictures/IMG_4822.HEIC", "sunset", 22, 6, .heic), ("Pictures/IMG_4907.HEIC", "forest", 23, 3, .heic),
    ("Pictures/IMG_5012.HEIC", "dawn", 24, 1, .heic), ("Pictures/IMG_5013.HEIC", "alpine", 25, 1, .heic),
    ("Pictures/Studio portrait backdrop.jpg", "night", 26, 70, .jpeg), ("Pictures/Album cover draft.jpg", "dawn", 27, 12, .jpeg),
]
for (rel, pal, seed, days, type) in photos {
    save(landscape(palettes[pal]!, seed: seed), rel, type: type)
    meta(rel, size: Int64(3 + seed % 6) * MB + Int64(seed * 137_000), added: days, modified: days)
}
// Frames for the generated videos
for (name, pal, seed) in [("coast", "coast", 31), ("alpine", "alpine", 32), ("sunset", "sunset", 33), ("night", "night", 34),
                          ("forest", "forest", 35), ("desert", "desert", 36), ("dawn", "dawn", 37)] as [(String, String, UInt64)] {
    save(landscape(palettes[pal]!, seed: seed, w: 3840, h: 2160), ".frames/\(name).jpg")
}

// Duplicates: identical bytes in three places
let lisbon = try! Data(contentsOf: root.appendingPathComponent("Pictures/Lisbon sunset.jpg"))
try! lisbon.write(to: root.appendingPathComponent("Downloads/Lisbon sunset (1).jpg"))
try! lisbon.write(to: root.appendingPathComponent("Desktop/Lisbon sunset copy.jpg"))
meta("Downloads/Lisbon sunset (1).jpg", size: 7_400_000, added: 38, modified: 40, from: ["https://scontent.cdninstagram.com/v/t51/lisbon.jpg", "https://www.instagram.com/"])
meta("Desktop/Lisbon sunset copy.jpg", size: 7_400_000, added: 35, modified: 40)
meta("Pictures/Lisbon sunset.jpg", size: 7_400_000, added: 40, modified: 40)

// MARK: Screenshots with readable text

func drawText(_ ctx: CGContext, _ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular,
              color c: NSColor = .black, mono: Bool = false) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: c]).draw(at: NSPoint(x: x, y: y))
    NSGraphicsContext.restoreGraphicsState()
}

func screenshot(_ rel: String, dark: Bool, days: Double, _ body: (CGContext, CGFloat, CGFloat) -> Void) {
    let w = 2880, h = 1800
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(color(dark ? 0x1C1C1E : 0xF2F2F7)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    body(ctx, CGFloat(w), CGFloat(h))
    save(ctx.makeImage()!, rel, type: .png)
    meta(rel, size: Int64(1_800_000 + Int(days) * 11_000), added: days, modified: days, screenshot: true)
}

func card(_ ctx: CGContext, _ r: CGRect, dark: Bool) {
    ctx.setFillColor(color(dark ? 0x2C2C2E : 0xFFFFFF))
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: 36, cornerHeight: 36, transform: nil)); ctx.fillPath()
}

screenshot("Desktop/Screenshot 2026-11-21 at 09.41.12.png", dark: false, days: 4) { ctx, W, H in
    card(ctx, CGRect(x: W / 2 - 700, y: H / 2 - 420, width: 1400, height: 840), dark: false)
    drawText(ctx, "Wi-Fi", W / 2 - 600, H / 2 + 250, size: 84, weight: .bold)
    drawText(ctx, "Network", W / 2 - 600, H / 2 + 100, size: 52, color: .gray)
    drawText(ctx, "Attic Studio 5G", W / 2 - 600, H / 2 + 20, size: 64, weight: .semibold)
    drawText(ctx, "Password", W / 2 - 600, H / 2 - 120, size: 52, color: .gray)
    drawText(ctx, "lisbon-sunset-2026", W / 2 - 600, H / 2 - 210, size: 72, weight: .medium, mono: true)
    drawText(ctx, "Show QR code to share", W / 2 - 600, H / 2 - 340, size: 44, color: .systemBlue)
}
screenshot("Desktop/Screenshot 2026-11-19 at 18.02.55.png", dark: false, days: 6) { ctx, W, H in
    card(ctx, CGRect(x: 360, y: 300, width: W - 720, height: H - 600), dark: false)
    drawText(ctx, "Your order is on the way", 480, H - 520, size: 80, weight: .bold)
    drawText(ctx, "Arrives Thursday, Nov 27", 480, H - 640, size: 56, color: .darkGray)
    drawText(ctx, "Tracking number", 480, H - 820, size: 48, color: .gray)
    drawText(ctx, "1Z 84A 912 03 4471 2209", 480, H - 920, size: 70, weight: .semibold, mono: true)
    drawText(ctx, "Carrier: UPS Ground · 2 items · Ceramic pour-over set", 480, H - 1060, size: 46, color: .darkGray)
}
screenshot("Desktop/Screenshot 2026-11-14 at 21.30.07.png", dark: true, days: 11) { ctx, W, H in
    card(ctx, CGRect(x: 300, y: 260, width: W - 600, height: H - 520), dark: true)
    drawText(ctx, "Launch checklist", 420, H - 460, size: 84, weight: .bold, color: .white)
    for (i, line) in ["✓ Record demo video", "✓ Write README", "○ Post on X at 9am PT", "○ Reply to every comment"].enumerated() {
        drawText(ctx, line, 440, H - 640 - CGFloat(i) * 120, size: 62, color: .white)
    }
}
for (i, (name, days, title)) in [("Screenshot 2026-09-02 at 11.15.40.png", 84.0, "Boarding pass  LIS → SFO  ·  Gate 12  ·  Seat 14A"),
                                  ("Screenshot 2026-08-21 at 16.48.22.png", 96.0, "Q3 revenue  ·  $184,200  ·  up 23% from Q2"),
                                  ("Screenshot 2026-08-03 at 08.02.10.png", 114.0, "Recipe: Pastéis de nata  ·  makes 12"),
                                  ("Screenshot 2026-07-15 at 13.27.54.png", 133.0, "Meeting moved to Friday 3pm")].enumerated() {
    screenshot("Desktop/\(name)", dark: i % 2 == 0, days: days) { ctx, W, H in
        card(ctx, CGRect(x: 400, y: H / 2 - 300, width: W - 800, height: 600), dark: i % 2 == 0)
        drawText(ctx, title, 500, H / 2 - 40, size: 72, weight: .semibold, color: i % 2 == 0 ? .white : .black)
    }
}

// MARK: PDFs

func pdf(_ rel: String, title: String, lines: [String], accent: UInt32) {
    let url = root.appendingPathComponent(rel)
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
    ctx.beginPDFPage(nil)
    ctx.setFillColor(color(accent)); ctx.fill(CGRect(x: 0, y: 712, width: 612, height: 80))
    drawText(ctx, title, 48, 736, size: 26, weight: .bold, color: .white)
    for (i, l) in lines.enumerated() { drawText(ctx, l, 48, 660 - CGFloat(i) * 28, size: 14, color: .darkGray) }
    ctx.setFillColor(color(accent, 0.12)); ctx.fill(CGRect(x: 48, y: 120, width: 516, height: 160))
    ctx.endPDFPage(); ctx.closePDF()
}
pdf("Downloads/Invoice-2026-0412.pdf", title: "Invoice #2026-0412", lines: ["Northwind Studio", "Brand film production", "Amount due: $4,800.00", "Due: Dec 12, 2026"], accent: 0x2563EB)
meta("Downloads/Invoice-2026-0412.pdf", size: 412_000, added: 9, modified: 9, from: ["https://mail-attachment.googleusercontent.com/attachment/u/0/invoice", "https://mail.google.com/mail/u/0/"])
pdf("Downloads/Q3 Board Deck.pdf", title: "Q3 Board Update", lines: ["Revenue up 23%", "Runway 26 months", "Hiring: 4 roles"], accent: 0x7C3AED)
meta("Downloads/Q3 Board Deck.pdf", size: 18 * MB, added: 52, modified: 52, from: ["https://drive.usercontent.google.com/download?id=1x", "https://drive.google.com/"])
pdf("Downloads/Brand guidelines v4.pdf", title: "Brand Guidelines", lines: ["Logo, color, type", "Voice and tone"], accent: 0xF97316)
meta("Downloads/Brand guidelines v4.pdf", size: 42 * MB, added: 75, modified: 75, from: ["https://export-download.canva.com/brand.pdf", "https://www.canva.com/"])
pdf("Downloads/standup-notes.pdf", title: "Standup notes", lines: ["Ship onboarding v2", "Fix sync bug"], accent: 0x4A154B)
meta("Downloads/standup-notes.pdf", size: 220_000, added: 44, modified: 44, from: ["https://files.slack.com/files-pri/T0/notes.pdf", "https://app.slack.com/"])
pdf("Downloads/lease-agreement-signed.pdf", title: "Lease Agreement", lines: ["Signed by both parties"], accent: 0x16A34A)
meta("Downloads/lease-agreement-signed.pdf", size: 2_300_000, added: 120, modified: 120, from: ["https://web.whatsapp.com/"])
pdf("Downloads/flight-itinerary-LIS-SFO.pdf", title: "Your trip", lines: ["Lisbon → San Francisco", "Sep 2, 2026 · 11:40"], accent: 0x0EA5E9)
meta("Downloads/flight-itinerary-LIS-SFO.pdf", size: 680_000, added: 90, modified: 90, from: ["https://www.flytap.com/en-us/booking"])
pdf("Documents/Resume - Alex Rivera.pdf", title: "Alex Rivera", lines: ["Product designer", "10 years · Lisbon"], accent: 0x111827)
meta("Documents/Resume - Alex Rivera.pdf", size: 1_200_000, added: 200, modified: 200)
try! Data(contentsOf: root.appendingPathComponent("Documents/Resume - Alex Rivera.pdf")).write(to: root.appendingPathComponent("Downloads/Resume - Alex Rivera (1).pdf"))
meta("Downloads/Resume - Alex Rivera (1).pdf", size: 1_200_000, added: 61, modified: 200, from: ["https://mail-attachment.googleusercontent.com/attachment/u/0/resume", "https://mail.google.com/mail/u/0/"])
pdf("Documents/Taxes 2025.pdf", title: "2025 Tax Summary", lines: ["Prepared Apr 2026"], accent: 0x059669)
meta("Documents/Taxes 2025.pdf", size: 3_400_000, added: 220, modified: 220)
pdf("Documents/Travel - Lisbon.pdf", title: "Lisbon plan", lines: ["Alfama, Belém, Sintra"], accent: 0xE11D48)
meta("Documents/Travel - Lisbon.pdf", size: 900_000, added: 100, modified: 100)
try! "Month,Rent,Food,Travel\nJan,2100,640,300\nFeb,2100,610,0\n".write(to: root.appendingPathComponent("Documents/Budget 2026.csv"), atomically: true, encoding: .utf8)
meta("Documents/Budget 2026.csv", size: 48_000, added: 30, modified: 2)
try! "# Launch plan\n\n- Record the demo\n- Post the thread\n".write(to: root.appendingPathComponent("Documents/Notes - Launch plan.md"), atomically: true, encoding: .utf8)
meta("Documents/Notes - Launch plan.md", size: 6_000, added: 5, modified: 1)

// Downloads: images with sources
save(landscape(palettes["dawn"]!, seed: 41), "Downloads/ChatGPT Image Nov 3, 2026.png", type: .png)
meta("Downloads/ChatGPT Image Nov 3, 2026.png", size: 2_900_000, added: 22, modified: 22, from: ["https://files.oaiusercontent.com/file-7Q/image.png", "https://chatgpt.com/"])
save(landscape(palettes["desert"]!, seed: 42), "Downloads/canva-poster-final.png", type: .png)
meta("Downloads/canva-poster-final.png", size: 5_100_000, added: 14, modified: 14, from: ["https://export-download.canva.com/poster.png", "https://www.canva.com/"])
save(landscape(palettes["night"]!, seed: 43), "Downloads/thread-cover.png", type: .png)
meta("Downloads/thread-cover.png", size: 1_700_000, added: 3, modified: 3, from: ["https://pbs.twimg.com/media/cover.png", "https://x.com/"])
save(landscape(palettes["forest"]!, seed: 44), "Downloads/podcast-guest-photo.jpg")
meta("Downloads/podcast-guest-photo.jpg", size: 4_400_000, added: 33, modified: 33, from: ["https://s3.us-west-2.amazonaws.com/secure.notion-static.com/guest.jpg", "https://www.notion.so/"])

// Installers and archives: tiny files with real-world sizes in demo.json
func stub(_ rel: String, size: Int64, days: Double, from: [String]) {
    try! Data(repeating: 0x41, count: 4096).write(to: root.appendingPathComponent(rel))
    meta(rel, size: size, added: days, modified: days, from: from)
}
stub("Downloads/Xcode_26.1.xip", size: 7_900 * MB, days: 96, from: ["https://download.developer.apple.com/Developer_Tools/Xcode_26.1.xip", "https://developer.apple.com/download/"])
stub("Downloads/Docker.dmg", size: 1_400 * MB, days: 140, from: ["https://desktop.docker.com/mac/main/arm64/Docker.dmg", "https://www.docker.com/"])
stub("Downloads/Figma-125.1.dmg", size: 312 * MB, days: 63, from: ["https://desktop.figma.com/mac-arm/Figma.dmg", "https://www.figma.com/downloads/"])
stub("Downloads/Slack-4.41.dmg", size: 180 * MB, days: 81, from: ["https://downloads.slack-edge.com/desktop-releases/mac/Slack.dmg", "https://slack.com/downloads"])
stub("Downloads/zoom-installer.pkg", size: 95 * MB, days: 201, from: ["https://zoom.us/client/latest/Zoom.pkg", "https://zoom.us/download"])
stub("Downloads/Notion-4.2.dmg", size: 210 * MB, days: 45, from: ["https://desktop-release.notion-static.com/Notion.dmg", "https://www.notion.so/desktop"])
stub("Downloads/wedding-photos-export.zip", size: 3_800 * MB, days: 58, from: ["https://dl.dropboxusercontent.com/zip/wedding.zip", "https://www.dropbox.com/"])
stub("Downloads/client-assets-final.zip", size: 1_200 * MB, days: 126, from: ["https://drive.usercontent.google.com/download?id=2y", "https://drive.google.com/"])
stub("Downloads/design-system-v2.zip", size: 420 * MB, days: 37, from: ["https://codeload.github.com/acme/design-system/zip/v2", "https://github.com/acme/design-system"])
stub("Downloads/dataset-sample.csv", size: 64 * MB, days: 50, from: ["https://raw.githubusercontent.com/acme/data/main/sample.csv", "https://github.com/acme/data"])

// Developer junk folders (sizes come from demo.json)
let junk: [[String: Any]] = [
    ["path": "Developer/storefront-web/node_modules", "title": "storefront-web ▸ node_modules", "detail": "npm dependencies · ~/Developer/storefront-web", "group": "projects", "bytes": 1_840 * MB, "lastUsedDaysAgo": 64, "recommended": true],
    ["path": "Developer/ios-client/build", "title": "ios-client ▸ build", "detail": "Xcode build output · ~/Developer/ios-client", "group": "projects", "bytes": 4_600 * MB, "lastUsedDaysAgo": 45, "recommended": true],
    ["path": "Developer/ml-experiments/.venv", "title": "ml-experiments ▸ .venv", "detail": "Python environment · ~/Developer/ml-experiments", "group": "projects", "bytes": 2_300 * MB, "lastUsedDaysAgo": 92, "recommended": true],
    ["path": "Developer/mobile-app/node_modules", "title": "mobile-app ▸ node_modules", "detail": "npm dependencies · ~/Developer/mobile-app", "group": "projects", "bytes": 1_210 * MB, "lastUsedDaysAgo": 6, "recommended": false],
    ["path": "Developer/landing-page/node_modules", "title": "landing-page ▸ node_modules", "detail": "npm dependencies · ~/Developer/landing-page", "group": "projects", "bytes": 640 * MB, "lastUsedDaysAgo": 140, "recommended": true],
    ["path": "Developer/dashboard/.next", "title": "dashboard ▸ .next", "detail": "Next.js build cache · ~/Developer/dashboard", "group": "projects", "bytes": 380 * MB, "lastUsedDaysAgo": 33, "recommended": true],
    ["path": "Developer/.caches/DerivedData", "title": "Xcode build cache", "detail": "~/Library/Developer/Xcode/DerivedData", "group": "devCaches", "bytes": 6_800 * MB, "recommended": true],
    ["path": "Developer/.caches/npm", "title": "npm cache", "detail": "~/.npm/_cacache", "group": "devCaches", "bytes": 2_100 * MB, "recommended": true],
    ["path": "Developer/.caches/huggingface", "title": "Hugging Face models (re-download when used)", "detail": "~/.cache/huggingface", "group": "devCaches", "bytes": 4_500 * MB, "recommended": false],
    ["path": "Developer/.caches/Homebrew", "title": "Homebrew downloads", "detail": "~/Library/Caches/Homebrew", "group": "devCaches", "bytes": 1_300 * MB, "recommended": true],
    ["path": "Developer/.caches/spotify", "title": "Spotify cache", "detail": "~/Library/Caches/com.spotify.client", "group": "appCaches", "bytes": 1_900 * MB, "recommended": true],
    ["path": "Developer/.caches/figma", "title": "Figma", "detail": "~/Library/Caches/com.figma.Desktop", "group": "appCaches", "bytes": 450 * MB, "recommended": true],
    ["path": "Developer/.caches/whatsapp", "title": "WhatsApp media", "detail": "~/Library/Group Containers/…WhatsApp.shared", "group": "appData", "bytes": 13_000 * MB, "recommended": false],
    ["path": "Developer/.caches/slack", "title": "Slack", "detail": "~/Library/Application Support/Slack", "group": "appData", "bytes": 2_400 * MB, "recommended": false],
]
for j in junk { try? fm.createDirectory(at: root.appendingPathComponent(j["path"] as! String), withIntermediateDirectories: true) }

// Videos & music metadata (files come from make-media.sh)
meta("Movies/Drone - Coast 4K.mov", size: 21_700 * MB, added: 300, modified: 300, accessed: 280)
meta("Movies/Kyoto timelapse.mov", size: 3_200 * MB, added: 400, modified: 400, accessed: 390)
meta("Movies/Wedding film final.mov", size: 8_400 * MB, added: 220, modified: 220, accessed: 200)
meta("Movies/Wedding film final copy.mov", size: 8_400 * MB, added: 210, modified: 220, accessed: 210)
meta("Movies/Product demo v3.mp4", size: 640 * MB, added: 30, modified: 30)
meta("Movies/Screen Recording 2026-11-18 at 14.22.05.mov", size: 2_100 * MB, added: 7, modified: 7, screenshot: false)
meta("Movies/Lisbon trip.mp4", added: 40, modified: 40)
meta("Movies/Studio session raw.mov", added: 26, modified: 26)
meta("Music/Late night demo v3.mp3", size: 9 * MB, added: 12, modified: 12)
meta("Music/Podcast ep 12 - final.m4a", size: 68 * MB, added: 20, modified: 20)
meta("Music/Field recording - Lisbon tram.wav", size: 210 * MB, added: 41, modified: 41)
meta("Music/Voice memo - melody idea.m4a", size: 4 * MB, added: 2, modified: 2)

let manifest: [String: Any] = ["files": overrides, "junk": junk]
let json = try! JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
try! json.write(to: root.appendingPathComponent("demo.json"))
print("demo library at \(root.path): \(overrides.count) files described")
