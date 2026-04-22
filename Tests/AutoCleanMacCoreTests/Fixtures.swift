import Foundation
import XCTest

enum Fixtures {
    static func makeTempDir() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("AutoCleanMacTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Creates a regular file at `url` with `size` bytes of 'x'. Sets mtime to `ageInDays` ago.
    static func makeFile(at url: URL, size: Int = 16, ageInDays: Int = 0) throws {
        let bytes = Data(repeating: 0x78, count: size)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: url)
        let mtime = Date().addingTimeInterval(TimeInterval(-ageInDays * 86_400))
        try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: url.path)
    }

    /// Creates a symlink at `linkAt` pointing to `target`.
    static func makeSymlink(at linkAt: URL, pointingTo target: URL) throws {
        try FileManager.default.createDirectory(at: linkAt.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linkAt, withDestinationURL: target)
    }
}
