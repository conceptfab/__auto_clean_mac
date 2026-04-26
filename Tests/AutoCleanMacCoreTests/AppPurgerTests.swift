import XCTest
@testable import AutoCleanMacCore

final class SpyPreferencesDaemon: PreferencesDaemonClient, @unchecked Sendable {
    var calls: [String] = []
    func deleteAll(bundleID: String) -> Bool {
        calls.append(bundleID)
        return true
    }
}

final class SpyLaunchAgentClient: LaunchAgentClient, @unchecked Sendable {
    struct Call: Equatable { let plist: URL; let isSystem: Bool }
    var calls: [Call] = []
    func unload(plist: URL, domain: LaunchAgentDomain) -> Bool {
        calls.append(Call(plist: plist, isSystem: { if case .system = domain { return true } else { return false } }()))
        return true
    }
}

final class AppPurgerTests: XCTestCase {
    func test_purge_removes_app_and_userside_leftovers_in_dryRun() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppPurger-\(UUID().uuidString)")
        let appsDir = temp.appendingPathComponent("Applications")
        let appURL = appsDir.appendingPathComponent("MyApp.app")
        let lib = temp.appendingPathComponent("Library")
        let prefsURL = lib.appendingPathComponent("Preferences/com.example.MyApp.plist")
        let supportURL = lib.appendingPathComponent("Application Support/com.example.MyApp")
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: lib.appendingPathComponent("Preferences"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 100).write(to: prefsURL)
        defer { try? FileManager.default.removeItem(at: temp) }

        let logger = try Logger(directory: temp.appendingPathComponent("logs"))
        let purger = AppPurger(
            deleter: SafeDeleter(mode: .dryRun, logger: logger),
            prefsDaemon: SpyPreferencesDaemon(),
            launchAgents: SpyLaunchAgentClient(),
            elevatedRemove: { _ in XCTFail("Nie powinno być elewacji w dryRun") },
            logger: logger
        )

        let outcome = await purger.purge(
            bundleID: "com.example.MyApp",
            displayName: "MyApp",
            appURL: appURL,
            homeDirectory: temp,
            systemRoot: temp,
            includeSystemPaths: false
        )

        XCTAssertTrue(outcome.appRemoved)
        XCTAssertGreaterThan(outcome.bytesFreed, 0)
        XCTAssertTrue(outcome.failures.isEmpty)
        // dryRun nie usuwa fizycznie:
        XCTAssertTrue(FileManager.default.fileExists(atPath: appURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: prefsURL.path))
    }
}
