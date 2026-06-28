import Foundation
#if canImport(AppKit)
import AppKit
import CoreGraphics
#endif

/// Wykrywa czy dana przeglądarka jest aktualnie uruchomiona. Jeśli AppKit niedostępny
/// (np. testy na Linuksie) zawsze zwraca false — wtedy taski po prostu będą usuwać pliki
/// jakby browser był zamknięty.
public enum BrowserRunning {
    public static func isRunning(_ browser: BrowserIdentity) -> Bool {
        #if canImport(AppKit)
        return NSWorkspace.shared.runningApplications.contains { app in
            guard let bundleID = app.bundleIdentifier,
                  browser.bundleIdentifiers.contains(bundleID) else { return false }
            // Proces główny Chromium może żyć w tle po zamknięciu okien
            // (ustawienie „Continue running apps in background”). Pomijamy cleanup
            // tylko gdy przeglądarka ma widoczne okna.
            return hasVisibleWindows(processID: app.processIdentifier)
        }
        #else
        return false
        #endif
    }

    #if canImport(AppKit)
    static func hasVisibleWindows(processID: pid_t) -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }

        return windowList.contains { info in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID == processID else { return false }
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 0
            return layer == 0 && alpha > 0
        }
    }
    #endif
}
