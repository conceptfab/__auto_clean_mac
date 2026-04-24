import Foundation

public struct DSStoreTask: CleanupTask {
    public let displayName = ".DS_Store files"
    public let isEnabled: Bool

    public init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    public func run(context: CleanupContext) async -> TaskResult {
        guard isEnabled else {
            return TaskResult(skipped: true, skipReason: "disabled")
        }
        let roots = ["Desktop", "Documents", "Downloads"]
            .map { context.homeDirectory.appendingPathComponent($0) }
            .filter { context.fileManager.fileExists(atPath: $0.path) }
        guard !roots.isEmpty else {
            return TaskResult(skipped: true, skipReason: "no roots present")
        }
        var freed: Int64 = 0
        var itemsDeleted = 0
        var warnings: [String] = []
        for root in roots {
            let files = FileEnumerator.files(inRoot: root, namedExactly: ".DS_Store")
            for url in files {
                do {
                    let metrics = try context.deleteMeasured(url, withinRoot: root)
                    freed += metrics.bytesFreed
                    itemsDeleted += metrics.itemsDeleted
                } catch {
                    warnings.append("\(url.path): \(error)")
                }
            }
        }
        return TaskResult(bytesFreed: freed, itemsDeleted: itemsDeleted, warnings: warnings)
    }
}
