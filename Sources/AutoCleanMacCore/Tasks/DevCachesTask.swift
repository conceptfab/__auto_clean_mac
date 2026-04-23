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
            context.logger.log(event: "brew_cleanup_start", fields: [
                "path": brew,
                "prune_days": "\(context.retentionDays)",
            ])

            let outcome = Self.runProcess(
                brew,
                args: ["cleanup", "--prune=\(context.retentionDays)"],
                timeoutSeconds: 30
            )

            var logFields: [String: String] = [
                "status": "\(outcome.status)",
                "timed_out": outcome.timedOut ? "true" : "false",
            ]
            let outputPreview = Self.logPreview(outcome.combinedOutput)
            if !outputPreview.isEmpty {
                logFields["output"] = outputPreview
            }
            context.logger.log(event: "brew_cleanup_finish", fields: logFields)

            if let approxBytes = Self.approximateFreedBytes(from: outcome.combinedOutput) {
                freed += approxBytes
            }

            if outcome.timedOut {
                warnings.append("brew cleanup timed out after 30s")
            } else if outcome.status != 0 {
                warnings.append("brew cleanup exited \(outcome.status)")
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

    struct ProcessOutcome {
        let status: Int32
        let stdout: String
        let stderr: String
        let timedOut: Bool

        var combinedOutput: String {
            [stdout, stderr]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }
    }

    static func approximateFreedBytes(from output: String) -> Int64? {
        let pattern = #"freed(?: approximately)? ([0-9]+(?:\.[0-9]+)?)\s*([KMGTP]?B)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        let matches = regex.matches(in: output, options: [], range: range)
        var best: Int64?

        for match in matches {
            guard match.numberOfRanges == 3,
                  let amountRange = Range(match.range(at: 1), in: output),
                  let unitRange = Range(match.range(at: 2), in: output),
                  let amount = Double(output[amountRange]) else {
                continue
            }

            let unit = output[unitRange].uppercased()
            let multiplier: Double
            switch unit {
            case "KB": multiplier = 1_024
            case "MB": multiplier = 1_048_576
            case "GB": multiplier = 1_073_741_824
            case "TB": multiplier = 1_099_511_627_776
            case "PB": multiplier = 1_125_899_906_842_624
            case "B":  multiplier = 1
            default:   continue
            }

            let value = Int64(amount * multiplier)
            best = max(best ?? 0, value)
        }
        return best
    }

    private static func runProcess(_ path: String, args: [String], timeoutSeconds: Int) -> ProcessOutcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args

        let tempDir = FileManager.default.temporaryDirectory
        let stdoutURL = tempDir.appendingPathComponent("autocleanmac-brew-\(UUID().uuidString).stdout")
        let stderrURL = tempDir.appendingPathComponent("autocleanmac-brew-\(UUID().uuidString).stderr")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)

        let stdoutHandle: FileHandle?
        let stderrHandle: FileHandle?
        do {
            stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
            stderrHandle = try FileHandle(forWritingTo: stderrURL)
        } catch {
            try? FileManager.default.removeItem(at: stdoutURL)
            try? FileManager.default.removeItem(at: stderrURL)
            return ProcessOutcome(status: -1, stdout: "", stderr: "failed to open temp log files: \(error)", timedOut: false)
        }

        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }

        defer {
            try? stdoutHandle?.close()
            try? stderrHandle?.close()
            try? FileManager.default.removeItem(at: stdoutURL)
            try? FileManager.default.removeItem(at: stderrURL)
        }

        do {
            try process.run()
        } catch {
            return ProcessOutcome(status: -1, stdout: "", stderr: "failed to run process: \(error)", timedOut: false)
        }

        let waitResult = semaphore.wait(timeout: .now() + .seconds(timeoutSeconds))
        let timedOut = waitResult == .timedOut
        if timedOut {
            process.interrupt()
            if semaphore.wait(timeout: .now() + .seconds(2)) == .timedOut {
                process.terminate()
                _ = semaphore.wait(timeout: .now() + .seconds(2))
            }
        }

        try? stdoutHandle?.synchronize()
        try? stderrHandle?.synchronize()

        let stdout = (try? String(contentsOf: stdoutURL, encoding: .utf8)) ?? ""
        let stderr = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""
        let status = process.isRunning ? -1 : process.terminationStatus
        return ProcessOutcome(status: status, stdout: stdout, stderr: stderr, timedOut: timedOut)
    }

    private static func logPreview(_ output: String) -> String {
        output
            .split(whereSeparator: \.isNewline)
            .prefix(6)
            .joined(separator: " | ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
