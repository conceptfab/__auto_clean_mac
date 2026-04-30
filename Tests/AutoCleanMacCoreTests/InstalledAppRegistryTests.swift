import XCTest
@testable import AutoCleanMacCore

final class InstalledAppRegistryTests: XCTestCase {
    func test_collects_bundle_ids_from_app_directories() throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Registry-\(UUID().uuidString)")
        let dirA = temp.appendingPathComponent("Applications")
        let dirB = temp.appendingPathComponent("UserApps")
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        try makeAppBundle(at: dirA.appendingPathComponent("Foo.app"), bundleID: "com.example.foo")
        try makeAppBundle(at: dirB.appendingPathComponent("Bar.app"), bundleID: "com.example.bar")
        defer { try? FileManager.default.removeItem(at: temp) }

        let registry = InstalledAppRegistry()
        let ids = registry.installedBundleIDs(searchRoots: [dirA, dirB])
        XCTAssertEqual(ids, ["com.example.foo", "com.example.bar"])
    }

    private func makeAppBundle(at url: URL, bundleID: String) throws {
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleName": url.deletingPathExtension().lastPathComponent]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }
}
