import Foundation

public struct UserCachesTask: CleanupTask {
    public let displayName = "User caches"
    public let isEnabled: Bool
    private let isBundleIDRunning: (String) -> Bool
    private let whitelistedBundleIDs: Set<String>

    public init(
        isEnabled: Bool,
        isBundleIDRunning: @escaping (String) -> Bool = { AppRunning.isRunning(bundleIdentifier: $0) },
        whitelistedBundleIDs: [String] = []
    ) {
        self.isEnabled = isEnabled
        self.isBundleIDRunning = isBundleIDRunning
        self.whitelistedBundleIDs = Set(whitelistedBundleIDs)
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
        var itemsDeleted = 0
        var warnings: [String] = []
        for candidateRoot in deletionRoots(in: root, context: context) {
            // Filtr wieku: pliki świeższe niż retencja mogą być w użyciu (aplikacje nie zawsze
            // mają bundle-ID-ową nazwę katalogu, więc test „czy działa” nie wszystko łapie).
            let files = FileEnumerator.files(
                inRoot: candidateRoot,
                olderThanDays: context.retentionDays,
                fileManager: context.fileManager
            )
            for url in files {
                if Self.isProtectedNested(url, cachesRoot: root) {
                    continue
                }
                do {
                    let metrics = try context.deleteMeasured(url, withinRoot: candidateRoot)
                    freed += metrics.bytesFreed
                    itemsDeleted += metrics.itemsDeleted
                } catch {
                    warnings.append("\(url.lastPathComponent): \(error)")
                }
            }
        }
        return TaskResult(bytesFreed: freed, itemsDeleted: itemsDeleted, warnings: warnings)
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
                    "reason": Self.isBrowserCacheVendor(name) ? "browser_data_task" : "protected_top_level",
                ])
                continue
            }

            if Self.looksLikeBundleIdentifier(name) {
                if whitelistedBundleIDs.contains(name) {
                    context.logger.log(event: "user_cache_skip", fields: [
                        "path": child.path,
                        "reason": "whitelisted",
                    ])
                    continue
                }
                
                if isBundleIDRunning(name) {
                    context.logger.log(event: "user_cache_skip", fields: [
                        "path": child.path,
                        "reason": "active_bundle_identifier",
                    ])
                    continue
                }
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

    /// Pliki wewnątrz katalogów cache, które niosą stan (nie są odtwarzalnym cache) albo są
    /// w trakcie zapisu — np. środowiska Poetry, pobierania Homebrew `*.incomplete`.
    private static func isProtectedNested(_ url: URL, cachesRoot: URL) -> Bool {
        if protectedFileSuffixes.contains(where: { url.lastPathComponent.hasSuffix($0) }) {
            return true
        }
        let rootPath = cachesRoot.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return false }
        let relative = String(path.dropFirst(rootPath.count + 1))
        return protectedNestedPrefixes.contains { relative == $0 || relative.hasPrefix($0 + "/") }
    }

    private static let protectedNestedPrefixes: [String] = [
        "pypoetry/virtualenvs",
    ]

    private static let protectedFileSuffixes: [String] = [
        ".incomplete",   // Homebrew: pobieranie w toku
        ".part",
        ".partial",
        ".download",
    ]

    private static func isBrowserCacheVendor(_ name: String) -> Bool {
        browserCacheVendorNames.contains(name)
    }

    private static let browserCacheVendorNames: Set<String> = [
        "Arc",
        "BraveSoftware",
        "Firefox",
        "Google",
        "Google Chrome",
        "Microsoft Edge",
        "Vivaldi",
    ]

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
        // Stan, nie cache: pobrane przeglądarki/binarki narzędzi — usunięcie psuje narzędzie.
        "ms-playwright",
        "ms-playwright-go",
        "Cypress",
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
