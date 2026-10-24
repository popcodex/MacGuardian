import Foundation

/// Immutable, prepared once on a worker task. Drawing the UI must not walk a file tree.
public struct DirectoryBlock: Identifiable, Sendable {
    public var id: String { path }
    public let path: String
    public var bytes: Int64
    public let isDirectory: Bool
}
public struct DirectorySummary: Sendable {
    public var blocks: [DirectoryBlock] = []
    public var logical: Int64 = 0
    public init(blocks: [DirectoryBlock] = [], logical: Int64 = 0) { self.blocks = blocks; self.logical = logical }
}
public struct ScanIndex: Sendable {
    public var logical: Int64 = 0
    public var allocated: Int64 = 0
    public var candidateCount = 0
    public var categories: [String] = []
    public var directories: [String: DirectorySummary] = [:]
    public var byPath: [String: FileRecord] = [:]
    public init() {}
    public static func build(_ scan: ScanResult) throws -> ScanIndex {
        var result = ScanIndex(), identities = Set<String>(), categories = Set<String>()
        var nodes: [String: [String: DirectoryBlock]] = [:]
        for (offset, file) in scan.files.enumerated() {
            if offset % 512 == 0 { try Task.checkCancellation() }
            result.logical += file.size; result.byPath[file.path] = file; categories.insert(file.category)
            if identities.insert("\(file.device):\(file.inode)").inserted { result.allocated += file.allocated }
            if FileScope.clean.includes(file) { result.candidateCount += 1 }
            var child = file.path, parent = file.url.deletingLastPathComponent().path
            while Safety.isInside(parent, root: scan.root) {
                var block = nodes[parent]?[child] ?? DirectoryBlock(path: child, bytes: 0, isDirectory: child != file.path)
                block.bytes += file.size; nodes[parent, default: [:]][child] = block
                if parent == scan.root || parent == "/" { break }
                child = parent; parent = URL(fileURLWithPath: parent).deletingLastPathComponent().path
            }
        }
        for (path, children) in nodes {
            try Task.checkCancellation()
            let blocks = children.values.sorted { $0.bytes == $1.bytes ? $0.path < $1.path : $0.bytes > $1.bytes }
            result.directories[path] = DirectorySummary(blocks: blocks, logical: blocks.reduce(0) { $0 + $1.bytes })
        }
        result.categories = categories.sorted(); return result
    }
}
public enum FileScope: String, Hashable, Sendable {
    case all, clean, development
    public func includes(_ file: FileRecord) -> Bool {
        switch self {
        case .all: return true
        case .clean: return ["Cachés", "Registros", "Instaladores", "Comprimidos", "Desarrollo"].contains(file.category) && file.risk != .protected
        case .development: return file.category == "Desarrollo"
        }
    }
}
public struct FileQuery: Hashable, Sendable {
    public var revision: Int = 0
    public var scope: FileScope = .all
    public var directory: String?
    public var category = "Todas"
    public var search = ""
    public var order = "Tamaño"
    public var risk = "Todos"
    public init(revision: Int = 0, scope: FileScope = .all, directory: String? = nil, category: String = "Todas", search: String = "", order: String = "Tamaño", risk: String = "Todos") {
        self.revision = revision; self.scope = scope; self.directory = directory; self.category = category; self.search = search; self.order = order; self.risk = risk
    }
    public func matches(_ file: FileRecord) -> Bool {
        scope.includes(file) && (directory == nil || Safety.isInside(file.path, root: directory!)) && (category == "Todas" || file.category == category) && (search.isEmpty || file.path.localizedCaseInsensitiveContains(search)) && (risk == "Todos" || file.risk.rawValue == risk)
    }
    public func evaluate(files: [FileRecord], limit: Int = 1000) throws -> FileQueryResult {
        var matching: [FileRecord] = []
        for (i, file) in files.enumerated() { if i % 512 == 0 { try Task.checkCancellation() }; if matches(file) { matching.append(file) } }
        matching.sort {
            switch order { case "Nombre": return $0.path < $1.path; case "Antigüedad": return $0.modified == $1.modified ? $0.path < $1.path : $0.modified < $1.modified; default: return $0.size == $1.size ? $0.path < $1.path : $0.size > $1.size }
        }
        try Task.checkCancellation()
        return FileQueryResult(rows: Array(matching.prefix(max(0, limit))), count: matching.count)
    }
}
public struct FileQueryResult: Sendable {
    public var rows: [FileRecord] = []
    public var count = 0
    public init(rows: [FileRecord] = [], count: Int = 0) { self.rows = rows; self.count = count }
}
