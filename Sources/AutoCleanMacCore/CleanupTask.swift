import Foundation

public struct TaskResult: Equatable {
    public var bytesFreed: Int64
    public var warnings: [String]
    public var skipped: Bool
    public var skipReason: String?

    public init(bytesFreed: Int64 = 0, warnings: [String] = [], skipped: Bool = false, skipReason: String? = nil) {
        self.bytesFreed = bytesFreed
        self.warnings = warnings
        self.skipped = skipped
        self.skipReason = skipReason
    }
}

public struct CleanupContext {
    public let retentionDays: Int
    public let deleter: SafeDeleter
    public let logger: Logger
    public let fileManager: FileManager
    public let homeDirectory: URL

    public init(
        retentionDays: Int,
        deleter: SafeDeleter,
        logger: Logger,
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.retentionDays = retentionDays
        self.deleter = deleter
        self.logger = logger
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
    }
}

public protocol CleanupTask {
    var displayName: String { get }
    var isEnabled: Bool { get }
    func run(context: CleanupContext) async -> TaskResult
}

/// Shared helper: enumerate regular files + symlinks under `root`, applying an optional mtime filter.
public struct FileEnumerator {
    public static func files(
        inRoot root: URL,
        olderThanDays days: Int? = nil,
        namedExactly exactName: String? = nil,
        fileManager: FileManager = .default,
        clock: () -> Date = Date.init
    ) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey],
            options: []
        ) else { return [] }
        let now = clock()
        let cutoff = days.map { now.addingTimeInterval(TimeInterval(-$0 * 86_400)) }
        var out: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey])
            let isFile = (values?.isRegularFile ?? false) || (values?.isSymbolicLink ?? false)
            guard isFile else { continue }
            if let name = exactName, url.lastPathComponent != name { continue }
            if let cutoff, let mtime = values?.contentModificationDate, mtime > cutoff { continue }
            out.append(url)
        }
        return out
    }
}
