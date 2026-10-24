import SwiftUI
import AppKit
import ServiceManagement
import MacGuardianCore

struct StorageView: View {
    @EnvironmentObject var m: AppModel
    @Binding var review: Bool
    @ViewState private var category = "Todas"
    @ViewState private var directory: String?
    struct Block: Identifiable { var id: String; var bytes: Int64; var isDirectory: Bool }
    var current: String { directory ?? m.scan?.root ?? "" }
    var children: [Block] {
        guard let scan = m.scan else { return [] }
        var blocks: [String: Block] = [:]
        for file in scan.files where Safety.isInside(file.path, root: current) {
            let rest = file.path.dropFirst(current.count + (current.hasSuffix("/") ? 0 : 1)); let parts = rest.split(separator: "/")
            guard let first = parts.first else { continue }
            let key = (current == "/" ? "" : current) + "/" + first
            var block = blocks[key] ?? Block(id: key, bytes: 0, isDirectory: parts.count > 1)
            block.bytes += file.size; blocks[key] = block
        }
        return blocks.values.sorted { $0.bytes > $1.bytes }
    }
    var categories: [String] { ["Todas"] + Set(m.scan?.files.map(\.category) ?? []).sorted() }
    var files: [FileRecord] { m.scan?.files.filter { Safety.isInside($0.path, root: current) && (category == "Todas" || $0.category == category) } ?? [] }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let scan = m.scan {
                HStack(spacing: 15) { MetricCard(label: "Tamaño lógico analizado", value: sizeText(scan.logical), symbol: "doc.on.doc", detail: "Incluye cada ruta de archivo regular"); MetricCard(label: "Bloques asignados", value: sizeText(scan.allocated), symbol: "externaldrive", detail: "Enlaces físicos contados una vez; clones APFS pueden compartir bloques") }.frame(height: 135)
                HStack { Button { let parent = URL(fileURLWithPath: current).deletingLastPathComponent().path; directory = Safety.isInside(parent, root: scan.root) ? parent : scan.root } label: { Image(systemName: "arrow.up") }.disabled(current == scan.root); Text(current).font(.caption).lineLimit(1).truncationMode(.middle); Spacer(); Picker("Categoría", selection: $category) { ForEach(categories, id: \.self) { Text($0) } }.frame(width: 240) }
                GeometryReader { geo in
                    let total = max(1, children.reduce(Int64(0)) { $0 + $1.bytes })
                    HStack(spacing: 2) {
                        ForEach(Array(children.prefix(12).enumerated()), id: \.element.id) { index, block in
                            Button {
                                if block.isDirectory { directory = block.id } else { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: block.id)]) }
                            } label: {
                                VStack(alignment: .leading, spacing: 6) { Image(systemName: block.isDirectory ? "folder" : "doc"); Text(URL(fileURLWithPath: block.id).lastPathComponent).lineLimit(2); Text(sizeText(block.bytes)).font(.caption2) }.padding(8).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Color(hue: Double(index) / 16 + 0.35, saturation: 0.52, brightness: 0.62), in: RoundedRectangle(cornerRadius: 7))
                            }.buttonStyle(.plain).frame(width: max(2, (geo.size.width - 24) * CGFloat(block.bytes) / CGFloat(total))).clipped().help("\(block.id) · \(sizeText(block.bytes)) · Pulsa para explorar")
                        }
                    }
                }.frame(height: 105)
                Text("Mapa proporcional por tamaño lógico · hasta 12 elementos mayores · pulsa una carpeta para navegar").font(.caption2).foregroundStyle(.secondary)
                if !scan.issues.isEmpty || scan.truncated || scan.cancelled { DisclosureGroup("Cobertura parcial e incidencias (\(scan.issues.count + scan.omittedIssues))") { ScrollView { Text((scan.cancelled ? "Cancelado.\n" : "") + (scan.truncated ? "Límite de 250 000 entradas alcanzado.\n" : "") + scan.issues.joined(separator: "\n")).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 100) } }
            }
            FileBrowser(title: "Archivos", files: files, review: $review)
        }.onChange(of: m.scan?.root) { _, _ in directory = nil; category = "Todas" }
    }
}
struct ApplicationsView: View {
    @EnvironmentObject var m: AppModel
    @ViewState private var search = ""
    @ViewState private var confirm = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { TextField("Buscar aplicación o identificador", text: $search).textFieldStyle(.roundedBorder); Button("Actualizar") { Task { await m.inventories() } } }
            Text("La revisión asociada utiliza el identificador exacto del paquete. Los datos compartidos y personales se conservan. La fecha de acceso no equivale a la última ejecución.").font(.callout).foregroundStyle(.secondary)
            HSplitView {
                List(m.apps.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.bundleID.localizedCaseInsensitiveContains(search) }) { app in
                    Button { m.inspect(app) } label: {
                        HStack { Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 36, height: 36); VStack(alignment: .leading) { Text(app.name).fontWeight(.medium); Text("\(app.version) · \(app.running ? "En ejecución" : "Cerrada")").font(.caption).foregroundStyle(.secondary) }; Spacer() }.padding(.vertical, 5).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }.frame(minWidth: 260)
                ScrollView {
                    if let app = m.appDetails {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(app.name).font(.title2.bold()); Text(app.bundleID).font(.caption).textSelection(.enabled); Text(app.url.path).font(.caption).textSelection(.enabled)
                            Text("Tamaño lógico: \(m.appSize.map(sizeText) ?? "Calculando…")\(m.appSizePartial ? " (parcial)" : "")")
                            Text("Desarrollador: no verificado mediante firma. Última ejecución: no disponible.").font(.caption).foregroundStyle(.secondary)
                            HStack { Button("Mostrar en Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }; Button("Abrir") { NSWorkspace.shared.open(app.url) } }
                            Divider(); Text("Datos asociados · conservar por defecto").font(.headline)
                            ForEach(m.associated) { item in VStack(alignment: .leading, spacing: 5) { Text(item.url.path).font(.caption).textSelection(.enabled); Text(item.reason).font(.caption2).foregroundStyle(.secondary); Button("Revisar en Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } } }
                            if m.associated.isEmpty { Text("Sin coincidencias exactas en ubicaciones accesibles. Esto no garantiza ausencia de otros archivos.").font(.caption).foregroundStyle(.secondary) }
                            Divider(); Text("Para aplicaciones con controladores, VPN, antivirus o servicios privilegiados, utiliza el desinstalador del fabricante. Esta acción mueve solo el paquete .app y conserva sus datos.").font(.caption).foregroundStyle(.secondary)
                            Button("Mover aplicación a Papelera…", role: .destructive) { confirm = true }.disabled(app.running || app.bundleID.hasPrefix("com.apple.") || app.bundleID == "local.macguardian.app")
                        }.padding(18)
                    } else { ContentUnavailableView("Selecciona una aplicación", systemImage: "app.badge") }
                }.frame(minWidth: 340)
            }
        }.alert("¿Mover esta aplicación a la Papelera?", isPresented: $confirm) { Button("Cancelar", role: .cancel) {}; Button("Autorizar", role: .destructive) { if let app = m.appDetails { m.recycleApp(app) } } } message: { Text("\(m.appDetails?.url.path ?? "")\nLos datos asociados permanecerán en el disco. Puedes restaurar el paquete desde la Papelera. No equivale a ejecutar el desinstalador del fabricante.") }
    }
}
struct ProcessesView: View {
    @EnvironmentObject var m: AppModel
    @ViewState private var query = ""
    @ViewState private var chosen: ProcessRow?
    @ViewState private var force = false
    @ViewState private var order = "CPU"
    var rows: [ProcessRow] { let rows = m.processes.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || String($0.pid).contains(query) }; return order == "Memoria" ? rows.sorted { $0.memory > $1.memory } : rows }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { TextField("Buscar nombre o PID", text: $query).textFieldStyle(.roundedBorder); Picker("Orden", selection: $order) { Text("CPU").tag("CPU"); Text("Memoria").tag("Memoria") }.frame(width: 200) }
            if let issue = m.processIssue { Label("Procesos no disponibles: " + issue, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            Text("CPU de ps: promedio durante la vida del proceso; puede superar 100 % con varios núcleos. Memoria: RSS. Solo se permite cerrar aplicaciones identificadas por macOS, del usuario actual y fuera del sistema.").font(.caption).foregroundStyle(.secondary)
            List(rows) { row in
                HStack {
                    VStack(alignment: .leading, spacing: 4) { Text(row.name).bold(); Text("PID \(row.pid) · padre \(row.parent) · \(row.user) · \(row.elapsed) · \(row.state)").font(.caption).foregroundStyle(.secondary); Text(row.observation).font(.caption2).foregroundStyle(.secondary) }.help(row.executable)
                    Spacer(); Text(String(format: "%.1f %%", row.cpu)).monospacedDigit().frame(width: 70); Text(sizeText(row.memory)).frame(width: 85)
                    Menu { Button("Mostrar ejecutable") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: row.executable)]) }; Button("Solicitar cierre…") { force = false; chosen = row }.disabled(!ProcessService.canTerminate(row)); Button("Forzar cierre…", role: .destructive) { force = true; chosen = row }.disabled(!ProcessService.canTerminate(row)) } label: { Image(systemName: "ellipsis.circle") }.fixedSize()
                }.padding(.vertical, 5)
            }
            HStack { Text("Actualización cada \(Int(m.interval)) s · \(m.processes.count) procesos").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Abrir Monitor de Actividad") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")) } }
        }.alert(force ? "¿Forzar el cierre?" : "¿Solicitar el cierre?", isPresented: Binding(get: { chosen != nil }, set: { if !$0 { chosen = nil } })) { Button("Cancelar", role: .cancel) { chosen = nil }; Button("Autorizar cierre", role: .destructive) { if let row = chosen { m.closeProcess(row, force: force) }; chosen = nil } } message: { Text("\(chosen?.name ?? "") · PID \(chosen?.pid ?? 0)\n\(chosen?.executable ?? "")\nPuedes perder cambios sin guardar. La solicitud normal permite que la aplicación decida cómo terminar.") }
    }
}
struct StartupView: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card { Label("Gestionado por macOS", systemImage: "lock.shield").font(.headline); Text("Esta lista muestra archivos plist accesibles, no un inventario completo de elementos modernos. La presencia de un archivo no prueba que el servicio esté cargado. SMAppService solo administra los servicios propios; los elementos de terceros se controlan en Ajustes.").foregroundStyle(.secondary); Button("Abrir Ítems de inicio y extensiones") { SMAppService.openSystemSettingsLoginItems() } }
            List(m.startup) { item in VStack(alignment: .leading, spacing: 5) { HStack { Text(item.label).bold(); Spacer(); Text(item.type).font(.caption).foregroundStyle(.secondary); Button("Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)]) } }; Text(item.program).font(.caption).textSelection(.enabled); Text("\(item.path) · Estado y desarrollador: no verificados · Impacto: no medido").font(.caption2).foregroundStyle(.secondary) }.padding(.vertical, 5) }
        }
    }
}
struct DuplicatesView: View {
    @EnvironmentObject var m: AppModel
    @Binding var review: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Se omiten enlaces físicos repetidos, archivos vacíos y datos protegidos. Los clones APFS pueden compartir bloques: una copia redundante no equivale a espacio físico recuperable.").font(.callout).foregroundStyle(.secondary)
            Button("Comparar archivos del último análisis") { m.findDuplicates() }.buttonStyle(.borderedProminent).tint(.teal).disabled(m.scan == nil || m.busy)
            if m.duplicates.isEmpty { ContentUnavailableView("Sin grupos comparados", systemImage: "square.on.square", description: Text("Analiza una carpeta y ejecuta la comparación. Ningún archivo se selecciona automáticamente.")) } else {
                ScrollView { LazyVStack(alignment: .leading, spacing: 18) { ForEach(m.duplicates) { group in Card { HStack { Text("\(group.files.count) copias idénticas").font(.headline); Spacer(); Text("\(sizeText(group.redundantLogical)) lógicos redundantes").font(.caption) }; ForEach(group.files) { file in HStack { Toggle(isOn: Binding(get: { m.selected.contains(file.path) }, set: { if $0 { m.selected.insert(file.path) } else { m.selected.remove(file.path) } })) { VStack(alignment: .leading) { Text(file.url.lastPathComponent); Text("\(file.path) · \(file.modified.formatted())").font(.caption).foregroundStyle(.secondary).lineLimit(2) } }.toggleStyle(.checkbox); Button("Finder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) } } }; Text("Conserva al menos una copia. La validación bloqueará una selección de todas las copias.").font(.caption).foregroundStyle(.secondary) } } } }
            }
            HStack { Spacer(); Button("Revisar selección (\(m.selected.count))") { review = true }.disabled(m.selected.isEmpty || m.busy) }
        }
    }
}
struct DiagnosticsView: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack { MetricCard(label: "CPU", value: m.metrics.cpuBusy.map { String(format: "%.1f %%", $0) } ?? "Midiendo…", symbol: "cpu", detail: "Ticks ocupados / ticks totales entre muestras"); MetricCard(label: "RAM instalada", value: sizeText(m.metrics.ram), symbol: "memorychip", detail: "Memoria física informada por macOS") }
                Card { Text("Memoria").font(.headline); LabeledContent("Activa + cableada + comprimida", value: sizeText(m.metrics.usedMemory)); LabeledContent("Presión informada por el kernel", value: m.metrics.pressure); Text("Esta suma no incluye todas las categorías de Monitor de Actividad; la memoria de archivos puede ser reutilizada.").font(.caption).foregroundStyle(.secondary); Text("Swap: \(m.metrics.swap)").font(.caption).textSelection(.enabled) }
                Card { Text("Almacenamiento").font(.headline); LabeledContent("Capacidad del volumen", value: sizeText(m.metrics.capacity)); LabeledContent("Disponible", value: sizeText(m.metrics.available)); if m.metrics.capacity > 0 { ProgressView(value: Double(m.metrics.capacity - m.metrics.available), total: Double(m.metrics.capacity)).tint(.mint) }; Text("Capacidad y espacio libre del sistema de archivos. Los volúmenes APFS comparten contenedor; no se suman snapshots, espacio purgable ni cuotas como espacio garantizado.").font(.caption).foregroundStyle(.secondary) }
                Card { Text("Alimentación").font(.headline); Text(m.metrics.battery); Text("Ciclos, salud y capacidad máxima: no expuestos por IOPowerSources en esta versión. Temperaturas y consumo energético por proceso: no disponibles mediante las APIs implementadas.").font(.caption).foregroundStyle(.secondary) }
                Card { Text("Métricas ampliadas").font(.headline); Text("Actividad de disco y red: consulta Monitor de Actividad. MacGuardian no estima tasas sin contadores fiables ni utiliza sensores privados.").foregroundStyle(.secondary); Button("Abrir Monitor de Actividad") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")) } }
            }
        }
    }
}
struct HistoryView: View {
    @EnvironmentObject var m: AppModel
    @ViewState private var search = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { Text("El historial se guarda únicamente en este Mac. Contiene rutas locales; los informes exportados también pueden revelar nombres de archivos.").font(.callout).foregroundStyle(.secondary); TextField("Buscar en el historial", text: $search).textFieldStyle(.roundedBorder); List(m.history.filter { search.isEmpty || $0.detail.localizedCaseInsensitiveContains(search) || $0.action.localizedCaseInsensitiveContains(search) }) { event in VStack(alignment: .leading, spacing: 6) { HStack { Text(event.action).bold(); Spacer(); Text(event.date.formatted()).font(.caption).foregroundStyle(.secondary) }; Text(event.detail).font(.caption).textSelection(.enabled) }.padding(.vertical, 5) } }
    }
}
struct SettingsView: View {
    @EnvironmentObject var m: AppModel
    @AppStorage("appearance") private var appearance = "Oscuro"
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Card { Text("Apariencia y monitor").font(.headline); Picker("Apariencia", selection: $appearance) { ForEach(["Oscuro", "Claro", "Sistema"], id: \.self) { Text($0) } }.pickerStyle(.segmented); Toggle("Mostrar monitor en la barra de menús", isOn: $m.showMenu).onChange(of: m.showMenu) { _, v in UserDefaults.standard.set(v, forKey: "showMenu") }; HStack { Text("Actualización de métricas"); Picker("Intervalo", selection: $m.interval) { Text("3 segundos").tag(3.0); Text("5 segundos").tag(5.0); Text("10 segundos").tag(10.0); Text("30 segundos").tag(30.0) }.labelsHidden().frame(width: 180) }.onChange(of: m.interval) { _, v in UserDefaults.standard.set(v, forKey: "interval") } }
                Card { HStack { Text("Exclusiones protegidas").font(.headline); Spacer(); Button("Añadir ruta…") { m.addExclusion() } }; ForEach(m.exclusions, id: \.self) { path in HStack { Text(path).font(.caption).textSelection(.enabled); Spacer(); Button("Quitar exclusión") { m.removeExclusion(path) } } }; Text("Las exclusiones se aplican al siguiente análisis y se revalidan antes de cada acción.").font(.caption).foregroundStyle(.secondary) }
                Card { Label("Control y privacidad", systemImage: "lock.shield").font(.headline); Text("Sin red, cuentas, publicidad ni telemetría. Sin helper privilegiado ni inicio automático. Todo análisis funciona como simulación: no modifica los archivos examinados. Los permisos de macOS pueden dejar partes sin analizar; se informa de esas incidencias.").foregroundStyle(.secondary); Text("Límite por análisis: 250 000 entradas. Paquetes, .git, enlaces simbólicos y elementos de iCloud se omiten para evitar accesos inesperados. El análisis no representa todo el disco.").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}
