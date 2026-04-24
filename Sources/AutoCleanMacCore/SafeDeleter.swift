import Foundation

public final class SafeDeleter {
    public struct DeletionMetrics: Equatable, Sendable {
        public var bytesFreed: Int64
        public var itemsDeleted: Int

        public init(bytesFreed: Int64, itemsDeleted: Int) {
            self.bytesFreed = bytesFreed
            self.itemsDeleted = itemsDeleted
        }
    }

    public enum Mode { case live, dryRun, trash }

    public enum DeletionError: Error, CustomStringConvertible {
        case outsideAllowedRoot(path: String, root: String)
        case excludedPath(path: String)
        case notFound(path: String)

        public var description: String {
            switch self {
            case .outsideAllowedRoot(let p, let r): return "Path \(p) escapes root \(r)"
            case .excludedPath(let p):              return "Excluded path: \(p)"
            case .notFound(let p):                  return "Not found: \(p)"
            }
        }
    }

    private let mode: Mode
    private let logger: Logger

    public init(mode: Mode, logger: Logger) {
        self.mode = mode
        self.logger = logger
    }

    @discardableResult
    public func delete(_ path: URL, withinRoot: URL) throws -> Int64 {
        try deleteMeasured(path, withinRoot: withinRoot).bytesFreed
    }

    @discardableResult
    public func deleteMeasured(_ path: URL, withinRoot: URL) throws -> DeletionMetrics {
        let resolvedPath = path.resolvingSymlinksInPath().standardizedFileURL
        let resolvedRoot = withinRoot.resolvingSymlinksInPath().standardizedFileURL

        let rootStr = resolvedRoot.path
        let pathStr = resolvedPath.path
        let rootWithSep = rootStr.hasSuffix("/") ? rootStr : rootStr + "/"

        guard pathStr == rootStr || pathStr.hasPrefix(rootWithSep) else {
            throw DeletionError.outsideAllowedRoot(path: pathStr, root: rootStr)
        }

        let metrics: DeletionMetrics
        do {
            metrics = try Self.recursiveMetrics(at: path)
        } catch {
            throw DeletionError.notFound(path: path.path)
        }

        let event: String
        switch mode {
        case .dryRun: event = "dryrun"
        case .live:   event = "delete"
        case .trash:  event = "trash"
        }
        logger.log(event: event, fields: [
            "path": path.path,
            "size": "\(metrics.bytesFreed)",
            "items": "\(metrics.itemsDeleted)",
        ])

        switch mode {
        case .dryRun:
            break
        case .live:
            try FileManager.default.removeItem(at: path)
        case .trash:
            var resulting: NSURL? = nil
            try FileManager.default.trashItem(at: path, resultingItemURL: &resulting)
            if let dst = resulting as URL? {
                logger.log(event: "trash_dst", fields: ["path": path.path, "dst": dst.path])
            }
        }
        return metrics
    }

    /// Returns the sum of file sizes under `url`, recursing into directories.
    /// Does not follow symlinks to directories (they are sized by their link size via lstat).
    public static func recursiveMetrics(at url: URL) throws -> DeletionMetrics {
        let fm = FileManager.default
        let attrs = try fm.attributesOfItem(atPath: url.path)
        let type = attrs[.type] as? FileAttributeType
        if type == .typeDirectory {
            var total: Int64 = 0
            var items = 0
            let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
            guard let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: keys,
                options: [],
                errorHandler: { _, _ in true }
            ) else {
                return DeletionMetrics(bytesFreed: (attrs[.size] as? Int64) ?? 0, itemsDeleted: 0)
            }
            for case let child as URL in enumerator {
                let values = try? child.resourceValues(forKeys: Set(keys))
                if values?.isDirectory == true { continue }
                if values?.isSymbolicLink == true {
                    let linkAttrs = try? fm.attributesOfItem(atPath: child.path)
                    total += (linkAttrs?[.size] as? Int64) ?? 0
                    items += 1
                    continue
                }
                total += Int64(values?.fileSize ?? 0)
                items += 1
            }
            return DeletionMetrics(bytesFreed: total, itemsDeleted: items)
        } else {
            return DeletionMetrics(bytesFreed: (attrs[.size] as? Int64) ?? 0, itemsDeleted: 1)
        }
    }
}
