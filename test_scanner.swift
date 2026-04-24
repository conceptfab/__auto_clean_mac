import Foundation
import AutoCleanMacCore

let config = Config.default
let tempLogDir = FileManager.default.temporaryDirectory.appendingPathComponent("AutoCleanMacScannerLogs")
let logger = try! Logger(directory: tempLogDir)
let deleter = SafeDeleter(mode: .dryRun, logger: logger)
let ctx = CleanupContext(
    retentionDays: config.retentionDays,
    deleter: deleter,
    deletionMode: .dryRun,
    logger: logger,
    excludedPaths: config.resolvedExcludedPathURLs()
)
let engine = CleanupEngine.makeDefault(config: config)

let semaphore = DispatchSemaphore(value: 0)

Task {
    let _ = await engine.run(context: ctx) { event in
        switch event {
        case .taskFinished(let name, let result):
            print("Finished \(name): \(result.bytesFreed) bytes")
        default:
            break
        }
    }
    semaphore.signal()
}

semaphore.wait()
print("Done")
