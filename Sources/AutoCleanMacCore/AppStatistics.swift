import Foundation

public struct CleanupRunRecord: Codable, Equatable, Sendable {
    public var cleanedAt: Date
    public var bytesFreed: Int64
    public var itemsDeleted: Int
    public var warningsCount: Int
    public var durationMs: Int

    public init(
        cleanedAt: Date,
        bytesFreed: Int64,
        itemsDeleted: Int,
        warningsCount: Int,
        durationMs: Int
    ) {
        self.cleanedAt = cleanedAt
        self.bytesFreed = bytesFreed
        self.itemsDeleted = itemsDeleted
        self.warningsCount = warningsCount
        self.durationMs = durationMs
    }
}

public struct AppStatistics: Codable, Equatable, Sendable {
    public var totalRuns: Int
    public var totalItemsDeleted: Int
    public var totalBytesFreed: Int64
    public var lastCleanupAt: Date?
    public var recentRuns: [CleanupRunRecord]

    public static let empty = AppStatistics(
        totalRuns: 0,
        totalItemsDeleted: 0,
        totalBytesFreed: 0,
        lastCleanupAt: nil,
        recentRuns: []
    )

    public init(
        totalRuns: Int,
        totalItemsDeleted: Int,
        totalBytesFreed: Int64,
        lastCleanupAt: Date?,
        recentRuns: [CleanupRunRecord]
    ) {
        self.totalRuns = totalRuns
        self.totalItemsDeleted = totalItemsDeleted
        self.totalBytesFreed = totalBytesFreed
        self.lastCleanupAt = lastCleanupAt
        self.recentRuns = recentRuns
    }

    public func recording(
        _ summary: CleanupEngine.Summary,
        at date: Date = Date(),
        recentRunLimit: Int = 10
    ) -> AppStatistics {
        let record = CleanupRunRecord(
            cleanedAt: date,
            bytesFreed: summary.bytesFreed,
            itemsDeleted: summary.itemsDeleted,
            warningsCount: summary.warningsCount,
            durationMs: summary.durationMs
        )
        let limit = max(0, recentRunLimit)
        return AppStatistics(
            totalRuns: totalRuns + 1,
            totalItemsDeleted: totalItemsDeleted + summary.itemsDeleted,
            totalBytesFreed: totalBytesFreed + summary.bytesFreed,
            lastCleanupAt: date,
            recentRuns: Array(([record] + recentRuns).prefix(limit))
        )
    }

    private enum CodingKeys: String, CodingKey {
        case totalRuns
        case totalItemsDeleted
        case totalBytesFreed
        case lastCleanupAt
        case recentRuns
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalRuns = try container.decode(Int.self, forKey: .totalRuns)
        totalItemsDeleted = try container.decode(Int.self, forKey: .totalItemsDeleted)
        totalBytesFreed = try container.decode(Int64.self, forKey: .totalBytesFreed)
        lastCleanupAt = try container.decodeIfPresent(Date.self, forKey: .lastCleanupAt)
        recentRuns = try container.decodeIfPresent([CleanupRunRecord].self, forKey: .recentRuns) ?? []
    }
}

public enum AppStatisticsStore {
    public static func loadOrDefault(from url: URL, logger: Logger? = nil) -> AppStatistics {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .empty
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(AppStatistics.self, from: data)
        } catch {
            logger?.log(event: "statistics_load_failed", fields: ["error": "\(error)"])
            return .empty
        }
    }

    public static func write(_ statistics: AppStatistics, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(statistics)
        try data.write(to: url, options: .atomic)
    }
}
