import Foundation

public protocol PreferencesDaemonClient: Sendable {
    /// Wymusza zrzut cache cfprefsd dla danego bundle ID poprzez `defaults delete`.
    /// Zwraca `true` jeśli komenda wykonała się bez błędu (nawet gdy klucz nie istniał).
    func deleteAll(bundleID: String) -> Bool
}
