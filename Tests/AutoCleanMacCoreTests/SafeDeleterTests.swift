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
}
