import AppIntents
import AppKit

/// Siri and Shortcuts. Everything here runs on this Mac.

struct FindFilesIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Files in Attic"
    static let description = IntentDescription("Search your Mac in plain English, like “pdfs from last week over 5 mb”.")
    static let openAppWhenRun = true

    @Parameter(title: "Search", requestValueDialog: "What are you looking for?")
    var query: String

    @MainActor
    func perform() async throws -> some IntentResult {
        NSApp.activate(ignoringOtherApps: true)
        AppState.shared.library.startIfNeeded()
        AppState.shared.nav.searchText = query
        return .result()
    }
}

struct StorageStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Mac Storage"
    static let description = IntentDescription("How much space is free, and how much swap is using your disk.")

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let disk = DiskStats.current()
        let mem = MemoryMonitor.readSnapshot()
        let text = "You have \(Fmt.bytes(disk.available)) free of \(Fmt.bytes(disk.total)). "
            + "Swap is using \(Fmt.bytes(Int64(mem.swapUsed))), with \(Fmt.bytes(Int64(mem.swapFilesOnDisk))) of swap files on disk."
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

struct FreeUpSpaceIntent: AppIntent {
    static let title: LocalizedStringResource = "Free Up Space with Attic"
    static let description = IntentDescription("Opens Attic’s Clean Up cards.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NSApp.activate(ignoringOtherApps: true)
        AppState.shared.library.startIfNeeded()
        AppState.shared.nav.go(.cleanup)
        return .result()
    }
}

struct AtticShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: FindFilesIntent(), phrases: ["Find files in \(.applicationName)", "Search \(.applicationName)"],
                    shortTitle: "Find Files", systemImageName: "magnifyingglass")
        AppShortcut(intent: StorageStatusIntent(), phrases: ["How much space is left in \(.applicationName)", "Check storage with \(.applicationName)"],
                    shortTitle: "Check Storage", systemImageName: "internaldrive")
        AppShortcut(intent: FreeUpSpaceIntent(), phrases: ["Free up space with \(.applicationName)", "Clean up my Mac with \(.applicationName)"],
                    shortTitle: "Free Up Space", systemImageName: "sparkles")
    }
}
