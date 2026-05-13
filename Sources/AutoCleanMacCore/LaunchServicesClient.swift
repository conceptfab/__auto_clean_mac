import Foundation

public protocol LaunchServicesClient: Sendable {
    /// `lsregister -u <app>` — usuwa wpis bundla z bazy LaunchServices.
    /// Wywoływane PRZED skasowaniem `.app` z dysku.
    func unregister(app: URL)

    /// `lsregister -gc` + `-r -f -domain ...` — pełna przebudowa bazy.
    /// Drogie (~kilka sekund). Wywoływać RAZ po całym batchu uninstalla.
    func rebuild()
}

public struct ShellLaunchServicesClient: LaunchServicesClient {
    public init() {}

    private static let lsregisterPath =
        "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

    public func unregister(app: URL) {
        run(args: ["-u", app.path], timeout: 5)
    }

    public func rebuild() {
        // GC first (cheap), then full rebuild. Both swallow failures — this is best-effort
        // cosmetic cleanup of Spotlight/Dock app metadata.
        run(args: ["-gc"], timeout: 10)
        let primary = run(args: ["-r", "-f", "-domain", "local", "-domain", "user", "-domain", "system"], timeout: 15)
        if !primary {
            // Lighter fallback: drop system domain (requires sudo on some setups).
            _ = run(args: ["-r", "-f", "-domain", "local", "-domain", "user"], timeout: 10)
        }
    }

    @discardableResult
    private func run(args: [String], timeout: TimeInterval) -> Bool {
        let exec = URL(fileURLWithPath: Self.lsregisterPath)
        guard FileManager.default.isExecutableFile(atPath: exec.path) else { return false }

        let p = Process()
        p.executableURL = exec
        p.arguments = args
        let null = FileHandle(forWritingAtPath: "/dev/null")
        p.standardOutput = null
        p.standardError = null

        do {
            try p.run()
        } catch {
            return false
        }

        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning {
            if Date() > deadline {
                p.terminate()
                return false
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return p.terminationStatus == 0
    }
}
