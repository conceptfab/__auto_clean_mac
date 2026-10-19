import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Wykrywa czy dana przeglądarka jest aktualnie uruchomiona. Jeśli AppKit niedostępny
/// (np. testy na Linuksie) sprawdzana jest tylko blokada profilu Chromium.
public enum BrowserRunning {
    public static func isRunning(_ browser: BrowserIdentity) -> Bool {
        isRunning(
            browser,
            runningBundleIDs: currentRunningBundleIDs(for: browser),
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    /// Przeglądarka liczy się jako uruchomiona, gdy żyje jakikolwiek jej proces — także
    /// zminimalizowany, ukryty, na innym Space albo działający w tle bez okien. Wtedy jej bazy
    /// SQLite są otwarte i nie wolno ich kasować. Dodatkowo dla Chromium honorujemy
    /// `SingletonLock` (np. przeglądarka uruchomiona z innego bundle'a / innej kopii).
    static func isRunning(
        _ browser: BrowserIdentity,
        runningBundleIDs: Set<String>,
        homeDirectory: URL,
        isProcessAlive: (pid_t) -> Bool = BrowserRunning.isProcessAlive
    ) -> Bool {
        if browser.bundleIdentifiers.contains(where: runningBundleIDs.contains) {
            return true
        }
        guard browser.isChromium else { return false }
        return browser.applicationSupportProfileRoots(homeDirectory: homeDirectory).contains { root in
            hasLiveSingletonLock(in: root, isProcessAlive: isProcessAlive)
        }
    }

    private static func currentRunningBundleIDs(for browser: BrowserIdentity) -> Set<String> {
        #if canImport(AppKit)
        var result: Set<String> = []
        for bundleID in browser.bundleIdentifiers {
            let alive = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .contains { !$0.isTerminated }
            if alive { result.insert(bundleID) }
        }
        return result
        #else
        return []
        #endif
    }

    /// Chromium trzyma w katalogu danych symlink `SingletonLock` → `<host>-<pid>`. Po crashu
    /// symlink potrafi zostać, więc liczy się tylko wtedy, gdy proces o tym PID-zie żyje.
    /// Gdy celu nie da się sparsować — zachowawczo uznajemy przeglądarkę za uruchomioną.
    static func hasLiveSingletonLock(in root: URL, isProcessAlive: (pid_t) -> Bool) -> Bool {
        let lock = root.appendingPathComponent("SingletonLock")
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: lock.path) else {
            return false
        }
        guard let pidPart = target.split(separator: "-").last, let pid = pid_t(pidPart), pid > 0 else {
            return true
        }
        return isProcessAlive(pid)
    }

    static func isProcessAlive(_ pid: pid_t) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }
}
