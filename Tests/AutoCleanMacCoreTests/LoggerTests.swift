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
}
