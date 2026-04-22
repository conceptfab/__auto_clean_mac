import Foundation

public struct DevCachesTask: CleanupTask {
    public let displayName = "Dev caches"
    public let isEnabled: Bool
    private let runBrew: Bool

    public init(isEnabled: Bool, runBrew: Bool = true) {
        self.isEnabled = isEnabled
        self.runBrew = runBrew
    }

    public func run(context: CleanupContext) async -> TaskResult {
        guard isEnabled else {
            return TaskResult(skipped: true, skipReason: "disabled")
        }

        let roots: [URL] = [
            context.homeDirectory.appendingPathComponent("Library/Developer/Xcode/DerivedData"),
            context.homeDirectory.appendingPathComponent(".npm/_cacache"),
            context.homeDirectory.appendingPathComponent("Library/Caches/pip"),
        ].filter { context.fileManager.fileExists(atPath: $0.path) }

        var freed: Int64 = 0
        var warnings: [String] = []

        for root in roots {
            for url in FileEnumerator.files(inRoot: root, olderThanDays: context.retentionDays) {
                do {
                    freed += try context.deleter.delete(url, withinRoot: root)
                } catch {
                    warnings.append("\(url.lastPathComponent): \(error)")
                }
            }
        }

        if runBrew, let brew = Self.findExecutable("brew") {
            let status = Self.shell(brew, args: ["cleanup", "--prune=\(context.retentionDays)"])
            if status != 0 {
                warnings.append("brew cleanup exited \(status)")
            }
        }

        return TaskResult(bytesFreed: freed, warnings: warnings)
    }

    private static func findExecutable(_ name: String) -> String? {
        for path in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] {
            let full = "\(path)/\(name)"
            if FileManager.default.isExecutableFile(atPath: full) { return full }
        }
        return nil
    }

    private static func shell(_ path: String, args: [String]) -> Int32 {
        let process = Process()
        process.launchPath = path
        process.arguments = args
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
