import SwiftUI
import AppKit
import MacGuardianCore

@MainActor final class AppModel: ObservableObject {
    @Published var scan: ScanResult?
    @Published var duplicates: [DuplicateGroup] = []
    @Published var processes: [ProcessRow] = []
    @Published var processIssue: String?
    @Published var apps: [InstalledApp] = []
    @Published var startup: [StartupItem] = []
    @Published var metrics = Metrics()
    @Published var busy = false
    @Published var status = "Selecciona una carpeta para comenzar."
    @Published var processed = 0
    @Published var hashDone = 0
    @Published var hashTotal = 0
    @Published var error: String?
    @Published var selected = Set<String>()
    @Published var history: [HistoryEvent] = []
    @Published var exclusions: [String] = UserDefaults.standard.stringArray(forKey: "exclusions") ?? []
    @Published var folder: URL?
    @Published var appDetails: InstalledApp?
    @Published var associated: [AssociatedFile] = []
    @Published var appSize: Int64?
    @Published var appSizePartial = false
    @Published var showMenu = UserDefaults.standard.bool(forKey: "showMenu")
    @Published var interval = max(3, UserDefaults.standard.double(forKey: "interval"))
    private var operation: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private let sampler = MetricsSampler()
    private var store: HistoryStore?
    init() {
        do { store = try HistoryStore(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MacGuardian/history.json")); history = store?.events ?? [] } catch { self.error = "No se pudo leer el historial: \(error.localizedDescription). Las modificaciones quedan bloqueadas." }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                await self.refresh()
                try? await Task.sleep(for: .seconds(self.interval))
            }
        }
        Task { await inventories() }
    }
    func refresh() async {
        let sampler = self.sampler
        let result = await Task.detached(priority: .utility) { (sampler.sample(), Result { try ProcessService.list() }) }.value
        metrics = result.0
        switch result.1 { case .success(let rows): processes = rows; processIssue = nil; case .failure(let error): processIssue = error.localizedDescription }
    }
    func inventories() async {
        let result = await Task.detached(priority: .utility) { (ApplicationService.list(roots: [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]), StartupService.list()) }.value
        apps = result.0; startup = result.1
    }
    func log(_ action: String, _ detail: String) throws {
        guard let store else { throw GuardianError.permission("Historial no disponible: modificación bloqueada.") }
        try store.append(HistoryEvent(action: action, detail: detail)); history = store.events
    }
    func chooseFolder() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.message = "Autoriza una carpeta para un análisis de solo lectura. También puedes elegir una unidad externa."
        if p.runModal() == .OK, let url = p.url { folder = url; startScan(url) }
    }
    func startScan(_ url: URL) {
        guard !busy else { return }; busy = true; processed = 0; scan = nil; duplicates = []; selected = []; status = "Analizando \(url.path)…"; folder = url
        let exclusions = exclusions
        operation = Task { [self] in
            let worker = Task.detached(priority: .utility) {
                await Scanner.scan(root: url, exclusions: exclusions) { p in Task { @MainActor [weak self] in self?.processed = p.visited } }
            }
            let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            scan = result; busy = false
            status = "\(result.files.count) archivos · \(result.cancelled ? "Cancelado: resultado parcial" : result.truncated ? "Límite alcanzado: resultado parcial" : "Análisis terminado") · \(result.issues.count + result.omittedIssues) incidencias"
            do { try log("Análisis", "\(url.path) · \(status) · \(sizeText(result.logical)) lógicos") } catch { self.error = error.localizedDescription }
        }
    }
    func cancel() { operation?.cancel(); status = "Cancelación solicitada…" }
    func findDuplicates() {
        guard let scan, !busy else { return }; busy = true; hashDone = 0; hashTotal = 0; duplicates = []; status = "Comparando tamaño, SHA-256 y contenido…"
        operation = Task { [self] in
            do {
                let worker = Task.detached(priority: .utility) {
                    try await Duplicates.find(scan.files) { done, total in Task { @MainActor [weak self] in self?.hashDone = done; self?.hashTotal = total } }
                }
                duplicates = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                status = "\(duplicates.count) grupos idénticos. No se seleccionó ninguna copia."
                try log("Duplicados", status)
            } catch is CancellationError { status = "Comparación cancelada." } catch { self.error = "Comparación interrumpida: \(error.localizedDescription). Vuelve a analizar." }
            busy = false
        }
    }
    func addExclusion() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = true; p.message = "Elige una ruta para protegerla de análisis y acciones."
        if p.runModal() == .OK, let url = p.url { exclusions.append(Safety.lexicalPath(url.path)); UserDefaults.standard.set(exclusions, forKey: "exclusions"); selected = [] }
    }
    func removeExclusion(_ path: String) { exclusions.removeAll { $0 == path }; UserDefaults.standard.set(exclusions, forKey: "exclusions") }
    func trashSelection() {
        guard let scan, !busy else { return }
        let records = scan.files.filter { selected.contains($0.path) }
        do {
            try Safety.validateSelection(records, roots: [scan.root], exclusions: exclusions, duplicateGroups: duplicates)
            try log("Autorización de Papelera", records.map(\.path).joined(separator: "\n"))
            var failures: [String] = []; var moved = Set<String>()
            for record in records {
                do {
                    try Safety.validate(record, roots: [scan.root], exclusions: exclusions)
                    var coordinationError: NSError?; var actionError: Error?
                    NSFileCoordinator().coordinate(writingItemAt: record.url, options: .forMoving, error: &coordinationError) { url in
                        do {
                            try Safety.validate(record, roots: [scan.root], exclusions: exclusions)
                            var destination: NSURL?
                            try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
                            moved.insert(record.path)
                            try log("Movido a Papelera", "\(record.path) → \(destination?.path ?? "Papelera"). Tamaño lógico: \(sizeText(record.size)). Espacio libre no garantizado.")
                        } catch { actionError = error }
                    }
                    if let e = coordinationError ?? actionError as NSError? { throw e }
                } catch { failures.append("\(record.path): \(error.localizedDescription)"); try? log("Error de Papelera", failures.last!) }
            }
            self.scan?.files.removeAll { moved.contains($0.path) }; selected = []; duplicates = []
            status = "\(moved.count) archivos movidos a la Papelera. Restaura desde Finder → Papelera → Sacar de la papelera."
            if !failures.isEmpty { self.error = failures.joined(separator: "\n") }
        } catch { self.error = error.localizedDescription }
    }
    func inspect(_ app: InstalledApp) {
        appDetails = app; associated = ApplicationService.related(app); appSize = nil; appSizePartial = false
        Task {
            let result = await Task.detached(priority: .utility) { await Scanner.scan(root: app.url, limit: 100_000) }.value
            if appDetails?.id == app.id { appSize = result.logical; appSizePartial = result.truncated || !result.issues.isEmpty }
        }
    }
    func recycleApp(_ app: InstalledApp) {
        do {
            let allowed = ["/Applications", NSHomeDirectory() + "/Applications"]
            let parent = app.url.deletingLastPathComponent().path
            let attrs = try FileManager.default.attributesOfItem(atPath: app.url.path)
            guard allowed.contains(parent), app.url.resolvingSymlinksInPath().path == app.url.path, !app.bundleID.isEmpty, !app.bundleID.hasPrefix("com.apple."), app.bundleID != "local.macguardian.app", !app.running, (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(), !exclusions.contains(where: { Safety.isInside(app.url.path, root: $0) }), Bundle(url: app.url)?.bundleIdentifier == app.bundleID else { throw GuardianError.unsafe("Aplicación protegida, en ejecución, excluida o no administrable por este usuario. Usa su desinstalador oficial o Finder.") }
            try log("Autorización para desinstalar", "Mover solo \(app.url.path). Datos asociados conservados.")
            var destination: NSURL?; try FileManager.default.trashItem(at: app.url, resultingItemURL: &destination)
            try log("Aplicación en Papelera", "\(app.url.path) → \(destination?.path ?? "Papelera"). Se conservaron los datos asociados.")
            appDetails = nil; Task { await inventories() }
        } catch { self.error = error.localizedDescription }
    }
    func closeProcess(_ row: ProcessRow, force: Bool) {
        do { try log("Solicitud de cierre", "PID \(row.pid) · \(row.executable) · forzar: \(force)"); try ProcessService.terminate(row, force: force); try log("Cierre solicitado a macOS", "PID \(row.pid). Consulta la siguiente actualización para verificar si terminó.") } catch { self.error = error.localizedDescription }
    }
    func exportReport(csv: Bool = false) {
        guard let scan else { return }; let p = NSSavePanel(); p.nameFieldStringValue = csv ? "MacGuardian.csv" : "MacGuardian.json"
        guard p.runModal() == .OK, let url = p.url else { return }
        do {
            if csv {
                func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
                let rows = scan.files.map { [q($0.path), String($0.size), String($0.allocated), q($0.category), q($0.risk.rawValue)].joined(separator: ",") }
                try ("ruta,bytes_logicos,bytes_asignados,categoria,riesgo\n" + rows.joined(separator: "\n")).write(to: url, atomically: true, encoding: .utf8)
            } else { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(scan).write(to: url, options: .atomic) }
        } catch { self.error = error.localizedDescription }
    }
}
