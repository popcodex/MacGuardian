import SwiftUI
import AppKit
import MacGuardianCore

@MainActor final class AppModel: ObservableObject {
    @Published var scan: ScanResult?
    @Published var scanIndex = ScanIndex()
    @Published var scanRevision = 0
    @Published var duplicates: [DuplicateGroup] = []
    @Published var processes: [ProcessRow] = []
    @Published var processIssue: String?
    @Published var apps: [InstalledApp] = []
    @Published var startup: [StartupItem] = []
    @Published var runningPaths = Set<String>()
    @Published var inventoryBusy = false
    @Published var appRoots = UserDefaults.standard.stringArray(forKey: "applicationRoots") ?? []
    @Published var metrics = Metrics()
    @Published var busy = false
    @Published var status = "Selecciona una carpeta para comenzar."
    @Published var processed = 0
    @Published var hashDone = 0
    @Published var hashTotal = 0
    @Published var progressKind = "archivos comparados"
    @Published var error: String?
    @Published var selected = Set<String>()
    @Published var history: [HistoryEvent] = []
    @Published var exclusions: [String] = UserDefaults.standard.stringArray(forKey: "exclusions") ?? []
    @Published var folder: URL?
    @Published var appDetails: InstalledApp?
    @Published var associated: [AssociatedFile] = []
    @Published var appSize: Int64?
    @Published var appSizePartial = false
    @Published var quickPlan: QuickCleanPlan?
    @Published var cleanupSummary: CleanupReport?
    @Published var showMenu = UserDefaults.standard.bool(forKey: "showMenu")
    @Published var interval = max(3, UserDefaults.standard.double(forKey: "interval"))
    private var operation: Task<Void, Never>?
    private var inspection: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private let sampler = MetricsSampler()
    private var store: HistoryStore?
    init() {
        do { store = try HistoryStore(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MacGuardian/history.json")); history = store?.events ?? [] }
        catch { self.error = "No se pudo leer el historial: \(error.localizedDescription). Las modificaciones quedan bloqueadas." }
        timer = Task { [weak self] in
            while !Task.isCancelled { guard let self else { break }; await self.refresh(); try? await Task.sleep(for: .seconds(self.interval)) }
        }
        Task { await inventories() }
    }
    func refresh() async {
        let sampler = self.sampler
        let result = await Task.detached(priority: .utility) { (sampler.sample(), Result { try ProcessService.list() }) }.value
        metrics = result.0
        switch result.1 { case .success(let rows): processes = rows; processIssue = nil; case .failure(let error): processIssue = error.localizedDescription }
        runningPaths = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL.map { ApplicationService.canonicalURL($0).path } })
    }
    func isRunning(_ app: InstalledApp) -> Bool { runningPaths.contains { Safety.isInside($0, root: app.url.path) } }
    func inventories() async {
        guard !inventoryBusy else { return }; inventoryBusy = true
        let roots = ApplicationService.defaultRoots + appRoots.map { URL(fileURLWithPath: $0) }
        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleURL)
        let result = await Task.detached(priority: .utility) { (ApplicationService.list(roots: roots, discovered: running, includeSpotlight: true), StartupService.list()) }.value
        apps = result.0; startup = result.1; inventoryBusy = false
        runningPaths = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL.map { ApplicationService.canonicalURL($0).path } })
    }
    func addApplicationRoot() {
        let p = NSOpenPanel(); p.canChooseFiles = false; p.canChooseDirectories = true; p.message = "Añade una carpeta que contenga aplicaciones. No se moverá ni cerrará ninguna."
        if p.runModal() == .OK, let url = p.url {
            let path = Safety.lexicalPath(url.path)
            if !appRoots.contains(path) { appRoots.append(path); UserDefaults.standard.set(appRoots, forKey: "applicationRoots") }
            Task { await inventories() }
        }
    }
    func removeApplicationRoot(_ path: String) {
        guard !busy else { return }; appRoots.removeAll { $0 == path }; UserDefaults.standard.set(appRoots, forKey: "applicationRoots"); Task { await inventories() }
    }
    func startupIcon(_ item: StartupItem) -> String? {
        if let path = item.iconPath { return path }
        return apps.filter { !$0.bundleID.isEmpty && (item.label == $0.bundleID || item.label.hasPrefix($0.bundleID + ".")) }.max { $0.bundleID.count < $1.bundleID.count }?.url.path
    }
    func developmentIcon(_ file: FileRecord) -> String? {
        if file.path.contains("/DerivedData/") || file.path.contains("/CoreSimulator/") { return apps.first { $0.bundleID == "com.apple.dt.Xcode" }?.url.path }
        if file.path.contains("/__pycache__/") || file.path.contains("/Caches/pip/") { return apps.first { $0.bundleID.hasPrefix("org.python.") }?.url.path }
        if file.path.contains("/Docker/") { return apps.first { $0.bundleID == "com.docker.docker" }?.url.path }
        return nil
    }
    func log(_ action: String, _ detail: String) throws {
        guard let store else { throw GuardianError.permission("Historial no disponible: modificación bloqueada.") }
        try store.append(HistoryEvent(action: action, detail: detail)); history = store.events
    }
    private func begin(_ message: String) { busy = true; processed = 0; hashDone = 0; hashTotal = 0; status = message }
    private func publish(_ result: ScanResult, index: ScanIndex) { scanIndex = index; scan = result; scanRevision += 1 }
    func chooseFolder() {
        guard !busy else { return }
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.message = "Autoriza una carpeta para un análisis de solo lectura. También puedes elegir una unidad externa."
        if p.runModal() == .OK, let url = p.url { startScan(url) }
    }
    func startScan(_ url: URL) {
        guard !busy else { return }; begin("Analizando \(url.path)…"); duplicates = []; selected = []; folder = url
        let exclusions = exclusions
        operation = Task { [self] in
            let worker = Task.detached(priority: .utility) {
                let result = await Scanner.scan(root: url, exclusions: exclusions) { p in Task { @MainActor [weak self] in self?.processed = p.visited } }
                // Partial scans remain browsable even when the scan was cancelled.
                let index = await Task.detached(priority: .utility) { try? ScanIndex.build(result) }.value ?? ScanIndex()
                return (result, index)
            }
            let (result, index) = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            publish(result, index: index); busy = false
            status = "\(result.files.count) archivos · \(result.cancelled ? "Cancelado: resultado parcial" : result.truncated ? "Límite alcanzado: resultado parcial" : "Análisis terminado") · \(result.issues.count + result.omittedIssues) incidencias"
            do { try log("Análisis", "\(url.path) · \(status) · \(sizeText(index.logical)) lógicos") } catch { self.error = error.localizedDescription }
        }
    }
    func cancel() { operation?.cancel(); status = "Cancelación solicitada…" }
    func selectAll(_ query: FileQuery, recommended: Bool) {
        guard let scan, !busy else { return }; begin(recommended ? "Buscando recomendaciones conservadoras…" : "Seleccionando archivos permitidos…")
        let exclusions = exclusions, groups = duplicates, revision = scanRevision
        operation = Task { [self] in
            do {
                let worker = Task.detached(priority: .utility) { () throws -> Set<String> in
                    let context = recommended ? RecommendationContext.current() : RecommendationContext(processSnapshotAvailable: false, runningExecutables: [])
                    var paths = try RecommendationPolicy.select(files: scan.files, query: query, roots: scan.scopeRoots, exclusions: exclusions, recommendedOnly: recommended, context: context)
                    // Preserve one verified copy when groups have already been compared.
                    for group in groups where group.files.allSatisfy({ paths.contains($0.path) }) { if let first = group.files.first { paths.remove(first.path) } }
                    return paths
                }
                let paths = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                if revision == scanRevision { selected = paths }
                status = paths.isEmpty ? (recommended ? "No hay recomendaciones conservadoras en este filtro. Se conservan todos los archivos." : "No hay archivos seleccionables en este filtro.") : "\(paths.count) seleccionados\(recommended ? " por reglas conservadoras" : " en el filtro actual"). Revisa y autoriza antes de moverlos."
            } catch is CancellationError { status = "Selección cancelada." } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
    func findDuplicates() {
        guard let scan, !busy else { return }; begin("Comparando tamaño, SHA-256 y contenido…"); duplicates = []; progressKind = "archivos comparados"
        operation = Task { [self] in
            do {
                let worker = Task.detached(priority: .utility) { try await Duplicates.find(scan.files) { done, total in if done % 16 == 0 || done == total { Task { @MainActor [weak self] in self?.hashDone = done; self?.hashTotal = total } } } }
                duplicates = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                status = "\(duplicates.count) grupos idénticos. Ninguna copia se seleccionó automáticamente."; try log("Duplicados", status)
            } catch is CancellationError { status = "Comparación cancelada." } catch { self.error = "Comparación interrumpida: \(error.localizedDescription). Vuelve a analizar." }
            busy = false
        }
    }
    func addExclusion() {
        guard !busy else { return }
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = true; p.message = "Elige una ruta para protegerla de análisis y acciones."
        if p.runModal() == .OK, let url = p.url { exclusions.append(Safety.lexicalPath(url.path)); UserDefaults.standard.set(exclusions, forKey: "exclusions"); selected = [] }
    }
    func removeExclusion(_ path: String) { guard !busy else { return }; exclusions.removeAll { $0 == path }; UserDefaults.standard.set(exclusions, forKey: "exclusions") }
    func prepareQuickCleanup() {
        guard !busy else { return }; begin("Analizando cachés regenerables conocidas…")
        let exclusions = exclusions
        operation = Task { [self] in
            let worker = Task.detached(priority: .utility) { () async -> QuickCleanPlan in
                let roots = RecommendationPolicy.quickRoots().filter { FileManager.default.fileExists(atPath: $0.path) }
                var files: [FileRecord] = [], issues: [String] = [], visited = 0
                for root in roots {
                    if Task.isCancelled { break }
                    let remaining = 100_000 - visited
                    if remaining <= 0 { issues.append("Límite de 100 000 entradas para limpieza rápida."); break }
                    let baseVisited = visited
                    let scan = await Scanner.scan(root: root, exclusions: exclusions, limit: remaining) { p in Task { @MainActor [weak self] in self?.processed = baseVisited + p.visited } }
                    visited += scan.visited; files += scan.files; issues += scan.issues
                    if scan.cancelled || scan.truncated { issues.append("Análisis parcial en \(root.path)") }
                    let reported = visited
                    Task { @MainActor [weak self] in self?.processed = reported }
                }
                let context = RecommendationContext.current()
                if !context.processSnapshotAvailable { issues.append("Sin inventario de procesos fiable: no se recomendarán archivos.") }
                let paths = (try? RecommendationPolicy.select(files: files, query: FileQuery(), roots: roots.map(\.path), exclusions: exclusions, recommendedOnly: true, context: context)) ?? []
                return QuickCleanPlan(files: files.filter { paths.contains($0.path) }, roots: roots.map(\.path), issues: Array(issues.prefix(200)), examined: visited)
            }
            let plan = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            busy = false
            if Task.isCancelled { status = "Limpieza rápida cancelada antes de modificar archivos."; return }
            quickPlan = plan; status = "Recomendación preparada: \(plan.files.count) archivos. No se ha modificado nada."
        }
    }
    func trashSelection() {
        guard let scan, !busy else { return }
        let paths = selected, map = scanIndex.byPath
        // This only copies selected snapshots; all filesystem work runs in the worker.
        let files = paths.compactMap { map[$0] }
        executeCleanup(files: files, roots: scan.scopeRoots, recommended: false)
    }
    func executeQuick(_ plan: QuickCleanPlan) { quickPlan = nil; executeCleanup(files: plan.files, roots: plan.roots, recommended: true) }
    private func executeCleanup(files: [FileRecord], roots: [String], recommended: Bool) {
        guard !busy, let store else { error = "Historial no disponible o hay una operación en curso."; return }
        begin("Moviendo únicamente los archivos autorizados a la Papelera…"); progressKind = "archivos procesados"; hashTotal = files.count
        let exclusions = exclusions, groups = duplicates, originalScan = scan
        operation = Task { [self] in
            let worker = Task.detached(priority: .utility) {
                let report = await CleanupEngine.perform(files: files, roots: roots, exclusions: exclusions, duplicateGroups: groups, journal: store, recommendationsOnly: recommended, progress: { done, total in
                    if done % 32 == 0 || done == total { Task { @MainActor [weak self] in self?.hashDone = done; self?.hashTotal = total } }
                })
                var next = originalScan
                let moved = Set(report.moved)
                next?.files.removeAll { moved.contains($0.path) }
                // Index rebuilding is kept off the UI actor, including after cancellation.
                let index = await Task.detached(priority: .utility) { next.flatMap { try? ScanIndex.build($0) } }.value
                return (report, next, index)
            }
            let (report, next, index) = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            if let next, let index { publish(next, index: index) }
            selected = []; duplicates = []; history = store.events; busy = false; cleanupSummary = report
            status = "\(report.moved.count) archivos en Papelera · \(report.failures.count) incidencias\(report.cancelled ? " · cancelado" : ""). Consulta el resumen."
            await refresh()
        }
    }
    func inspect(_ app: InstalledApp) {
        inspection?.cancel(); appDetails = app; associated = ApplicationService.related(app); appSize = nil; appSizePartial = false
        inspection = Task {
            let worker = Task.detached(priority: .utility) { await Scanner.scan(root: app.url, limit: 100_000) }
            let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            if !Task.isCancelled && appDetails?.id == app.id { appSize = result.logical; appSizePartial = result.truncated || !result.issues.isEmpty }
        }
    }
    func recycleApp(_ app: InstalledApp, forceClose: Bool = false) {
        guard !busy else { return }; begin(forceClose ? "Comprobando cierre y desinstalación de \(app.name)…" : "Comprobando \(app.name)…")
        let roots = ["/Applications", NSHomeDirectory() + "/Applications"] + appRoots, exclusions = exclusions
        operation = Task { [self] in
            do {
                let identity = try AppBundleIdentity(app: app)
                let processes = try await Task.detached(priority: .utility) { try ProcessService.list() }.value
                try AppRemoval.validate(app, identity: identity, roots: roots, exclusions: exclusions, processes: processes, allowRunning: forceClose)
                try log("Autorización para desinstalar", "\(app.url.path) · forzar cierre: \(forceClose) · conservar datos asociados")
                let related = NSWorkspace.shared.runningApplications.filter { $0.bundleURL.map { Safety.isInside(ApplicationService.canonicalURL($0).path, root: app.url.path) } ?? false }
                if !related.isEmpty {
                    guard forceClose else { throw GuardianError.unsafe("La aplicación está abierta. Usa Forzar cierre y desinstalar.") }
                    for running in related {
                        guard processes.contains(where: { $0.pid == running.processIdentifier && $0.uid == getuid() }), running.forceTerminate() else { throw GuardianError.permission("No se pudo cerrar la aplicación. No se desinstaló.") }
                    }
                    for _ in 0..<50 {
                        try Task.checkCancellation()
                        if related.allSatisfy(\.isTerminated) { break }
                        try await Task.sleep(for: .milliseconds(160))
                    }
                    guard related.allSatisfy(\.isTerminated) else { throw GuardianError.unsafe("macOS no confirmó el cierre. No se desinstaló.") }
                }
                try Task.checkCancellation()
                let destination = try await Task.detached(priority: .utility) { try AppRemoval.trash(app, identity: identity, roots: roots, exclusions: exclusions) }.value
                try log("Aplicación en Papelera", "\(app.url.path) → \(destination?.path ?? "Papelera"). Se conservaron sus datos.")
                appDetails = nil; status = "\(app.name) en Papelera; datos asociados conservados."; await inventories()
            } catch is CancellationError { status = "Desinstalación cancelada. Comprueba si la aplicación llegó a cerrarse." }
            catch { self.error = error.localizedDescription; try? log("Error de desinstalación", "\(app.url.path): \(error.localizedDescription)") }
            busy = false
        }
    }
    func closeProcess(_ row: ProcessRow, force: Bool) {
        do { try log("Solicitud de cierre", "PID \(row.pid) · \(row.executable) · forzar: \(force)"); try ProcessService.terminate(row, force: force); try log("Cierre solicitado a macOS", "PID \(row.pid). Consulta la siguiente actualización para verificar si terminó.") } catch { self.error = error.localizedDescription }
    }
    func exportReport(csv: Bool = false) {
        guard let scan, !busy else { return }; let p = NSSavePanel(); p.nameFieldStringValue = csv ? "MacGuardian.csv" : "MacGuardian.json"
        guard p.runModal() == .OK, let url = p.url else { return }; begin("Exportando informe…")
        operation = Task { [self] in
            do {
                let worker = Task.detached(priority: .utility) {
                    if csv {
                        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
                        let rows = scan.files.map { [q($0.path), String($0.size), String($0.allocated), q($0.category), q($0.risk.rawValue)].joined(separator: ",") }
                        try Task.checkCancellation(); try ("ruta,bytes_logicos,bytes_asignados,categoria,riesgo\n" + rows.joined(separator: "\n")).write(to: url, atomically: true, encoding: .utf8)
                    } else { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; let data = try encoder.encode(scan); try Task.checkCancellation(); try data.write(to: url, options: .atomic) }
                }
                try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }; status = "Informe exportado."
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}
