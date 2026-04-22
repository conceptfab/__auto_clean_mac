import XCTest
@testable import AutoCleanMacCore

final class SmokeTests: XCTestCase {
    func test_version_is_defined() {
        XCTAssertFalse(AutoCleanMacCore.version.isEmpty)
    }
}
