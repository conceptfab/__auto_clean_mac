import Foundation
import AppKit

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

@MainActor
enum ElevatedUninstall {
    /// Przenosi element do Kosza przez Finder. macOS sam pokaże prompt o hasło, jeśli trzeba.
    static func trashViaFinder(_ url: URL) throws {
        let escaped = escapeForAppleScript(url.path)
        let source = """
        tell application "Finder"
            delete POSIX file "\(escaped)"
        end tell
        """
        try runScript(source)
    }

    /// Trwale usuwa element z autoryzacją administratora. macOS pokazuje standardowe okno hasła.
    /// Autoryzacja jest cache'owana ~5 minut, więc seria deinstalacji = jeden prompt.
    static func removeWithAdmin(_ url: URL) throws {
        let escaped = escapeForAppleScript(url.path)
        let source = "do shell script \"rm -rf \" & quoted form of \"\(escaped)\" with administrator privileges"
        try runScript(source)
    }

    private static func escapeForAppleScript(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func runScript(_ source: String) throws {
        guard let script = NSAppleScript(source: source) else {
            throw ElevatedUninstallError.scriptCompileFailed
        }
        var errorDict: NSDictionary?
        _ = script.executeAndReturnError(&errorDict)
        guard let err = errorDict else { return }

        let code = (err[NSAppleScript.errorNumber] as? Int) ?? 0
        let message = (err[NSAppleScript.errorMessage] as? String) ?? "Nieznany błąd AppleScript."
        if code == -128 {
            throw ElevatedUninstallError.userCancelled
        }
        throw ElevatedUninstallError.scriptFailed(code: code, message: message)
    }
}
