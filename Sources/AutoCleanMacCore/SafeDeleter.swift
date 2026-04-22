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

        // Use lstat-style attributes so symlinks themselves can be sized/removed.
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path.path) else {
            throw DeletionError.notFound(path: path.path)
        }
        let size = (attrs[.size] as? Int64) ?? 0

        let event = mode == .dryRun ? "dryrun" : "delete"
        logger.log(event: event, fields: ["path": path.path, "size": "\(size)"])

        if mode == .live {
            try FileManager.default.removeItem(at: path)
        }
        return size
    }
}
