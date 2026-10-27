import Foundation
import AutoCleanMacCore

enum ElevatedUninstallError: Error, CustomStringConvertible {
    case scriptCompileFailed
    case userCancelled
    case scriptFailed(code: Int, message: String)

    var description: String {
        switch self {
        case .scriptCompileFailed: return "AppleScript nie skompilował się."
        case .userCancelled: return "Anulowano przez użytkownika."
        case .scriptFailed(_, let msg): return msg
        }
    }
}

/// Skrypty uruchamiamy przez `/usr/bin/osascript` na wątku w tle — NIE przez `NSAppleScript`
/// na main thread. Okno hasła administratora i samo `rm -rf` potrafią trwać minutami, a moduł
/// działa wewnątrz jednego procesu menu-bar („CFAB Control”) — blokada main threadu zamroziłaby cały hub.
enum ElevatedUninstall {
    static func remove(
        _ url: URL,
        mode: SafeDeleter.Mode,
        run: (String) async throws -> Void = runScript
    ) async throws {
        let source: String
        switch mode {
        case .dryRun:
            return
        case .trash:
            let escaped = escapeForAppleScript(url.path)
            source = """
            tell application "Finder"
                delete POSIX file "\(escaped)"
            end tell
            """
        case .live:
            source = adminRemoveScript(for: url)
        }
        try await run(source)
    }

    /// AppleScript usuwający element z autoryzacją administratora: macOS pokazuje własne okno
    /// hasła (nigdy `sudo` w tle). Systemowy LaunchDaemon/Agent najpierw wyładowujemy jako root
    /// (z konta użytkownika `bootout system` zawsze się nie udaje); błąd bootout nie blokuje `rm`.
    static func adminRemoveScript(for url: URL) -> String {
        let escaped = escapeForAppleScript(url.path)
        let isSystemService = ["/Library/LaunchDaemons", "/Library/LaunchAgents"]
            .contains { url.isStrictlyWithin(URL(fileURLWithPath: $0)) }
        let bootout = isSystemService
            ? "\"launchctl bootout system \" & quoted form of \"\(escaped)\" & \" 2>/dev/null; \" & "
            : ""
        return "do shell script \(bootout)\"rm -rf \" & quoted form of \"\(escaped)\" with administrator privileges"
    }

    private static func escapeForAppleScript(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func runScript(_ source: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try runScriptBlocking(source)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Blokujące wykonanie przez `osascript` — wolno wołać wyłącznie poza main threadem.
    private static func runScriptBlocking(_ source: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw ElevatedUninstallError.scriptFailed(code: -1, message: "Nie udało się uruchomić osascript: \(error)")
        }
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus != 0 else { return }

        let message = String(data: errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let code = appleScriptErrorCode(in: message) ?? Int(process.terminationStatus)
        if code == -128 {
            throw ElevatedUninstallError.userCancelled
        }
        if code == -2740 || code == -2741 {
            throw ElevatedUninstallError.scriptCompileFailed
        }
        throw ElevatedUninstallError.scriptFailed(
            code: code,
            message: message.isEmpty ? "Nieznany błąd AppleScript." : message
        )
    }

    /// `osascript` zgłasza błędy jako `0:42: execution error: User canceled. (-128)` —
    /// wyciągamy numer z końcowego nawiasu.
    static func appleScriptErrorCode(in message: String) -> Int? {
        guard message.hasSuffix(")"), let open = message.lastIndex(of: "(") else { return nil }
        let inner = message[message.index(after: open)..<message.index(before: message.endIndex)]
        return Int(inner)
    }
}
