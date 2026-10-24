import Foundation
import Darwin

public func sizeText(_ bytes: Int64) -> String { bytes == 0 ? "0 bytes" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
public enum Risk: String, Codable, Sendable { case review = "Revisar", protected = "Protegido", regenerable = "Regenerable" }
public struct FileRecord: Identifiable, Codable, Sendable, Hashable {
    public var id: String { path }
    public let path: String
    public let size: Int64
    public let allocated: Int64
    public let modified: Date
    public let device: Int32
    public let inode: UInt64
    public let links: UInt16
    public let category: String
    public let risk: Risk
    public let reason: String
    public var url: URL { URL(fileURLWithPath: path) }
    public static func read(_ url: URL, now: Date = Date()) throws -> FileRecord {
        var s = stat()
        guard lstat(url.path, &s) == 0, (s.st_mode & S_IFMT) == S_IFREG else { throw GuardianError.unsafe("No es un archivo regular: \(url.path)") }
        let date = Date(timeIntervalSince1970: Double(s.st_mtimespec.tv_sec) + Double(s.st_mtimespec.tv_nsec) / 1e9)
        let c = classify(url, modified: date, now: now)
        return FileRecord(path: Safety.lexicalPath(url.path), size: s.st_size, allocated: Int64(s.st_blocks) * 512, modified: date, device: s.st_dev, inode: s.st_ino, links: s.st_nlink, category: c.0, risk: c.1, reason: c.2)
    }
}
public enum GuardianError: LocalizedError {
    case unsafe(String), changed(String), permission(String)
    public var errorDescription: String? { switch self { case .unsafe(let s), .changed(let s), .permission(let s): return s } }
}
public func classify(_ url: URL, modified: Date, now: Date) -> (String, Risk, String) {
    let p = url.path, ext = url.pathExtension.lowercased()
    let old = now.timeIntervalSince(modified) > 30 * 86400
    if p.contains("/.ssh/") || p.contains("/.gnupg/") || p.contains("/.aws/") || p.contains("/.codex/") || p.contains("/.agents/") || url.lastPathComponent == ".env" || ["pem", "key", "p12"].contains(ext) || p.contains("/.git/") || p.contains(".photoslibrary/") || p.contains("/Containers/") || p.contains("/Group Containers/") || p.contains("/Mail/") || p.contains("/Messages/") || p.contains("/Keychains/") || p.contains("/Application Support/") || ["db", "sqlite", "sqlite3", "keychain-db"].contains(ext) {
        return ("Datos de aplicaciones", .protected, "Puede contener datos personales o una base de datos activa; solo lectura.")
    }
    if p.contains("/node_modules/") || p.contains("/.venv/") || p.contains("/venv/") || p.contains("/CoreSimulator/") || p.contains("/Docker/") { return ("Desarrollo", .protected, "Dependencia, entorno o imagen: conservar. Utiliza la herramienta del entorno para administrarlo.") }
    if p.contains("/__pycache__/") && ext == "pyc" && old { return ("Desarrollo", .regenerable, "Bytecode de Python sin modificar durante más de 30 días; puede regenerarse. Cierra Python antes de revisarlo.") }
    if p.contains("/DerivedData/") || p.contains("/.npm/_cacache/") || p.contains("/Caches/Homebrew/") || p.contains("/Caches/pip/") { return ("Desarrollo", .review, "Datos de desarrollo potencialmente regenerables. Cierra las herramientas; la próxima compilación o descarga tardará más.") }
    if p.contains("/Caches/") { return ("Cachés", .review, "Caché de usuario. Puede estar en uso o contener estado; cierra la aplicación y revisa antes de moverla.") }
    if p.contains("/Logs/") && old { return ("Registros", .review, "Registro con más de 30 días; puede ser útil para diagnosticar errores.") }
    if ["dmg", "pkg", "iso"].contains(ext) { return ("Instaladores", .review, "Instalador; comprueba que ya no lo necesitas y que no esté montado.") }
    if ["zip", "tar", "gz", "7z", "rar"].contains(ext) { return ("Comprimidos", .review, "Archivo comprimido: podría ser una copia única. Revisión individual.") }
    if ["jpg", "jpeg", "png", "heic", "raw", "gif", "tiff"].contains(ext) { return ("Fotografías", .review, "Archivo personal. No se considera innecesario.") }
    if ["mp4", "mov", "mkv", "avi"].contains(ext) { return ("Videos", .review, "Archivo personal. No se considera innecesario.") }
    if ["mp3", "m4a", "wav", "flac"].contains(ext) { return ("Música", .review, "Archivo personal. No se considera innecesario.") }
    return (p.contains("/Downloads/") ? "Descargas" : "Documentos y otros", .review, old ? "Sin modificar durante más de 30 días. La antigüedad no implica que sea innecesario." : "Archivo personal; conservar salvo decisión explícita.")
}
public struct ScanResult: Codable, Sendable {
    public var root: String
    public var files: [FileRecord] = []
    public var visited: Int = 0
    public var issues: [String] = []
    public var omittedIssues = 0
    public var cancelled = false
    public var truncated = false
    public var date = Date()
    public var logical: Int64 { files.reduce(0) { $0 + $1.size } }
    public var allocated: Int64 { var seen = Set<String>(); return files.reduce(0) { total, f in seen.insert("\(f.device):\(f.inode)").inserted ? total + f.allocated : total } }
    public var candidates: [FileRecord] { files.filter { ["Cachés", "Registros", "Instaladores", "Comprimidos", "Desarrollo"].contains($0.category) && $0.risk != .protected } }
}
public struct DuplicateGroup: Identifiable, Sendable {
    public let id: String
    public let files: [FileRecord]
    public var redundantLogical: Int64 { Int64(max(0, files.count - 1)) * (files.first?.size ?? 0) }
}
