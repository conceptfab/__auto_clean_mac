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

    func test_chrome_cookies_deletes_Cookies_and_journal() async throws {
        let profile = tempDir.appendingPathComponent("Library/Application Support/Google/Chrome/Default")
        try Fixtures.makeFile(at: profile.appendingPathComponent("Cookies"),         size: 500)
        try Fixtures.makeFile(at: profile.appendingPathComponent("Cookies-journal"), size: 50)
        try Fixtures.makeFile(at: profile.appendingPathComponent("Bookmarks"),       size: 999) // zostaje

        let task = BrowserDataTask(browser: .chrome, dataType: .cookies, isEnabled: true, isBrowserRunning: { _ in false })
        let result = await task.run(context: context())

        XCTAssertEqual(result.bytesFreed, 550)
        XCTAssertFalse(FileManager.default.fileExists(atPath: profile.appendingPathComponent("Cookies").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: profile.appendingPathComponent("Cookies-journal").path))
        XCTAssertTrue (FileManager.default.fileExists(atPath: profile.appendingPathComponent("Bookmarks").path))
    }

    func test_chrome_cookies_also_deletes_Network_Cookies() async throws {
        let profile = tempDir.appendingPathComponent("Library/Application Support/Google/Chrome/Default")
        try Fixtures.makeFile(at: profile.appendingPathComponent("Network/Cookies"),         size: 400)
        try Fixtures.makeFile(at: profile.appendingPathComponent("Network/Cookies-journal"), size: 30)

        let task = BrowserDataTask(browser: .chrome, dataType: .cookies, isEnabled: true, isBrowserRunning: { _ in false })
        let result = await task.run(context: context())

        XCTAssertEqual(result.bytesFreed, 430)
        XCTAssertFalse(FileManager.default.fileExists(atPath: profile.appendingPathComponent("Network/Cookies").path))
    }

    func test_firefox_cookies_deletes_sqlite_and_wal_shm() async throws {
        let profile = tempDir.appendingPathComponent("Library/Application Support/Firefox/Profiles/abc.default")
        try Fixtures.makeFile(at: profile.appendingPathComponent("cookies.sqlite"),     size: 400)
        try Fixtures.makeFile(at: profile.appendingPathComponent("cookies.sqlite-wal"), size: 30)
        try Fixtures.makeFile(at: profile.appendingPathComponent("cookies.sqlite-shm"), size: 20)
        try Fixtures.makeFile(at: profile.appendingPathComponent("places.sqlite"),      size: 9999) // MUSI zostać

        let task = BrowserDataTask(browser: .firefox, dataType: .cookies, isEnabled: true, isBrowserRunning: { _ in false })
        let result = await task.run(context: context())

        XCTAssertEqual(result.bytesFreed, 450)
        XCTAssertFalse(FileManager.default.fileExists(atPath: profile.appendingPathComponent("cookies.sqlite").path))
        XCTAssertTrue (FileManager.default.fileExists(atPath: profile.appendingPathComponent("places.sqlite").path))
    }
}
