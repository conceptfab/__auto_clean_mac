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

    // MARK: - DSStoreTask

    func test_dsstore_deletes_only_dsstore_files() async throws {
        let desktop = tempDir.appendingPathComponent("Desktop")
        try Fixtures.makeFile(at: desktop.appendingPathComponent(".DS_Store"), size: 50)
        try Fixtures.makeFile(at: desktop.appendingPathComponent("important.txt"), size: 500)
        try Fixtures.makeFile(at: desktop.appendingPathComponent("sub/.DS_Store"), size: 70)
        let task = DSStoreTask(isEnabled: true)
        let result = await task.run(context: makeContext())
        XCTAssertEqual(result.bytesFreed, 120)
        XCTAssertTrue(FileManager.default.fileExists(atPath: desktop.appendingPathComponent("important.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: desktop.appendingPathComponent(".DS_Store").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: desktop.appendingPathComponent("sub/.DS_Store").path))
    }

    // MARK: - UserLogsTask

    func test_user_logs_deletes_old_files_only() async throws {
        let logsRoot = tempDir.appendingPathComponent("Library/Logs")
        try Fixtures.makeFile(at: logsRoot.appendingPathComponent("old.log"),   size: 300, ageInDays: 30)
        try Fixtures.makeFile(at: logsRoot.appendingPathComponent("fresh.log"), size: 300, ageInDays: 1)
        let task = UserLogsTask(isEnabled: true)
        let result = await task.run(context: makeContext())
        XCTAssertEqual(result.bytesFreed, 300)
        XCTAssertFalse(FileManager.default.fileExists(atPath: logsRoot.appendingPathComponent("old.log").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: logsRoot.appendingPathComponent("fresh.log").path))
    }

    // MARK: - SystemTempTask

    func test_system_temp_deletes_old_files_only() async throws {
        let temp = tempDir.appendingPathComponent("temp-root")
        try Fixtures.makeFile(at: temp.appendingPathComponent("old.tmp"),   size: 80, ageInDays: 30)
        try Fixtures.makeFile(at: temp.appendingPathComponent("fresh.tmp"), size: 80, ageInDays: 1)
        let task = SystemTempTask(isEnabled: true, rootOverride: temp)
        let result = await task.run(context: makeContext())
        XCTAssertEqual(result.bytesFreed, 80)
    }

    // MARK: - UserCachesTask

    func test_user_caches_deletes_all_files_regardless_of_mtime() async throws {
        let caches = tempDir.appendingPathComponent("Library/Caches")
        try Fixtures.makeFile(at: caches.appendingPathComponent("a/x.bin"),  size: 100, ageInDays: 0)
        try Fixtures.makeFile(at: caches.appendingPathComponent("b/y.bin"),  size: 200, ageInDays: 30)
        let task = UserCachesTask(isEnabled: true)
        let result = await task.run(context: makeContext())
        XCTAssertEqual(result.bytesFreed, 300)
    }
}
