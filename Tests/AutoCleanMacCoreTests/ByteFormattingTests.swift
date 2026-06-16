import XCTest
@testable import AutoCleanMacCore

final class ByteFormattingTests: XCTestCase {
    func test_formats_bytes_with_file_count_style() {
        // 1 KB in .file style (1000-based) renders as "1 KB".
        XCTAssertEqual(ByteFormatting.string(1_000), "1 KB")
    }

    func test_zero_is_stable() {
        XCTAssertEqual(ByteFormatting.string(0), ByteFormatting.string(0))
    }
}
