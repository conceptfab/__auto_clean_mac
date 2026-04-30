import XCTest
@testable import AutoCleanMacCore

final class OrphanScannerTests: XCTestCase {
    func test_scan_returns_orphan_for_pref_without_installed_app() throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Orphan-\(UUID().uuidString)")
        let prefs = temp.appendingPathComponent("Library/Preferences")
        try FileManager.default.createDirectory(at: prefs, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 200).write(to: prefs.appendingPathComponent("com.dead.app.plist"))
        try Data(repeating: 1, count: 200).write(to: prefs.appendingPathComponent("com.alive.app.plist"))
        defer { try? FileManager.default.removeItem(at: temp) }

        let scanner = OrphanScanner()
        let orphans = scanner.scan(homeDirectory: temp, installedBundleIDs: ["com.alive.app"])
        let bundleIDs = orphans.map(\.bundleID).sorted()
        XCTAssertEqual(bundleIDs, ["com.dead.app"])
        XCTAssertEqual(orphans.first?.paths.count, 1)
        XCTAssertEqual(orphans.first?.totalBytes, 200)
    }

    func test_scan_groups_multiple_paths_for_same_bundle_id() throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Orphan-\(UUID().uuidString)")
        let prefs = temp.appendingPathComponent("Library/Preferences")
        let support = temp.appendingPathComponent("Library/Application Support/com.dead.app")
        try FileManager.default.createDirectory(at: prefs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 100).write(to: prefs.appendingPathComponent("com.dead.app.plist"))
        try Data(repeating: 1, count: 50).write(to: support.appendingPathComponent("data.bin"))
        defer { try? FileManager.default.removeItem(at: temp) }

        let orphans = OrphanScanner().scan(homeDirectory: temp, installedBundleIDs: [])
        XCTAssertEqual(orphans.count, 1)
        XCTAssertEqual(orphans.first?.paths.count, 2)
        XCTAssertEqual(orphans.first?.totalBytes, 150)
    }

    func test_scan_skips_apple_system_bundle_ids() throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Orphan-\(UUID().uuidString)")
        let prefs = temp.appendingPathComponent("Library/Preferences")
        try FileManager.default.createDirectory(at: prefs, withIntermediateDirectories: true)
        try Data().write(to: prefs.appendingPathComponent("com.apple.dock.plist"))
        try Data().write(to: prefs.appendingPathComponent(".GlobalPreferences.plist"))
        defer { try? FileManager.default.removeItem(at: temp) }

        let orphans = OrphanScanner().scan(homeDirectory: temp, installedBundleIDs: [])
        XCTAssertTrue(orphans.isEmpty)
    }
}
