import Foundation

public struct CleanupFailure: Identifiable, Sendable {
    public var id: String { path }
    public let path: String
    public let reason: String
}
public struct CleanupReport: Identifiable, Sendable {
    public let id = UUID()
    public var moved: [String] = []
    public var logicalMoved: Int64 = 0
    public var failures: [CleanupFailure] = []
    public var cancelled = false
    public var freeBefore: Int64?
    public var freeAfter: Int64?
    public var measuredRoot: String = ""
    public var observedFreeChange: Int64? { guard let a = freeBefore, let b = freeAfter else { return nil }; return b - a }
    public init() {}
}
public enum CleanupEngine {
    public static func freeBytes(at path: String) -> Int64? {
        (try? FileManager.default.attributesOfFileSystem(forPath: path)[.systemFreeSize] as? NSNumber)?.int64Value
    }
    public static func moveToTrash(_ file: FileRecord, roots: [String], exclusions: [String]) throws -> URL? {
        var coordinationError: NSError?, actionError: Error?, destination: NSURL?
        NSFileCoordinator().coordinate(writingItemAt: file.url, options: .forMoving, error: &coordinationError) { url in
            do { try Safety.validate(file, roots: roots, exclusions: exclusions); try FileManager.default.trashItem(at: url, resultingItemURL: &destination) } catch { actionError = error }
        }
        if let error = coordinationError { throw error }; if let error = actionError { throw error }
        return destination as URL?
    }
    /// Called after explicit UI authorization (including the Home quick-clean button). Tests inject a fixture-only mover.
    public static func perform(files: [FileRecord], roots: [String], exclusions: [String], duplicateGroups: [DuplicateGroup] = [], journal: HistoryStore, recommendationsOnly: Bool = false, contextProvider: @Sendable () -> RecommendationContext = { .current() }, mover: (@Sendable (FileRecord) throws -> URL?)? = nil, progress: @Sendable (Int, Int) -> Void = { _, _ in }) async -> CleanupReport {
        var report = CleanupReport(); report.measuredRoot = roots.first ?? NSHomeDirectory()
        report.freeBefore = freeBytes(at: report.measuredRoot)
        let selectedPaths = Set(files.map(\.path))
        do {
            guard selectedPaths.count == files.count else { throw GuardianError.unsafe("Selección repetida") }
            try Safety.validateKeepers(selectedPaths: selectedPaths, duplicateGroups: duplicateGroups)
            try journal.append(HistoryEvent(action: "Limpieza autorizada", detail: "\(files.count) archivos; alcance: \(roots.joined(separator: ", ")); solo recomendaciones: \(recommendationsOnly). Detalle por archivo en el registro de acciones."))
            var context: RecommendationContext?
            for (i, file) in files.enumerated() {
                if Task.isCancelled { report.cancelled = true; break }
                if recommendationsOnly && (i % 16 == 0 || context == nil) { context = contextProvider() }
                do {
                    try Safety.validate(file, roots: roots, exclusions: exclusions)
                    try Safety.validateKeepers(selectedPaths: selectedPaths, duplicateGroups: duplicateGroups)
                    if recommendationsOnly { guard let context, RecommendationPolicy.reason(for: file, context: context) != nil else { throw GuardianError.unsafe("Ya no cumple la recomendación conservadora, o su herramienta está activa.") } }
                } catch {
                    report.failures.append(CleanupFailure(path: file.path, reason: error.localizedDescription)); try journal.audit(HistoryEvent(action: "Archivo conservado", detail: "\(file.path): \(error.localizedDescription)")); progress(i + 1, files.count); continue
                }
                // A failed audit write stops further modifications rather than silently continuing.
                try journal.audit(HistoryEvent(action: "Autorización de archivo", detail: file.path))
                do {
                    let destination: URL?
                    if let mover { destination = try mover(file) } else { destination = try moveToTrash(file, roots: roots, exclusions: exclusions) }
                    report.moved.append(file.path); report.logicalMoved += file.size
                    try journal.audit(HistoryEvent(action: "Archivo movido", detail: "\(file.path) → \(destination?.path ?? "Papelera")"))
                } catch {
                    report.failures.append(CleanupFailure(path: file.path, reason: error.localizedDescription))
                    // This audit is required before moving the next file.
                    try journal.audit(HistoryEvent(action: "Error de archivo", detail: "\(file.path): \(error.localizedDescription)"))
                }
                progress(i + 1, files.count)
                if i % 16 == 0 { await Task.yield() }
            }
        } catch { report.failures.append(CleanupFailure(path: "Operación", reason: error.localizedDescription)) }
        report.freeAfter = freeBytes(at: report.measuredRoot)
        do { try journal.append(HistoryEvent(action: "Resumen de limpieza", detail: "\(report.moved.count) archivos en Papelera · \(sizeText(report.logicalMoved)) lógicos · \(report.failures.count) incidencias · cancelada: \(report.cancelled) · variación de disponible: \(report.observedFreeChange.map(String.init) ?? "no medida") bytes. La variación no se atribuye exclusivamente a esta operación.")) } catch { report.failures.append(CleanupFailure(path: "Historial", reason: error.localizedDescription)) }
        return report
    }
}
