import XCTest
@testable import AutoCleanMacCore

final class TasksTests: XCTestCase {
    var tempDir: URL!
    var logger: Logger!
    var deleter: SafeDeleter!

    override func setUpWithError() throws {
        tempDir = try Fixtures.makeTempDir()
        logger = try Logger(directory: tempDir.appendingPathComponent("logs"))
        deleter = SafeDeleter(mode: .live, logger: logger)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func makeContext(home: URL? = nil) -> CleanupContext {
        CleanupContext(
            retentionDays: 7,
            deleter: deleter,
            logger: logger,
            homeDirectory: home ?? tempDir
        )
    }

    // MARK: - TrashTask

    func test_trash_deletes_files_older_than_retention() async throws {
        let trash = tempDir.appendingPathComponent(".Trash")
        try Fixtures.makeFile(at: trash.appendingPathComponent("old.txt"), size: 100, ageInDays: 30)
        try Fixtures.makeFile(at: trash.appendingPathComponent("fresh.txt"), size: 100, ageInDays: 1)
        let task = TrashTask(isEnabled: true)
        let result = await task.run(context: makeContext())
        XCTAssertEqual(result.bytesFreed, 100)
        XCTAssertFalse(FileManager.default.fileExists(atPath: trash.appendingPathComponent("old.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trash.appendingPathComponent("fresh.txt").path))
    }

    func test_trash_skipped_when_disabled() async throws {
        let task = TrashTask(isEnabled: false)
        let result = await task.run(context: makeContext())
        XCTAssertTrue(result.skipped)
        XCTAssertEqual(result.bytesFreed, 0)
    }

    func test_trash_skipped_when_root_missing() async throws {
        let task = TrashTask(isEnabled: true)
        let result = await task.run(context: makeContext())
        XCTAssertTrue(result.skipped)
    }
}
