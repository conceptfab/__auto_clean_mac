import Foundation

public struct TrashTask: CleanupTask {
    public let displayName = "Trash (>retention)"
    public let isEnabled: Bool
    private let trashedDate: (URL) -> Date?

    public init(isEnabled: Bool) {
        self.init(isEnabled: isEnabled, trashedDate: Self.defaultTrashedDate)
    }

    /// Testowalny init — pozwala wstrzyknąć datę wrzucenia elementu do Kosza.
    init(isEnabled: Bool, trashedDate: @escaping (URL) -> Date?) {
        self.isEnabled = isEnabled
        self.trashedDate = trashedDate
    }

    public func run(context: CleanupContext) async -> TaskResult {
        guard isEnabled else {
            return TaskResult(skipped: true, skipReason: "disabled")
        }
        let root = context.homeDirectory.appendingPathComponent(".Trash")
        guard context.fileManager.fileExists(atPath: root.path) else {
            return TaskResult(skipped: true, skipReason: "root missing")
        }
        // Tylko elementy najwyższego poziomu Kosza, usuwane w całości — nigdy pojedyncze pliki
        // z wnętrza wyrzuconych folderów. Wiek liczymy od daty wrzucenia do Kosza, nie od
        // daty modyfikacji treści (ta nie zmienia się przy przenoszeniu do Kosza).
        guard let entries = try? context.fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.addedToDirectoryDateKey, .attributeModificationDateKey],
            options: []
        ) else {
            return TaskResult(skipped: true, skipReason: "unreadable")
        }
        let cutoff = Date().addingTimeInterval(-TimeInterval(context.retentionDays) * 86_400)
        var freed: Int64 = 0
        var itemsDeleted = 0
        var warnings: [String] = []
        // Elementy już są w Koszu — „przeniesienie do Kosza” nic by nie zwolniło, więc w trybie
        // trash usuwamy trwale (dry-run nadal nic nie rusza). Te same bramki SafeDeleter i wykluczenia.
        let deleter = context.deleter.mode == .trash ? SafeDeleter(mode: .live, logger: context.logger) : context.deleter
        for url in entries {
            // Brak daty = nie wiemy, kiedy element trafił do Kosza → zostawiamy.
            guard let trashed = trashedDate(url), trashed <= cutoff else { continue }
            do {
                let metrics = try deleter.deleteMeasured(url, withinRoot: root, excluding: context.excludedPaths)
                freed += metrics.bytesFreed
                itemsDeleted += metrics.itemsDeleted
            } catch {
                warnings.append("\(url.lastPathComponent): \(error)")
            }
        }
        return TaskResult(bytesFreed: freed, itemsDeleted: itemsDeleted, warnings: warnings)
    }

    /// Data wrzucenia do Kosza: `addedToDirectoryDate`, a gdy niedostępna — data zmiany
    /// atrybutów (ctime, aktualizowana przy przeniesieniu). Nigdy `contentModificationDate`.
    static func defaultTrashedDate(_ url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey, .attributeModificationDateKey])
        return values?.addedToDirectoryDate ?? values?.attributeModificationDate
    }
}
