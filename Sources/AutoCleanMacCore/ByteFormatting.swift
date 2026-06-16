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
        // ByteCountFormatter renders 0 as the English "Zero KB", which reads wrong in the
        // app's Polish UI. Use a language-neutral "0 KB" for non-positive sizes.
        guard bytes > 0 else { return "0 KB" }
        return formatter.string(fromByteCount: bytes)
    }
}
