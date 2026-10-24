import SwiftUI
import AppKit
import ServiceManagement
import Combine
import MacGuardianCore

// Explicit property-wrapper alias avoids the SDK 27 State macro, absent from Command Line Tools.
typealias ViewState<Value> = SwiftUI.State<Value>

@main enum MacGuardianMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = GuardianDelegate()
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
@MainActor final class GuardianDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var model: AppModel!
    var statusItem: NSStatusItem?
    var subscriptions = Set<AnyCancellable>()
    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        let menu = NSMenu()
        let main = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Acerca de MacGuardian", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Salir de MacGuardian", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.submenu = appMenu; menu.addItem(main); NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 790), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "MacGuardian"
        window.minSize = NSSize(width: 1000, height: 680)
        window.contentView = NSHostingView(rootView: WindowRoot().environmentObject(model))
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        model.$showMenu.sink { [weak self] enabled in self?.updateMenu(enabled: enabled) }.store(in: &subscriptions)
        model.$metrics.sink { [weak self] _ in if self?.statusItem != nil { self?.updateMenu(enabled: true) } }.store(in: &subscriptions)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { window.makeKeyAndOrderFront(nil); return true }
    func updateMenu(enabled: Bool) {
        if !enabled { if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }; statusItem = nil; return }
        if statusItem == nil { statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength); statusItem?.button?.image = NSImage(systemSymbolName: "shield.lefthalf.filled", accessibilityDescription: "MacGuardian") }
        let menu = NSMenu()
        let cpu = model.metrics.cpuBusy.map { String(format: "%.1f %%", $0) } ?? "Midiendo…"
        for text in ["CPU: \(cpu)", "Memoria: \(sizeText(model.metrics.usedMemory))", "Disponible: \(sizeText(model.metrics.available))"] { let item = NSMenuItem(title: text, action: nil, keyEquivalent: ""); item.isEnabled = false; menu.addItem(item) }
        menu.addItem(.separator())
        let show = NSMenuItem(title: "Abrir MacGuardian", action: #selector(showWindow), keyEquivalent: ""); show.target = self; menu.addItem(show)
        let hide = NSMenuItem(title: "Quitar de la barra", action: #selector(hideMenu), keyEquivalent: ""); hide.target = self; menu.addItem(hide)
        statusItem?.menu = menu
    }
    @objc func showWindow() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func hideMenu() { model.showMenu = false; UserDefaults.standard.set(false, forKey: "showMenu") }
}
struct WindowRoot: View {
    @AppStorage("appearance") var appearance = "Oscuro"
    var body: some View { MainView().environment(\.locale, Locale(identifier: "es")).preferredColorScheme(appearance == "Sistema" ? nil : appearance == "Claro" ? .light : .dark) }
}
struct GuardianLogo: View {
    var size: CGFloat = 42
    static let artwork: NSImage = {
        if let url = Bundle.main.url(forResource: "MacGuardian", withExtension: "icns"), let image = NSImage(contentsOf: url) { return image }
        return NSImage(systemSymbolName: "shield.lefthalf.filled", accessibilityDescription: "MacGuardian")!
    }()
    var body: some View { Image(nsImage: Self.artwork).resizable().aspectRatio(contentMode: .fit).frame(width: size, height: size).accessibilityLabel("Logotipo de MacGuardian") }
}
enum Section: String, CaseIterable {
    case home = "Inicio", storage = "Almacenamiento", clean = "Limpieza", apps = "Aplicaciones", processes = "Procesos", startup = "Inicio automático", duplicates = "Duplicados", development = "Desarrollo", diagnostics = "Diagnóstico", history = "Historial", settings = "Configuración"
    var symbol: String { switch self { case .home: return "square.grid.2x2"; case .storage: return "internaldrive"; case .clean: return "sparkles"; case .apps: return "app.badge"; case .processes: return "waveform.path.ecg"; case .startup: return "power"; case .duplicates: return "square.on.square"; case .development: return "chevron.left.forwardslash.chevron.right"; case .diagnostics: return "stethoscope"; case .history: return "clock.arrow.circlepath"; case .settings: return "slider.horizontal.3" } }
    var subtitle: String { switch self { case .home: return "Tu Mac, con claridad."; case .storage: return "Explora los archivos de las carpetas que autorizas."; case .clean: return "Revisa cada archivo. Tú decides qué conservar."; case .apps: return "Aplicaciones y datos asociados con evidencia verificable."; case .processes: return "Actividad real. Un consumo alto no implica una amenaza."; case .startup: return "Conoce los servicios y gestiona el inicio desde macOS."; case .duplicates: return "Mismo tamaño, SHA-256 y contenido idéntico."; case .development: return "Comprende lo que ocupan tus herramientas de trabajo."; case .diagnostics: return "Métricas del sistema, sin puntuaciones inventadas."; case .history: return "Registro local de análisis y operaciones."; case .settings: return "Tu privacidad y tus preferencias." } }
}
struct MainView: View {
    @EnvironmentObject var m: AppModel
    @ViewState private var section: Section = .home
    @ViewState private var search = ""
    @ViewState private var review = false
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 10) { GuardianLogo(); VStack(alignment: .leading) { Text("MacGuardian").font(.headline); Text("ESPACIO PARA LO IMPORTANTE").font(.system(size: 8, weight: .semibold)).tracking(1).foregroundStyle(.secondary) } }.padding(.horizontal, 12).padding(.top, 22)
                List(Section.allCases, id: \.self, selection: $section) { item in Label(item.rawValue, systemImage: item.symbol).padding(.vertical, 4).tag(item) }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 7) { Label("Local y privado", systemImage: "lock.shield").foregroundStyle(Color.mint); Text("Sin cuentas · Sin telemetría").font(.caption).foregroundStyle(.secondary); Text("v0.1.0 · Edición personal").font(.caption2).foregroundStyle(.tertiary) }.padding(18)
            }.frame(width: 235)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) { Text(section.rawValue).font(.system(size: 29, weight: .bold, design: .rounded)); Text(section.subtitle).foregroundStyle(.secondary) }
                    Spacer()
                    if m.busy { Button("Cancelar", role: .cancel) { m.cancel() } } else { Button { m.chooseFolder() } label: { Label("Analizar carpeta", systemImage: "plus.magnifyingglass") }.buttonStyle(.borderedProminent).tint(.teal) }
                }.padding(28)
                if m.busy { VStack(alignment: .leading, spacing: 6) { if m.hashTotal > 0 { ProgressView(value: Double(m.hashDone), total: Double(m.hashTotal)) } else { ProgressView().controlSize(.small) }; Text(m.hashTotal > 0 ? "\(m.hashDone) de \(m.hashTotal) candidatos comparados" : "\(m.processed) entradas visitadas · El total se conoce al terminar").font(.caption).foregroundStyle(.secondary) }.padding(.horizontal, 28).padding(.bottom, 12) }
                Divider()
                content.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Divider()
                HStack { Circle().fill(m.busy ? .orange : .mint).frame(width: 6, height: 6); Text(m.status).font(.caption).lineLimit(2); Spacer(); if m.scan != nil { Menu("Exportar") { Button("JSON") { m.exportReport() }; Button("CSV") { m.exportReport(csv: true) } }.fixedSize() } }.foregroundStyle(.secondary).padding(12)
            }.background(Color(nsColor: .windowBackgroundColor))
        }.tint(.mint)
        .alert("MacGuardian", isPresented: Binding(get: { m.error != nil }, set: { if !$0 { m.error = nil } })) { Button("Entendido") { m.error = nil } } message: { Text(m.error ?? "") }
        .sheet(isPresented: $review) { ReviewSheet().environmentObject(m) }
        .onChange(of: section) { _, _ in search = "" }
    }
    @ViewBuilder var content: some View {
        switch section {
        case .home: HomeView()
        case .storage: StorageView(review: $review)
        case .clean: FileBrowser(title: "Archivos que requieren revisión", files: m.scan?.candidates ?? [], review: $review, note: "Nada está seleccionado por defecto. Las cachés pueden estar activas. Cierra la aplicación responsable antes de revisarlas.")
        case .apps: ApplicationsView()
        case .processes: ProcessesView()
        case .startup: StartupView()
        case .duplicates: DuplicatesView(review: $review)
        case .development: FileBrowser(title: "Entornos y archivos de desarrollo", files: m.scan?.files.filter { $0.category == "Desarrollo" } ?? [], review: $review, note: "Las dependencias, entornos virtuales, Docker y simuladores están protegidos. No se ejecutan purgas de herramientas ni desinstalaciones ocultas.")
        case .diagnostics: DiagnosticsView()
        case .history: HistoryView()
        case .settings: SettingsView()
        }
    }
}
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { VStack(alignment: .leading, spacing: 14) { content }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(.primary.opacity(0.06))) }
}
struct MetricCard: View {
    let label: String; let value: String; let symbol: String; var detail = ""
    var body: some View { Card { Label(label, systemImage: symbol).font(.subheadline).foregroundStyle(.secondary); Text(value).font(.system(size: 25, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6); Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2) } }
}
struct HomeView: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Card {
                    HStack(spacing: 24) {
                        GuardianLogo(size: 80)
                        VStack(alignment: .leading, spacing: 10) { Text("Cuida lo que importa.").font(.system(size: 28, weight: .semibold, design: .rounded)); Text("Descubre qué ocupa espacio y toma decisiones con contexto.\nCada análisis es de solo lectura.").foregroundStyle(.secondary); Button("ANALIZAR MI MAC") { m.chooseFolder() }.buttonStyle(.borderedProminent).tint(.teal).disabled(m.busy) }
                        Spacer()
                    }.padding(.vertical, 12)
                }
                HStack(spacing: 16) { MetricCard(label: "Almacenamiento disponible", value: sizeText(m.metrics.available), symbol: "internaldrive", detail: "De \(sizeText(m.metrics.capacity)) · volumen de usuario"); MetricCard(label: "CPU ocupada", value: m.metrics.cpuBusy.map { String(format: "%.1f %%", $0) } ?? "Midiendo…", symbol: "cpu", detail: "Diferencia de ticks entre muestras"); MetricCard(label: "Memoria", value: sizeText(m.metrics.usedMemory), symbol: "memorychip", detail: "Activa + cableada + comprimida") }
                Card {
                    HStack { Text("Tu equipo").font(.headline); Spacer(); Text(m.metrics.model).foregroundStyle(.secondary) }
                    HStack { Label(m.metrics.cpu, systemImage: "desktopcomputer"); Spacer(); Text("\(sizeText(m.metrics.ram)) RAM") }; Text(m.metrics.os).font(.caption).foregroundStyle(.secondary)
                    Divider()
                    HStack { Label("\(m.processes.count) procesos", systemImage: "waveform.path.ecg"); Spacer(); Label("\(m.apps.count) aplicaciones", systemImage: "app"); Spacer(); Label("\(m.startup.count) servicios en plist", systemImage: "power") }.font(.callout)
                }
                if let scan = m.scan { Card { Text("Último análisis").font(.headline); Text(scan.root).textSelection(.enabled); Text("\(scan.files.count) archivos · \(sizeText(scan.logical)) lógicos · \(scan.candidates.count) candidatos para revisar"); Text("Los candidatos no equivalen a espacio recuperable garantizado. Mover a Papelera no libera espacio hasta vaciarla desde Finder.").font(.caption).foregroundStyle(.secondary) } }
            }
        }
    }
}
struct FileBrowser: View {
    @EnvironmentObject var m: AppModel
    let title: String; let files: [FileRecord]; @Binding var review: Bool; var note = ""
    @ViewState private var query = ""
    @ViewState private var sort = "Tamaño"
    @ViewState private var riskFilter = "Todos"
    var filtered: [FileRecord] {
        let list = files.filter { (query.isEmpty || $0.path.localizedCaseInsensitiveContains(query)) && (riskFilter == "Todos" || $0.risk.rawValue == riskFilter) }
        return list.sorted { sort == "Nombre" ? $0.path < $1.path : sort == "Antigüedad" ? $0.modified < $1.modified : $0.size > $1.size }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            if !note.isEmpty { Text(note).font(.callout).foregroundStyle(.secondary) }
            HStack { TextField("Buscar por nombre o ruta", text: $query).textFieldStyle(.roundedBorder); Picker("Orden", selection: $sort) { ForEach(["Tamaño", "Nombre", "Antigüedad"], id: \.self) { Text($0) } }.frame(width: 180); Picker("Riesgo", selection: $riskFilter) { ForEach(["Todos", "Revisar", "Regenerable", "Protegido"], id: \.self) { Text($0) } }.frame(width: 180) }
            if m.scan == nil { ContentUnavailableView("Elige una carpeta", systemImage: "folder.badge.questionmark", description: Text("El análisis se limita a la carpeta que autorices.")) } else if filtered.isEmpty { ContentUnavailableView("Sin resultados", systemImage: "checkmark.circle", description: Text("No hay archivos que coincidan en el alcance analizado.")) } else {
                List(filtered.prefix(3000)) { file in
                    HStack(spacing: 12) {
                        Toggle("Seleccionar \(file.url.lastPathComponent)", isOn: Binding(get: { m.selected.contains(file.path) }, set: { if $0 { m.selected.insert(file.path) } else { m.selected.remove(file.path) } })).labelsHidden().toggleStyle(.checkbox).disabled(file.risk == .protected || file.links > 1 || m.busy)
                        Image(systemName: file.risk == .protected ? "lock.fill" : "doc").foregroundStyle(file.risk == .protected ? .red : .mint)
                        VStack(alignment: .leading, spacing: 3) { Text(file.url.lastPathComponent).lineLimit(1); Text(file.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle); Text("\(file.category) · \(file.risk.rawValue) · \(file.modified.formatted(date: .abbreviated, time: .omitted))").font(.caption2).foregroundStyle(.secondary) }.help(file.reason + "\n" + file.path)
                        Spacer(); Text(sizeText(file.size)).monospacedDigit(); Button { NSWorkspace.shared.activateFileViewerSelecting([file.url]) } label: { Image(systemName: "folder") }.help("Mostrar en Finder"); Button { NSWorkspace.shared.open(file.url) } label: { Image(systemName: "eye") }.help("Abrir con la aplicación predeterminada")
                    }.padding(.vertical, 5)
                }.listStyle(.inset).clipShape(RoundedRectangle(cornerRadius: 12))
            }
            HStack { Text("\(filtered.count) resultados\(filtered.count > 3000 ? " · se muestran los primeros 3000; refina la búsqueda o exporta" : "")").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Quitar selección") { m.selected = [] }.disabled(m.selected.isEmpty); Button("Revisar selección (\(m.selected.count))") { review = true }.buttonStyle(.borderedProminent).tint(.teal).disabled(m.selected.isEmpty || m.busy) }
        }
    }
}
struct ReviewSheet: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.dismiss) var dismiss
    @ViewState private var accepted = false
    var records: [FileRecord] { m.scan?.files.filter { m.selected.contains($0.path) } ?? [] }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Revisar antes de mover", systemImage: "trash").font(.title2.bold())
            Text("Se moverán únicamente los archivos seleccionados a la Papelera. Cierra sus aplicaciones antes de continuar. Puedes restaurarlos desde Finder mientras no vacíes la Papelera.").foregroundStyle(.secondary)
            Text("Tamaño lógico: \(sizeText(records.reduce(0) { $0 + $1.size })) · No es espacio físico garantizado. APFS puede compartir bloques.").font(.callout)
            List(records) { f in VStack(alignment: .leading, spacing: 5) { HStack { Text(f.url.lastPathComponent).bold(); Spacer(); Text(sizeText(f.size)); Text(f.risk.rawValue).foregroundStyle(.orange) }; Text(f.path).font(.caption).textSelection(.enabled); Text(f.reason).font(.caption).foregroundStyle(.secondary); Text("Aplicación responsable: no verificada. Recuperación: Papelera, salvo restricciones del volumen.").font(.caption2) } }
            Toggle("He revisado las rutas y autorizo mover estos archivos a la Papelera.", isOn: $accepted)
            HStack { Button("Cancelar") { dismiss() }; Spacer(); Button("Autorizar y mover a Papelera", role: .destructive) { m.trashSelection(); dismiss() }.disabled(!accepted || records.isEmpty) }
        }.padding(26).frame(width: 760, height: 560)
    }
}
