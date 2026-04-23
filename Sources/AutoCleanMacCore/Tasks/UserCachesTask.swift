import Foundation

public struct UserCachesTask: CleanupTask {
    public let displayName = "User caches"
    public let isEnabled: Bool
    private let isBundleIDRunning: (String) -> Bool

    public init(
        isEnabled: Bool,
        isBundleIDRunning: @escaping (String) -> Bool = { AppRunning.isRunning(bundleIdentifier: $0) }
    ) {
        self.isEnabled = isEnabled
        self.isBundleIDRunning = isBundleIDRunning
    }

    public func run(context: CleanupContext) async -> TaskResult {
        guard isEnabled else {
            return TaskResult(skipped: true, skipReason: "disabled")
        }
        let root = context.homeDirectory.appendingPathComponent("Library/Caches")
        guard context.fileManager.fileExists(atPath: root.path) else {
            return TaskResult(skipped: true, skipReason: "root missing")
        }

        var freed: Int64 = 0
        var warnings: [String] = []
        for candidateRoot in deletionRoots(in: root, context: context) {
            for url in FileEnumerator.files(inRoot: candidateRoot, fileManager: context.fileManager) {
                do {
                    freed += try context.deleter.delete(url, withinRoot: candidateRoot)
                } catch {
                    warnings.append("\(url.lastPathComponent): \(error)")
                }
            }
        }
        return TaskResult(bytesFreed: freed, warnings: warnings)
    }

    private func deletionRoots(in root: URL, context: CleanupContext) -> [URL] {
        guard let children = try? context.fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var roots: [URL] = []
        for child in children {
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else {
                context.logger.log(event: "user_cache_skip", fields: [
                    "path": child.path,
                    "reason": "top_level_not_directory",
                ])
                continue
            }

            let name = child.lastPathComponent
            if Self.isProtectedTopLevel(name) {
                context.logger.log(event: "user_cache_skip", fields: [
                    "path": child.path,
                    "reason": "protected_top_level",
                ])
                continue
            }

            if Self.looksLikeBundleIdentifier(name), isBundleIDRunning(name) {
                context.logger.log(event: "user_cache_skip", fields: [
                    "path": child.path,
                    "reason": "active_bundle_identifier",
                ])
                continue
            }

            roots.append(child)
        }
        return roots
    }

    private static func looksLikeBundleIdentifier(_ name: String) -> Bool {
        name.contains(".") && !name.hasPrefix(".")
    }

    private static func isProtectedTopLevel(_ name: String) -> Bool {
        if protectedExactNames.contains(name) {
            return true
        }
        return protectedPrefixes.contains { name.hasPrefix($0) }
    }

    private static let protectedExactNames: Set<String> = [
        "Arc",
        "BraveSoftware",
        "CloudKit",
        "Dropbox",
        "Firefox",
        "Google",
        "Google Chrome",
        "Microsoft Edge",
        "OneDrive",
        "Vivaldi",
    ]

    private static let protectedPrefixes: [String] = [
        "com.apple.",
        "com.brave.",
        "com.google.",
        "com.microsoft.",
        "company.thebrowser.",
        "org.mozilla.",
    ]
}
