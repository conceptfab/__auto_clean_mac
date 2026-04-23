import Foundation

public final class SafeDeleter {
    public enum Mode { case live, dryRun }

    public enum DeletionError: Error, CustomStringConvertible {
        case outsideAllowedRoot(path: String, root: String)
        case notFound(path: String)

        public var description: String {
            switch self {
            case .outsideAllowedRoot(let p, let r): return "Path \(p) escapes root \(r)"
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
        let resolvedPath = path.resolvingSymlinksInPath().standardizedFileURL
        let resolvedRoot = withinRoot.resolvingSymlinksInPath().standardizedFileURL

        let rootStr = resolvedRoot.path
        let pathStr = resolvedPath.path
        let rootWithSep = rootStr.hasSuffix("/") ? rootStr : rootStr + "/"

        guard pathStr == rootStr || pathStr.hasPrefix(rootWithSep) else {
            throw DeletionError.outsideAllowedRoot(path: pathStr, root: rootStr)
        }

        let size: Int64
        do {
            size = try Self.recursiveSize(at: path)
        } catch {
            throw DeletionError.notFound(path: path.path)
        }

        let event = mode == .dryRun ? "dryrun" : "delete"
        logger.log(event: event, fields: ["path": path.path, "size": "\(size)"])

        if mode == .live {
            try FileManager.default.removeItem(at: path)
        }
        return size
    }

    /// Returns the sum of file sizes under `url`, recursing into directories.
    /// Does not follow symlinks to directories (they are sized by their link size via lstat).
    private static func recursiveSize(at url: URL) throws -> Int64 {
        let fm = FileManager.default
        let attrs = try fm.attributesOfItem(atPath: url.path)
        let type = attrs[.type] as? FileAttributeType
        if type == .typeDirectory {
            var total: Int64 = 0
            let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
            guard let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: keys,
                options: [],
                errorHandler: { _, _ in true }
            ) else {
                return (attrs[.size] as? Int64) ?? 0
            }
            for case let child as URL in enumerator {
                let values = try? child.resourceValues(forKeys: Set(keys))
                if values?.isDirectory == true { continue }
                if values?.isSymbolicLink == true {
                    let linkAttrs = try? fm.attributesOfItem(atPath: child.path)
                    total += (linkAttrs?[.size] as? Int64) ?? 0
                    continue
                }
                total += Int64(values?.fileSize ?? 0)
            }
            return total
        } else {
            return (attrs[.size] as? Int64) ?? 0
        }
    }
}
