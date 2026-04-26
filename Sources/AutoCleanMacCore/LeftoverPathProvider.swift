import Foundation

public enum LeftoverPathProvider {
    /// Ścieżki w obrębie `~/Library` powiązane z bundle ID i opcjonalną nazwą wyświetlaną aplikacji.
    /// Zwraca wszystkie kandydatury, niezależnie od istnienia na dysku — istnienie sprawdza wywołujący.
    public static func userPaths(
        bundleID: String,
        displayName: String?,
        homeDirectory: URL
    ) -> [URL] {
        let lib = homeDirectory.appendingPathComponent("Library")
        var paths: [URL] = [
            lib.appendingPathComponent("Preferences/\(bundleID).plist"),
            lib.appendingPathComponent("Application Support/\(bundleID)"),
            lib.appendingPathComponent("Caches/\(bundleID)"),
            lib.appendingPathComponent("Containers/\(bundleID)"),
            lib.appendingPathComponent("Saved Application State/\(bundleID).savedState"),
            lib.appendingPathComponent("HTTPStorages/\(bundleID)"),
            lib.appendingPathComponent("Logs/\(bundleID)"),
            lib.appendingPathComponent("WebKit/\(bundleID)"),
            lib.appendingPathComponent("Cookies/\(bundleID).binarycookies"),
            lib.appendingPathComponent("Application Scripts/\(bundleID)"),
        ]
        if let name = displayName, !name.isEmpty, name != bundleID {
            paths.append(lib.appendingPathComponent("Application Support/\(name)"))
            paths.append(lib.appendingPathComponent("Caches/\(name)"))
        }
        return paths
    }
}

extension LeftoverPathProvider {
    /// Ścieżki, których nie da się statycznie wyliczyć — wymagają enumeracji katalogów
    /// (np. ByHost preferences z UUID-em hosta, Group Containers z prefiksem teamID).
    public static func resolveDynamic(
        bundleID: String,
        homeDirectory: URL
    ) -> [URL] {
        let fm = FileManager.default
        let lib = homeDirectory.appendingPathComponent("Library")
        var results: [URL] = []

        let byHost = lib.appendingPathComponent("Preferences/ByHost")
        if let entries = try? fm.contentsOfDirectory(atPath: byHost.path) {
            for name in entries where name.hasPrefix("\(bundleID).") && name.hasSuffix(".plist") {
                results.append(byHost.appendingPathComponent(name))
            }
        }

        let groupContainers = lib.appendingPathComponent("Group Containers")
        if let entries = try? fm.contentsOfDirectory(atPath: groupContainers.path) {
            for name in entries {
                let isGroupPrefixed = name == "group.\(bundleID)" || name.hasPrefix("group.\(bundleID).")
                let isTeamPrefixed = name.hasSuffix(".\(bundleID)") && name.split(separator: ".").count >= 2 && !name.hasPrefix("group.")
                if isGroupPrefixed || isTeamPrefixed {
                    results.append(groupContainers.appendingPathComponent(name))
                }
            }
        }

        let userAgents = lib.appendingPathComponent("LaunchAgents")
        if let entries = try? fm.contentsOfDirectory(atPath: userAgents.path) {
            for name in entries where name.hasSuffix(".plist") {
                let stem = String(name.dropLast(".plist".count))
                if stem == bundleID || stem.hasPrefix("\(bundleID).") {
                    results.append(userAgents.appendingPathComponent(name))
                }
            }
        }

        return results
    }
}
