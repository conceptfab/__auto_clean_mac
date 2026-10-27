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

    func test_scan_treats_bundleID_suffixed_files_of_installed_app_as_installed() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Orphan-\(UUID().uuidString)")
        let prefs = temp.appendingPathComponent("Library/Preferences")
        try FileManager.default.createDirectory(at: prefs, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        for name in ["com.alive.app.autoclean.plist", "com.alive.application.plist"] {
            let url = prefs.appendingPathComponent(name)
            try Data(repeating: 1, count: 10).write(to: url)
            try makeOld(url)
        }

        let orphans = await OrphanScanner().scan(homeDirectory: temp, installedBundleIDs: ["com.alive.app"])
        // Granica na kropce: `com.alive.application` to inna aplikacja — nadal sierota.
        XCTAssertEqual(orphans.map(\.bundleID), ["com.alive.application"])
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

    func test_scan_ignores_non_bundle_id_and_shared_folders() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Orphan-\(UUID().uuidString)")
        let lib = temp.appendingPathComponent("Library")
        defer { try? FileManager.default.removeItem(at: temp) }
        let names = [
            "Application Support/MobileSync",
            "Application Support/AddressBook",
            "Application Support/CloudDocs",
            "Application Support/Code",
            "Application Support/Steam",
            "Application Support/com.google.Keystone",
            "Application Support/org.sparkle-project.Sparkle",
            "Application Support/com.vendor",          // tylko jedna kropka
            "Caches/pypoetry",
            "Logs/Some Folder.with.dots",               // spacja — to nie bundle ID
            "Application Support/com.dead.app",
        ]
        for name in names {
            let dir = lib.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 10).write(to: dir.appendingPathComponent("data.bin"))
            try makeOld(dir)
        }
        let prefs = lib.appendingPathComponent("Preferences")
        try FileManager.default.createDirectory(at: prefs, withIntermediateDirectories: true)
        let loginwindow = prefs.appendingPathComponent("loginwindow.plist")
        try Data(repeating: 1, count: 10).write(to: loginwindow)
        try makeOld(loginwindow)

        let orphans = await OrphanScanner().scan(homeDirectory: temp, installedBundleIDs: [])

        XCTAssertEqual(orphans.map(\.bundleID), ["com.dead.app"])
    }

    func test_scan_matches_installed_bundle_ids_case_insensitively() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Orphan-\(UUID().uuidString)")
        let support = temp.appendingPathComponent("Library/Application Support/com.Vendor.App")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try makeOld(support)
        defer { try? FileManager.default.removeItem(at: temp) }

        let orphans = await OrphanScanner().scan(homeDirectory: temp, installedBundleIDs: ["com.vendor.app"])

        XCTAssertTrue(orphans.isEmpty)
    }

    func test_looks_like_bundle_identifier() {
        XCTAssertTrue(OrphanScanner.looksLikeBundleIdentifier("com.dead.app"))
        XCTAssertTrue(OrphanScanner.looksLikeBundleIdentifier("org.my-co.App_Helper"))
        XCTAssertFalse(OrphanScanner.looksLikeBundleIdentifier("com.vendor"))
        XCTAssertFalse(OrphanScanner.looksLikeBundleIdentifier("MobileSync"))
        XCTAssertFalse(OrphanScanner.looksLikeBundleIdentifier("com..app"))
        XCTAssertFalse(OrphanScanner.looksLikeBundleIdentifier("com.dead.app/.."))
        XCTAssertFalse(OrphanScanner.looksLikeBundleIdentifier("a b.c.d"))
    }

    private func makeOld(_ url: URL) throws {
        let oldDate = Date(timeIntervalSinceNow: -31 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: url.path)
    }
}
