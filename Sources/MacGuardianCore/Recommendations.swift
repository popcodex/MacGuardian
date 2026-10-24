import Foundation
import Darwin

public struct RecommendationContext: Sendable {
    public let home: String
    public let now: Date
    public let processSnapshotAvailable: Bool
    public let runningExecutables: [String]
    public init(home: String = NSHomeDirectory(), now: Date = Date(), processSnapshotAvailable: Bool, runningExecutables: [String]) {
        self.home = home; self.now = now; self.processSnapshotAvailable = processSnapshotAvailable; self.runningExecutables = runningExecutables
    }
    public static func current(home: String = NSHomeDirectory()) -> RecommendationContext {
        let rows = try? ProcessService.list()
        return RecommendationContext(home: home, processSnapshotAvailable: rows?.isEmpty == false, runningExecutables: rows?.map(\.executable) ?? [])
    }
    func hasTool(_ families: [String]) -> Bool {
        runningExecutables.contains { path in let name = URL(fileURLWithPath: path).lastPathComponent.lowercased(); return families.contains { name.hasPrefix($0) } }
    }
}
public enum RecommendationPolicy {
    public static func reason(for file: FileRecord, context: RecommendationContext) -> String? {
        guard context.processSnapshotAvailable, file.risk != .protected, file.links == 1, file.owner == getuid(), file.size > 0 else { return nil }
        let age = context.now.timeIntervalSince(file.modified)
        guard age > 30 * 86400 else { return nil }
        let p = file.path, h = context.home
        if p.contains("/__pycache__/") && file.url.pathExtension.lowercased() == "pyc" && !context.hasTool(["python", "pip"]) {
            return "Bytecode Python regenerable, sin cambios durante más de 30 días y sin Python o pip detectados en ejecución."
        }
        if Safety.isInside(p, root: h + "/Library/Logs/DiagnosticReports"), ["ips", "crash"].contains(file.url.pathExtension.lowercased()) {
            return "Informe de fallo con más de 30 días: solo conserva información de diagnóstico, no datos necesarios para ejecutar aplicaciones. Se perderá ese diagnóstico antiguo."
        }
        let rules: [(String, [String], String)] = [
            (h + "/Library/Caches/pip", ["python", "pip"], "Caché de descargas de pip"),
            (h + "/Library/Caches/Homebrew", ["brew", "ruby"], "Caché de descargas de Homebrew"),
            (h + "/.npm/_cacache", ["node", "npm", "npx"], "Caché de paquetes npm"),
            (h + "/Library/Developer/Xcode/DerivedData", ["xcode", "swift", "clang", "llbuild", "simulator"], "Artefacto regenerable de Xcode")
        ]
        for (root, tools, label) in rules where p != root && Safety.isInside(p, root: root) && !context.hasTool(tools) {
            // Generated databases, environments, project data and credentials remain protected by classify().
            return "\(label), sin cambios durante más de 30 días y sin sus herramientas detectadas en ejecución. Volver a descargar o compilar puede tardar más."
        }
        return nil
    }
    public static func quickRoots(home: String = NSHomeDirectory()) -> [URL] {
        ["Library/Caches/pip", "Library/Caches/Homebrew", ".npm/_cacache", "Library/Developer/Xcode/DerivedData", "Library/Logs/DiagnosticReports"].map { URL(fileURLWithPath: home).appendingPathComponent($0) }
    }
    public static func select(files: [FileRecord], query: FileQuery, roots: [String], exclusions: [String], recommendedOnly: Bool, context: RecommendationContext) throws -> Set<String> {
        var selected = Set<String>()
        for (i, file) in files.enumerated() {
            if i % 256 == 0 { try Task.checkCancellation() }
            guard query.matches(file), Safety.canSelect(file, roots: roots, exclusions: exclusions) else { continue }
            if !recommendedOnly || reason(for: file, context: context) != nil { selected.insert(file.path) }
        }
        return selected
    }
}
public struct QuickCleanPlan: Identifiable, Sendable {
    public let id = UUID()
    public let files: [FileRecord]
    public let roots: [String]
    public let issues: [String]
    public let examined: Int
    public let logical: Int64
    public init(files: [FileRecord], roots: [String], issues: [String], examined: Int) { self.files = files; self.roots = roots; self.issues = issues; self.examined = examined; self.logical = files.reduce(0) { $0 + $1.size } }
}
