import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Wspólne helpery do sprawdzania, czy aplikacja o danym bundle identifierze aktualnie działa.
public enum AppRunning {
    public static func isRunning(bundleIdentifier: String) -> Bool {
        #if canImport(AppKit)
        let running = NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier }
        return running.contains(bundleIdentifier)
        #else
        return false
        #endif
    }
}
