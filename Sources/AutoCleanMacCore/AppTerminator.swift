import Foundation

/// Best-effort terminacja działającej aplikacji przed jej usunięciem.
/// Logika oparta na `__mole/lib/core/app_protection.sh:force_kill_app`.
public protocol AppTerminator: Sendable {
    /// Próbuje zamknąć aplikację. Sukces oznacza, że proces nie żyje po wywołaniu;
    /// zwrócenie `false` oznacza, że proces *może* nadal żyć (uninstall powinien iść dalej —
    /// macOS pozwala usunąć działający bundle).
    func terminate(bundleID: String, executableName: String?) async -> Bool
}

public struct ShellAppTerminator: AppTerminator {
    public init() {}

    public func terminate(bundleID: String, executableName: String?) async -> Bool {
        let match = executableName?.isEmpty == false ? executableName! : bundleID

        guard isRunning(match: match) else { return true }

        // 1) Apple Event "quit" przez osascript — zarządza Tauri/Electron/SwiftUI poprawnie.
        if !bundleID.isEmpty {
            _ = await runWithTimeout(seconds: 3) {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                p.arguments = ["-e", "tell application id \"\(bundleID)\" to quit"]
                let null = FileHandle(forWritingAtPath: "/dev/null")
                p.standardOutput = null
                p.standardError = null
                try? p.run()
                p.waitUntilExit()
            }
            // Daj procesowi do 2s na łagodne zamknięcie.
            for _ in 0..<20 {
                if !isRunning(match: match) { return true }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        // 2) SIGTERM
        runPkill(args: ["-x", match])
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        if !isRunning(match: match) { return true }

        // 3) SIGKILL
        runPkill(args: ["-9", "-x", match])
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        return !isRunning(match: match)
    }

    private func isRunning(match: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-x", match]
        let null = FileHandle(forWritingAtPath: "/dev/null")
        p.standardOutput = null
        p.standardError = null
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func runPkill(args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        p.arguments = args
        let null = FileHandle(forWritingAtPath: "/dev/null")
        p.standardOutput = null
        p.standardError = null
        try? p.run()
        p.waitUntilExit()
    }

    private func runWithTimeout(seconds: TimeInterval, _ work: @escaping @Sendable () -> Void) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                work()
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }
}
