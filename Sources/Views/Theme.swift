import SwiftUI

// MARK: - Looks

/// Two looks: soft colour (Playful) or black, white and grey (Minimal). ⌃⌘T switches.
enum Look: String, CaseIterable, Identifiable {
    case playful, minimal
    var id: String { rawValue }
    var title: String { self == .playful ? "Playful" : "Minimal" }
    var symbol: String { self == .playful ? "paintpalette" : "circle.lefthalf.filled" }

    static var current: Look { Look(rawValue: UserDefaults.standard.string(forKey: Prefs.look) ?? "") ?? .playful }

    static func toggle() {
        UserDefaults.standard.set((current == .playful ? Look.minimal : .playful).rawValue, forKey: Prefs.look)
    }
}

extension FileCategory {
    /// The soft colour used for this kind of file in the Playful look.
    var pastel: Color {
        switch self {
        case .images: return Color(red: 0.98, green: 0.42, blue: 0.62)
        case .videos: return Color(red: 0.55, green: 0.45, blue: 0.98)
        case .music: return Color(red: 1.00, green: 0.56, blue: 0.28)
        case .documents: return Color(red: 0.26, green: 0.55, blue: 0.98)
        case .archives: return Color(red: 0.93, green: 0.68, blue: 0.16)
        case .apps: return Color(red: 0.16, green: 0.72, blue: 0.66)
        case .other: return Color(red: 0.55, green: 0.58, blue: 0.64)
        }
    }
}

enum Palette {
    static let folderBlue = Color(red: 0.30, green: 0.60, blue: 0.98)
    static let good = Color(red: 0.13, green: 0.68, blue: 0.38)

    /// A stable soft colour for anything with a name (download sources, cards).
    static func tint(for name: String) -> Color {
        let options: [Color] = [FileCategory.images.pastel, FileCategory.videos.pastel, FileCategory.music.pastel,
                                FileCategory.documents.pastel, FileCategory.archives.pastel, FileCategory.apps.pastel]
        let n = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
        return options[n % options.count]
    }
}

// MARK: - Folder card shape

/// A folder silhouette: a tab on the top left, then the body.
struct FolderShape: Shape {
    var radius: CGFloat = 14
    var tabFraction: CGFloat = 0.34
    var tabHeight: CGFloat = 11

    func path(in r: CGRect) -> Path {
        let rad = min(radius, r.height / 4)
        let tw = max(54, r.width * tabFraction)
        let th = tabHeight
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY - rad))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.minX + tw, y: r.minY), radius: rad)
        p.addLine(to: CGPoint(x: r.minX + tw - th * 0.8, y: r.minY))
        p.addCurve(to: CGPoint(x: r.minX + tw + th * 0.5, y: r.minY + th),
                   control1: CGPoint(x: r.minX + tw - th * 0.15, y: r.minY),
                   control2: CGPoint(x: r.minX + tw - th * 0.05, y: r.minY + th))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY + th), tangent2End: CGPoint(x: r.maxX, y: r.maxY), radius: rad)
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY), radius: rad)
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.minY), radius: rad)
        p.closeSubpath()
        return p
    }
}

/// A soft coloured folder card (Playful).
struct PastelFolder<Content: View>: View {
    let tint: Color
    var selected = false
    @ViewBuilder var content: () -> Content
    @State private var hover = false

    var body: some View {
        content()
            .padding(.horizontal, 14)
            .padding(.top, 22)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    FolderShape().fill(tint.opacity(0.26))
                    // The front flap, a little lighter, like a real folder.
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(LinearGradient(colors: [tint.opacity(0.16), tint.opacity(0.10)], startPoint: .top, endPoint: .bottom))
                        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.background))
                        .padding(.top, 9)
                }
            }
            .overlay {
                FolderShape().stroke(selected ? Color.accentColor : tint.opacity(hover ? 0.55 : 0.32), lineWidth: selected ? 2 : 1)
            }
            .shadow(color: tint.opacity(hover ? 0.22 : 0.08), radius: hover ? 10 : 4, y: hover ? 4 : 2)
            .scaleEffect(hover ? 1.01 : 1)
            .animation(.easeOut(duration: 0.15), value: hover)
            .onHover { hover = $0 }
    }
}

/// A grey folder with a few files peeking out of it (Minimal).
struct PeekFolderIcon: View {
    let samples: [URL]
    var width: CGFloat = 96

    var body: some View {
        let h = width * 0.72
        ZStack(alignment: .bottom) {
            FolderShape(radius: 8, tabFraction: 0.38, tabHeight: width * 0.08)
                .fill(Color.primary.opacity(0.42))
                .frame(width: width, height: h)
            HStack(spacing: -width * 0.12) {
                ForEach(Array(samples.prefix(3).enumerated()), id: \.offset) { i, u in
                    ThumbView(url: u, side: width * 0.6, plain: true, fill: true)
                        .frame(width: width * 0.36, height: width * 0.42)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.white.opacity(0.7), lineWidth: 1))
                        .rotationEffect(.degrees(Double(i - 1) * 6))
                        .offset(y: i == 1 ? -4 : 0)
                }
            }
            .frame(height: h * 0.8, alignment: .top)
            .offset(y: -h * 0.22)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.55))
                .frame(width: width, height: h * 0.62)
        }
        .frame(width: width, height: h)
    }
}

// MARK: - Small pieces

/// A key on the keyboard, for shortcut hints like ⌘ F.
struct KeyCap: View {
    let key: String
    init(_ key: String) { self.key = key }
    var body: some View {
        Text(key)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(minWidth: 17, minHeight: 17)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.14)))
    }
}

struct CountPill: View {
    let count: Int
    var body: some View {
        Text(Fmt.count(count))
            .font(.caption.weight(.semibold)).monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Color.primary.opacity(0.07), in: Capsule())
    }
}

/// "Free up to 14 GB": green in Playful, black in Minimal.
struct GoodPill: View {
    let text: String
    @AppStorage(Prefs.look) private var look = Look.playful.rawValue
    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(look == Look.minimal.rawValue ? Color(nsColor: .windowBackgroundColor) : .white)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(look == Look.minimal.rawValue ? Color.primary : Palette.good, in: Capsule())
    }
}

/// Section title used on Home and in folders: "Library 6 ··· See all →"
struct ShelfTitle<Accessory: View>: View {
    let title: String
    var count: Int? = nil
    var seeAll: (() -> Void)? = nil
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.title3.weight(.medium))
            if let count { CountPill(count: count) }
            accessory()
            Spacer()
            if let seeAll {
                Button(action: seeAll) {
                    HStack(spacing: 3) { Text("See all"); Image(systemName: "arrow.right") }.font(.callout)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
    }
}

extension ShelfTitle where Accessory == EmptyView {
    init(title: String, count: Int? = nil, seeAll: (() -> Void)? = nil) {
        self.init(title: title, count: count, seeAll: seeAll, accessory: { EmptyView() })
    }
}

/// Overlapping round thumbnails, like avatars, with "+N" for the rest.
struct AvatarStack: View {
    let urls: [URL]
    var extra: Int = 0
    var size: CGFloat = 24

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(Array(urls.prefix(3).enumerated()), id: \.offset) { _, u in
                ThumbView(url: u, side: size * 2, plain: true, fill: true)
                    .frame(width: size, height: size)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
            }
            if extra > 0 {
                Text("+\(min(extra, 99))")
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: size, minHeight: size)
                    .background(Color(nsColor: .windowBackgroundColor), in: Circle())
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.12)))
            }
        }
    }
}

/// A rounded icon in a soft circle, used on cards.
struct IconBubble: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 30
    @AppStorage(Prefs.look) private var look = Look.playful.rawValue

    var body: some View {
        let t = look == Look.minimal.rawValue ? Color.primary : tint
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .medium))
            .foregroundStyle(t.opacity(0.9))
            .frame(width: size, height: size)
            .background(t.opacity(0.13), in: Circle())
    }
}

/// A filter as a small rounded menu: "Date: Any ⌄".
struct FilterPill<Content: View>: View {
    let label: String
    let value: String
    var active = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        Menu(content: content) {
            HStack(spacing: 4) {
                Text("\(label):").foregroundStyle(.secondary)
                Text(value).foregroundStyle(active ? Color.accentColor : .primary)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            .font(.callout)
            .lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
            .overlay(Capsule().strokeBorder(active ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.12)))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// Soft coloured card (Clean Up, Downloaded From) that turns grey in the Minimal look.
struct SoftCard: ViewModifier {
    let tint: Color
    var strong = true
    @AppStorage(Prefs.look) private var look = Look.playful.rawValue
    @State private var hover = false

    func body(content: Content) -> some View {
        let minimal = look == Look.minimal.rawValue
        let t = minimal ? Color.primary : tint
        content
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [t.opacity(minimal ? 0.03 : (strong ? 0.13 : 0.06)), t.opacity(minimal ? 0.03 : (strong ? 0.07 : 0.03))],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            }
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(t.opacity(hover ? 0.45 : (minimal ? 0.12 : 0.25))))
            .shadow(color: .black.opacity(hover ? 0.08 : 0.03), radius: hover ? 8 : 3, y: 2)
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.15), value: hover)
    }
}

extension View {
    func softCard(_ tint: Color, strong: Bool = true) -> some View { modifier(SoftCard(tint: tint, strong: strong)) }
}

/// The two-button look switcher in the top bar.
struct LookSwitcher: View {
    @AppStorage(Prefs.look) private var look = Look.playful.rawValue
    var body: some View {
        Picker("Look", selection: $look) {
            ForEach(Look.allCases) { l in
                Image(systemName: l.symbol).help("\(l.title) look (⌃⌘T)").tag(l.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}
