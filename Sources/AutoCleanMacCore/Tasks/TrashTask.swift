import Foundation

public struct TrashTask: CleanupTask {
    public let displayName = "Trash (>retention)"
    public let isEnabled: Bool

    public init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    public func run(context: CleanupContext) async -> TaskResult {
        guard isEnabled else {
            return TaskResult(skipped: true, skipReason: "disabled")
        }
        let root = context.homeDirectory.appendingPathComponent(".Trash")
        guard context.fileManager.fileExists(atPath: root.path) else {
            return TaskResult(skipped: true, skipReason: "root missing")
        }
        let candidates = FileEnumerator.files(inRoot: root, olderThanDays: context.retentionDays)
        var freed: Int64 = 0
        var warnings: [String] = []
        for url in candidates {
            do {
                freed += try context.deleter.delete(url, withinRoot: root)
            } catch {
                warnings.append("\(url.lastPathComponent): \(error)")
            }
        }
        return TaskResult(bytesFreed: freed, warnings: warnings)
    }
}
