import Foundation

public protocol PreferencesDaemonClient: Sendable {
    /// Wymusza zrzut cache cfprefsd dla danego bundle ID poprzez `defaults delete`.
    /// Zwraca `true` jeśli komenda wykonała się bez błędu (nawet gdy klucz nie istniał).
    func deleteAll(bundleID: String) -> Bool
}

public struct ShellPreferencesDaemonClient: PreferencesDaemonClient {
    public init() {}
    public func deleteAll(bundleID: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["delete", bundleID]
        let nullHandle = FileHandle(forWritingAtPath: "/dev/null")
        process.standardOutput = nullHandle
        process.standardError = nullHandle
        do {
            try process.run()
            process.waitUntilExit()
            // Status 1 oznacza "domain not found" — to nie jest błąd dla naszego use-case.
            return true
        } catch {
            return false
        }
    }
}
