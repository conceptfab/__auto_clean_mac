import XCTest
@testable import AutoCleanMacCore

final class LoggerTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("AutoCleanMacTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_creates_log_directory_if_missing() throws {
        let logDir = tempDir.appendingPathComponent("logs")
        let logger = try Logger(directory: logDir, clock: { Date(timeIntervalSince1970: 1_700_000_000) })
        logger.log(event: "start", fields: ["source": "test"])
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: logDir.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    func test_writes_line_with_iso_timestamp_and_event() throws {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14T22:13:20Z
        let logger = try Logger(directory: tempDir, clock: { fixedDate })
        logger.log(event: "start", fields: ["source": "login"])
        let file = tempDir.appendingPathComponent("2023-11-14.log")
        let contents = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(contents.contains("2023-11-14T22:13:20Z"))
        XCTAssertTrue(contents.contains("start"))
        XCTAssertTrue(contents.contains("source=login"))
    }

    func test_appends_multiple_lines() throws {
        let logger = try Logger(directory: tempDir, clock: { Date(timeIntervalSince1970: 1_700_000_000) })
        logger.log(event: "a", fields: [:])
        logger.log(event: "b", fields: [:])
        let file = tempDir.appendingPathComponent("2023-11-14.log")
        let contents = try String(contentsOf: file, encoding: .utf8)
        XCTAssertEqual(contents.split(separator: "\n").count, 2)
    }

    func test_rolls_over_to_new_file_when_day_changes() throws {
        final class Clock: @unchecked Sendable { var now = Date(timeIntervalSince1970: 1_700_000_000) }
        let clock = Clock()
        let logger = try Logger(directory: tempDir, clock: { clock.now })
        logger.log(event: "day1", fields: [:])
        clock.now = clock.now.addingTimeInterval(86_400)
        logger.log(event: "day2", fields: [:])
        let first = try String(contentsOf: tempDir.appendingPathComponent("2023-11-14.log"), encoding: .utf8)
        let second = try String(contentsOf: tempDir.appendingPathComponent("2023-11-15.log"), encoding: .utf8)
        XCTAssertTrue(first.contains("day1") && !first.contains("day2"))
        XCTAssertTrue(second.contains("day2"))
    }

    func test_concurrent_writes_keep_every_line() throws {
        let logger = try Logger(directory: tempDir, clock: { Date(timeIntervalSince1970: 1_700_000_000) })
        DispatchQueue.concurrentPerform(iterations: 200) { i in
            logger.log(event: "e\(i)", fields: [:])
        }
        let contents = try String(contentsOf: tempDir.appendingPathComponent("2023-11-14.log"), encoding: .utf8)
        XCTAssertEqual(contents.split(separator: "\n").count, 200)
    }

    func test_appends_to_existing_file_from_previous_logger() throws {
        let clock: @Sendable () -> Date = { Date(timeIntervalSince1970: 1_700_000_000) }
        try Logger(directory: tempDir, clock: clock).log(event: "first", fields: [:])
        try Logger(directory: tempDir, clock: clock).log(event: "second", fields: [:])
        let contents = try String(contentsOf: tempDir.appendingPathComponent("2023-11-14.log"), encoding: .utf8)
        XCTAssertEqual(contents.split(separator: "\n").count, 2)
    }
}
