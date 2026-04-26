import XCTest
@testable import AutoCleanMacCore

final class LeftoverPathProviderTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/test")
    private let bundleID = "com.example.MyApp"

    func test_userPaths_includes_classic_locations() {
        let paths = LeftoverPathProvider.userPaths(
            bundleID: bundleID,
            displayName: nil,
            homeDirectory: home
        )
        let asStrings = paths.map(\.path)
        XCTAssertTrue(asStrings.contains("/Users/test/Library/Preferences/com.example.MyApp.plist"))
        XCTAssertTrue(asStrings.contains("/Users/test/Library/Application Support/com.example.MyApp"))
        XCTAssertTrue(asStrings.contains("/Users/test/Library/Caches/com.example.MyApp"))
        XCTAssertTrue(asStrings.contains("/Users/test/Library/Containers/com.example.MyApp"))
        XCTAssertTrue(asStrings.contains("/Users/test/Library/Saved Application State/com.example.MyApp.savedState"))
        XCTAssertTrue(asStrings.contains("/Users/test/Library/HTTPStorages/com.example.MyApp"))
        XCTAssertTrue(asStrings.contains("/Users/test/Library/Logs/com.example.MyApp"))
        XCTAssertTrue(asStrings.contains("/Users/test/Library/WebKit/com.example.MyApp"))
        XCTAssertTrue(asStrings.contains("/Users/test/Library/Cookies/com.example.MyApp.binarycookies"))
        XCTAssertTrue(asStrings.contains("/Users/test/Library/Application Scripts/com.example.MyApp"))
    }

    func test_userPaths_includes_display_name_variants_when_provided() {
        let paths = LeftoverPathProvider.userPaths(
            bundleID: "com.example.MyApp",
            displayName: "MyApp",
            homeDirectory: home
        )
        let asStrings = paths.map(\.path)
        XCTAssertTrue(asStrings.contains("/Users/test/Library/Application Support/MyApp"))
        XCTAssertTrue(asStrings.contains("/Users/test/Library/Caches/MyApp"))
    }

    func test_userPaths_skips_display_name_when_equal_to_bundle_id() {
        let paths = LeftoverPathProvider.userPaths(
            bundleID: "com.example.MyApp",
            displayName: "com.example.MyApp",
            homeDirectory: home
        )
        let appSupport = paths.filter { $0.path.hasSuffix("/Application Support/com.example.MyApp") }
        XCTAssertEqual(appSupport.count, 1, "Nie duplikuj display-name jeśli to ten sam string co bundle ID")
    }

    func test_resolveByHostAndGroupContainers_finds_matching_files() throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LeftoverPathProvider-\(UUID().uuidString)")
        let lib = temp.appendingPathComponent("Library")
        let byHostDir = lib.appendingPathComponent("Preferences/ByHost")
        let groupDir = lib.appendingPathComponent("Group Containers")
        try FileManager.default.createDirectory(at: byHostDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: groupDir, withIntermediateDirectories: true)
        try Data().write(to: byHostDir.appendingPathComponent("com.example.MyApp.ABCDEF.plist"))
        try Data().write(to: byHostDir.appendingPathComponent("com.other.thing.XYZ.plist"))
        try FileManager.default.createDirectory(at: groupDir.appendingPathComponent("group.com.example.MyApp"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: groupDir.appendingPathComponent("ABCD1234.com.example.MyApp"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: groupDir.appendingPathComponent("group.com.unrelated"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let resolved = LeftoverPathProvider.resolveDynamic(
            bundleID: "com.example.MyApp",
            homeDirectory: temp
        )
        let paths = resolved.map(\.path)
        XCTAssertTrue(paths.contains(byHostDir.appendingPathComponent("com.example.MyApp.ABCDEF.plist").path))
        XCTAssertFalse(paths.contains(byHostDir.appendingPathComponent("com.other.thing.XYZ.plist").path))
        XCTAssertTrue(paths.contains(groupDir.appendingPathComponent("group.com.example.MyApp").path))
        XCTAssertTrue(paths.contains(groupDir.appendingPathComponent("ABCD1234.com.example.MyApp").path))
        XCTAssertFalse(paths.contains(groupDir.appendingPathComponent("group.com.unrelated").path))
    }

    func test_resolveDynamic_finds_user_launchagents() throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LeftoverPathProvider-\(UUID().uuidString)")
        let agents = temp.appendingPathComponent("Library/LaunchAgents")
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        try Data().write(to: agents.appendingPathComponent("com.example.MyApp.plist"))
        try Data().write(to: agents.appendingPathComponent("com.example.MyApp.helper.plist"))
        try Data().write(to: agents.appendingPathComponent("com.unrelated.helper.plist"))
        defer { try? FileManager.default.removeItem(at: temp) }

        let resolved = LeftoverPathProvider.resolveDynamic(bundleID: "com.example.MyApp", homeDirectory: temp)
        let paths = resolved.map(\.path)
        XCTAssertTrue(paths.contains(agents.appendingPathComponent("com.example.MyApp.plist").path))
        XCTAssertTrue(paths.contains(agents.appendingPathComponent("com.example.MyApp.helper.plist").path))
        XCTAssertFalse(paths.contains(agents.appendingPathComponent("com.unrelated.helper.plist").path))
    }
}
