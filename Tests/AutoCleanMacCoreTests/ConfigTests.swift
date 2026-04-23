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

    func test_loads_delete_mode_trash_explicit() throws {
        let file = tempDir.appendingPathComponent("c.json")
        try #"{ "delete_mode": "trash" }"#.write(to: file, atomically: true, encoding: .utf8)
        var warnings: [String] = []
        let config = Config.loadOrDefault(from: file, warn: { warnings.append($0) })
        XCTAssertEqual(config.deleteMode, .trash)
        XCTAssertTrue(warnings.isEmpty)
    }

    func test_default_browsers_all_types_off() {
        let missing = tempDir.appendingPathComponent("nope.json")
        let config = Config.loadOrDefault(from: missing, warn: { _ in })
        for browser in BrowserIdentity.allCases {
            XCTAssertFalse(config.browsers[browser, default: .none].contains(.cache))
            XCTAssertFalse(config.browsers[browser, default: .none].contains(.cookies))
            XCTAssertFalse(config.browsers[browser, default: .none].contains(.history))
        }
    }

    func test_legacy_browser_caches_true_enables_cache_for_all_browsers() throws {
        let file = tempDir.appendingPathComponent("c.json")
        try #"{ "tasks": { "browser_caches": true } }"#.write(to: file, atomically: true, encoding: .utf8)
        let config = Config.loadOrDefault(from: file, warn: { _ in })
        for browser in BrowserIdentity.allCases {
            XCTAssertTrue(config.browsers[browser, default: .none].contains(.cache),
                          "cache powinno być włączone dla \(browser) przez legacy browser_caches")
            XCTAssertFalse(config.browsers[browser, default: .none].contains(.cookies))
        }
    }

    func test_explicit_browsers_section_takes_precedence() throws {
        let file = tempDir.appendingPathComponent("c.json")
        let json = """
        {
          "browsers": {
            "chrome":  { "cache": true,  "cookies": true,  "history": false },
            "firefox": { "cache": false, "cookies": true,  "history": true  }
          }
        }
        """
        try json.write(to: file, atomically: true, encoding: .utf8)
        let config = Config.loadOrDefault(from: file, warn: { _ in })
        XCTAssertTrue (config.browsers[.chrome]!.contains(.cache))
        XCTAssertTrue (config.browsers[.chrome]!.contains(.cookies))
        XCTAssertFalse(config.browsers[.chrome]!.contains(.history))
        XCTAssertFalse(config.browsers[.firefox]!.contains(.cache))
        XCTAssertTrue (config.browsers[.firefox]!.contains(.cookies))
        XCTAssertTrue (config.browsers[.firefox]!.contains(.history))
        XCTAssertEqual(config.browsers[.edge, default: .none].types, [])
    }

    func test_explicit_browsers_override_legacy() throws {
        let file = tempDir.appendingPathComponent("c.json")
        let json = """
        {
          "tasks":   { "browser_caches": true },
          "browsers": { "chrome": { "cache": false, "cookies": false, "history": false } }
        }
        """
        try json.write(to: file, atomically: true, encoding: .utf8)
        let config = Config.loadOrDefault(from: file, warn: { _ in })
        XCTAssertFalse(config.browsers[.chrome, default: .none].contains(.cache))
        XCTAssertTrue (config.browsers[.firefox, default: .none].contains(.cache))
    }
}
