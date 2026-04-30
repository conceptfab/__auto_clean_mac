import Foundation

public struct InstalledAppRegistry: Sendable {
    public init() {}

    /// Domyślne lokalizacje skanowania (production).
    public static func defaultSearchRoots(homeDirectory: URL) -> [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            homeDirectory.appendingPathComponent("Applications"),
        ]
    }

    /// Zbiera bundle ID wszystkich `.app` w podanych katalogach (rekurencyjnie, ale `skipsPackageDescendants`).
    public func installedBundleIDs(searchRoots: [URL]) -> Set<String> {
        let fm = FileManager.default
        var ids: Set<String> = []
        for root in searchRoots {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsPackageDescendants, .skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "app" {
                if let bundle = Bundle(url: url), let id = bundle.bundleIdentifier {
                    ids.insert(id)
                }
            }
        }
        return ids
    }
}
