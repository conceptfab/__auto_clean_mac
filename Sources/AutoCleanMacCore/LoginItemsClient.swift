import Foundation

public protocol LoginItemsClient: Sendable {
    /// Best-effort: usuwa wpis o danej nazwie/bundle ID z Login Items.
    /// Brak gwarancji — wymaga uprawnień AppleScript do System Events.
    func removeLoginItem(appName: String?, bundleID: String)
}
