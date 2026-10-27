import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Best-effort terminacja działającej aplikacji przed jej usunięciem.
/// Logika oparta na `__mole/lib/core/app_protection.sh:force_kill_app`.
public protocol AppTerminator: Sendable {
    /// Próbuje zamknąć aplikację. Sukces oznacza, że proces nie żyje po wywołaniu;
    /// zwrócenie `false` oznacza, że proces *może* nadal żyć (uninstall powinien iść dalej —
    /// macOS pozwala usunąć działający bundle).
    func terminate(bundleID: String) async -> Bool
}

/// Minimalny interfejs uruchomionej aplikacji (testowalny zamiennik `NSRunningApplication`).
protocol TerminatableApp: AnyObject {
    var hasExited: Bool { get }
    @discardableResult func terminate() -> Bool
    @discardableResult func forceTerminate() -> Bool
}

#if canImport(AppKit)
extension NSRunningApplication: TerminatableApp {
    /// `isTerminated` aktualizuje się przez main run loop; dodatkowo sprawdzamy PID przez `kill(pid, 0)`,
    /// żeby odpytywanie działało także, gdy main thread jest zajęty.
    var hasExited: Bool {
        if isTerminated { return true }
        let pid = processIdentifier
        guard pid > 0 else { return true }
        return kill(pid, 0) != 0 && errno == ESRCH
    }
}
#endif

/// Zamyka aplikację po bundle ID przez `NSRunningApplication`: najpierw łagodne `terminate()`
/// (Apple Event „quit”), potem `forceTerminate()`, za każdym razem z prawdziwym limitem czasu
/// (odpytywanie stanu procesu — nic nie blokuje wątku bez końca).
/// Nazwa zachowana dla zgodności; nie używa już `pgrep`/`pkill`/`osascript`.
public struct ShellAppTerminator: AppTerminator {
    private let runningApps: @Sendable (String) -> [TerminatableApp]
    private let gracefulTimeout: TimeInterval
    private let forceTimeout: TimeInterval
    private let pollInterval: TimeInterval

    public init() {
        self.init(
            runningApps: Self.systemRunningApps,
            gracefulTimeout: 3,
            forceTimeout: 2,
            pollInterval: 0.1
        )
    }

    init(
        runningApps: @escaping @Sendable (String) -> [TerminatableApp],
        gracefulTimeout: TimeInterval,
        forceTimeout: TimeInterval,
        pollInterval: TimeInterval
    ) {
        self.runningApps = runningApps
        self.gracefulTimeout = gracefulTimeout
        self.forceTimeout = forceTimeout
        self.pollInterval = pollInterval
    }

    /// Identyfikujemy procesy wyłącznie po bundle ID (dopasowanie po nazwie procesu mogłoby
    /// trafić w obcy proces).
    public func terminate(bundleID: String) async -> Bool {
        guard !bundleID.isEmpty else { return true }
        let apps = runningApps(bundleID).filter { !$0.hasExited }
        guard !apps.isEmpty else { return true }

        // 1) Łagodne zamknięcie — aplikacja może zapisać stan (Tauri/Electron/SwiftUI).
        for app in apps { app.terminate() }
        if await waitUntilExited(apps, timeout: gracefulTimeout) { return true }

        // 2) Wymuszenie (SIGKILL) dla tych, które nadal żyją.
        for app in apps where !app.hasExited { app.forceTerminate() }
        return await waitUntilExited(apps, timeout: forceTimeout)
    }

    private func waitUntilExited(_ apps: [TerminatableApp], timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if apps.allSatisfy({ $0.hasExited }) { return true }
            if Date() >= deadline { return false }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
    }

    private static let systemRunningApps: @Sendable (String) -> [TerminatableApp] = { bundleID in
        #if canImport(AppKit)
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        #else
        return []
        #endif
    }
}
