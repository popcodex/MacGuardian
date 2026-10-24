import Foundation
import Darwin

public enum Safety {
    public static func lexicalPath(_ path: String) -> String {
        var parts: [Substring] = []
        for part in path.split(separator: "/") {
            if part == "." { continue }
            if part == ".." { if !parts.isEmpty { parts.removeLast() } } else { parts.append(part) }
        }
        return "/" + parts.joined(separator: "/")
    }
    public static func hasNoSymbolicAncestors(_ url: URL) -> Bool {
        var current = URL(fileURLWithPath: lexicalPath(url.path))
        while current.path != "/" {
            var info = stat()
            guard lstat(current.path, &info) == 0, (info.st_mode & S_IFMT) != S_IFLNK else { return false }
            current.deleteLastPathComponent()
        }
        return true
    }
    public static func isInside(_ path: String, root: String) -> Bool { path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/") }
    public static func validate(_ record: FileRecord, roots: [String], exclusions: [String]) throws {
        let path = record.path
        guard path == lexicalPath(record.url.path), roots.contains(where: { isInside(path, root: $0) && path != $0 }) else { throw GuardianError.unsafe("Fuera del alcance autorizado: \(path)") }
        let blocked = ["/System", "/Library", "/usr", "/bin", "/sbin", "/private/var", "/dev", "/Volumes/Preboot", NSHomeDirectory() + "/Library/Keychains", NSHomeDirectory() + "/Library/Mail", NSHomeDirectory() + "/Library/Messages", NSHomeDirectory() + "/.Trash"]
        guard !blocked.contains(where: { isInside(path, root: $0) }), !exclusions.contains(where: { isInside(path, root: $0) }) else { throw GuardianError.unsafe("Ruta protegida o excluida: \(path)") }
        guard !path.components(separatedBy: "/").contains(where: { $0.hasSuffix(".app") || $0.hasSuffix(".photoslibrary") || $0 == ".git" }), record.risk != .protected else { throw GuardianError.unsafe("Datos protegidos: \(path)") }
        guard record.links == 1 else { throw GuardianError.unsafe("Enlace físico: conservar para evitar estimaciones incorrectas.") }
        var current = record.url
        while current.path != "/" {
            var s = stat()
            guard lstat(current.path, &s) == 0, (s.st_mode & S_IFMT) != S_IFLNK else { throw GuardianError.unsafe("Enlace simbólico o ruta inaccesible: \(current.path)") }
            current.deleteLastPathComponent()
        }
        var info = stat()
        guard lstat(path, &info) == 0, info.st_uid == getuid(), access(path, W_OK) == 0 else { throw GuardianError.permission("Archivo ajeno o sin permiso: \(path)") }
        guard try FileRecord.read(record.url) == record else { throw GuardianError.changed("El archivo cambió desde el análisis. Vuelve a analizar: \(path)") }
    }
    public static func validateSelection(_ records: [FileRecord], roots: [String], exclusions: [String], duplicateGroups: [DuplicateGroup] = []) throws {
        guard !records.isEmpty else { throw GuardianError.unsafe("Selección vacía") }
        let paths = Set(records.map(\.path))
        guard paths.count == records.count else { throw GuardianError.unsafe("Selección repetida") }
        for group in duplicateGroups where group.files.contains(where: { paths.contains($0.path) }) {
            let keepers = group.files.filter { !paths.contains($0.path) }
            guard keepers.contains(where: { (try? FileRecord.read($0.url)) == $0 }) else { throw GuardianError.unsafe("Debes conservar al menos una copia sin cambios de cada grupo. Vuelve a analizar si una copia desapareció.") }
        }
        for record in records { try validate(record, roots: roots, exclusions: exclusions) }
    }
}
public struct HistoryEvent: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var action: String
    public var detail: String
    public init(action: String, detail: String) { self.action = action; self.detail = detail }
}
public final class HistoryStore {
    public let url: URL
    public private(set) var events: [HistoryEvent]
    public init(url: URL) throws {
        self.url = url
        if FileManager.default.fileExists(atPath: url.path) { events = try JSONDecoder().decode([HistoryEvent].self, from: Data(contentsOf: url)) } else { events = [] }
    }
    public func append(_ event: HistoryEvent) throws {
        var next = events; next.insert(event, at: 0)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(next).write(to: url, options: .atomic)
        events = next
    }
}
