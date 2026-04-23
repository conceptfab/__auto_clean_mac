import XCTest
@testable import AutoCleanMacCore

final class BrowserIdentityTests: XCTestCase {
    let home = URL(fileURLWithPath: "/Users/test")

    func test_all_browsers_have_stable_raw_values() {
        XCTAssertEqual(BrowserIdentity.chrome.rawValue,  "chrome")
        XCTAssertEqual(BrowserIdentity.firefox.rawValue, "firefox")
        XCTAssertEqual(BrowserIdentity.edge.rawValue,    "edge")
        XCTAssertEqual(BrowserIdentity.brave.rawValue,   "brave")
        XCTAssertEqual(BrowserIdentity.vivaldi.rawValue, "vivaldi")
        XCTAssertEqual(BrowserIdentity.arc.rawValue,     "arc")
    }

    func test_data_type_raw_values() {
        XCTAssertEqual(BrowserDataType.cache.rawValue,   "cache")
        XCTAssertEqual(BrowserDataType.cookies.rawValue, "cookies")
        XCTAssertEqual(BrowserDataType.history.rawValue, "history")
    }

    func test_chrome_profile_roots_include_default() {
        let roots = BrowserIdentity.chrome.profileRoots(homeDirectory: home)
        XCTAssertTrue(roots.contains(home.appendingPathComponent("Library/Application Support/Google/Chrome")))
    }

    func test_firefox_profile_roots_include_app_support_and_caches() {
        let roots = BrowserIdentity.firefox.profileRoots(homeDirectory: home)
        XCTAssertTrue(roots.contains(home.appendingPathComponent("Library/Application Support/Firefox/Profiles")))
        XCTAssertTrue(roots.contains(home.appendingPathComponent("Library/Caches/Firefox/Profiles")))
    }

    func test_edge_brave_vivaldi_arc_roots() {
        XCTAssertTrue(BrowserIdentity.edge.profileRoots(homeDirectory: home)
            .contains(home.appendingPathComponent("Library/Application Support/Microsoft Edge")))
        XCTAssertTrue(BrowserIdentity.brave.profileRoots(homeDirectory: home)
            .contains(home.appendingPathComponent("Library/Application Support/BraveSoftware/Brave-Browser")))
        XCTAssertTrue(BrowserIdentity.vivaldi.profileRoots(homeDirectory: home)
            .contains(home.appendingPathComponent("Library/Application Support/Vivaldi")))
        XCTAssertTrue(BrowserIdentity.arc.profileRoots(homeDirectory: home)
            .contains(home.appendingPathComponent("Library/Application Support/Arc/User Data")))
    }

    func test_bundle_identifiers_are_stable() {
        XCTAssertEqual(BrowserIdentity.chrome.bundleIdentifiers,  ["com.google.Chrome"])
        XCTAssertEqual(BrowserIdentity.firefox.bundleIdentifiers, ["org.mozilla.firefox"])
        XCTAssertEqual(BrowserIdentity.edge.bundleIdentifiers,    ["com.microsoft.edgemac"])
        XCTAssertEqual(BrowserIdentity.brave.bundleIdentifiers,   ["com.brave.Browser"])
        XCTAssertEqual(BrowserIdentity.vivaldi.bundleIdentifiers, ["com.vivaldi.Vivaldi"])
        XCTAssertEqual(BrowserIdentity.arc.bundleIdentifiers,     ["company.thebrowser.Browser"])
    }
}
