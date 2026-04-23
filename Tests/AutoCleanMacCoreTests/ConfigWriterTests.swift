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
}
