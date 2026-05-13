import XCTest
@testable import AutoCleanMacCore

final class AppProtectionGuardTests: XCTestCase {
    func test_finder_is_protected() {
        XCTAssertTrue(AppProtectionGuard.isProtected(bundleID: "com.apple.finder"))
    }

    func test_dock_is_protected() {
        XCTAssertTrue(AppProtectionGuard.isProtected(bundleID: "com.apple.dock"))
    }

    func test_system_settings_is_protected() {
        XCTAssertTrue(AppProtectionGuard.isProtected(bundleID: "com.apple.systempreferences"))
        XCTAssertTrue(AppProtectionGuard.isProtected(bundleID: "com.apple.SystemSettings"))
    }

    func test_system_settings_panel_wildcard_is_protected() {
        XCTAssertTrue(AppProtectionGuard.isProtected(bundleID: "com.apple.Settings.AppleAccount"))
        XCTAssertTrue(AppProtectionGuard.isProtected(bundleID: "com.apple.Settings.Wifi"))
    }

    func test_control_center_wildcard_is_protected() {
        XCTAssertTrue(AppProtectionGuard.isProtected(bundleID: "com.apple.controlcenter"))
        XCTAssertTrue(AppProtectionGuard.isProtected(bundleID: "com.apple.controlcenter.Bluetooth"))
    }

    func test_xcode_is_uninstallable_despite_apple_prefix() {
        XCTAssertFalse(AppProtectionGuard.isProtected(bundleID: "com.apple.dt.Xcode"))
        XCTAssertFalse(AppProtectionGuard.isProtected(bundleID: "com.apple.dt.Instruments"))
    }

    func test_iwork_apps_are_uninstallable() {
        XCTAssertFalse(AppProtectionGuard.isProtected(bundleID: "com.apple.iWork.Pages"))
        XCTAssertFalse(AppProtectionGuard.isProtected(bundleID: "com.apple.iWork.Numbers"))
        XCTAssertFalse(AppProtectionGuard.isProtected(bundleID: "com.apple.iWork.Keynote"))
    }

    func test_final_cut_pro_is_uninstallable() {
        XCTAssertFalse(AppProtectionGuard.isProtected(bundleID: "com.apple.FinalCut"))
        XCTAssertFalse(AppProtectionGuard.isProtected(bundleID: "com.apple.FinalCutPro"))
    }

    func test_third_party_apps_are_not_protected() {
        XCTAssertFalse(AppProtectionGuard.isProtected(bundleID: "com.example.MyApp"))
        XCTAssertFalse(AppProtectionGuard.isProtected(bundleID: "com.spotify.client"))
        XCTAssertFalse(AppProtectionGuard.isProtected(bundleID: "com.google.Chrome"))
    }

    func test_empty_bundle_id_is_protected_defensively() {
        XCTAssertTrue(AppProtectionGuard.isProtected(bundleID: ""))
    }

    func test_loginwindow_legacy_token_is_protected() {
        XCTAssertTrue(AppProtectionGuard.isProtected(bundleID: "loginwindow"))
        XCTAssertTrue(AppProtectionGuard.isProtected(bundleID: "com.apple.loginwindow"))
    }
}
