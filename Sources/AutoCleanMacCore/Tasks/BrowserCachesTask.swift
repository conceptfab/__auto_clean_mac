import Foundation

public struct BrowserCachesTask: CleanupTask {
    public let displayName = "Browser caches"
    public let isEnabled: Bool

    private static let allowedDirNames: Set<String> = ["Cache", "Code Cache", "cache2"]

    public init(isEnabled: Bool) { self.isEnabled = isEnabled }

    public func run(context: CleanupContext) async -> TaskResult {
        guard isEnabled else {
            return TaskResult(skipped: true, skipReason: "disabled")
        }
        let appSupport = context.homeDirectory.appendingPathComponent("Library/Application Support")
        let roots: [URL] = [
            appSupport.appendingPathComponent("Google/Chrome"),
            appSupport.appendingPathComponent("Firefox/Profiles"),
        ].filter { context.fileManager.fileExists(atPath: $0.path) }
        guard !roots.isEmpty else {
            return TaskResult(skipped: true, skipReason: "no browser profile directories")
        }

        var freed: Int64 = 0
        var warnings: [String] = []

        for root in roots {
            let allowedDirs = findAllowedCacheDirs(under: root, fileManager: context.fileManager)
            for dir in allowedDirs {
                for url in FileEnumerator.files(inRoot: dir) {
                    do {
                        freed += try context.deleter.delete(url, withinRoot: dir)
                    } catch {
                        warnings.append("\(url.lastPathComponent): \(error)")
                    }
                }
            }
        }
        return TaskResult(bytesFreed: freed, warnings: warnings)
    }

    private func findAllowedCacheDirs(under root: URL, fileManager: FileManager) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return [] }
        var dirs: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true, Self.allowedDirNames.contains(url.lastPathComponent) {
                dirs.append(url)
                enumerator.skipDescendants()
            }
        }
        return dirs
    }
}
