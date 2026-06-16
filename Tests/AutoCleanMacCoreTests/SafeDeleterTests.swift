import XCTest
@testable import AutoCleanMacCore

final class SafeDeleterTests: XCTestCase {
    var tempDir: URL!
    var logDir: URL!
    var logger: Logger!

    override func setUpWithError() throws {
        tempDir = try Fixtures.makeTempDir()
        logDir = tempDir.appendingPathComponent("logs")
        logger = try Logger(directory: logDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_delete_file_within_root_removes_and_returns_size() throws {
        let root = tempDir.appendingPathComponent("root")
        let file = root.appendingPathComponent("a.txt")
        try Fixtures.makeFile(at: file, size: 100)
        let deleter = SafeDeleter(mode: .live, logger: logger)
        let freed = try deleter.delete(file, withinRoot: root)
        XCTAssertEqual(freed, 100)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func test_delete_rejects_path_outside_root() throws {
        let root = tempDir.appendingPathComponent("root")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let outside = tempDir.appendingPathComponent("other/file.txt")
        try Fixtures.makeFile(at: outside)
        let deleter = SafeDeleter(mode: .live, logger: logger)
        XCTAssertThrowsError(try deleter.delete(outside, withinRoot: root)) { error in
            guard case SafeDeleter.DeletionError.outsideAllowedRoot = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func test_delete_rejects_symlink_escaping_root() throws {
        let root = tempDir.appendingPathComponent("root")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let outside = tempDir.appendingPathComponent("secret.txt")
        try Fixtures.makeFile(at: outside)
        let link = root.appendingPathComponent("trap")
        try Fixtures.makeSymlink(at: link, pointingTo: outside)
        let deleter = SafeDeleter(mode: .live, logger: logger)
        XCTAssertThrowsError(try deleter.delete(link, withinRoot: root)) { error in
            guard case SafeDeleter.DeletionError.outsideAllowedRoot = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func test_dry_run_does_not_delete_but_returns_size() throws {
        let root = tempDir.appendingPathComponent("root")
        let file = root.appendingPathComponent("a.txt")
        try Fixtures.makeFile(at: file, size: 42)
        let deleter = SafeDeleter(mode: .dryRun, logger: logger)
        let freed = try deleter.delete(file, withinRoot: root)
        XCTAssertEqual(freed, 42)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func test_delete_nonexistent_file_throws() throws {
        let root = tempDir.appendingPathComponent("root")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("gone.txt")
        let deleter = SafeDeleter(mode: .live, logger: logger)
        XCTAssertThrowsError(try deleter.delete(file, withinRoot: root))
    }

    func test_delete_directory_returns_recursive_size() throws {
        let root = tempDir.appendingPathComponent("root")
        let dir = root.appendingPathComponent("cache")
        try Fixtures.makeFile(at: dir.appendingPathComponent("a.bin"), size: 1_000)
        try Fixtures.makeFile(at: dir.appendingPathComponent("sub/b.bin"), size: 2_500)
        try Fixtures.makeFile(at: dir.appendingPathComponent("sub/deeper/c.bin"), size: 500)
        let deleter = SafeDeleter(mode: .live, logger: logger)
        let freed = try deleter.delete(dir, withinRoot: root)
        XCTAssertEqual(freed, 4_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }

    func test_dry_run_directory_returns_recursive_size_without_deleting() throws {
        let root = tempDir.appendingPathComponent("root")
        let dir = root.appendingPathComponent("cache")
        try Fixtures.makeFile(at: dir.appendingPathComponent("x.bin"), size: 300)
        try Fixtures.makeFile(at: dir.appendingPathComponent("y.bin"), size: 700)
        let deleter = SafeDeleter(mode: .dryRun, logger: logger)
        let freed = try deleter.delete(dir, withinRoot: root)
        XCTAssertEqual(freed, 1_000)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
    }

    func test_delete_directory_counts_hidden_files() throws {
        let root = tempDir.appendingPathComponent("root")
        let dir = root.appendingPathComponent("cache")
        try Fixtures.makeFile(at: dir.appendingPathComponent("visible.bin"), size: 200)
        try Fixtures.makeFile(at: dir.appendingPathComponent(".DS_Store"), size: 300)
        try Fixtures.makeFile(at: dir.appendingPathComponent(".hidden/blob.bin"), size: 500)
        let deleter = SafeDeleter(mode: .dryRun, logger: logger)
        let freed = try deleter.delete(dir, withinRoot: root)
        XCTAssertEqual(freed, 1_000)
    }

    func test_trash_mode_moves_file_and_returns_size() throws {
        let root = tempDir.appendingPathComponent("root")
        let file = root.appendingPathComponent("doomed.txt")
        try Fixtures.makeFile(at: file, size: 128)
        let deleter = SafeDeleter(mode: .trash, logger: logger)
        let freed = try deleter.delete(file, withinRoot: root)
        XCTAssertEqual(freed, 128)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func test_trash_mode_still_rejects_path_outside_root() throws {
        let root = tempDir.appendingPathComponent("root")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let outside = tempDir.appendingPathComponent("safe.txt")
        try Fixtures.makeFile(at: outside)
        let deleter = SafeDeleter(mode: .trash, logger: logger)
        XCTAssertThrowsError(try deleter.delete(outside, withinRoot: root)) { error in
            guard case SafeDeleter.DeletionError.outsideAllowedRoot = error else {
                return XCTFail("Wrong error: \(error)")
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func test_trash_mode_directory_returns_recursive_size() throws {
        let root = tempDir.appendingPathComponent("root")
        let dir = root.appendingPathComponent("cache")
        try Fixtures.makeFile(at: dir.appendingPathComponent("a.bin"), size: 1_000)
        try Fixtures.makeFile(at: dir.appendingPathComponent("sub/b.bin"), size: 2_500)
        try Fixtures.makeFile(at: dir.appendingPathComponent(".hidden.bin"), size: 500)
        let deleter = SafeDeleter(mode: .trash, logger: logger)
        let freed = try deleter.delete(dir, withinRoot: root)
        XCTAssertEqual(freed, 4_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }

    func test_isWithin_requires_path_boundary_not_just_prefix() {
        let root = URL(fileURLWithPath: "/Users/x/Library/LaunchAgents")
        let inside = URL(fileURLWithPath: "/Users/x/Library/LaunchAgents/com.foo.plist")
        let sibling = URL(fileURLWithPath: "/Users/x/Library/LaunchAgents-Backup/com.foo.plist")
        XCTAssertTrue(inside.isWithin(root))
        XCTAssertTrue(root.isWithin(root))          // the root itself counts as within
        XCTAssertFalse(sibling.isWithin(root))      // the bug: must NOT match
    }

    func test_isWithin_descendant_and_outside_cases() {
        let root = URL(fileURLWithPath: "/Users/x/Library/LaunchAgents")
        // Deeper descendant is within.
        XCTAssertTrue(URL(fileURLWithPath: "/Users/x/Library/LaunchAgents/sub/com.foo.plist").isWithin(root))
        // Parent and unrelated paths are NOT within.
        XCTAssertFalse(URL(fileURLWithPath: "/Users/x/Library").isWithin(root))
        XCTAssertFalse(URL(fileURLWithPath: "/Users/x/Other").isWithin(root))
        // Trailing slash on the root still matches.
        XCTAssertTrue(URL(fileURLWithPath: "/Users/x/Library/LaunchAgents/com.foo.plist")
            .isWithin(URL(fileURLWithPath: "/Users/x/Library/LaunchAgents/")))
    }

    func test_recursiveMetrics_counts_files_and_symlink_without_following() throws {
        let dir = tempDir.appendingPathComponent("tree")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Fixtures.makeFile(at: dir.appendingPathComponent("a.txt"), size: 100)
        try Fixtures.makeFile(at: dir.appendingPathComponent("sub/b.txt"), size: 50)
        let target = tempDir.appendingPathComponent("outside.txt")
        try Fixtures.makeFile(at: target, size: 999)
        try Fixtures.makeSymlink(at: dir.appendingPathComponent("link"), pointingTo: target)

        let metrics = try SafeDeleter.recursiveMetrics(at: dir)

        // 2 regular files (100 + 50) plus the symlink's own size, which on macOS equals the
        // byte length of the target path it stores. The symlink is NOT followed (999 excluded).
        let expectedSymlinkSize = Int64(target.path.utf8.count)
        XCTAssertEqual(metrics.itemsDeleted, 3)
        XCTAssertEqual(metrics.bytesFreed, 150 + expectedSymlinkSize)
    }
}
