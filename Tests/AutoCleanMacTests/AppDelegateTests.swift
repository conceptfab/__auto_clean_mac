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
