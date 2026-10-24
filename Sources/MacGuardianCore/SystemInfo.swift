import Foundation
import Darwin
import AppKit
import IOKit.ps

public enum Command {
    // Only fixed executables and argument arrays. No shell or interpolation.
    public static func run(_ path: String, _ args: [String]) throws -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        try p.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw GuardianError.permission("No disponible: \(path)") }
        return String(decoding: data, as: UTF8.self)
    }
    public static func sysctlString(_ name: String) -> String {
        var n = 0; guard sysctlbyname(name, nil, &n, nil, 0) == 0, n > 0 else { return "No disponible" }
        var data = [CChar](repeating: 0, count: n)
        guard sysctlbyname(name, &data, &n, nil, 0) == 0 else { return "No disponible" }
        return String(cString: data)
    }
}
public struct ProcessRow: Identifiable, Sendable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let parent: Int32
    public let uid: UInt32
    public let user: String
    public let cpu: Double
    public let memory: Int64
    public let elapsed: String
    public let state: String
    public let executable: String
    public let name: String
    public var observation: String { state.contains("Z") ? "Zombi: terminó y el padre aún no lo recogió" : cpu > 80 ? "CPU > 80 %; no implica actividad maliciosa" : parent == 1 ? "Administrado por launchd o reasignado; puede ser normal" : "Sin regla de aviso" }
}
public enum ProcessService {
    public static func list() throws -> [ProcessRow] {
        let output = try Command.run("/bin/ps", ["-ww", "-axo", "pid=,ppid=,uid=,user=,%cpu=,rss=,etime=,stat=,comm="])
        return parse(output)
    }
    public static func parse(_ output: String) -> [ProcessRow] {
        return output.split(separator: "\n").compactMap { line in
            let c = line.split(maxSplits: 8, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard c.count == 9, let pid = Int32(c[0]), let parent = Int32(c[1]), let uid = UInt32(c[2]), let cpu = Double(c[4]), let rss = Int64(c[5]) else { return nil }
            return ProcessRow(pid: pid, parent: parent, uid: uid, user: c[3], cpu: cpu, memory: rss * 1024, elapsed: c[6], state: c[7], executable: c[8].trimmingCharacters(in: .whitespaces), name: URL(fileURLWithPath: c[8].trimmingCharacters(in: .whitespaces)).lastPathComponent)
        }.sorted { $0.cpu > $1.cpu }
    }
    public static func canTerminate(_ row: ProcessRow) -> Bool {
        row.pid > 1 && row.pid != getpid() && row.uid == getuid() && !row.state.contains("Z") && (row.executable.hasPrefix("/Applications/") || row.executable.hasPrefix(NSHomeDirectory() + "/Applications/")) && !row.executable.contains("MacGuardian.app/")
    }
    public static func terminate(_ row: ProcessRow, force: Bool) throws {
        guard canTerminate(row), let fresh = try list().first(where: { $0.pid == row.pid }), fresh.executable == row.executable, fresh.uid == row.uid, canTerminate(fresh) else { throw GuardianError.unsafe("El proceso cambió o está protegido.") }
        // Restrict to an NSRunningApplication so PID reuse cannot target an arbitrary service.
        guard let app = NSRunningApplication(processIdentifier: row.pid), app.executableURL?.path == row.executable else { throw GuardianError.unsafe("Solo se pueden cerrar aplicaciones identificadas por macOS. Usa Monitor de Actividad para este servicio.") }
        guard force ? app.forceTerminate() : app.terminate() else { throw GuardianError.permission("macOS rechazó la solicitud.") }
    }
}
public struct Metrics: Sendable {
    public var model = Command.sysctlString("hw.model")
    public var cpu = Command.sysctlString("machdep.cpu.brand_string")
    public var ram = Int64(ProcessInfo.processInfo.physicalMemory)
    public var os = ProcessInfo.processInfo.operatingSystemVersionString
    public var capacity: Int64 = 0
    public var available: Int64 = 0
    public var usedMemory: Int64 = 0
    public var swap = "No disponible"
    public var pressure = "No disponible"
    public var battery = "No disponible"
    public var batteryDetails = "No disponible"
    public var cpuBusy: Double? = nil
    public var network = "No disponible"
    public var disk = "No disponible"
    public init() {}
}
public final class MetricsSampler {
    private var previous: [UInt32]?
    public init() {}
    public func sample() -> Metrics {
        var m = Metrics()
        if let fs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()) {
            m.capacity = (fs[.systemSize] as? NSNumber)?.int64Value ?? 0
            m.available = (fs[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        }
        var cpu = host_cpu_load_info(); var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &cpu) { p in p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) } }
        if r == KERN_SUCCESS {
            let ticks = [cpu.cpu_ticks.0, cpu.cpu_ticks.1, cpu.cpu_ticks.2, cpu.cpu_ticks.3]
            if let prev = previous { let d = zip(ticks, prev).map { UInt64($0 &- $1) }; let total = d.reduce(0,+); if total > 0 { m.cpuBusy = 100 * Double(total - d[2]) / Double(total) } }
            previous = ticks
        }
        var vm = vm_statistics64(); var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let vmr = withUnsafeMutablePointer(to: &vm) { p in p.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount) } }
        if vmr == KERN_SUCCESS { var page: vm_size_t = 0; host_page_size(mach_host_self(), &page); m.usedMemory = Int64(UInt64(vm.active_count) + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)) * Int64(page) }
        m.swap = (try? Command.run("/usr/sbin/sysctl", ["-n", "vm.swapusage"]).trimmingCharacters(in: .whitespacesAndNewlines)) ?? "No disponible"
        let pressure = (try? Command.run("/usr/sbin/sysctl", ["-n", "kern.memorystatus_vm_pressure_level"]).trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
        m.pressure = ["1": "Normal", "2": "Advertencia", "4": "Crítica"][pressure] ?? "No disponible"
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in list {
                if let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any], let current = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 {
                    m.battery = "\(current * 100 / max) % · \(d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue ? "Conectado a corriente" : "Batería")"
                }
            }
        }
        return m
    }
}
public struct InstalledApp: Identifiable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let version: String
    public let bundleID: String
    public let lastUsed: Date?
    public var running: Bool { NSWorkspace.shared.runningApplications.contains { $0.bundleURL == url } }
}
public struct AssociatedFile: Identifiable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let reason: String
    public let personal: Bool
}
public enum ApplicationService {
    public static func canonicalURL(_ url: URL) -> URL {
        guard let resolved = realpath(url.path, nil) else { return url }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved))
    }
    public static var defaultRoots: [URL] {
        ["/Applications", "/System/Applications", "/System/Library/CoreServices/Applications", NSHomeDirectory() + "/Applications"].map { URL(fileURLWithPath: $0) }
    }
    public static func bundlePath(forExecutable path: String) -> String? {
        let parts = path.split(separator: "/")
        guard let index = parts.firstIndex(where: { $0.lowercased().hasSuffix(".app") }) else { return nil }
        return "/" + parts[...index].joined(separator: "/")
    }
    public static func list(roots: [URL], discovered: [URL] = [], includeSpotlight: Bool = false) -> [InstalledApp] {
        var candidates = discovered
        if includeSpotlight, let output = try? Command.run("/usr/bin/mdfind", ["kMDItemContentType == 'com.apple.application-bundle'"]) {
            candidates += output.split(separator: "\n").prefix(20_000).map { URL(fileURLWithPath: String($0)) }
        }
        for root in roots {
            if root.pathExtension.lowercased() == "app" { candidates.append(root); continue }
            guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isUbiquitousItemKey], options: [.skipsPackageDescendants, .skipsHiddenFiles]) else { continue }
            for case let url as URL in e {
                let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isUbiquitousItemKey])
                if values?.isUbiquitousItem == true { e.skipDescendants(); continue }
                if url.pathExtension.lowercased() == "app" { candidates.append(url); e.skipDescendants() }
                else if values?.isSymbolicLink == true { e.skipDescendants() }
            }
        }
        var seen = Set<String>(), apps: [InstalledApp] = []
        for candidate in candidates {
            let url = canonicalURL(candidate)
            let isInternalComponent = url.path.hasPrefix("/System/Library/") || url.path.hasPrefix("/Library/Apple/System/Library/")
            if isInternalComponent && url.path != "/System/Library/CoreServices/Finder.app" && !roots.contains(where: { Safety.isInside(url.path, root: $0.path) }) { continue }
            guard url.pathExtension.lowercased() == "app", bundlePath(forExecutable: url.path) == url.path, seen.insert(url.path).inserted,
                  (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) != true,
                  let b = Bundle(url: url) else { continue }
            apps.append(InstalledApp(url: url, name: b.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? b.object(forInfoDictionaryKey: "CFBundleName") as? String ?? url.deletingPathExtension().lastPathComponent, version: b.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "No disponible", bundleID: b.bundleIdentifier ?? "", lastUsed: nil))
        }
        return apps.sorted { $0.name == $1.name ? $0.url.path < $1.url.path : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    public static func related(_ app: InstalledApp) -> [AssociatedFile] {
        guard !app.bundleID.isEmpty, !app.bundleID.contains("/"), app.bundleID != ".", app.bundleID != ".." else { return [] }
        let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        let pairs: [(String, Bool)] = [("Caches/\(app.bundleID)", false), ("Preferences/\(app.bundleID).plist", false), ("Saved Application State/\(app.bundleID).savedState", false), ("Application Support/\(app.bundleID)", true), ("Containers/\(app.bundleID)", true), ("LaunchAgents/\(app.bundleID).plist", true)]
        return pairs.compactMap { p, personal in let url = home.appendingPathComponent(p); guard FileManager.default.fileExists(atPath: url.path) else { return nil }; return AssociatedFile(url: url, reason: "Coincidencia exacta con CFBundleIdentifier: \(app.bundleID). \(personal ? "Puede contener datos personales o servicios; conservar." : "Puede contener configuración; revisar en Finder.")", personal: personal) }
    }
}
public struct StartupItem: Identifiable, Sendable {
    public var id: String { path }
    public let label: String
    public let path: String
    public let program: String
    public let type: String
    public let loaded: Bool?
    public let iconPath: String?
}
public enum StartupService {
    public static func list() -> [StartupItem] {
        let roots = [(NSHomeDirectory() + "/Library/LaunchAgents", "Agente del usuario"), ("/Library/LaunchAgents", "Agente global"), ("/Library/LaunchDaemons", "Servicio global")]
        return roots.flatMap { root, type -> [StartupItem] in
            let urls = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil)) ?? []
            return urls.filter { $0.pathExtension == "plist" }.compactMap { url in
                guard let data = try? Data(contentsOf: url), let d = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
                let arguments = d["ProgramArguments"] as? [String] ?? []
                let program = d["Program"] as? String ?? arguments.first ?? "No especificado"
                let iconPath = ([program] + arguments).first(where: { $0.hasPrefix("/") && $0.contains(".app") }).flatMap { ApplicationService.bundlePath(forExecutable: $0) }
                return StartupItem(label: d["Label"] as? String ?? url.lastPathComponent, path: url.path, program: program, type: type, loaded: nil, iconPath: iconPath)
            }
        }.sorted { $0.label < $1.label }
    }
}
