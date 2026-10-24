import Foundation
import CryptoKit
import Darwin

public struct ScanProgress: Sendable { public let visited: Int; public let path: String }
public enum Scanner {
    private static func next(_ e: FileManager.DirectoryEnumerator) -> URL? { e.nextObject() as? URL }
    public static func scan(root: URL, exclusions: [String] = [], limit: Int = 250_000, progress: @Sendable (ScanProgress) -> Void = { _ in }) async -> ScanResult {
        var result = ScanResult(root: Safety.lexicalPath(root.path))
        func issue(_ text: String) { if result.issues.count < 200 { result.issues.append(text) } else { result.omittedIssues += 1 } }
        guard Safety.hasNoSymbolicAncestors(root) else { issue("La raíz contiene un enlace simbólico; selecciona la carpeta real."); return result }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .isPackageKey, .isUbiquitousItemKey]
        // Traversal is read-only. Never follow symbolic links or enter cloud placeholders/packages.
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants], errorHandler: { url, error in
            issue("\(url.path): \(error.localizedDescription)"); return true
        }) else { issue("No se pudo abrir la carpeta."); return result }
        while let url = next(e) {
            if Task.isCancelled { result.cancelled = true; break }
            result.visited += 1
            if result.visited > limit { result.truncated = true; break }
            if result.visited % 128 == 0 { progress(ScanProgress(visited: result.visited, path: url.path)); await Task.yield() }
            if exclusions.contains(where: { Safety.isInside(url.path, root: $0) }) { e.skipDescendants(); continue }
            do {
                let v = try url.resourceValues(forKeys: Set(keys))
                if v.isUbiquitousItem == true { issue("Omitido por iCloud/File Provider para evitar descargas: \(url.path)"); e.skipDescendants(); continue }
                if v.isSymbolicLink == true || url.lastPathComponent == ".git" { e.skipDescendants(); continue }
                if v.isRegularFile == true { result.files.append(try FileRecord.read(url)) }
            } catch { issue("\(url.path): \(error.localizedDescription)") }
        }
        progress(ScanProgress(visited: result.visited, path: root.path))
        return result
    }
}
public enum Duplicates {
    static func digest(_ file: FileRecord) throws -> String {
        let fd = open(file.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw GuardianError.permission(file.path) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var s = stat(); guard fstat(fd, &s) == 0, s.st_ino == file.inode, s.st_dev == file.device, s.st_size == file.size, (s.st_mode & S_IFMT) == S_IFREG else { throw GuardianError.changed(file.path) }
        var hash = SHA256()
        while true {
            try Task.checkCancellation()
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty { break }; hash.update(data: data)
        }
        guard try FileRecord.read(file.url) == file else { throw GuardianError.changed("Cambió durante el hash: \(file.path)") }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func identical(_ a: FileRecord, _ b: FileRecord) throws -> Bool {
        let fa = open(a.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK), fb = open(b.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fa >= 0, fb >= 0 else { if fa >= 0 { close(fa) }; if fb >= 0 { close(fb) }; throw GuardianError.permission("Sin acceso a un duplicado") }
        let ha = FileHandle(fileDescriptor: fa, closeOnDealloc: true), hb = FileHandle(fileDescriptor: fb, closeOnDealloc: true)
        while true { try Task.checkCancellation(); let x = try ha.read(upToCount: 1_048_576) ?? Data(), y = try hb.read(upToCount: 1_048_576) ?? Data(); if x != y { return false }; if x.isEmpty { break } }
        return try FileRecord.read(a.url) == a && FileRecord.read(b.url) == b
    }
    public static func find(_ files: [FileRecord], progress: @Sendable (Int, Int) -> Void = { _, _ in }) async throws -> [DuplicateGroup] {
        var seen = Set<String>()
        let unique = files.filter { $0.size > 0 && $0.risk != .protected && seen.insert("\($0.device):\($0.inode)").inserted }
        let buckets = Dictionary(grouping: unique, by: \.size).values.filter { $0.count > 1 }
        let total = buckets.reduce(0) { $0 + $1.count }; var done = 0; var groups: [DuplicateGroup] = []
        for bucket in buckets {
            var hashes: [String: [FileRecord]] = [:]
            for f in bucket { try Task.checkCancellation(); let h = try digest(f); hashes[h, default: []].append(f); done += 1; progress(done, total); await Task.yield() }
            for (h, candidates) in hashes where candidates.count > 1 {
                var verified: [FileRecord] = [candidates[0]]
                for f in candidates.dropFirst() { if try identical(candidates[0], f) { verified.append(f) } }
                if verified.count > 1 { groups.append(DuplicateGroup(id: h, files: verified.sorted { $0.path < $1.path })) }
            }
        }
        return groups.sorted { $0.redundantLogical > $1.redundantLogical }
    }
}
