import Foundation

public struct TaskResult: Equatable, Sendable {
    public var bytesFreed: Int64
    public var itemsDeleted: Int
    public var warnings: [String]
    public var skipped: Bool
    public var skipReason: String?

    public init(
        bytesFreed: Int64 = 0,
        itemsDeleted: Int = 0,
        warnings: [String] = [],
        skipped: Bool = false,
        skipReason: String? = nil
    ) {
        self.bytesFreed = bytesFreed
        self.itemsDeleted = itemsDeleted
        self.warnings = warnings
        self.skipped = skipped
        self.skipReason = skipReason
    }
}

public struct CleanupContext {
    public let retentionDays: Int
    public let deleter: SafeDeleter
    public let deletionMode: SafeDeleter.Mode
    public let logger: Logger
    public let fileManager: FileManager
    public let homeDirectory: URL
    public let excludedPaths: [URL]

    public init(
        retentionDays: Int,
        deleter: SafeDeleter,
        deletionMode: SafeDeleter.Mode = .live,
        logger: Logger,
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        excludedPaths: [URL] = []
    ) {
        self.retentionDays = retentionDays
        self.deleter = deleter
        self.deletionMode = deletionMode
        self.logger = logger
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
        self.excludedPaths = excludedPaths.map { $0.resolvingSymlinksInPath().standardizedFileURL }
    }

    public func isExcluded(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return excludedPaths.contains { excluded in
            let root = excluded.path
            let rootWithSep = root.hasSuffix("/") ? root : root + "/"
            return path == root || path.hasPrefix(rootWithSep)
        }
    }

    @discardableResult
    public func deleteMeasured(_ url: URL, withinRoot root: URL) throws -> SafeDeleter.DeletionMetrics {
        if isExcluded(url) {
            throw SafeDeleter.DeletionError.excludedPath(path: url.path)
        }
        return try deleter.deleteMeasured(url, withinRoot: root)
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
            if let cutoff {
                guard let mtime = values?.contentModificationDate, mtime <= cutoff else { continue }
            }
            out.append(url)
        }
        return out
    }
}
