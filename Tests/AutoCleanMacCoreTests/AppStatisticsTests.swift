import XCTest
@testable import AutoCleanMacCore

final class AppStatisticsTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = try Fixtures.makeTempDir()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_recording_updates_totals_and_prepends_recent_run() {
        let date = Date(timeIntervalSince1970: 1_000)
        let summary = CleanupEngine.Summary(
            bytesFreed: 1_024,
            itemsDeleted: 3,
            warningsCount: 1,
            durationMs: 250
        )

        let updated = AppStatistics.empty.recording(summary, at: date)

        XCTAssertEqual(updated.totalRuns, 1)
        XCTAssertEqual(updated.totalBytesFreed, 1_024)
        XCTAssertEqual(updated.totalItemsDeleted, 3)
        XCTAssertEqual(updated.lastCleanupAt, date)
        XCTAssertEqual(updated.recentRuns, [
            CleanupRunRecord(
                cleanedAt: date,
                bytesFreed: 1_024,
                itemsDeleted: 3,
                warningsCount: 1,
                durationMs: 250
            ),
        ])
    }

    func test_recording_keeps_only_recent_run_limit() {
        var stats = AppStatistics.empty
        for index in 0..<12 {
            let summary = CleanupEngine.Summary(
                bytesFreed: Int64(index),
                itemsDeleted: index,
                warningsCount: 0,
                durationMs: 10
            )
            stats = stats.recording(summary, at: Date(timeIntervalSince1970: TimeInterval(index)))
        }

        XCTAssertEqual(stats.totalRuns, 12)
        XCTAssertEqual(stats.recentRuns.count, 10)
        XCTAssertEqual(stats.recentRuns.first?.itemsDeleted, 11)
        XCTAssertEqual(stats.recentRuns.last?.itemsDeleted, 2)
    }

    func test_store_round_trips_statistics_with_iso_dates() throws {
        let file = tempDir.appendingPathComponent("stats/statistics.json")
        let stats = AppStatistics.empty.recording(
            CleanupEngine.Summary(bytesFreed: 4_096, itemsDeleted: 8, warningsCount: 2, durationMs: 900),
            at: Date(timeIntervalSince1970: 2_000)
        )

        try AppStatisticsStore.write(stats, to: file)
        let reloaded = AppStatisticsStore.loadOrDefault(from: file)

        XCTAssertEqual(reloaded, stats)
    }

    func test_store_loads_legacy_statistics_without_recent_runs() throws {
        let file = tempDir.appendingPathComponent("legacy.json")
        let json = """
        {
          "lastCleanupAt" : "1970-01-01T00:33:20Z",
          "totalBytesFreed" : 4096,
          "totalItemsDeleted" : 8,
          "totalRuns" : 2
        }
        """
        try json.write(to: file, atomically: true, encoding: .utf8)

        let reloaded = AppStatisticsStore.loadOrDefault(from: file)

        XCTAssertEqual(reloaded.totalRuns, 2)
        XCTAssertEqual(reloaded.totalBytesFreed, 4_096)
        XCTAssertEqual(reloaded.totalItemsDeleted, 8)
        XCTAssertEqual(reloaded.lastCleanupAt, Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(reloaded.recentRuns, [])
    }

    func test_store_returns_empty_for_malformed_json() throws {
        let file = tempDir.appendingPathComponent("bad.json")
        try "{ nope".write(to: file, atomically: true, encoding: .utf8)

        let reloaded = AppStatisticsStore.loadOrDefault(from: file)

        XCTAssertEqual(reloaded, .empty)
    }
}
