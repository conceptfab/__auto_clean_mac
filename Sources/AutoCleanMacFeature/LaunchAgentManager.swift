import Foundation

enum LaunchAgentManager {
    enum Error: Swift.Error, LocalizedError {
        case missingExecutable
        case launchctlFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingExecutable:
                return "Nie udało się ustalić ścieżki do binarki aplikacji."
            case .launchctlFailed(let output):
                return output.isEmpty ? "launchctl zakończył się błędem." : output
            }
        }
    }

    private static let appName = "AutoCleanMac"
    private static let bundleID = "com.micz.autocleanmac"

    static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(bundleID).plist")
    }

    static var logsDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/AutoCleanMac")
    }

    static var configDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/autoclean-mac")
    }

    static var disabledMarkerURL: URL {
        configDirectoryURL.appendingPathComponent("launch_at_login.disabled")
    }

    static func isEnabled(fileManager: FileManager = .default) -> Bool {
        if fileManager.fileExists(atPath: disabledMarkerURL.path) {
            return false
        }
        return fileManager.fileExists(atPath: launchAgentURL.path)
    }

    static func setEnabled(_ enabled: Bool, fileManager: FileManager = .default) throws {
        if enabled {
            try install(fileManager: fileManager)
        } else {
            try uninstall(fileManager: fileManager)
        }
    }

    private static func install(fileManager: FileManager) throws {
        guard let executablePath = Bundle.main.executableURL?.path else {
            throw Error.missingExecutable
        }

        try fileManager.createDirectory(at: launchAgentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: logsDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)

        let plist = launchAgentPlist(appBinaryPath: executablePath, logsDirectoryPath: logsDirectoryURL.path)
        try plist.write(to: launchAgentURL, atomically: true, encoding: .utf8)

        _ = try? runLaunchctl(["unload", launchAgentURL.path])
        _ = try runLaunchctl(["load", "-w", launchAgentURL.path])

        if fileManager.fileExists(atPath: disabledMarkerURL.path) {
            try? fileManager.removeItem(at: disabledMarkerURL)
        }
    }

    private static func uninstall(fileManager: FileManager) throws {
        if fileManager.fileExists(atPath: launchAgentURL.path) {
            _ = try? runLaunchctl(["unload", "-w", launchAgentURL.path])
            try? fileManager.removeItem(at: launchAgentURL)
        }

        try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
        let marker = "disabled"
        try marker.write(to: disabledMarkerURL, atomically: true, encoding: .utf8)
    }

    private static func runLaunchctl(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile() + stderr.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw Error.launchctlFailed(output)
        }
        return output
    }

    static func launchAgentPlist(appBinaryPath: String, logsDirectoryPath: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(bundleID)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(appBinaryPath)</string>
                <string>--launch-agent</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
            <key>ProcessType</key>
            <string>Interactive</string>
            <key>StandardOutPath</key>
            <string>\(logsDirectoryPath)/launchd.out.log</string>
            <key>StandardErrorPath</key>
            <string>\(logsDirectoryPath)/launchd.err.log</string>
        </dict>
        </plist>
        """
    }
}
