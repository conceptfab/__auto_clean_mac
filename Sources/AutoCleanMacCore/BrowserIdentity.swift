import Foundation

/// Identyfikator obsługiwanej przeglądarki. Safari celowo pominięte w v1 (wymaga TCC Full Disk Access).
public enum BrowserIdentity: String, CaseIterable, Equatable, Hashable {
    case chrome, firefox, edge, brave, vivaldi, arc

    public var displayName: String {
        switch self {
        case .chrome:  return "Google Chrome"
        case .firefox: return "Firefox"
        case .edge:    return "Microsoft Edge"
        case .brave:   return "Brave"
        case .vivaldi: return "Vivaldi"
        case .arc:     return "Arc"
        }
    }

    /// Katalogi w których leżą profile przeglądarki (każdy profil to podkatalog, np. "Default", "Profile 1").
    public func profileRoots(homeDirectory: URL) -> [URL] {
        let appSupport = homeDirectory.appendingPathComponent("Library/Application Support")
        let caches     = homeDirectory.appendingPathComponent("Library/Caches")
        switch self {
        case .chrome:  return [appSupport.appendingPathComponent("Google/Chrome")]
        case .firefox:
            return [
                appSupport.appendingPathComponent("Firefox/Profiles"),
                caches.appendingPathComponent("Firefox/Profiles"),
            ]
        case .edge:    return [appSupport.appendingPathComponent("Microsoft Edge")]
        case .brave:   return [appSupport.appendingPathComponent("BraveSoftware/Brave-Browser")]
        case .vivaldi: return [appSupport.appendingPathComponent("Vivaldi")]
        case .arc:     return [appSupport.appendingPathComponent("Arc/User Data")]
        }
    }

    /// Bundle identifiery do wykrywania czy przeglądarka jest uruchomiona (NSRunningApplication).
    public var bundleIdentifiers: [String] {
        switch self {
        case .chrome:  return ["com.google.Chrome"]
        case .firefox: return ["org.mozilla.firefox"]
        case .edge:    return ["com.microsoft.edgemac"]
        case .brave:   return ["com.brave.Browser"]
        case .vivaldi: return ["com.vivaldi.Vivaldi"]
        case .arc:     return ["company.thebrowser.Browser"]
        }
    }

    /// Czy to silnik Chromium (wspólny layout profili). Explicit switch — nowy case enuma
    /// wymusi jawną decyzję, a nie cichy fallback do true.
    public var isChromium: Bool {
        switch self {
        case .chrome, .edge, .brave, .vivaldi, .arc: return true
        case .firefox: return false
        }
    }
}

public enum BrowserDataType: String, CaseIterable, Equatable, Hashable {
    case cache, cookies, history

    public var displayName: String {
        switch self {
        case .cache:   return "Cache"
        case .cookies: return "Ciasteczka"
        case .history: return "Historia"
        }
    }
}
