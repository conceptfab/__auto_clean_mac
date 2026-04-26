import Foundation

public protocol LaunchAgentClient: Sendable {
    /// Próbuje wyładować plist agenta. `domain` to `gui/<uid>` dla user-side, `system` dla `/Library/LaunchDaemons`.
    func unload(plist: URL, domain: LaunchAgentDomain) -> Bool
}

public enum LaunchAgentDomain: Sendable {
    case userGUI(uid: uid_t)
    case system
}
