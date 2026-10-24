import Foundation
import Testing
import Darwin
@testable import MacGuardianCore

@Suite(.serialized) final class UpdateTests {
    let root: URL
    init() throws { root = URL(fileURLWithPath: "/private/tmp/MacGuardian-update-" + UUID().uuidString); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    deinit { try? FileManager.default.removeItem(at: root) }
    func file(_ name: String, text: String = "fixture", old: Bool = false) throws -> FileRecord {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        if old { try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -45 * 86400)], ofItemAtPath: url.path) }
        return try FileRecord.read(url)
    }
    func context(active: [String] = [], available: Bool = true) -> RecommendationContext { RecommendationContext(home: root.path, processSnapshotAvailable: available, runningExecutables: active) }
    @Test func quickCleanupWithNoCandidatesIsSuccessfulAndDoesNotMoveAnything() async throws {
        let journal = try HistoryStore(url: root.appendingPathComponent("history.json"))
        let report = await CleanupEngine.perform(files: [], roots: [root.path], exclusions: [], journal: journal, recommendationsOnly: true, mover: { _ in throw GuardianError.unsafe("No debe ejecutarse") })
        #expect(report.moved.isEmpty)
        #expect(report.failures.isEmpty)
        #expect(report.freeBefore != nil)
        #expect(report.freeAfter != nil)
    }
    @Test func automaticQuickPipelineSelectsOnlyOldKnownGarbageWithoutManualSelection() async throws {
        let oldCache = try file("Library/Caches/pip/old.whl", old: true)
        let recent = try file("Library/Caches/pip/recent.whl")
        let personal = try file("Documents/personal.txt", old: true)
        var files: [FileRecord] = []
        let roots = RecommendationPolicy.quickRoots(home: root.path).filter { FileManager.default.fileExists(atPath: $0.path) }
        for scope in roots { files += await Scanner.scan(root: scope).files }
        let selected = try RecommendationPolicy.select(files: files, query: FileQuery(), roots: roots.map(\.path), exclusions: [], recommendedOnly: true, context: context())
        #expect(selected == [oldCache.path])
        let journal = try HistoryStore(url: root.appendingPathComponent("history.json"))
        let trash = root.appendingPathComponent("fixture-trash"); try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let home = root.path
        let report = await CleanupEngine.perform(files: files.filter { selected.contains($0.path) }, roots: roots.map(\.path), exclusions: [], journal: journal, recommendationsOnly: true, contextProvider: { RecommendationContext(home: home, processSnapshotAvailable: true, runningExecutables: []) }, mover: { record in
            let destination = trash.appendingPathComponent(record.url.lastPathComponent)
            try FileManager.default.moveItem(at: record.url, to: destination); return destination
        })
        #expect(report.moved == [oldCache.path])
        #expect(report.failures.isEmpty)
        #expect(FileManager.default.fileExists(atPath: recent.path))
        #expect(FileManager.default.fileExists(atPath: personal.path))
    }
    @Test func processParserPreservesAbsolutePathsWithPaddingAndSpaces() throws {
        let rows = ProcessService.parse("  99   1  501 fixture  1.5  1024  00:12 S     /Applications/Example App.app/Contents/MacOS/Example App\n")
        #expect(rows.count == 1)
        #expect(rows.first?.executable == "/Applications/Example App.app/Contents/MacOS/Example App")
        #expect(rows.first?.name == "Example App")
        #expect(ApplicationService.bundlePath(forExecutable: rows[0].executable) == "/Applications/Example App.app")
        #expect(rows.first?.memory == 1_048_576)
    }
    @Test func bulkSelectionRespectsFiltersExclusionsAndProtectedFiles() throws {
        let a = try file("Downloads/a.txt"), b = try file("Downloads/b.txt"), db = try file("Downloads/private.sqlite"), c = try file("Other/c.txt")
        let files = [a, b, db, c]
        let query = FileQuery(directory: root.appendingPathComponent("Downloads").path)
        let selected = try RecommendationPolicy.select(files: files, query: query, roots: [root.path], exclusions: [b.path], recommendedOnly: false, context: context())
        #expect(selected == [a.path]); #expect(!selected.contains(db.path)); #expect(!selected.contains(c.path))
    }
    @Test func bulkSelectionSkipsHardLinksAndPackages() throws {
        let a = try file("linked.txt")
        try FileManager.default.linkItem(at: a.url, to: root.appendingPathComponent("also-linked.txt"))
        let linked = try FileRecord.read(a.url), bundled = try file("Fixture.app/Contents/test.txt")
        let selected = try RecommendationPolicy.select(files: [linked,bundled], query: FileQuery(), roots: [root.path], exclusions: [], recommendedOnly: false, context: context())
        #expect(selected.isEmpty)
    }
    @Test func recommendationsRequireRecognizedOldRegenerableData() throws {
        let old = try file("Library/Caches/pip/archive.whl", old: true)
        let recent = try file("Library/Caches/pip/recent.whl")
        let personal = try file("Downloads/photo.heic", old: true)
        let installer = try file("Downloads/installer.dmg", old: true)
        let arbitrary = try file("Project/Caches/pip/user.txt", old: true)
        let protected = try file("Library/Caches/pip/database.sqlite", old: true)
        #expect(RecommendationPolicy.reason(for: old, context: context()) != nil)
        for f in [recent, personal, installer, arbitrary, protected] { #expect(RecommendationPolicy.reason(for: f, context: context()) == nil) }
        #expect(RecommendationPolicy.reason(for: old, context: context(active: ["/usr/bin/python3"])) == nil)
        #expect(RecommendationPolicy.reason(for: old, context: context(available: false)) == nil)
    }
    @Test func oldDiagnosticReportsAreRecommendedOnlyInTheirKnownUserFolder() throws {
        let report = try file("Library/Logs/DiagnosticReports/fixture.ips", old: true)
        let personal = try file("Documents/fixture.ips", old: true)
        let recent = try file("Library/Logs/DiagnosticReports/recent.crash")
        #expect(RecommendationPolicy.reason(for: report, context: context()) != nil)
        #expect(RecommendationPolicy.reason(for: personal, context: context()) == nil)
        #expect(RecommendationPolicy.reason(for: recent, context: context()) == nil)
    }
    @Test func pythonBytecodeAndNpmActivityRules() throws {
        let py = try file("Project/__pycache__/a.pyc", old: true), npm = try file(".npm/_cacache/a", old: true)
        #expect(RecommendationPolicy.reason(for: py, context: context()) != nil)
        #expect(RecommendationPolicy.reason(for: py, context: context(active: ["/usr/bin/python3.14"])) == nil)
        #expect(RecommendationPolicy.reason(for: npm, context: context(active: ["/opt/homebrew/bin/node"])) == nil)
        #expect(RecommendationPolicy.quickRoots(home: root.path).allSatisfy { !$0.path.contains("Documents") && Safety.isInside($0.path, root: root.path) })
    }
    @Test func queryLimitsRowsButBulkSelectionUsesAllMatches() throws {
        var files: [FileRecord] = []
        for i in 0..<1200 { files.append(try file("data/\(i).txt")) }
        let query = FileQuery(order: "Nombre")
        let result = try query.evaluate(files: files, limit: 20)
        #expect(result.count == 1200); #expect(result.rows.count == 20)
        let selected = try RecommendationPolicy.select(files: files, query: query, roots: [root.path], exclusions: [], recommendedOnly: false, context: context())
        #expect(selected.count == 1200)
    }
    @Test func directoryIndexMatchesTotalsAndDirectChildren() async throws {
        let a = try file("one/a.txt", text: "abc"), b = try file("one/nested/b.txt", text: "12345"), c = try file("two/c.txt", text: "xx")
        var scan = ScanResult(root: root.path); scan.files = [a,b,c]
        let index = try await Task.detached { try ScanIndex.build(scan) }.value
        #expect(index.logical == scan.logical); #expect(index.allocated == scan.allocated)
        #expect(index.directories[root.path]?.blocks.count == 2)
        #expect(index.directories[root.appendingPathComponent("one").path]?.logical == 8)
        #expect(index.byPath[b.path] == b)
    }
    @Test func largeIndexAndQueryRunOnWorker() async throws {
        let seed = try file("seed.txt")
        let records = (0..<50_000).map { i in FileRecord(path: root.path + "/group\(i % 100)/\(i).txt", size: Int64(i % 100 + 1), allocated: 4096, modified: seed.modified, device: seed.device, inode: UInt64(i + 1000), links: 1, owner: getuid(), category: "Documentos y otros", risk: .review, reason: "fixture") }
        var snapshot = ScanResult(root: root.path); snapshot.files = records
        let start = ProcessInfo.processInfo.systemUptime
        let worker = Task.detached { () throws -> (ScanIndex,FileQueryResult) in let index = try ScanIndex.build(snapshot); return (index,try FileQuery().evaluate(files: snapshot.files)) }
        // The main actor can be serviced while the detached task prepares the index and sorting.
        let heartbeat = await MainActor.run { true }
        let (index, rows) = try await worker.value
        #expect(heartbeat); #expect(index.byPath.count == 50_000); #expect(rows.rows.count == 1000); #expect(rows.count == 50_000)
        print("INDEX_BENCHMARK files=50000 seconds=\(ProcessInfo.processInfo.systemUptime - start)")
    }
    @Test func cleanupMovesOnlyAuthorizedFixturesAndWritesAudit() async throws {
        let a = try file("selected.txt"), keep = try file("keep.txt"), trash = root.appendingPathComponent("fixture-trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let journal = try HistoryStore(url: root.appendingPathComponent("history.json"))
        let report = await CleanupEngine.perform(files: [a], roots: [root.path], exclusions: [], journal: journal, mover: { record in let destination = trash.appendingPathComponent(record.url.lastPathComponent); try FileManager.default.moveItem(at: record.url, to: destination); return destination })
        #expect(report.moved == [a.path]); #expect(report.logicalMoved == a.size); #expect(report.failures.isEmpty)
        #expect(FileManager.default.fileExists(atPath: keep.path)); #expect(FileManager.default.fileExists(atPath: trash.appendingPathComponent("selected.txt").path))
        #expect(report.freeBefore != nil && report.freeAfter != nil)
        let lines = try String(contentsOf: root.appendingPathComponent("history.actions.jsonl"), encoding: .utf8)
        #expect(lines.contains("Autorización de archivo")); #expect(lines.contains("Archivo movido"))
    }
    @Test func changedAndProtectedFilesAreNotMoved() async throws {
        let changed = try file("changed.txt"), db = try file("secret.sqlite")
        try Data("new content".utf8).write(to: changed.url)
        let journal = try HistoryStore(url: root.appendingPathComponent("history.json"))
        let report = await CleanupEngine.perform(files: [changed,db], roots: [root.path], exclusions: [], journal: journal, mover: { _ in throw GuardianError.unsafe("Mover must never be called") })
        #expect(report.moved.isEmpty); #expect(report.failures.count == 2)
        #expect(FileManager.default.fileExists(atPath: changed.path)); #expect(FileManager.default.fileExists(atPath: db.path))
    }
    @Test func failedAuditBlocksAllMoves() async throws {
        let a = try file("selected.txt"), target = try file("private.txt")
        let journal = try HistoryStore(url: root.appendingPathComponent("history.json"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("history.actions.jsonl"), withDestinationURL: target.url)
        let report = await CleanupEngine.perform(files: [a], roots: [root.path], exclusions: [], journal: journal, mover: { _ in throw GuardianError.unsafe("Mover must never be called") })
        #expect(report.moved.isEmpty); #expect(!report.failures.isEmpty); #expect(FileManager.default.fileExists(atPath: a.path))
        #expect(try String(contentsOf: target.url, encoding: .utf8) == "fixture")
    }
    @Test func quickCleanupRechecksToolActivityBeforeActing() async throws {
        let a = try file("Library/Caches/pip/old.whl", old: true), home = root.path
        let journal = try HistoryStore(url: root.appendingPathComponent("history.json"))
        let report = await CleanupEngine.perform(files: [a], roots: [root.path], exclusions: [], journal: journal, recommendationsOnly: true, contextProvider: { RecommendationContext(home: home, processSnapshotAvailable: true, runningExecutables: ["/usr/bin/python3"]) }, mover: { _ in throw GuardianError.unsafe("Mover must never be called") })
        #expect(report.moved.isEmpty); #expect(report.failures.count == 1)
    }
    @Test func cancelledCleanupDoesNotMoveFixtures() async throws {
        let a = try file("selected.txt"), base = root.path, journal = try HistoryStore(url: root.appendingPathComponent("history.json"))
        let task = Task { await CleanupEngine.perform(files: [a], roots: [base], exclusions: [], journal: journal, mover: { _ in throw GuardianError.unsafe("Mover must never be called") }) }
        task.cancel(); let report = await task.value
        #expect(report.cancelled); #expect(report.moved.isEmpty); #expect(FileManager.default.fileExists(atPath: a.path))
    }
    func app(_ name: String = "Fixture", id: String = "com.example.fixture") throws -> InstalledApp {
        let url = root.appendingPathComponent(name + ".app"), contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier":id,"CFBundleName":name,"CFBundleVersion":"1","CFBundlePackageType":"APPL"], format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return InstalledApp(url: url, name: name, version: "1", bundleID: id, lastUsed: nil)
    }
    @Test func appInventoryIncludesAdditionalRootsAndDeduplicates() throws {
        let fixture = try app(), nested = try app("Second")
        let list = ApplicationService.list(roots: [root], discovered: [fixture.url,nested.url])
        #expect(list.count == 2); #expect(list.contains { $0.url.path == fixture.url.path })
        #expect(ApplicationService.defaultRoots.contains { $0.path == "/System/Applications" })
        #expect(ApplicationService.bundlePath(forExecutable: fixture.url.path + "/Contents/MacOS/Fixture") == fixture.url.path)
    }
    @Test func uninstallBlocksActiveProtectedExcludedAndReplacedBundles() throws {
        let fixture = try app(), identity = try AppBundleIdentity(app: fixture)
        let process = ProcessRow(pid: 99999, parent: 1, uid: getuid(), user: "fixture", cpu: 0, memory: 1, elapsed: "0", state: "S", executable: fixture.url.path + "/Contents/MacOS/Fixture", name: "Fixture")
        #expect(throws: (any Error).self) { try AppRemoval.validate(fixture, identity: identity, roots: [root.path], exclusions: [], processes: [process]) }
        try AppRemoval.validate(fixture, identity: identity, roots: [root.path], exclusions: [], processes: [process], allowRunning: true)
        #expect(throws: (any Error).self) { try AppRemoval.validate(fixture, identity: identity, roots: [root.path], exclusions: [fixture.url.path], processes: []) }
        let apple = try app("Protected",id:"com.apple.fixture")
        #expect(throws: (any Error).self) { try AppRemoval.validate(apple, identity: AppBundleIdentity(app: apple), roots: [root.path], exclusions: [], processes: []) }
        try FileManager.default.moveItem(at: fixture.url, to: root.appendingPathComponent("old.app"))
        _ = try app()
        #expect(throws: (any Error).self) { try AppRemoval.validate(fixture, identity: identity, roots: [root.path], exclusions: [], processes: []) }
    }
}
