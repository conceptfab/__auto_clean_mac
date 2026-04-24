import XCTest
@testable import AutoCleanMacCore

final class SmokeTests: XCTestCase {
    func test_taskresult_defaults() {
        let r = TaskResult()
        XCTAssertEqual(r.bytesFreed, 0)
        XCTAssertEqual(r.itemsDeleted, 0)
        XCTAssertTrue(r.warnings.isEmpty)
        XCTAssertFalse(r.skipped)
    }

    func test_dev_caches_parses_approximate_brew_size() {
        let output = "This operation has freed approximately 1.5GB of disk space."
        XCTAssertEqual(DevCachesTask.approximateFreedBytes(from: output), 1_610_612_736)
    }

    func test_dev_caches_returns_nil_when_brew_output_has_no_size() {
        XCTAssertNil(DevCachesTask.approximateFreedBytes(from: "Nothing to do."))
    }
}
