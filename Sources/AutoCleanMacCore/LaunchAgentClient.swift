import Foundation

public protocol LaunchAgentClient: Sendable {
    /// Próbuje wyładować plist agenta. `domain` to `gui/<uid>` dla user-side, `system` dla `/Library/LaunchDaemons`.
    func unload(plist: URL, domain: LaunchAgentDomain) -> Bool
}

public enum LaunchAgentDomain: Sendable {
    case userGUI(uid: uid_t)
    case system
}

public struct ShellLaunchAgentClient: LaunchAgentClient {
    public init() {}
    public func unload(plist: URL, domain: LaunchAgentDomain) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        switch domain {
        case .userGUI(let uid):
            process.arguments = ["bootout", "gui/\(uid)", plist.path]
        case .system:
            process.arguments = ["bootout", "system", plist.path]
        }
        let nullHandle = FileHandle(forWritingAtPath: "/dev/null")
        process.standardOutput = nullHandle
        process.standardError = nullHandle
        do {
            try process.run()
            process.waitUntilExit()
            return true
        } catch {
            return false
        }
    }
}
