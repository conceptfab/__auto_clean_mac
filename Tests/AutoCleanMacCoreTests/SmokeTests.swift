import XCTest
@testable import AutoCleanMacCore

final class SmokeTests: XCTestCase {
    func test_taskresult_defaults() {
        let r = TaskResult()
        XCTAssertEqual(r.bytesFreed, 0)
        XCTAssertTrue(r.warnings.isEmpty)
        XCTAssertFalse(r.skipped)
    }
}
