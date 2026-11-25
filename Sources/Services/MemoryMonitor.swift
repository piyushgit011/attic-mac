import Foundation
import AppKit
import Darwin
import Observation

/// Live memory + swap picture, and which apps are holding the most memory right now.
/// macOS writes overflow memory to swap files on the startup disk (/System/Volumes/VM), so heavy swap = lost disk space.
struct MemorySnapshot: Equatable {
    var physical: UInt64 = 0
    var used: UInt64 = 0
    var appMemory: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var cached: UInt64 = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    var swapFilesOnDisk: UInt64 = 0
    var swapFileCount: Int = 0
    var pressure: Int = 1 // 1 normal, 2 warning, 4 critical

    var pressureLabel: String {
        switch pressure {
        case 4: return "Critical"
        case 2: return "High"
        default: return swapUsed > physical / 4 ? "Normal, but swapping" : "Normal"
        }
    }
}

struct AppMemory: Identifiable, Hashable {
    let id: String              // group key (app bundle path or executable name)
    let name: String
    let bundleURL: URL?
    var pids: [pid_t]
    var footprint: UInt64       // what Activity Monitor calls "Memory"
    var isGUI: Bool
    var isActive: Bool
    var isSelf: Bool
    var isAppleSystem: Bool
    var processCount: Int { pids.count }

    var suggestion: String? {
        if isSelf || isAppleSystem { return nil }
        if footprint > 2_000_000_000 { return "Using a lot of memory" }
        if footprint > 700_000_000 && !isActive { return "Idle in the background" }
        return nil
    }
}

@MainActor @Observable
final class MemoryMonitor {
    var snapshot = MemorySnapshot()
    var apps: [AppMemory] = []
    var isRefreshing = false
    private var timer: Timer?

    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        if DemoData.root != nil {
            snapshot = MemoryMonitor.demoSnapshot
            apps = MemoryMonitor.demoApps
            return
        }
        guard !isRefreshing else { return }
        isRefreshing = true
        let running = NSWorkspace.shared.runningApplications.map {
            ($0.processIdentifier, $0.bundleURL, $0.localizedName, $0.activationPolicy == .regular, $0.isActive, $0.bundleIdentifier)
        }
        Task.detached(priority: .utility) {
            let snap = MemoryMonitor.readSnapshot()
            let groups = MemoryMonitor.readApps(running: running)
            await MainActor.run {
                self.snapshot = snap
                self.apps = groups
                self.isRefreshing = false
            }
        }
    }

    // MARK: Demo data (screenshots and recordings)

    static let demoSnapshot = MemorySnapshot(physical: 17_179_869_184, used: 15_600_000_000, appMemory: 11_200_000_000,
                                             wired: 2_100_000_000, compressed: 2_300_000_000, cached: 900_000_000,
                                             swapUsed: 9_400_000_000, swapTotal: 10_737_418_240, swapFilesOnDisk: 10_737_418_240,
                                             swapFileCount: 10, pressure: 2)

    static var demoApps: [AppMemory] {
        func app(_ name: String, _ bundle: String, _ gb: Double, _ procs: Int, active: Bool = false, system: Bool = false, me: Bool = false) -> AppMemory {
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
            return AppMemory(id: bundle, name: name, bundleURL: url, pids: Array(repeating: 0, count: procs), footprint: UInt64(gb * 1_000_000_000),
                             isGUI: true, isActive: active, isSelf: me, isAppleSystem: system)
        }
        return [
            app("Google Chrome", "com.google.Chrome", 6.2, 38),
            app("Docker Desktop", "com.docker.docker", 2.4, 6),
            app("Xcode", "com.apple.dt.Xcode", 3.1, 9, active: true),
            app("Figma", "com.figma.Desktop", 1.8, 7),
            app("Slack", "com.tinyspeck.slackmacgap", 1.4, 8),
            app("Visual Studio Code", "com.microsoft.VSCode", 1.1, 14),
            app("Spotify", "com.spotify.client", 0.64, 5),
            app("Notion", "notion.id", 0.52, 4),
            app("Safari", "com.apple.Safari", 0.48, 6, system: true),
            app("Attic", "studio.versely.attic", 0.12, 1, me: true),
        ]
    }

    // MARK: Actions

    /// Asks the app to quit normally (it can save its work).
    func quit(_ app: AppMemory) {
        if DemoData.root != nil { apps.removeAll { $0.id == app.id }; return }
        var asked = false
        for pid in app.pids {
            if let ra = NSRunningApplication(processIdentifier: pid) {
                asked = ra.terminate() || asked
            }
        }
        if !asked { for pid in app.pids { kill(pid, SIGTERM) } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.refresh() }
    }

    func forceQuit(_ app: AppMemory) {
        for pid in app.pids {
            if let ra = NSRunningApplication(processIdentifier: pid) { _ = ra.forceTerminate() } else { kill(pid, SIGKILL) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.refresh() }
    }

    // MARK: Reading

    nonisolated static func readSnapshot() -> MemorySnapshot {
        var s = MemorySnapshot()
        s.physical = ProcessInfo.processInfo.physicalMemory

        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64_data_t()
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        if kr == KERN_SUCCESS {
            let page = UInt64(vm_kernel_page_size)
            let internalPages = UInt64(stats.internal_page_count) - UInt64(stats.purgeable_count)
            s.appMemory = internalPages * page
            s.wired = UInt64(stats.wire_count) * page
            s.compressed = UInt64(stats.compressor_page_count) * page
            s.cached = (UInt64(stats.external_page_count) + UInt64(stats.purgeable_count)) * page
            s.used = s.appMemory + s.wired + s.compressed
        }

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            s.swapUsed = swap.xsu_used
            s.swapTotal = swap.xsu_total
        }
        var level: Int32 = 1
        var levelSize = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &levelSize, nil, 0) == 0 {
            s.pressure = Int(level)
        }
        if let files = try? FileManager.default.contentsOfDirectory(atPath: "/System/Volumes/VM") {
            let swaps = files.filter { $0.hasPrefix("swapfile") }
            s.swapFileCount = swaps.count
            for f in swaps {
                let attrs = try? FileManager.default.attributesOfItem(atPath: "/System/Volumes/VM/" + f)
                s.swapFilesOnDisk += (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
            }
        }
        if s.swapFilesOnDisk == 0 { s.swapFilesOnDisk = s.swapTotal }
        return s
    }

    nonisolated static func readApps(running: [(pid_t, URL?, String?, Bool, Bool, String?)]) -> [AppMemory] {
        let myPid = getpid()
        let uid = getuid()
        var byPid: [pid_t: (URL?, String?, Bool, Bool, String?)] = [:]
        for r in running { byPid[r.0] = (r.1, r.2, r.3, r.4, r.5) }

        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard n > 0 else { return [] }

        var groups: [String: AppMemory] = [:]
        for pid in pids.prefix(Int(n)) where pid > 0 {
            // Only this user's processes; those are the ones you can quit.
            var info = proc_bsdinfo()
            let infoSize = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
            guard infoSize == Int32(MemoryLayout<proc_bsdinfo>.size), info.pbi_uid == uid else { continue }

            var usage = rusage_info_v4()
            let ok = withUnsafeMutablePointer(to: &usage) { ptr -> Bool in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) == 0
                }
            }
            guard ok else { continue }
            let footprint = usage.ri_phys_footprint
            guard footprint > 5_000_000 else { continue }

            var pathBuf = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
            let len = proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count))
            let path = len > 0 ? String(cString: pathBuf) : ""

            let (key, name, bundle) = groupKey(path: path, pid: pid, info: &info)
            let ra = byPid[pid]
            let isAppleSystem = path.hasPrefix("/System/") || path.hasPrefix("/usr/") || path.hasPrefix("/sbin/")
                || path.hasPrefix("/Library/Apple/") || (ra?.4?.hasPrefix("com.apple.") ?? false && path.hasPrefix("/System"))
            if var g = groups[key] {
                g.pids.append(pid)
                g.footprint += footprint
                if let ra { g.isGUI = g.isGUI || ra.2; g.isActive = g.isActive || ra.3 }
                if pid == myPid { g.isSelf = true }
                groups[key] = g
            } else {
                groups[key] = AppMemory(id: key, name: ra?.1 ?? name, bundleURL: ra?.0 ?? bundle, pids: [pid], footprint: footprint,
                                        isGUI: ra?.2 ?? false, isActive: ra?.3 ?? false, isSelf: pid == myPid,
                                        isAppleSystem: isAppleSystem)
            }
        }
        return groups.values.filter { $0.footprint > 40_000_000 }.sorted { $0.footprint > $1.footprint }
    }

    /// Groups helper processes under their app: everything inside "X.app" counts as X.
    nonisolated static func groupKey(path: String, pid: pid_t, info: inout proc_bsdinfo) -> (String, String, URL?) {
        if let range = path.range(of: ".app/") {
            let bundlePath = String(path[..<range.lowerBound]) + ".app"
            let name = (bundlePath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
            return (bundlePath, name, URL(fileURLWithPath: bundlePath))
        }
        let comm = withUnsafeBytes(of: &info.pbi_comm) { raw -> String in
            String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
        }
        let exe = path.isEmpty ? comm : (path as NSString).lastPathComponent
        let friendly: [String: String] = ["node": "Node.js", "python3": "Python", "python": "Python", "java": "Java",
                                          "claude": "Claude Code (CLI)", "docker": "Docker", "qemu-system-aarch64": "QEMU VM"]
        return ("exe:" + exe, friendly[exe] ?? exe, nil)
    }
}
