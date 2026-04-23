import XCTest
@testable import AutoCleanMacCore

final class BrowserDataTaskTests: XCTestCase {
    var tempDir: URL!
    var logger: Logger!

    override func setUpWithError() throws {
        tempDir = try Fixtures.makeTempDir()
        logger = try Logger(directory: tempDir.appendingPathComponent("logs"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func context() -> CleanupContext {
        CleanupContext(
            retentionDays: 7,
            deleter: SafeDeleter(mode: .live, logger: logger),
            logger: logger,
            homeDirectory: tempDir
        )
    }

    func test_disabled_task_skips() async throws {
        let task = BrowserDataTask(browser: .chrome, dataType: .cache, isEnabled: false)
        let result = await task.run(context: context())
        XCTAssertTrue(result.skipped)
    }

    func test_chrome_cache_deletes_Cache_and_CodeCache_under_each_profile() async throws {
        let base = tempDir.appendingPathComponent("Library/Application Support/Google/Chrome")
        let defaultCache = base.appendingPathComponent("Default/Cache/f1.bin")
        let defaultCode  = base.appendingPathComponent("Default/Code Cache/js/f2.bin")
        let p1Cache      = base.appendingPathComponent("Profile 1/Cache/f3.bin")
        let outside      = base.appendingPathComponent("Default/Bookmarks") // MUSI zostać
        try Fixtures.makeFile(at: defaultCache, size: 100)
        try Fixtures.makeFile(at: defaultCode,  size: 200)
        try Fixtures.makeFile(at: p1Cache,      size: 300)
        try Fixtures.makeFile(at: outside,      size: 999)

        let task = BrowserDataTask(browser: .chrome, dataType: .cache, isEnabled: true, isBrowserRunning: { _ in false })
        let result = await task.run(context: context())

        XCTAssertEqual(result.bytesFreed, 600)
        XCTAssertFalse(result.skipped)
        XCTAssertFalse(FileManager.default.fileExists(atPath: defaultCache.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: defaultCode.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: p1Cache.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func test_skips_when_no_profile_root_exists() async throws {
        // brak żadnego katalogu Chrome w tempDir
        let task = BrowserDataTask(browser: .chrome, dataType: .cache, isEnabled: true, isBrowserRunning: { _ in false })
        let result = await task.run(context: context())
        XCTAssertTrue(result.skipped)
        XCTAssertEqual(result.skipReason, "no browser profile directories")
    }

    func test_running_browser_skips_with_warning() async throws {
        let profile = tempDir.appendingPathComponent("Library/Application Support/Google/Chrome/Default/Cache/x.bin")
        try Fixtures.makeFile(at: profile, size: 100)

        let task = BrowserDataTask(browser: .chrome, dataType: .cache, isEnabled: true, isBrowserRunning: { _ in true })
        let result = await task.run(context: context())

        XCTAssertTrue(result.skipped)
        XCTAssertEqual(result.skipReason, "browser running")
        XCTAssertFalse(result.warnings.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: profile.path))
    }
}
