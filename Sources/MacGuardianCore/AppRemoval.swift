import Foundation
import Darwin

public struct AppBundleIdentity: Sendable {
    public let device: Int32
    public let inode: UInt64
    public let bundleID: String
    public init(app: InstalledApp) throws {
        var info = stat()
        guard lstat(app.url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else { throw GuardianError.unsafe("Paquete no válido o enlace simbólico") }
        device = info.st_dev; inode = info.st_ino; bundleID = app.bundleID
    }
}
public enum AppRemoval {
    public static func validate(_ app: InstalledApp, identity: AppBundleIdentity, roots: [String], exclusions: [String], processes: [ProcessRow], allowRunning: Bool = false) throws {
        let path = app.url.path
        guard path.hasSuffix(".app"), path == Safety.lexicalPath(path), roots.contains(where: { path != $0 && Safety.isInside(path, root: $0) }),
              !["/System", "/Library", "/usr", "/bin", "/sbin"].contains(where: { Safety.isInside(path, root: $0) }),
              !exclusions.contains(where: { Safety.isInside(path, root: $0) }), Safety.hasNoSymbolicAncestors(app.url),
              !app.bundleID.isEmpty, !app.bundleID.hasPrefix("com.apple."), app.bundleID != "local.macguardian.app",
              Bundle(url: app.url)?.bundleIdentifier == identity.bundleID, identity.bundleID == app.bundleID else { throw GuardianError.unsafe("Aplicación protegida, excluida o fuera de las carpetas administradas. Añade su carpeta si corresponde.") }
        var info = stat()
        guard lstat(path, &info) == 0, info.st_dev == identity.device, info.st_ino == identity.inode, info.st_uid == getuid(),
              FileManager.default.isWritableFile(atPath: app.url.deletingLastPathComponent().path) else { throw GuardianError.unsafe("El paquete cambió, pertenece a otro usuario o no hay permiso de escritura.") }
        if !allowRunning && processes.contains(where: { Safety.isInside($0.executable, root: path) }) { throw GuardianError.unsafe("Aún hay procesos de esta aplicación activos. No se desinstaló.") }
    }
    public static func trash(_ app: InstalledApp, identity: AppBundleIdentity, roots: [String], exclusions: [String]) throws -> URL? {
        let processes = try ProcessService.list()
        try validate(app, identity: identity, roots: roots, exclusions: exclusions, processes: processes)
        var coordinatorError: NSError?, actionError: Error?, destination: NSURL?
        NSFileCoordinator().coordinate(writingItemAt: app.url, options: .forMoving, error: &coordinatorError) { url in
            do {
                try validate(app, identity: identity, roots: roots, exclusions: exclusions, processes: try ProcessService.list())
                try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
            } catch { actionError = error }
        }
        if let error = coordinatorError { throw error }; if let error = actionError { throw error }
        return destination as URL?
    }
}
