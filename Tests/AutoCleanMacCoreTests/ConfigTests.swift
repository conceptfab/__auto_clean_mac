import XCTest
@testable import AutoCleanMacCore

final class ConfigTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("AutoCleanMacTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_default_when_file_missing() {
        let missing = tempDir.appendingPathComponent("nope.json")
        let config = Config.loadOrDefault(from: missing, warn: { _ in })
        XCTAssertEqual(config.retentionDays, 7)
        XCTAssertTrue(config.tasks.userCaches)
        XCTAssertFalse(config.tasks.downloads)
        XCTAssertEqual(config.window.fadeInMs, 800)
    }

    func test_loads_custom_values() throws {
        let file = tempDir.appendingPathComponent("c.json")
        let json = """
        {
          "retention_days": 14,
          "window": { "fade_in_ms": 500, "hold_after_ms": 2000, "fade_out_ms": 500 },
          "tasks": { "downloads": true, "user_caches": false }
        }
        """
        try json.write(to: file, atomically: true, encoding: .utf8)
        let config = Config.loadOrDefault(from: file, warn: { _ in })
        XCTAssertEqual(config.retentionDays, 14)
        XCTAssertEqual(config.window.fadeInMs, 500)
        XCTAssertTrue(config.tasks.downloads)
        XCTAssertFalse(config.tasks.userCaches)
        // Unspecified keys keep defaults:
        XCTAssertTrue(config.tasks.trash)
    }

    func test_malformed_json_falls_back_to_defaults_and_warns() throws {
        let file = tempDir.appendingPathComponent("bad.json")
        try "{ not valid json".write(to: file, atomically: true, encoding: .utf8)
        var warnings: [String] = []
        let config = Config.loadOrDefault(from: file, warn: { warnings.append($0) })
        XCTAssertEqual(config.retentionDays, 7)
        XCTAssertFalse(warnings.isEmpty)
    }

    func test_unknown_keys_are_ignored() throws {
        let file = tempDir.appendingPathComponent("unknown.json")
        let json = """
        { "retention_days": 3, "future_feature": "abc" }
        """
        try json.write(to: file, atomically: true, encoding: .utf8)
        let config = Config.loadOrDefault(from: file, warn: { _ in })
        XCTAssertEqual(config.retentionDays, 3)
    }

    func test_default_delete_mode_is_trash() {
        let missing = tempDir.appendingPathComponent("nope.json")
        let config = Config.loadOrDefault(from: missing, warn: { _ in })
        XCTAssertEqual(config.deleteMode, .trash)
    }

    func test_loads_delete_mode_live() throws {
        let file = tempDir.appendingPathComponent("c.json")
        try #"{ "delete_mode": "live" }"#.write(to: file, atomically: true, encoding: .utf8)
        let config = Config.loadOrDefault(from: file, warn: { _ in })
        XCTAssertEqual(config.deleteMode, .live)
    }

    func test_loads_delete_mode_dry_run() throws {
        let file = tempDir.appendingPathComponent("c.json")
        try #"{ "delete_mode": "dry_run" }"#.write(to: file, atomically: true, encoding: .utf8)
        let config = Config.loadOrDefault(from: file, warn: { _ in })
        XCTAssertEqual(config.deleteMode, .dryRun)
    }

    func test_unknown_delete_mode_warns_and_keeps_default() throws {
        let file = tempDir.appendingPathComponent("c.json")
        try #"{ "delete_mode": "nuke_everything" }"#.write(to: file, atomically: true, encoding: .utf8)
        var warnings: [String] = []
        let config = Config.loadOrDefault(from: file, warn: { warnings.append($0) })
        XCTAssertEqual(config.deleteMode, .trash)
        XCTAssertTrue(warnings.contains(where: { $0.contains("delete_mode") }))
    }
}
