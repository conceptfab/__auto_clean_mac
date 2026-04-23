import XCTest
@testable import AutoCleanMacCore

final class ConfigWriterTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = try Fixtures.makeTempDir()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_round_trip_preserves_delete_mode_retention_and_browsers() throws {
        var cfg = Config.default
        cfg.retentionDays = 14
        cfg.deleteMode = .live
        cfg.browsers = [
            .chrome:  BrowserPreferences(types: [.cache, .cookies]),
            .firefox: BrowserPreferences(types: [.history]),
        ]
        cfg.tasks.downloads = true

        let file = tempDir.appendingPathComponent("out.json")
        try ConfigWriter.write(cfg, to: file)

        let reloaded = Config.loadOrDefault(from: file, warn: { _ in })
        XCTAssertEqual(reloaded.retentionDays, 14)
        XCTAssertEqual(reloaded.deleteMode, .live)
        XCTAssertTrue(reloaded.tasks.downloads)
        XCTAssertEqual(reloaded.browsers[.chrome]?.types,  [.cache, .cookies])
        XCTAssertEqual(reloaded.browsers[.firefox]?.types, [.history])
        XCTAssertNil(reloaded.browsers[.edge])
    }

    func test_round_trip_dry_run_mode_uses_snake_case() throws {
        var cfg = Config.default
        cfg.deleteMode = .dryRun

        let file = tempDir.appendingPathComponent("dry.json")
        try ConfigWriter.write(cfg, to: file)

        // Pod spodem w JSON powinno być "dry_run" (snake_case), nie "dryRun"
        let data = try Data(contentsOf: file)
        let text = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("\"dry_run\""))
        XCTAssertFalse(text.contains("\"dryRun\""))

        // Reloaded musi dać się z powrotem sparsować jako .dryRun
        let reloaded = Config.loadOrDefault(from: file, warn: { _ in })
        XCTAssertEqual(reloaded.deleteMode, .dryRun)
    }

    func test_write_creates_parent_dirs_atomically() throws {
        let nested = tempDir.appendingPathComponent("a/b/c/config.json")
        try ConfigWriter.write(Config.default, to: nested)
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path))
    }

    func test_full_config_round_trip_equality() throws {
        var cfg = Config.default
        cfg.retentionDays = 21
        cfg.deleteMode = .trash
        cfg.window = Config.Window(fadeInMs: 500, holdAfterMs: 2500, fadeOutMs: 600)
        cfg.tasks = Config.Tasks(
            userCaches: false,
            systemTemp: true,
            trash: false,
            dsStore: true,
            userLogs: false,
            devCaches: true,
            downloads: true
        )
        cfg.browsers = [
            .chrome:  BrowserPreferences(types: [.cache, .cookies, .history]),
            .firefox: BrowserPreferences(types: [.cookies]),
            .brave:   BrowserPreferences(types: [.cache]),
        ]

        let file = tempDir.appendingPathComponent("full.json")
        try ConfigWriter.write(cfg, to: file)

        let reloaded = Config.loadOrDefault(from: file, warn: { _ in })
        XCTAssertEqual(reloaded, cfg, "pełny Config musi się zachować przez ConfigWriter round-trip")
    }
}
