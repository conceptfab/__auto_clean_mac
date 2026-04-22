import Foundation

public final class CleanupEngine {
    public struct Summary: Equatable {
        public var bytesFreed: Int64
        public var warningsCount: Int
        public var durationMs: Int
    }

    public enum Event {
        case started
        case taskStarted(name: String)
        case taskFinished(name: String, result: TaskResult)
        case summary(Summary)
    }

    private let tasks: [CleanupTask]

    public init(tasks: [CleanupTask]) {
        self.tasks = tasks
    }

    public func run(context: CleanupContext, onEvent: @escaping (Event) -> Void) async -> Summary {
        onEvent(.started)
        let start = Date()
        var totalBytes: Int64 = 0
        var totalWarnings = 0

        for task in tasks {
            onEvent(.taskStarted(name: task.displayName))
            let result = await task.run(context: context)
            onEvent(.taskFinished(name: task.displayName, result: result))
            totalBytes += result.bytesFreed
            totalWarnings += result.warnings.count
        }

        let duration = Int(Date().timeIntervalSince(start) * 1000)
        let summary = Summary(bytesFreed: totalBytes, warningsCount: totalWarnings, durationMs: duration)
        onEvent(.summary(summary))
        context.logger.log(event: "summary", fields: [
            "freed": "\(summary.bytesFreed)",
            "duration_ms": "\(summary.durationMs)",
            "warnings": "\(summary.warningsCount)",
        ])
        return summary
    }
}

public extension CleanupEngine {
    static func makeDefault(config: Config) -> CleanupEngine {
        CleanupEngine(tasks: [
            UserCachesTask(isEnabled: config.tasks.userCaches),
            SystemTempTask(isEnabled: config.tasks.systemTemp),
            TrashTask(isEnabled: config.tasks.trash),
            DSStoreTask(isEnabled: config.tasks.dsStore),
            UserLogsTask(isEnabled: config.tasks.userLogs),
            BrowserCachesTask(isEnabled: config.tasks.browserCaches),
            DevCachesTask(isEnabled: config.tasks.devCaches),
            DownloadsTask(isEnabled: config.tasks.downloads),
        ])
    }
}
