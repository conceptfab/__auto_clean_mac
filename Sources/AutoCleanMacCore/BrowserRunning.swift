import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Wykrywa czy dana przeglądarka jest aktualnie uruchomiona. Jeśli AppKit niedostępny
/// (np. testy na Linuksie) zawsze zwraca false — wtedy taski po prostu będą usuwać pliki
/// jakby browser był zamknięty.
public enum BrowserRunning {
    public static func isRunning(_ browser: BrowserIdentity) -> Bool {
        #if canImport(AppKit)
        let running = NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier }
        return browser.bundleIdentifiers.contains { running.contains($0) }
        #else
        return false
        #endif
    }
}
