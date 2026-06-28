import Foundation

/// Usuwa z plików Chromium `Preferences` / `Secure Preferences` stan przywracania sesji.
/// Samo skasowanie katalogu `Sessions/` nie wystarcza — przeglądarka odtwarza ostatnie karty
/// z kluczy `sessions` i `profile.exit_type` w JSON-ie preferencji profilu.
public enum ChromiumPreferencesScrubber {
    public enum ScrubError: Error {
        case invalidFormat
    }

    private static let sessionTopLevelKeys = ["sessions", "saved_tab_groups", "session"]
    private static let vendorNamespaces = ["brave", "vivaldi", "arc", "comet"]
    private static let vendorSessionKeys = ["sessions"]

    /// Zwraca `true`, gdy plik został zmodyfikowany.
    public static func scrubSessionRestoreData(at url: URL, fileManager: FileManager = .default) throws -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return false }

        let data = try Data(contentsOf: url)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ScrubError.invalidFormat
        }

        var changed = false

        for key in sessionTopLevelKeys where root.removeValue(forKey: key) != nil {
            changed = true
        }

        if var profile = root["profile"] as? [String: Any] {
            if let exitType = profile["exit_type"] as? String, exitType != "Normal" {
                profile["exit_type"] = "Normal"
                root["profile"] = profile
                changed = true
            }
        }

        for vendor in vendorNamespaces {
            guard var vendorDict = root[vendor] as? [String: Any] else { continue }
            var vendorChanged = false
            for key in vendorSessionKeys where vendorDict.removeValue(forKey: key) != nil {
                vendorChanged = true
            }
            if vendorChanged {
                root[vendor] = vendorDict
                changed = true
            }
        }

        guard changed else { return false }

        let output = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        try output.write(to: url, options: .atomic)
        return true
    }
}
