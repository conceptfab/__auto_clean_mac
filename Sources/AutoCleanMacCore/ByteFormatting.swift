import Foundation

/// Single source of truth for human-readable byte sizes across the app.
public enum ByteFormatting {
    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter
    }()

    public static func string(_ bytes: Int64) -> String {
        formatter.string(fromByteCount: bytes)
    }
}
