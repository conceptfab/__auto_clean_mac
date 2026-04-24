import Foundation

public struct DownloadsTask: CleanupTask {
    public let displayName = "Downloads (>retention, opt-in)"
    public let isEnabled: Bool

    public init(isEnabled: Bool) { self.isEnabled = isEnabled }

    public func run(context: CleanupContext) async -> TaskResult {
        guard isEnabled else {
            return TaskResult(skipped: true, skipReason: "disabled")
        }
        let root = context.homeDirectory.appendingPathComponent("Downloads")
        guard context.fileManager.fileExists(atPath: root.path) else {
            return TaskResult(skipped: true, skipReason: "root missing")
        }

        guard let entries = try? context.fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            return TaskResult(skipped: true, skipReason: "unreadable")
        }

        let now = Date()
        let cutoff = now.addingTimeInterval(TimeInterval(-context.retentionDays * 86_400))
        var freed: Int64 = 0
        var itemsDeleted = 0
        var warnings: [String] = []

        for url in entries {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            guard let mtime = values?.contentModificationDate, mtime <= cutoff else { continue }
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
