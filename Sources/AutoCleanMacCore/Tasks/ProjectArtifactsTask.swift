import Foundation

public struct ProjectArtifactsTask: CleanupTask {
    public let displayName = "Artefakty projektów"
    public let isEnabled: Bool

    private let searchRootsOverride: [URL]?
    private let maxDepth: Int
    private let maxCandidates: Int
    private let scanTimeoutSeconds: TimeInterval

    public init(
        isEnabled: Bool,
        searchRoots: [URL]? = nil,
        maxDepth: Int = 9,
        maxCandidates: Int = 5_000,
        scanTimeoutSeconds: TimeInterval = 6
    ) {
        self.isEnabled = isEnabled
        self.searchRootsOverride = searchRoots
        self.maxDepth = max(1, maxDepth)
        self.maxCandidates = max(1, maxCandidates)
        self.scanTimeoutSeconds = max(1, scanTimeoutSeconds)
    }

    public func run(context: CleanupContext) async -> TaskResult {
        guard isEnabled else {
            return TaskResult(skipped: true, skipReason: "disabled")
        }

        let roots = (searchRootsOverride ?? Self.defaultSearchRoots(homeDirectory: context.homeDirectory))
            .filter { isScannableRoot($0, context: context) }
        guard !roots.isEmpty else {
            return TaskResult(skipped: true, skipReason: "no_roots")
        }

        var freed: Int64 = 0
        var itemsDeleted = 0
        var warnings: [String] = []
        var candidates: [URL] = []

        for root in roots {
            let result = collectCandidates(in: root, context: context)
            candidates.append(contentsOf: result.candidates)
            warnings.append(contentsOf: result.warnings)
            if candidates.count >= maxCandidates {
                warnings.append("Project artifacts scan limited to \(maxCandidates) candidates")
                break
            }
        }

        for candidate in candidates.prefix(maxCandidates) {
            guard !context.isExcluded(candidate) else {
                warnings.append("\(candidate.lastPathComponent): excluded path")
                continue
            }

            let root = containingSearchRoot(for: candidate, roots: roots) ?? candidate.deletingLastPathComponent()
            do {
                let metrics = try context.deleteMeasured(candidate, withinRoot: root)
                freed += metrics.bytesFreed
                itemsDeleted += metrics.itemsDeleted
            } catch {
                warnings.append("\(candidate.lastPathComponent): \(error)")
            }
        }

        return TaskResult(bytesFreed: freed, itemsDeleted: itemsDeleted, warnings: warnings)
    }

    public static func defaultSearchRoots(homeDirectory: URL) -> [URL] {
        [
            homeDirectory.appendingPathComponent("dev"),
            homeDirectory.appendingPathComponent("Developer"),
            homeDirectory.appendingPathComponent("Projects"),
            homeDirectory.appendingPathComponent("GitHub"),
        ]
    }

    private func isScannableRoot(_ root: URL, context: CleanupContext) -> Bool {
        var isDirectory: ObjCBool = false
        guard context.fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              !context.isExcluded(root) else {
            return false
        }
        guard let values = try? root.resourceValues(forKeys: [.isSymbolicLinkKey]),
              values.isSymbolicLink != true else {
            return false
        }
        return true
    }

    private func collectCandidates(in root: URL, context: CleanupContext) -> (candidates: [URL], warnings: [String]) {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = context.fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return ([], [])
        }

        let rootDepth = depth(of: root)
        let deadline = Date().addingTimeInterval(scanTimeoutSeconds)
        var candidates: [URL] = []
        var warnings: [String] = []

        for case let url as URL in enumerator {
            if Date() > deadline {
                warnings.append("Project artifacts scan timed out under \(root.path)")
                break
            }
            if candidates.count >= maxCandidates { break }

            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isDirectory == true else { continue }
            if values?.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }

            let relativeDepth = depth(of: url) - rootDepth
            if relativeDepth > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            let name = url.lastPathComponent
            if let directCandidate = directArtifactCandidate(for: url, name: name, fileManager: context.fileManager) {
                candidates.append(directCandidate)
                enumerator.skipDescendants()
                continue
            }

            if Self.prunedDirectoryNames.contains(name) {
                enumerator.skipDescendants()
            }
        }

        return (deduplicated(candidates), warnings)
    }

    private func directArtifactCandidate(for url: URL, name: String, fileManager: FileManager) -> URL? {
        switch name {
        case ".next":
            let cache = url.appendingPathComponent("cache")
            return directoryExists(cache, fileManager: fileManager) ? cache : nil
        case "__pycache__":
            return hasPythonBytecode(in: url, fileManager: fileManager) ? url : nil
        case ".dart_tool", ".pytest_cache", ".mypy_cache", ".ruff_cache":
            return url
        case "node_modules":
            let cache = url.appendingPathComponent(".cache")
            return directoryExists(cache, fileManager: fileManager) ? cache : nil
        default:
            return nil
        }
    }

    private static let prunedDirectoryNames: Set<String> = [
        ".git",
        "Library",
        ".Trash",
        "venv",
        ".venv",
        "Pods",
        "DerivedData",
        "site-packages",
    ]

    private func directoryExists(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func hasPythonBytecode(in url: URL, fileManager: FileManager) -> Bool {
        guard let entries = try? fileManager.contentsOfDirectory(atPath: url.path) else { return false }
        return entries.contains { $0.hasSuffix(".pyc") || $0.hasSuffix(".pyo") }
    }

    private func containingSearchRoot(for candidate: URL, roots: [URL]) -> URL? {
        let candidatePath = candidate.resolvingSymlinksInPath().standardizedFileURL.path
        return roots.first { root in
            let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
            let rootWithSep = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
            return candidatePath == rootPath || candidatePath.hasPrefix(rootWithSep)
        }
    }

    private func depth(of url: URL) -> Int {
        url.standardizedFileURL.pathComponents.count
    }

    private func deduplicated(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        var out: [URL] = []
        for url in urls {
            let key = url.resolvingSymlinksInPath().standardizedFileURL.path
            if seen.insert(key).inserted {
                out.append(url)
            }
        }
        return out
    }
}
