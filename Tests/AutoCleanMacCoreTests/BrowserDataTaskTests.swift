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

    func test_chromium_cache_deletes_under_Library_Caches_root() async throws {
        // Na macOS realny cache Chromium leży w ~/Library/Caches/<vendor>/<profil>/, NIE w Application Support.
        let cachesBase = tempDir.appendingPathComponent("Library/Caches/BraveSoftware/Brave-Browser")
        let defaultCache = cachesBase.appendingPathComponent("Default/Cache/data_1")
        let defaultCode  = cachesBase.appendingPathComponent("Default/Code Cache/js/x.bin")
        try Fixtures.makeFile(at: defaultCache, size: 1000)
        try Fixtures.makeFile(at: defaultCode,  size: 500)

        // Dane w Application Support (cookies) muszą pozostać nietknięte przy czyszczeniu cache.
        let appSupport = tempDir.appendingPathComponent("Library/Application Support/BraveSoftware/Brave-Browser/Default")
        try Fixtures.makeFile(at: appSupport.appendingPathComponent("Cookies"), size: 999)

        let task = BrowserDataTask(browser: .brave, dataType: .cache, isEnabled: true, isBrowserRunning: { _ in false })
        let result = await task.run(context: context())

        XCTAssertEqual(result.bytesFreed, 1500)
        XCTAssertFalse(result.skipped)
        XCTAssertFalse(FileManager.default.fileExists(atPath: defaultCache.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: defaultCode.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: appSupport.appendingPathComponent("Cookies").path))
    }

    func test_permission_denied_on_profile_root_skips_with_full_disk_access_reason() async throws {
        // Symuluje ochronę TCC na nowym macOS: katalog profilu istnieje, ale nie da się go odczytać.
        try XCTSkipIf(getuid() == 0, "root omija uprawnienia POSIX — test nieistotny jako root")

        let root = tempDir.appendingPathComponent("Library/Application Support/BraveSoftware/Brave-Browser")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path) }

        let task = BrowserDataTask(browser: .brave, dataType: .cookies, isEnabled: true, isBrowserRunning: { _ in false })
        let result = await task.run(context: context())

        XCTAssertTrue(result.skipped)
        XCTAssertEqual(result.skipReason, "full_disk_access_required")
        XCTAssertTrue(
            result.warnings.contains { $0.localizedCaseInsensitiveContains("Full Disk Access") },
            "oczekiwano ostrzeżenia kierującego do Full Disk Access, otrzymano: \(result.warnings)"
        )
    }

    func test_chromium_cache_still_cleans_from_caches_when_application_support_is_blocked() async throws {
        try XCTSkipIf(getuid() == 0, "root omija uprawnienia POSIX — test nieistotny jako root")

        let appSupportRoot = tempDir.appendingPathComponent("Library/Application Support/BraveSoftware/Brave-Browser")
        try FileManager.default.createDirectory(at: appSupportRoot, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: appSupportRoot.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: appSupportRoot.path) }

        let cacheFile = tempDir.appendingPathComponent("Library/Caches/BraveSoftware/Brave-Browser/Default/Cache/data.bin")
        try Fixtures.makeFile(at: cacheFile, size: 500)

        let task = BrowserDataTask(browser: .brave, dataType: .cache, isEnabled: true, isBrowserRunning: { _ in false })
        let result = await task.run(context: context())

        XCTAssertFalse(result.skipped)
        XCTAssertEqual(result.bytesFreed, 500)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheFile.path))
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

    func test_chrome_history_deletes_History_and_journal() async throws {
        let profile = tempDir.appendingPathComponent("Library/Application Support/Google/Chrome/Default")
        try Fixtures.makeFile(at: profile.appendingPathComponent("History"),         size: 800)
        try Fixtures.makeFile(at: profile.appendingPathComponent("History-journal"), size: 40)
        try Fixtures.makeFile(at: profile.appendingPathComponent("Bookmarks"),       size: 999) // zostaje

        let task = BrowserDataTask(browser: .chrome, dataType: .history, isEnabled: true, isBrowserRunning: { _ in false })
        let result = await task.run(context: context())

        XCTAssertEqual(result.bytesFreed, 840)
        XCTAssertFalse(FileManager.default.fileExists(atPath: profile.appendingPathComponent("History").path))
        XCTAssertTrue (FileManager.default.fileExists(atPath: profile.appendingPathComponent("Bookmarks").path))
    }

    func test_firefox_history_preserves_places_sqlite_and_deletes_formhistory_downloads() async throws {
        let profile = tempDir.appendingPathComponent("Library/Application Support/Firefox/Profiles/abc.default")
        try Fixtures.makeFile(at: profile.appendingPathComponent("places.sqlite"),       size: 9999) // MUSI zostać (bookmarks!)
        try Fixtures.makeFile(at: profile.appendingPathComponent("formhistory.sqlite"),  size: 700)
        try Fixtures.makeFile(at: profile.appendingPathComponent("downloads.sqlite"),    size: 200)

        let task = BrowserDataTask(browser: .firefox, dataType: .history, isEnabled: true, isBrowserRunning: { _ in false })
        let result = await task.run(context: context())

        XCTAssertEqual(result.bytesFreed, 900)
        XCTAssertTrue (FileManager.default.fileExists(atPath: profile.appendingPathComponent("places.sqlite").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: profile.appendingPathComponent("formhistory.sqlite").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: profile.appendingPathComponent("downloads.sqlite").path))
    }

    func test_chrome_history_scrubs_session_restore_from_preferences() async throws {
        let profile = tempDir.appendingPathComponent("Library/Application Support/Google/Chrome/Default")
        let prefsURL = profile.appendingPathComponent("Preferences")
        let securePrefsURL = profile.appendingPathComponent("Secure Preferences")
        let prefs: [String: Any] = [
            "sessions": ["event_log": [["type": 2, "tab_count": 1]], "session_data_status": 1],
            "saved_tab_groups": ["deleted_group_ids": [:]],
            "profile": ["exit_type": "CrashedOnlyOnce", "name": "Person 1"],
            "browser": ["window_placement": ["left": 0]],
            "brave": ["sessions": ["save_version": 1]],
        ]
        let securePrefs: [String: Any] = [
            "sessions": ["event_log": []],
            "profile": ["exit_type": "Crashed"],
        ]
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: prefs).write(to: prefsURL)
        try JSONSerialization.data(withJSONObject: securePrefs).write(to: securePrefsURL)

        let task = BrowserDataTask(browser: .chrome, dataType: .history, isEnabled: true, isBrowserRunning: { _ in false })
        _ = await task.run(context: context())

        let scrubbed = try JSONSerialization.jsonObject(with: Data(contentsOf: prefsURL)) as! [String: Any]
        XCTAssertNil(scrubbed["sessions"])
        XCTAssertNil(scrubbed["saved_tab_groups"])
        XCTAssertEqual((scrubbed["profile"] as? [String: Any])?["exit_type"] as? String, "Normal")
        XCTAssertNotNil(scrubbed["browser"])
        XCTAssertNil((scrubbed["brave"] as? [String: Any])?["sessions"])

        let scrubbedSecure = try JSONSerialization.jsonObject(with: Data(contentsOf: securePrefsURL)) as! [String: Any]
        XCTAssertNil(scrubbedSecure["sessions"])
        XCTAssertEqual((scrubbedSecure["profile"] as? [String: Any])?["exit_type"] as? String, "Normal")
    }

    func test_chrome_history_also_deletes_session_restore_files() async throws {
        let profile = tempDir.appendingPathComponent("Library/Application Support/Google/Chrome/Default")
        try Fixtures.makeFile(at: profile.appendingPathComponent("Current Session"), size: 100)
        try Fixtures.makeFile(at: profile.appendingPathComponent("Current Tabs"),    size: 50)
        try Fixtures.makeFile(at: profile.appendingPathComponent("Last Session"),    size: 80)
        try Fixtures.makeFile(at: profile.appendingPathComponent("Last Tabs"),       size: 40)
        try Fixtures.makeFile(at: profile.appendingPathComponent("Sessions/Session_00000001"), size: 200)
        try Fixtures.makeFile(at: profile.appendingPathComponent("Bookmarks"),       size: 999) // zostaje

        let task = BrowserDataTask(browser: .chrome, dataType: .history, isEnabled: true, isBrowserRunning: { _ in false })
        let result = await task.run(context: context())

        XCTAssertEqual(result.bytesFreed, 470)
        XCTAssertFalse(FileManager.default.fileExists(atPath: profile.appendingPathComponent("Current Session").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: profile.appendingPathComponent("Last Session").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: profile.appendingPathComponent("Sessions").path))
        XCTAssertTrue (FileManager.default.fileExists(atPath: profile.appendingPathComponent("Bookmarks").path))
    }
}
