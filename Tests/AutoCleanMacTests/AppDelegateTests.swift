import AppKit
import XCTest
@testable import AutoCleanMac

final class AppDelegateTests: XCTestCase {
    func test_appKeepsRunningAfterLastWindowCloses() {
        let delegate = AppDelegate()

        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }

    func test_appCancelsUnexpectedTerminationRequests() {
        let delegate = AppDelegate()

        XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateCancel)
    }
}

final class AppDelegateLaunchContextTests: XCTestCase {
    func test_launchContext_parsesCLIArguments() {
        XCTAssertEqual(AppDelegate.LaunchContext(arguments: ["app"]), .manual)
        XCTAssertEqual(AppDelegate.LaunchContext(arguments: ["app", "--run-cleanup"]), .cleanupOnly)
        XCTAssertEqual(AppDelegate.LaunchContext(arguments: ["app", "--settings"]), .settingsOnly)
        XCTAssertEqual(AppDelegate.LaunchContext(arguments: ["app", "--launch-agent"]), .launchAgent)
        // --settings ma pierwszeństwo, tak jak przed wydzieleniem kontrolera.
        XCTAssertEqual(AppDelegate.LaunchContext(arguments: ["app", "--launch-agent", "--settings"]), .settingsOnly)
    }

    func test_transientContexts_terminateAfterLastWindowCloses() {
        for flag in ["--run-cleanup", "--settings", "--launch-agent"] {
            let delegate = AppDelegate(arguments: ["app", flag])
            XCTAssertTrue(
                delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared),
                flag
            )
        }
        XCTAssertFalse(AppDelegate(arguments: ["app"]).applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }
}
