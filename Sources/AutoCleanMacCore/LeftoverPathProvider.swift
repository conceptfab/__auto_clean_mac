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
