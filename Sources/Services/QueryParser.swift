import Foundation

/// One piece of a plain-English search, shown to the user as a removable chip.
enum SearchChip: Hashable, Identifiable {
    case category(FileCategory)
    case exts(String, [String])
    case screenshots
    case iphone
    case dateRange(String, Date?, Date?)
    case olderThan(String, Date)
    case minSize(Int64)
    case maxSize(Int64)
    case source(String)
    case text(String)

    var id: String { label + "|" + kindKey }

    var kindKey: String {
        switch self {
        case .category, .exts, .screenshots, .iphone: return "type"
        case .dateRange, .olderThan: return "date"
        case .minSize, .maxSize: return "size"
        case .source: return "source"
        case .text: return "text"
        }
    }

    var isType: Bool { kindKey == "type" }

    var label: String {
        switch self {
        case .category(let c): return c.title
        case .exts(let label, _): return label
        case .screenshots: return "Screenshots"
        case .iphone: return "From iPhone"
        case .dateRange(let l, _, _): return l
        case .olderThan(let l, _): return l
        case .minSize(let n): return "Over \(Fmt.bytes(n))"
        case .maxSize(let n): return "Under \(Fmt.bytes(n))"
        case .source(let s): return "From \(s)"
        case .text(let t): return "“\(t)”"
        }
    }

    var symbol: String {
        switch self {
        case .category(let c): return c.symbol
        case .exts: return "doc"
        case .screenshots: return "camera.viewfinder"
        case .iphone: return "iphone"
        case .dateRange, .olderThan: return "calendar"
        case .minSize, .maxSize: return "scalemass"
        case .source(let s): return DownloadSource.symbol(for: s)
        case .text: return "text.magnifyingglass"
        }
    }

    func matches(_ it: FileItem, ocr: String?) -> Bool {
        switch self {
        case .category(let c): return it.category == c
        case .exts(_, let exts): return exts.contains(it.ext)
        case .screenshots: return it.isScreenshot
        case .iphone:
            return it.category != .apps && (it.ext == "heic" || it.ext == "heif" || it.name.hasPrefix("IMG_") || it.name.hasPrefix("VID_"))
        case .dateRange(_, let from, let to):
            let candidates = [it.arrivalDate, it.modified]
            return candidates.contains { d in (from.map { d >= $0 } ?? true) && (to.map { d < $0 } ?? true) }
        case .olderThan(_, let cutoff):
            return it.modified < cutoff && it.arrivalDate < cutoff
        case .minSize(let n): return it.spaceOnDisk >= n
        case .maxSize(let n): return it.spaceOnDisk <= n
        case .source(let s):
            if let src = it.source, src.caseInsensitiveCompare(s) == .orderedSame { return true }
            return it.whereFroms.contains { $0.lowercased().contains(s.lowercased()) }
        case .text(let t):
            let words = t.split(separator: " ").map(String.init)
            return words.allSatisfy { w -> Bool in
                let compact = String(w.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
                return it.lowerName.contains(w) || (ocr?.contains(w) ?? false) || (!compact.isEmpty && (ocr?.contains(compact) ?? false))
                    || it.folderName.lowercased().contains(w) || (it.source?.lowercased().contains(w) ?? false)
            }
        }
    }
}

struct SearchQuery: Equatable {
    var chips: [SearchChip] = []
    var isEmpty: Bool { chips.isEmpty }
    var wantsOCR: Bool { chips.contains { if case .text = $0 { return true } else { return false } } }

    func matches(_ it: FileItem, ocr: String?) -> Bool {
        let types = chips.filter(\.isType)
        if !types.isEmpty && !types.contains(where: { $0.matches(it, ocr: ocr) }) { return false }
        for c in chips where !c.isType {
            if !c.matches(it, ocr: ocr) { return false }
        }
        return true
    }

    func removing(_ chip: SearchChip) -> SearchQuery {
        SearchQuery(chips: chips.filter { $0 != chip })
    }
}

enum QueryParser {
    static let stopwords: Set<String> = [
        "my", "the", "a", "an", "of", "with", "and", "or", "in", "on", "from", "files", "file", "all", "show", "me",
        "find", "that", "are", "were", "is", "which", "any", "some", "containing", "called", "named", "i", "downloaded",
        "got", "saved", "sent", "received", "to", "for", "at", "by", "ago", "during", "than", "stuff", "things", "made",
        "taken", "were", "was", "please", "everything", "where", "has", "have",
    ]

    static let typeWords: [String: SearchChip] = {
        var m: [String: SearchChip] = [:]
        func add(_ words: [String], _ chip: SearchChip) { for w in words { m[w] = chip } }
        add(["pdf", "pdfs"], .exts("PDF", ["pdf"]))
        add(["image", "images", "photo", "photos", "picture", "pictures", "pic", "pics", "img", "imgs"], .category(.images))
        add(["png", "pngs"], .exts("PNG", ["png"]))
        add(["jpg", "jpgs", "jpeg", "jpegs"], .exts("JPEG", ["jpg", "jpeg"]))
        add(["heic"], .exts("HEIC", ["heic", "heif"]))
        add(["gif", "gifs"], .exts("GIF", ["gif"]))
        add(["svg", "svgs"], .exts("SVG", ["svg"]))
        add(["webp"], .exts("WebP", ["webp"]))
        add(["video", "videos", "movie", "movies", "clip", "clips", "recording", "recordings", "footage"], .category(.videos))
        add(["mp4", "mp4s"], .exts("MP4", ["mp4", "m4v"]))
        add(["mov", "movs"], .exts("MOV", ["mov"]))
        add(["mkv"], .exts("MKV", ["mkv"]))
        add(["music", "song", "songs", "audio", "track", "tracks", "podcast", "podcasts", "voice", "memos"], .category(.music))
        add(["mp3", "mp3s"], .exts("MP3", ["mp3"]))
        add(["wav"], .exts("WAV", ["wav"]))
        add(["m4a"], .exts("M4A", ["m4a"]))
        add(["doc", "docs", "document", "documents"], .category(.documents))
        add(["word", "docx"], .exts("Word", ["doc", "docx"]))
        add(["spreadsheet", "spreadsheets", "excel", "sheet", "sheets", "xlsx", "xls", "csv", "csvs"], .exts("Spreadsheets", ["xls", "xlsx", "csv", "numbers", "tsv", "ods"]))
        add(["presentation", "presentations", "slides", "deck", "decks", "keynote", "pptx", "ppt"], .exts("Presentations", ["key", "ppt", "pptx", "odp"]))
        add(["zip", "zips"], .exts("ZIP", ["zip"]))
        add(["archive", "archives", "compressed"], .category(.archives))
        add(["dmg", "dmgs", "installer", "installers", "pkg", "pkgs"], .exts("Installers", ["dmg", "pkg", "mpkg", "iso", "xip"]))
        add(["app", "apps", "application", "applications"], .category(.apps))
        add(["screenshot", "screenshots", "screengrab", "screengrabs", "screencap", "screencaps"], .screenshots)
        add(["font", "fonts", "ttf", "otf"], .exts("Fonts", ["ttf", "otf", "woff", "woff2"]))
        add(["ebook", "ebooks", "epub", "book", "books"], .exts("Books", ["epub", "mobi", "azw3"]))
        return m
    }()

    static let sourceWords: [String: String] = [
        "gmail": "Gmail", "email": "Gmail", "mail": "Gmail", "drive": "Google Drive", "gdrive": "Google Drive",
        "chatgpt": "ChatGPT", "openai": "ChatGPT", "claude": "Claude", "canva": "Canva", "twitter": "X",
        "slack": "Slack", "whatsapp": "WhatsApp", "github": "GitHub", "telegram": "Telegram", "discord": "Discord",
        "notion": "Notion", "figma": "Figma", "dropbox": "Dropbox", "youtube": "YouTube", "instagram": "Instagram",
        "linkedin": "LinkedIn", "extension": "Extensions", "extensions": "Extensions", "r2": "Cloudflare R2",
    ]

    static let months: [String: Int] = [
        "january": 1, "jan": 1, "february": 2, "feb": 2, "march": 3, "mar": 3, "april": 4, "apr": 4, "may": 5,
        "june": 6, "jun": 6, "july": 7, "jul": 7, "august": 8, "aug": 8, "september": 9, "sep": 9, "sept": 9,
        "october": 10, "oct": 10, "november": 11, "nov": 11, "december": 12, "dec": 12,
    ]

    static func parse(_ raw: String, now: Date = Date()) -> SearchQuery {
        var cleaned = raw.lowercased()
        // Quoted phrases become literal text.
        var quoted: [String] = []
        while let start = cleaned.firstIndex(where: { $0 == "\"" || $0 == "“" }),
              let end = cleaned[cleaned.index(after: start)...].firstIndex(where: { $0 == "\"" || $0 == "”" }) {
            let phrase = String(cleaned[cleaned.index(after: start)..<end]).trimmingCharacters(in: .whitespaces)
            if !phrase.isEmpty { quoted.append(phrase) }
            cleaned.removeSubrange(start...end)
        }
        let tokens = cleaned
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "?", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        var chips: [SearchChip] = []
        var text: [String] = []
        var i = 0
        while i < tokens.count {
            if let (chip, used) = matchSize(tokens, i) {
                chips.append(chip); i += used; continue
            }
            if let (chip, used) = matchDate(tokens, i, now: now) {
                chips.append(chip); i += used; continue
            }
            if let (chip, used) = matchSource(tokens, i) {
                chips.append(chip); i += used; continue
            }
            if let chip = typeWords[tokens[i]] {
                if !chips.contains(chip) { chips.append(chip) }
                i += 1; continue
            }
            if stopwords.contains(tokens[i]) { i += 1; continue }
            text.append(tokens[i])
            i += 1
        }
        for q in quoted { chips.append(.text(q)) }
        if !text.isEmpty { chips.append(.text(text.joined(separator: " "))) }
        return SearchQuery(chips: chips)
    }

    // MARK: Size

    static func matchSize(_ t: [String], _ i: Int) -> (SearchChip, Int)? {
        let w = t[i]
        if w == "big" || w == "large" || w == "biggest" || w == "largest" { return (.minSize(100_000_000), 1) }
        if w == "huge" || w == "massive" { return (.minSize(1_000_000_000), 1) }
        if w == "small" || w == "tiny" { return (.maxSize(1_000_000), 1) }

        let minWords: Set<String> = ["over", "above", "bigger", "larger", "greater", "more", ">", ">=", "least", "min"]
        let maxWords: Set<String> = ["under", "below", "smaller", "less", "<", "<=", "most", "max", "upto"]
        var j = i
        var isMin: Bool?
        if minWords.contains(w) { isMin = true } else if maxWords.contains(w) { isMin = false }
        if w == "at", i + 1 < t.count { // "at least" / "at most"
            if t[i + 1] == "least" { isMin = true; j += 1 } else if t[i + 1] == "most" { isMin = false; j += 1 }
        }
        if w == "up", i + 1 < t.count, t[i + 1] == "to" { isMin = false; j += 1 }
        guard let min = isMin else {
            // a bare "5mb" with no comparator means "about that size or bigger"
            if let (bytes, used) = number(t, i, requireUnit: true) { return (.minSize(bytes), used) }
            return nil
        }
        j += 1
        if j < t.count, t[j] == "than" { j += 1 }
        guard j < t.count, let (bytes, used) = number(t, j, requireUnit: false) else { return nil }
        return (min ? .minSize(bytes) : .maxSize(bytes), j - i + used)
    }

    static let sizeUnits: [String: Int64] = [
        "b": 1, "byte": 1, "bytes": 1, "k": 1_000, "kb": 1_000, "m": 1_000_000, "mb": 1_000_000, "meg": 1_000_000,
        "megs": 1_000_000, "g": 1_000_000_000, "gb": 1_000_000_000, "gig": 1_000_000_000, "gigs": 1_000_000_000,
        "t": 1_000_000_000_000, "tb": 1_000_000_000_000,
    ]

    static func number(_ t: [String], _ i: Int, requireUnit: Bool) -> (Int64, Int)? {
        let w = t[i]
        let digits = w.prefix { $0.isNumber || $0 == "." }
        guard !digits.isEmpty, let value = Double(digits) else { return nil }
        let rest = String(w.dropFirst(digits.count))
        if !rest.isEmpty {
            guard let unit = sizeUnits[rest] else { return nil }
            return (Int64(value * Double(unit)), 1)
        }
        if i + 1 < t.count, let unit = sizeUnits[t[i + 1]] {
            return (Int64(value * Double(unit)), 2)
        }
        if requireUnit { return nil }
        if i + 1 < t.count, timeUnit(t[i + 1]) != nil { return nil }
        return (Int64(value * 1_000_000), 1) // default MB
    }

    // MARK: Dates

    static func timeUnit(_ w: String) -> Calendar.Component? {
        switch w {
        case "day", "days", "d": return .day
        case "week", "weeks", "wk", "wks", "w": return .weekOfYear
        case "month", "months", "mo", "mos": return .month
        case "year", "years", "yr", "yrs", "y": return .year
        case "hour", "hours", "hr", "hrs": return .hour
        default: return nil
        }
    }

    static func matchDate(_ t: [String], _ i: Int, now: Date) -> (SearchChip, Int)? {
        let cal = Calendar.current
        let w = t[i]
        let next = i + 1 < t.count ? t[i + 1] : ""
        let startOfToday = cal.startOfDay(for: now)

        func start(of comp: Calendar.Component, _ d: Date) -> Date {
            cal.dateInterval(of: comp, for: d)?.start ?? d
        }

        switch w {
        case "today": return (.dateRange("Today", startOfToday, nil), 1)
        case "yesterday": return (.dateRange("Yesterday", cal.date(byAdding: .day, value: -1, to: startOfToday), startOfToday), 1)
        case "recent", "recently", "new", "newest", "latest": return (.dateRange("Past 2 weeks", cal.date(byAdding: .day, value: -14, to: now), nil), 1)
        default: break
        }

        if (w == "this" || w == "last" || w == "past" || w == "previous") && !next.isEmpty {
            let unitMap: [String: Calendar.Component] = ["week": .weekOfYear, "month": .month, "year": .year]
            if let comp = unitMap[next] {
                let label = next.capitalized
                if w == "this" { return (.dateRange("This \(next)", start(of: comp, now), nil), 2) }
                let thisStart = start(of: comp, now)
                guard let prevStart = cal.date(byAdding: comp, value: -1, to: thisStart) else { return nil }
                if comp == .year { return (.dateRange("Last year", prevStart, thisStart), 2) }
                return (.dateRange("Since last \(label.lowercased())", prevStart, nil), 2)
            }
            // "last 3 days", "past 2 weeks"
            if i + 2 < t.count, let n = Int(next), let comp = timeUnit(t[i + 2]),
               let from = cal.date(byAdding: comp, value: -n, to: now) {
                return (.dateRange("Past \(n) \(t[i + 2])", from, nil), 3)
            }
        }

        // "older than 6 months", "over 2 years old" (only "older than" to avoid clashing with sizes)
        if w == "older" || w == "before" && Int(next) != nil && timeUnit(i + 2 < t.count ? t[i + 2] : "") != nil {
            var j = i + 1
            if j < t.count, t[j] == "than" { j += 1 }
            if j + 1 < t.count, let n = Int(t[j]), let comp = timeUnit(t[j + 1]),
               let cutoff = cal.date(byAdding: comp, value: -n, to: now) {
                return (.olderThan("Older than \(n) \(t[j + 1])", cutoff), j + 2 - i)
            }
            if j < t.count, let (from, _, label) = monthOrYear(t, j, now: now) {
                _ = label
                return (.olderThan("Before \(label)", from), j + 1 - i)
            }
        }
        if w == "newer", i + 3 < t.count, t[i + 1] == "than", let n = Int(t[i + 2]), let comp = timeUnit(t[i + 3]),
           let from = cal.date(byAdding: comp, value: -n, to: now) {
            return (.dateRange("Newer than \(n) \(t[i + 3])", from, nil), 4)
        }
        if (w == "before" || w == "after" || w == "since"), !next.isEmpty, let (from, to, label) = monthOrYear(t, i + 1, now: now) {
            if w == "before" { return (.olderThan("Before \(label)", from), 2) }
            return (.dateRange("Since \(label)", w == "after" ? to : from, nil), 2)
        }
        // "3 days ago" → past 3 days
        if let n = Int(w), let comp = timeUnit(next), i + 2 < t.count, t[i + 2] == "ago",
           let from = cal.date(byAdding: comp, value: -(n + 1), to: now), let to = cal.date(byAdding: comp, value: -(n - 1), to: now) {
            return (.dateRange("About \(n) \(next) ago", from, to), 3)
        }
        if let (from, to, label) = monthOrYear(t, i, now: now) {
            let used = (months[w] != nil && i + 1 < t.count && Int(t[i + 1]).map { $0 > 1900 && $0 < 2200 } == true) ? 2 : 1
            return (.dateRange(label, from, to), used)
        }
        return nil
    }

    /// "august", "aug 2025", "2024"
    static func monthOrYear(_ t: [String], _ i: Int, now: Date) -> (Date, Date, String)? {
        let cal = Calendar.current
        let w = t[i]
        if let m = months[w] {
            var year = cal.component(.year, from: now)
            if i + 1 < t.count, let y = Int(t[i + 1]), y > 1900, y < 2200 {
                year = y
            } else if m > cal.component(.month, from: now) {
                year -= 1
            }
            guard let from = cal.date(from: DateComponents(year: year, month: m, day: 1)),
                  let to = cal.date(byAdding: .month, value: 1, to: from) else { return nil }
            let name = cal.monthSymbols[m - 1]
            let label = year == cal.component(.year, from: now) ? name : "\(name) \(year)"
            return (from, to, label)
        }
        if let y = Int(w), y > 1990, y < 2200, w.count == 4 {
            guard let from = cal.date(from: DateComponents(year: y, month: 1, day: 1)),
                  let to = cal.date(byAdding: .year, value: 1, to: from) else { return nil }
            return (from, to, String(y))
        }
        return nil
    }

    // MARK: Sources

    static func matchSource(_ t: [String], _ i: Int) -> (SearchChip, Int)? {
        let w = t[i]
        var j = i
        let lead: Set<String> = ["from", "via", "on", "off"]
        if lead.contains(w) { j += 1 }
        guard j < t.count else { return nil }
        if t[j] == "my", j + 1 < t.count { j += 1 }
        let word = t[j]
        if word == "iphone" || word == "phone" || word == "camera" { return (.iphone, j - i + 1) }
        if word == "google", j + 1 < t.count, t[j + 1] == "drive" { return (.source("Google Drive"), j - i + 2) }
        if lead.contains(w), word == "x" { return (.source("X"), j - i + 1) }
        if let s = sourceWords[word] {
            // bare source words only count when they're clearly a source ("gmail pdfs"), "mail" alone is too vague
            if !lead.contains(w) && (word == "mail" || word == "email" || word == "drive" || word == "extension") { return nil }
            return (.source(s), j - i + 1)
        }
        if lead.contains(w), word.contains("."), !word.hasPrefix("."), word.split(separator: ".").count >= 2 {
            return (.source(DownloadSource.registrableDomain(word)), j - i + 1)
        }
        return nil
    }
}
