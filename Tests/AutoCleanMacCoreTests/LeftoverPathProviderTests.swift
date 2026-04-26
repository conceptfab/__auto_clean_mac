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
}
