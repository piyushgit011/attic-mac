import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple Intelligence, on this Mac only. When a search has words the rule-based parser can't place
/// ("the invoice my accountant emailed me"), Apple's on-device language model turns it into filters.
/// Nothing is sent anywhere: the model runs locally through the FoundationModels framework.
enum LocalAI {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    static var statusText: String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return "Apple Intelligence is on. Searches it helps with never leave this Mac."
            case .unavailable(let reason): return "Apple Intelligence isn’t available (\(reason)). Search still works with Attic’s own rules."
            @unknown default: return "Apple Intelligence status unknown."
            }
        }
        #endif
        return "Needs macOS 26 with Apple Intelligence. Search still works with Attic’s own rules."
    }

    /// Should this search be handed to the on-device model?
    static func shouldAsk(_ q: SearchQuery) -> Bool {
        guard isAvailable else { return false }
        for c in q.chips { if case .text(let t) = c, t.split(separator: " ").count >= 3 { return true } }
        return false
    }

    /// Asks the on-device model to read a request. Returns nil if unavailable or it can't help.
    static func understand(_ text: String, rules: SearchQuery) async -> SearchQuery? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard isAvailable else { return nil }
            let session = LanguageModelSession(instructions: """
                You turn a person's description of a file on their Mac into search filters.
                Only fill a field when the request clearly says it. Keep `words` to the distinctive words \
                someone would find in the file name or inside the file (no filler like "the", "my", "file").
                """)
            do {
                let r = try await session.respond(to: text, generating: AIQuery.self)
                return merge(r.content, rules: rules, said: text.lowercased())
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func merge(_ a: AIQuery, rules: SearchQuery, said: String) -> SearchQuery {
        // The model sometimes fills a date or size nobody asked for; keep those only if the request mentions one.
        let words = Set(said.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        let timeWords: Set<String> = ["today", "yesterday", "week", "weeks", "month", "months", "year", "years", "ago", "old", "older",
                                      "recent", "recently", "new", "newest", "latest", "last", "since", "before", "after", "day", "days"]
        let sizeWords: Set<String> = ["big", "bigger", "biggest", "large", "larger", "largest", "huge", "massive", "heavy", "small",
                                      "tiny", "gb", "mb", "kb", "gigs", "megs"]
        let saidTime = !words.isDisjoint(with: timeWords) || !words.isDisjoint(with: Set(QueryParser.months.keys))
        let saidSize = !words.isDisjoint(with: sizeWords)
        var chips: [SearchChip] = []
        let kindMap: [String: SearchChip] = [
            "images": .category(.images), "photos": .category(.images), "videos": .category(.videos), "music": .category(.music),
            "audio": .category(.music), "documents": .category(.documents), "archives": .category(.archives), "apps": .category(.apps),
            "screenshots": .screenshots, "pdf": .exts("PDF", ["pdf"]),
            "installers": .exts("Installers", ["dmg", "pkg", "mpkg", "iso", "xip"]),
            "spreadsheets": .exts("Spreadsheets", ["xls", "xlsx", "csv", "numbers", "tsv", "ods"]),
            "presentations": .exts("Presentations", ["key", "ppt", "pptx", "odp"]),
        ]
        for k in a.kinds { if let c = kindMap[k.lowercased()], !chips.contains(c) { chips.append(c) } }
        switch saidSize ? a.size : .any {
        case .small: chips.append(.maxSize(1_000_000))
        case .large: chips.append(.minSize(100_000_000))
        case .huge: chips.append(.minSize(1_000_000_000))
        case .any: break
        }
        let cal = Calendar.current, now = Date()
        func start(_ c: Calendar.Component, _ d: Date) -> Date { cal.dateInterval(of: c, for: d)?.start ?? d }
        switch saidTime ? a.when : .any {
        case .today: chips.append(.dateRange("Today", cal.startOfDay(for: now), nil))
        case .thisWeek: chips.append(.dateRange("This week", start(.weekOfYear, now), nil))
        case .thisMonth: chips.append(.dateRange("This month", start(.month, now), nil))
        case .lastMonth:
            let s = cal.date(byAdding: .month, value: -1, to: start(.month, now))!
            chips.append(.dateRange("Last month", s, start(.month, now)))
        case .thisYear: chips.append(.dateRange("This year", start(.year, now), nil))
        case .lastYear:
            let s = cal.date(byAdding: .year, value: -1, to: start(.year, now))!
            chips.append(.dateRange("Last year", s, start(.year, now)))
        case .olderThanSixMonths: chips.append(.olderThan("Older than 6 months", cal.date(byAdding: .month, value: -6, to: now)!))
        case .olderThanOneYear: chips.append(.olderThan("Older than a year", cal.date(byAdding: .year, value: -1, to: now)!))
        case .any: break
        }
        // Only real download sources: a known service, or something that looks like a website.
        if let raw = a.source?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty {
            if let known = QueryParser.sourceWords[raw] ?? DownloadSource.known.first(where: { $0.name.lowercased() == raw })?.name {
                chips.append(.source(known))
            } else if raw.contains("."), !raw.contains(" ") {
                chips.append(.source(DownloadSource.registrableDomain(raw)))
            }
        }
        // Keep what the rules were sure about (exact sizes, "in October") when the model left that part out.
        for c in rules.chips where c.kindKey != "text" && !chips.contains(where: { $0.kindKey == c.kindKey }) { chips.append(c) }
        let filler = QueryParser.stopwords.union(QueryParser.typeWords.keys).union(["file", "files", "thing", "one", "that", "this", "something"])
        let keep = a.words.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            .filter { $0.count > 1 && !filler.contains($0) }
        if !keep.isEmpty { chips.append(.text(keep.joined(separator: " "))) }
        return SearchQuery(chips: chips, byAI: true)
    }
    #endif
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
enum AISize { case any, small, large, huge }

@available(macOS 26.0, *)
@Generable
enum AIWhen { case any, today, thisWeek, thisMonth, lastMonth, thisYear, lastYear, olderThanSixMonths, olderThanOneYear }

@available(macOS 26.0, *)
@Generable
struct AIQuery {
    @Guide(description: "Kinds of files the person asked for. Only these values: images, videos, music, documents, archives, apps, screenshots, pdf, installers, spreadsheets, presentations. Empty if not said.")
    var kinds: [String]
    @Guide(description: "Size only if the person said it: small, large (big), huge (very big, several GB). Otherwise any.")
    var size: AISize
    @Guide(description: "When only if the person said it. Otherwise any.")
    var when: AIWhen
    @Guide(description: "Only if the person said where it came from: Gmail for anything emailed or sent by email, or Slack, WhatsApp, ChatGPT, Google Drive, Dropbox, GitHub, or a website domain. Otherwise leave empty.")
    var source: String?
    @Guide(description: "One to three distinctive words to find in the file name or inside the file, such as invoice, tracking, drone. No kind words like video or screenshot.")
    var words: String
}
#endif
