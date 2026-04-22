import Foundation

public struct UserCachesTask: CleanupTask {
    public let displayName = "User caches"
    public let isEnabled: Bool

    public init(isEnabled: Bool) { self.isEnabled = isEnabled }

    public func run(context: CleanupContext) async -> TaskResult {
        guard isEnabled else {
            return TaskResult(skipped: true, skipReason: "disabled")
        }
        let root = context.homeDirectory.appendingPathComponent("Library/Caches")
        guard context.fileManager.fileExists(atPath: root.path) else {
            return TaskResult(skipped: true, skipReason: "root missing")
        }
        var freed: Int64 = 0
        var warnings: [String] = []
        for url in FileEnumerator.files(inRoot: root) {
            do {
                freed += try context.deleter.delete(url, withinRoot: root)
            } catch {
                warnings.append("\(url.lastPathComponent): \(error)")
            }
        }
        return TaskResult(bytesFreed: freed, warnings: warnings)
    }
}
