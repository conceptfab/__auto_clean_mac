import Foundation

public struct SystemTempTask: CleanupTask {
    public let displayName = "System temp (>retention)"
    public let isEnabled: Bool
    private let rootOverride: URL?
    private let isIdleSince: (URL, Date) -> Bool

    public init(isEnabled: Bool, rootOverride: URL? = nil) {
        self.init(isEnabled: isEnabled, rootOverride: rootOverride, isIdleSince: Self.defaultIsIdleSince)
    }

    /// Testowalny init — pozwala wstrzyknąć sprawdzenie dat dostępu/zmiany atrybutów.
    init(isEnabled: Bool, rootOverride: URL?, isIdleSince: @escaping (URL, Date) -> Bool) {
        self.isEnabled = isEnabled
        self.rootOverride = rootOverride
        self.isIdleSince = isIdleSince
    }

    public func run(context: CleanupContext) async -> TaskResult {
        guard isEnabled else {
            return TaskResult(skipped: true, skipReason: "disabled")
        }
        let root = rootOverride ?? URL(fileURLWithPath: NSTemporaryDirectory())
        guard context.fileManager.fileExists(atPath: root.path) else {
            return TaskResult(skipped: true, skipReason: "root missing")
        }
        let cutoff = Date().addingTimeInterval(-TimeInterval(context.retentionDays) * 86_400)
        var freed: Int64 = 0
        var itemsDeleted = 0
        var warnings: [String] = []
        for url in FileEnumerator.files(inRoot: root, olderThanDays: context.retentionDays) {
            // Stara treść nie znaczy „nieużywany” — plik w $TMPDIR może być otwarty/czytany
            // przez działający proces. Wymagamy też starego dostępu i zmiany atrybutów.
            guard isIdleSince(url, cutoff) else { continue }
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

    /// `true`, gdy zarówno data dostępu, jak i zmiany atrybutów (ctime) są nie nowsze niż `cutoff`.
    /// Brak którejkolwiek daty = nie wiemy → nie ruszamy pliku.
    static func defaultIsIdleSince(_ url: URL, cutoff: Date) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.contentAccessDateKey, .attributeModificationDateKey]),
              let accessed = values.contentAccessDate,
              let attributesChanged = values.attributeModificationDate else {
            return false
        }
        return accessed <= cutoff && attributesChanged <= cutoff
    }
}
