import XCTest
@testable import AutoCleanMacCore

final class OrphanScannerTests: XCTestCase {
    func test_scan_returns_orphan_for_pref_without_installed_app() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Orphan-\(UUID().uuidString)")
        let prefs = temp.appendingPathComponent("Library/Preferences")
        try FileManager.default.createDirectory(at: prefs, withIntermediateDirectories: true)
        let deadPref = prefs.appendingPathComponent("com.dead.app.plist")
        let alivePref = prefs.appendingPathComponent("com.alive.app.plist")
        try Data(repeating: 1, count: 200).write(to: deadPref)
        try Data(repeating: 1, count: 200).write(to: alivePref)
        try makeOld(deadPref)
        try makeOld(alivePref)
        defer { try? FileManager.default.removeItem(at: temp) }

        let scanner = OrphanScanner()
        let orphans = await scanner.scan(homeDirectory: temp, installedBundleIDs: ["com.alive.app"])
        let bundleIDs = orphans.map(\.bundleID).sorted()
        XCTAssertEqual(bundleIDs, ["com.dead.app"])
        XCTAssertEqual(orphans.first?.paths.count, 1)
        XCTAssertEqual(orphans.first?.totalBytes, 200)
    }

    func test_scan_groups_multiple_paths_for_same_bundle_id() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Orphan-\(UUID().uuidString)")
        let prefs = temp.appendingPathComponent("Library/Preferences")
        let support = temp.appendingPathComponent("Library/Application Support/com.dead.app")
        try FileManager.default.createDirectory(at: prefs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let deadPref = prefs.appendingPathComponent("com.dead.app.plist")
        try Data(repeating: 1, count: 100).write(to: deadPref)
        try Data(repeating: 1, count: 50).write(to: support.appendingPathComponent("data.bin"))
        try makeOld(deadPref)
        try makeOld(support)
        defer { try? FileManager.default.removeItem(at: temp) }

        let orphans = await OrphanScanner().scan(homeDirectory: temp, installedBundleIDs: [])
        XCTAssertEqual(orphans.count, 1)
        XCTAssertEqual(orphans.first?.paths.count, 2)
        XCTAssertEqual(orphans.first?.totalBytes, 150)
    }

    func test_scan_skips_apple_system_bundle_ids() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Orphan-\(UUID().uuidString)")
        let prefs = temp.appendingPathComponent("Library/Preferences")
        try FileManager.default.createDirectory(at: prefs, withIntermediateDirectories: true)
        try Data().write(to: prefs.appendingPathComponent("com.apple.dock.plist"))
        try Data().write(to: prefs.appendingPathComponent(".GlobalPreferences.plist"))
        defer { try? FileManager.default.removeItem(at: temp) }

        let orphans = await OrphanScanner().scan(homeDirectory: temp, installedBundleIDs: [])
        XCTAssertTrue(orphans.isEmpty)
    }

    func test_scan_skips_recent_candidates() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Orphan-\(UUID().uuidString)")
        let prefs = temp.appendingPathComponent("Library/Preferences")
        try FileManager.default.createDirectory(at: prefs, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 200).write(to: prefs.appendingPathComponent("com.dead.app.plist"))
        defer { try? FileManager.default.removeItem(at: temp) }

        let orphans = await OrphanScanner().scan(homeDirectory: temp, installedBundleIDs: [])

        XCTAssertTrue(orphans.isEmpty)
    }

    func test_scan_skips_risky_generic_orphan_roots() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Orphan-\(UUID().uuidString)")
        let lib = temp.appendingPathComponent("Library")
        let launchAgents = lib.appendingPathComponent("LaunchAgents")
        let containers = lib.appendingPathComponent("Containers/com.dead.app")
        let scripts = lib.appendingPathComponent("Application Scripts/com.dead.app")
        try FileManager.default.createDirectory(at: launchAgents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: containers, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        let agent = launchAgents.appendingPathComponent("com.dead.app.plist")
        try Data(repeating: 1, count: 100).write(to: agent)
        try makeOld(agent)
        try makeOld(containers)
        try makeOld(scripts)
        defer { try? FileManager.default.removeItem(at: temp) }

        let orphans = await OrphanScanner().scan(homeDirectory: temp, installedBundleIDs: [])

        XCTAssertTrue(orphans.isEmpty)
    }

    private func makeOld(_ url: URL) throws {
        let oldDate = Date(timeIntervalSinceNow: -31 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: url.path)
    }
}
