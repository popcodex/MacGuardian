import Foundation
import Testing
@testable import MacGuardianCore

@Suite(.serialized) final class CoreTests {
    var root: URL!
    init() throws {
        root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("MacGuardian-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: root) }
    @discardableResult func file(_ name: String, _ text: String = "test") throws -> URL {
        let url = root.appendingPathComponent(name); try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try Data(text.utf8).write(to: url); return url
    }
    @Test func testReadOnlyScanExclusionSymlinkAndHardlink() async throws {
        let a = try file("a.txt", "Hello")
        _ = try file("excluded/private.txt", "secret")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: a)
        try FileManager.default.linkItem(at: a, to: root.appendingPathComponent("hard.txt"))
        let scan = await Scanner.scan(root: root, exclusions: [root.appendingPathComponent("excluded").path])
        #expect(scan.files.count == 2)
        #expect(scan.logical == 10)
        #expect(scan.allocated == scan.files.first?.allocated)
        #expect(try String(contentsOf: a, encoding: .utf8) == "Hello")
    }
    @Test func testDuplicatesVerifyContentAndKeepOne() async throws {
        _ = try file("a.txt", "identical"); _ = try file("b.txt", "identical"); _ = try file("c.txt", "different")
        let scan = await Scanner.scan(root: root)
        let groups = try await Duplicates.find(scan.files)
        #expect(groups.count == 1); guard let group = groups.first else { return }; #expect(group.files.count == 2)
        #expect(throws: (any Error).self) { try Safety.validateSelection(group.files, roots: [root.path], exclusions: [], duplicateGroups: groups) }
        try Safety.validateSelection([group.files[0]], roots: [root.path], exclusions: [], duplicateGroups: groups)
    }
    @Test func testChangedFileAndSymlinkReplacementRejected() throws {
        let url = try file("a.txt"); let record = try FileRecord.read(url)
        try Data("changed".utf8).write(to: url)
        #expect(throws: (any Error).self) { try Safety.validate(record, roots: [root.path], exclusions: []) }
        try FileManager.default.removeItem(at: url)
        let other = try file("other.txt")
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: other)
        #expect(throws: (any Error).self) { try Safety.validate(record, roots: [root.path], exclusions: []) }
    }
    @Test func testRootBoundaryExclusionAndProtectedData() throws {
        let url = try file("safe.txt"); let record = try FileRecord.read(url)
        #expect(!Safety.isInside(root.path + "-other/a", root: root.path))
        #expect(throws: (any Error).self) { try Safety.validate(record, roots: [root.path + "-other"], exclusions: []) }
        #expect(throws: (any Error).self) { try Safety.validate(record, roots: [root.path], exclusions: [url.path]) }
        let db = try FileRecord.read(file("data.sqlite"))
        #expect(db.risk == .protected)
        #expect(throws: (any Error).self) { try Safety.validate(db, roots: [root.path], exclusions: []) }
        let bundle = try FileRecord.read(file("Example.app/Contents/a.txt"))
        #expect(throws: (any Error).self) { try Safety.validate(bundle, roots: [root.path], exclusions: []) }
    }
    @Test func testScanLimitAndCancellation() async throws {
        for i in 0..<300 { try file("\(i).txt") }
        let limited = await Scanner.scan(root: root, limit: 10)
        #expect(limited.truncated); #expect(limited.files.count == 10)
        let task = Task { await Scanner.scan(root: root) }; task.cancel()
        let cancelled = await task.value
        #expect(cancelled.cancelled)
    }
    @Test func testMissingRootReportsIssue() async {
        let scan = await Scanner.scan(root: root.appendingPathComponent("missing"))
        #expect(scan.files.isEmpty); #expect(!scan.issues.isEmpty)
    }
    @Test func testPermissionDeniedDirectoryAndParentSymlink() async throws {
        let denied = root.appendingPathComponent("denied")
        try FileManager.default.createDirectory(at: denied, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: denied.path)
        let result = await Scanner.scan(root: denied)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path)
        #expect(!result.issues.isEmpty)
        let real = root.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real)
        #expect(!Safety.hasNoSymbolicAncestors(alias))
        #expect(Safety.lexicalPath("/private/tmp/a/../b") == "/private/tmp/b")
    }
    @Test func testMissingDuplicateKeeperRejected() async throws {
        _ = try file("first.txt", "duplicate"); _ = try file("second.txt", "duplicate")
        let scan = await Scanner.scan(root: root)
        let groups = try await Duplicates.find(scan.files)
        guard let group = groups.first else { #expect(Bool(false)); return }
        try FileManager.default.removeItem(at: group.files[1].url)
        #expect(throws: (any Error).self) { try Safety.validateSelection([group.files[0]], roots: [root.path], exclusions: [], duplicateGroups: groups) }
    }
    @Test func testBoundedScanOnLargeFixture() async throws {
        for index in 0..<5000 { try file("large/\(index).txt", "fixture \(index)") }
        let start = ProcessInfo.processInfo.systemUptime
        let scan = await Scanner.scan(root: root, limit: 2000)
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        #expect(scan.truncated)
        #expect(scan.files.count <= 2000)
        print("BENCHMARK fixture=5000 limit=2000 visited=\(scan.visited) retained=\(scan.files.count) seconds=\(elapsed)")
    }
    @Test func testHistoryPersistence() throws {
        let url = root.appendingPathComponent("history.json")
        let store = try HistoryStore(url: url); try store.append(HistoryEvent(action: "Test", detail: "Solo fixture"))
        #expect(try HistoryStore(url: url).events.first?.action == "Test")
    }
    @Test func testClassificationDoesNotPromotePersonalFiles() throws {
        let old = Date(timeIntervalSinceNow: -90 * 86400)
        #expect(classify(root.appendingPathComponent("photo.heic"), modified: old, now: Date()).1 == .review)
        #expect(classify(root.appendingPathComponent("node_modules/a.js"), modified: old, now: Date()).1 == .protected)
        #expect(classify(root.appendingPathComponent("__pycache__/a.pyc"), modified: old, now: Date()).1 == .regenerable)
    }
}
