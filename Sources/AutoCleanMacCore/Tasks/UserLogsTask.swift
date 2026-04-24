import Foundation

public struct UserLogsTask: CleanupTask {
    public let displayName = "User logs (>retention)"
    public let isEnabled: Bool

    public init(isEnabled: Bool) { self.isEnabled = isEnabled }

    public func run(context: CleanupContext) async -> TaskResult {
        guard isEnabled else {
            return TaskResult(skipped: true, skipReason: "disabled")
        }
        let root = context.homeDirectory.appendingPathComponent("Library/Logs")
        guard context.fileManager.fileExists(atPath: root.path) else {
            return TaskResult(skipped: true, skipReason: "root missing")
        }
        var freed: Int64 = 0
        var itemsDeleted = 0
        var warnings: [String] = []
        for url in FileEnumerator.files(inRoot: root, olderThanDays: context.retentionDays) {
            do {
                let metrics = try context.deleteMeasured(url, withinRoot: root)
                freed += metrics.bytesFreed
                itemsDeleted += metrics.itemsDeleted
            } catch {
                warnings.append("\(url.lastPathComponent): \(error)")
            }
        }
        return TaskResult(bytesFreed: freed, itemsDeleted: itemsDeleted, warnings: warnings)
    }
}
