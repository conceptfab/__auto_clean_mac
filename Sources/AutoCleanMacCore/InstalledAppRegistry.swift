import Foundation

public struct InstalledAppRegistry: Sendable {
    private static let bundleExtensions: Set<String> = [
        "app",
        "appex",
        "bundle",
        "framework",
        "plugin",
        "xpc",
    ]

    public init() {}

    /// Domyślne lokalizacje skanowania (production).
    public static func defaultSearchRoots(homeDirectory: URL) -> [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Setapp"),
            URL(fileURLWithPath: "/System/Applications"),
            homeDirectory.appendingPathComponent("Applications"),
            homeDirectory.appendingPathComponent("Library/Application Support/Setapp/Applications"),
            URL(fileURLWithPath: "/opt/homebrew/Caskroom"),
            URL(fileURLWithPath: "/usr/local/Caskroom"),
        ]
    }

    /// Zbiera bundle ID wszystkich `.app` w podanych katalogach oraz ich zagnieżdżonych helperów.
    public func installedBundleIDs(searchRoots: [URL]) -> Set<String> {
        let fm = FileManager.default
        var ids: Set<String> = []
        for root in searchRoots {
            if root.pathExtension == "app" {
                ids.formUnion(bundleIdentifiers(inBundleAt: root, fileManager: fm))
                continue
            }
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsPackageDescendants, .skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "app" {
                ids.formUnion(bundleIdentifiers(inBundleAt: url, fileManager: fm))
            }
        }
        return ids
    }

    private func bundleIdentifiers(inBundleAt url: URL, fileManager: FileManager) -> Set<String> {
        var ids: Set<String> = []
        if let bundle = Bundle(url: url), let id = bundle.bundleIdentifier {
            ids.insert(id)
        }

        let contents = url.appendingPathComponent("Contents")
        guard let enumerator = fileManager.enumerator(
            at: contents,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return ids }

        for case let nestedURL as URL in enumerator {
            guard Self.bundleExtensions.contains(nestedURL.pathExtension) else { continue }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: nestedURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }

            ids.formUnion(bundleIdentifiers(inBundleAt: nestedURL, fileManager: fileManager))
            enumerator.skipDescendants()
        }
        return ids
    }
}
