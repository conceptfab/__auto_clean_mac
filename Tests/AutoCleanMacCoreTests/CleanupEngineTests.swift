import XCTest
@testable import AutoCleanMacCore

final class CleanupEngineTests: XCTestCase {
    var tempDir: URL!
    var logger: Logger!

    override func setUpWithError() throws {
        tempDir = try Fixtures.makeTempDir()
        logger = try Logger(directory: tempDir.appendingPathComponent("logs"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    struct StubTask: CleanupTask {
        let displayName: String
        let isEnabled: Bool
        let result: TaskResult
        func run(context: CleanupContext) async -> TaskResult { result }
    }

    func test_engine_runs_all_tasks_in_order_and_sums_bytes() async throws {
        let ctx = CleanupContext(
            retentionDays: 7,
            deleter: SafeDeleter(mode: .live, logger: logger),
            logger: logger,
            homeDirectory: tempDir
        )
        let engine = CleanupEngine(tasks: [
            StubTask(displayName: "A", isEnabled: true, result: TaskResult(bytesFreed: 100)),
            StubTask(displayName: "B", isEnabled: true, result: TaskResult(bytesFreed: 200, warnings: ["w"])),
            StubTask(displayName: "C", isEnabled: false, result: TaskResult()),
        ])

        var events: [CleanupEngine.Event] = []
        let summary = await engine.run(context: ctx) { events.append($0) }

        XCTAssertEqual(summary.bytesFreed, 300)
        XCTAssertEqual(summary.warningsCount, 1)
        let names = events.compactMap { event -> String? in
            if case .taskFinished(let name, _) = event { return name }
            return nil
        }
        XCTAssertEqual(names, ["A", "B", "C"])
        if case .summary(let s) = events.last { XCTAssertEqual(s.bytesFreed, 300) } else { XCTFail("no summary event") }
    }
}
