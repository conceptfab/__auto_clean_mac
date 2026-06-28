import Foundation

/// Wykrywanie statusu Full Disk Access (FDA / kTCCServiceSystemPolicyAllFiles).
///
/// macOS nie udostępnia oficjalnego API „czy mam FDA”. Standardowa metoda to próba
/// odczytu pliku chronionego przez TCC, do którego dostęp ma WYŁĄCZNIE aplikacja z FDA.
/// `~/Library/Application Support/com.apple.TCC/TCC.db` jest do tego idealny: zawsze istnieje,
/// a otwarcie go do odczytu bez FDA kończy się błędem „Operation not permitted”.
public enum FullDiskAccess {
    /// Zwraca `true`, gdy proces ma realny dostęp do plików chronionych przez TCC.
    public static func isGranted(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        for probe in probePaths(homeDirectory: homeDirectory) {
            guard fileManager.fileExists(atPath: probe.path) else { continue }
            if canRead(probe) {
                return true
            } else {
                // Plik istnieje, ale nie da się go odczytać → brak FDA.
                return false
            }
        }
        // Żaden z probe'ów nie istnieje (nietypowy system) — nie blokujemy.
        return true
    }

    private static func probePaths(homeDirectory: URL) -> [URL] {
        let appSupport = homeDirectory.appendingPathComponent("Library/Application Support")
        return [
            appSupport.appendingPathComponent("com.apple.TCC/TCC.db"),
            homeDirectory.appendingPathComponent("Library/Safari/Bookmarks.plist"),
        ]
    }

    private static func canRead(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 1)) != nil
    }
}
