import Foundation

public protocol LoginItemsClient: Sendable {
    /// Best-effort: usuwa wpis o danej nazwie/bundle ID z Login Items.
    /// Brak gwarancji — wymaga uprawnień AppleScript do System Events.
    func removeLoginItem(appName: String?, bundleID: String)
}

public struct ShellLoginItemsClient: LoginItemsClient {
    public init() {}

    public func removeLoginItem(appName: String?, bundleID: String) {
        let cleanName = (appName ?? "").replacingOccurrences(of: ".app", with: "")
        guard !cleanName.isEmpty else { return }

        let escaped = cleanName
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "System Events"
            try
                set itemCount to count of login items
                repeat with i from itemCount to 1 by -1
                    try
                        set itemName to name of login item i
                        if itemName is "\(escaped)" then
                            delete login item i
                        end if
                    end try
                end repeat
            end try
        end tell
        """

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let null = FileHandle(forWritingAtPath: "/dev/null")
        p.standardOutput = null
        p.standardError = null
        try? p.run()
        p.waitUntilExit()
    }
}
