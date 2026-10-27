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

final class SpyAppTerminator: AppTerminator, @unchecked Sendable {
    var calls: [String] = []
    func terminate(bundleID: String) async -> Bool {
        calls.append(bundleID)
        return true
    }
}

final class SpyLoginItemsClient: LoginItemsClient, @unchecked Sendable {
    struct Call: Equatable { let appName: String?; let bundleID: String }
    var calls: [Call] = []
    func removeLoginItem(appName: String?, bundleID: String) {
        calls.append(Call(appName: appName, bundleID: bundleID))
    }
}

final class SpyLaunchServicesClient: LaunchServicesClient, @unchecked Sendable {
    var unregisterCalls: [URL] = []
    var rebuildCalls: Int = 0
    func unregister(app: URL) {
        unregisterCalls.append(app)
    }
    func rebuild() {
        rebuildCalls += 1
    }
}

final class AppPurgerTests: XCTestCase {
    func test_shell_launch_agent_client_reports_failed_bootout() throws {
        // Nieistniejący plist — `launchctl bootout` kończy się błędem i niczego nie wyładowuje.
        let temp = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(at: temp) }
        let missing = temp.appendingPathComponent("com.example.missing.plist")
        XCTAssertFalse(ShellLaunchAgentClient().unload(plist: missing, domain: .userGUI(uid: getuid())))
    }

    func test_cancelled_app_removal_preserves_user_and_system_data() async throws {
        try XCTSkipIf(getuid() == 0, "root bypasses directory permissions")
        let fm = FileManager.default
        let temp = try Fixtures.makeTempDir()
        defer { try? fm.removeItem(at: temp) }
        let app = temp.appendingPathComponent("Applications/Locked.app")
        try fm.createDirectory(at: app, withIntermediateDirectories: true)
        let paths = [
            "Library/Preferences/com.example.Locked.plist",
            "Library/Application Support/com.example.Locked/data",
            "Library/LaunchAgents/com.example.Locked.worker.plist",
            "system/Library/LaunchDaemons/com.example.Locked.worker.plist"
        ].map { temp.appendingPathComponent($0) }
        for path in paths { try Fixtures.makeFile(at: path, size: 100) }
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: app.deletingLastPathComponent().path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: app.deletingLastPathComponent().path) }
        let logger = try Logger(directory: temp.appendingPathComponent("logs"))
        let prefs = SpyPreferencesDaemon()
        let agents = SpyLaunchAgentClient()
        let loginItems = SpyLoginItemsClient()
        let elevated = expectation(description: "Administrator removal was cancelled")
        elevated.assertForOverFulfill = true
        let outcome = await AppPurger(
            deleter: SafeDeleter(mode: .live, logger: logger), prefsDaemon: prefs,
            launchAgents: agents, terminator: SpyAppTerminator(), loginItems: loginItems,
            launchServices: SpyLaunchServicesClient(), elevatedRemove: { _ in
                elevated.fulfill()
                throw NSError(domain: "UserCancelled", code: -128)
            }, logger: logger
        ).purge(bundleID: "com.example.Locked", displayName: nil, appURL: app,
                homeDirectory: temp, systemRoot: temp.appendingPathComponent("system"), includeSystemPaths: true)

        await fulfillment(of: [elevated], timeout: 1)
        XCTAssertFalse(outcome.appRemoved)
        XCTAssertFalse(outcome.failures.isEmpty)
        XCTAssertTrue(fm.fileExists(atPath: app.path))
        for path in paths { XCTAssertTrue(fm.fileExists(atPath: path.path), path.path) }
        XCTAssertTrue(prefs.calls.isEmpty)
        XCTAssertTrue(agents.calls.isEmpty)
        XCTAssertTrue(loginItems.calls.isEmpty, "Login Item usunięty mimo anulowania")
    }

    func test_purge_keeps_excluded_userside_leftover() async throws {
        let fm = FileManager.default
        let temp = try Fixtures.makeTempDir()
        defer { try? fm.removeItem(at: temp) }
        let app = temp.appendingPathComponent("Applications/Tiny.app")
        try fm.createDirectory(at: app, withIntermediateDirectories: true)
        let excluded = temp.appendingPathComponent("Library/Application Support/com.example.Tiny/keep.db")
        let removable = temp.appendingPathComponent("Library/Preferences/com.example.Tiny.plist")
        try Fixtures.makeFile(at: excluded, size: 10)
        try Fixtures.makeFile(at: removable, size: 10)
        let logger = try Logger(directory: temp.appendingPathComponent("logs"))
        let outcome = await AppPurger(
            deleter: SafeDeleter(mode: .live, logger: logger), prefsDaemon: SpyPreferencesDaemon(),
            launchAgents: SpyLaunchAgentClient(), terminator: SpyAppTerminator(), loginItems: SpyLoginItemsClient(),
            launchServices: SpyLaunchServicesClient(), elevatedRemove: { _ in XCTFail("unexpected elevation") },
            excludedPaths: [excluded], logger: logger
        ).purge(bundleID: "com.example.Tiny", displayName: nil, appURL: app,
                homeDirectory: temp, systemRoot: temp, includeSystemPaths: false)

        XCTAssertTrue(outcome.appRemoved)
        XCTAssertTrue(fm.fileExists(atPath: excluded.path), "wykluczony plik usunięty razem z katalogiem")
        XCTAssertFalse(fm.fileExists(atPath: removable.path))
    }

    func test_dryRun_preserves_loaded_user_and_system_services() async throws {
        let fm = FileManager.default
        let temp = try Fixtures.makeTempDir()
        defer { try? fm.removeItem(at: temp) }
        let app = temp.appendingPathComponent("Applications/Tiny.app")
        try fm.createDirectory(at: app, withIntermediateDirectories: true)
        let paths = ["Library/LaunchAgents/com.example.Tiny.worker.plist",
                     "system/Library/LaunchDaemons/com.example.Tiny.worker.plist",
                     "system/Library/LaunchAgents/com.example.Tiny.worker.plist"]
            .map { temp.appendingPathComponent($0) }
        for path in paths { try Fixtures.makeFile(at: path, size: 100) }
        let logger = try Logger(directory: temp.appendingPathComponent("logs"))
        let agents = SpyLaunchAgentClient()
        let outcome = await AppPurger(
            deleter: SafeDeleter(mode: .dryRun, logger: logger), prefsDaemon: SpyPreferencesDaemon(),
            launchAgents: agents, terminator: SpyAppTerminator(), loginItems: SpyLoginItemsClient(),
            launchServices: SpyLaunchServicesClient(), elevatedRemove: { _ in XCTFail("dry-run elevated") },
            logger: logger
        ).purge(bundleID: "com.example.Tiny", displayName: nil, appURL: app,
                homeDirectory: temp, systemRoot: temp.appendingPathComponent("system"), includeSystemPaths: true)

        XCTAssertTrue(outcome.failures.isEmpty)
        XCTAssertTrue(agents.calls.isEmpty)
        for path in paths { XCTAssertTrue(fm.fileExists(atPath: path.path)) }
    }

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
            terminator: SpyAppTerminator(),
            loginItems: SpyLoginItemsClient(),
            launchServices: SpyLaunchServicesClient(),
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

    func test_purge_falls_back_to_elevated_on_permission_error() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppPurger-\(UUID().uuidString)")
        let appURL = temp.appendingPathComponent("Applications/Locked.app")
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 50).write(to: appURL.appendingPathComponent("contents"))
        defer { try? FileManager.default.removeItem(at: temp) }

        let logger = try Logger(directory: temp.appendingPathComponent("logs"))
        // Symulujemy "live" mode — żeby nie usunąć w fazie measurement, blokujemy zapis na katalogu rodzica.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: appURL.deletingLastPathComponent().path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: appURL.deletingLastPathComponent().path) }

        var elevatedCalls: [URL] = []
        let purger = AppPurger(
            deleter: SafeDeleter(mode: .live, logger: logger),
            prefsDaemon: SpyPreferencesDaemon(),
            launchAgents: SpyLaunchAgentClient(),
            terminator: SpyAppTerminator(),
            loginItems: SpyLoginItemsClient(),
            launchServices: SpyLaunchServicesClient(),
            elevatedRemove: { url in
                elevatedCalls.append(url)
                // "Udajemy" sukces — usuwamy ręcznie po zdjęciu blokady chwilowo
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.deletingLastPathComponent().path)
                try FileManager.default.removeItem(at: url)
            },
            logger: logger
        )

        let outcome = await purger.purge(
            bundleID: "com.example.Locked",
            displayName: "Locked",
            appURL: appURL,
            homeDirectory: temp,
            systemRoot: temp,
            includeSystemPaths: false
        )

        XCTAssertEqual(elevatedCalls, [appURL])
        XCTAssertTrue(outcome.appRemoved)
        XCTAssertTrue(outcome.elevatedFallbackUsed)
        XCTAssertGreaterThan(outcome.bytesFreed, 0)
        XCTAssertGreaterThan(outcome.itemsDeleted, 0)  // elevated path must report freed items, not just bytes
    }

    func test_purge_calls_prefs_daemon_in_live_mode() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppPurger-\(UUID().uuidString)")
        let appURL = temp.appendingPathComponent("Applications/Tiny.app")
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let logger = try Logger(directory: temp.appendingPathComponent("logs"))
        let prefs = SpyPreferencesDaemon()
        _ = await AppPurger(
            deleter: SafeDeleter(mode: .live, logger: logger),
            prefsDaemon: prefs,
            launchAgents: SpyLaunchAgentClient(),
            terminator: SpyAppTerminator(),
            loginItems: SpyLoginItemsClient(),
            launchServices: SpyLaunchServicesClient(),
            elevatedRemove: { _ in },
            logger: logger
        ).purge(
            bundleID: "com.example.Tiny",
            displayName: nil,
            appURL: appURL,
            homeDirectory: temp,
            systemRoot: temp,
            includeSystemPaths: false
        )
        XCTAssertEqual(prefs.calls, ["com.example.Tiny"])
    }

    func test_purge_skips_prefs_daemon_in_dryRun() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppPurger-\(UUID().uuidString)")
        let appURL = temp.appendingPathComponent("Applications/Tiny.app")
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let logger = try Logger(directory: temp.appendingPathComponent("logs"))
        let prefs = SpyPreferencesDaemon()
        _ = await AppPurger(
            deleter: SafeDeleter(mode: .dryRun, logger: logger),
            prefsDaemon: prefs,
            launchAgents: SpyLaunchAgentClient(),
            terminator: SpyAppTerminator(),
            loginItems: SpyLoginItemsClient(),
            launchServices: SpyLaunchServicesClient(),
            elevatedRemove: { _ in },
            logger: logger
        ).purge(
            bundleID: "com.example.Tiny",
            displayName: nil,
            appURL: appURL,
            homeDirectory: temp,
            systemRoot: temp,
            includeSystemPaths: false
        )
        XCTAssertTrue(prefs.calls.isEmpty)
    }

    func test_purge_refuses_to_remove_protected_app() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppPurger-\(UUID().uuidString)")
        let appURL = temp.appendingPathComponent("Applications/Finder.app")
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 100).write(to: appURL.appendingPathComponent("contents"))
        defer { try? FileManager.default.removeItem(at: temp) }

        let logger = try Logger(directory: temp.appendingPathComponent("logs"))
        let prefs = SpyPreferencesDaemon()
        let purger = AppPurger(
            deleter: SafeDeleter(mode: .live, logger: logger),
            prefsDaemon: prefs,
            launchAgents: SpyLaunchAgentClient(),
            terminator: SpyAppTerminator(),
            loginItems: SpyLoginItemsClient(),
            launchServices: SpyLaunchServicesClient(),
            elevatedRemove: { _ in XCTFail("Protected app must not trigger elevation") },
            logger: logger
        )

        let outcome = await purger.purge(
            bundleID: "com.apple.finder",
            displayName: "Finder",
            appURL: appURL,
            homeDirectory: temp,
            systemRoot: temp,
            includeSystemPaths: false
        )

        XCTAssertFalse(outcome.appRemoved)
        XCTAssertEqual(outcome.bytesFreed, 0)
        XCTAssertEqual(outcome.itemsDeleted, 0)
        XCTAssertEqual(outcome.failures.count, 1)
        XCTAssertEqual(outcome.failures.first?.path, appURL.path)
        XCTAssertTrue(outcome.failures.first?.reason.contains("chroniona") == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: appURL.path))
        XCTAssertTrue(prefs.calls.isEmpty, "prefs daemon must not be called for protected apps")
    }

    func test_purge_invokes_terminator_before_deletion() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppPurger-\(UUID().uuidString)")
        let appURL = temp.appendingPathComponent("Applications/Tiny.app")
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let terminator = SpyAppTerminator()
        let logger = try Logger(directory: temp.appendingPathComponent("logs"))
        _ = await AppPurger(
            deleter: SafeDeleter(mode: .live, logger: logger),
            prefsDaemon: SpyPreferencesDaemon(),
            launchAgents: SpyLaunchAgentClient(),
            terminator: terminator,
            loginItems: SpyLoginItemsClient(),
            launchServices: SpyLaunchServicesClient(),
            elevatedRemove: { _ in },
            logger: logger
        ).purge(
            bundleID: "com.example.Tiny",
            displayName: "Tiny",
            appURL: appURL,
            homeDirectory: temp,
            systemRoot: temp,
            includeSystemPaths: false
        )

        XCTAssertEqual(terminator.calls, ["com.example.Tiny"])
    }

    func test_purge_dryRun_skips_terminator() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppPurger-\(UUID().uuidString)")
        let appURL = temp.appendingPathComponent("Applications/Tiny.app")
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let terminator = SpyAppTerminator()
        let logger = try Logger(directory: temp.appendingPathComponent("logs"))
        _ = await AppPurger(
            deleter: SafeDeleter(mode: .dryRun, logger: logger),
            prefsDaemon: SpyPreferencesDaemon(),
            launchAgents: SpyLaunchAgentClient(),
            terminator: terminator,
            loginItems: SpyLoginItemsClient(),
            launchServices: SpyLaunchServicesClient(),
            elevatedRemove: { _ in },
            logger: logger
        ).purge(
            bundleID: "com.example.Tiny",
            displayName: "Tiny",
            appURL: appURL,
            homeDirectory: temp,
            systemRoot: temp,
            includeSystemPaths: false
        )

        XCTAssertTrue(terminator.calls.isEmpty)
    }

    func test_purge_invokes_loginItems_removal_in_live_mode() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppPurger-\(UUID().uuidString)")
        let appURL = temp.appendingPathComponent("Applications/Tiny.app")
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let loginItems = SpyLoginItemsClient()
        let logger = try Logger(directory: temp.appendingPathComponent("logs"))
        _ = await AppPurger(
            deleter: SafeDeleter(mode: .live, logger: logger),
            prefsDaemon: SpyPreferencesDaemon(),
            launchAgents: SpyLaunchAgentClient(),
            terminator: SpyAppTerminator(),
            loginItems: loginItems,
            launchServices: SpyLaunchServicesClient(),
            elevatedRemove: { _ in },
            logger: logger
        ).purge(
            bundleID: "com.example.Tiny",
            displayName: "Tiny",
            appURL: appURL,
            homeDirectory: temp,
            systemRoot: temp,
            includeSystemPaths: false
        )

        XCTAssertEqual(loginItems.calls, [SpyLoginItemsClient.Call(appName: "Tiny", bundleID: "com.example.Tiny")])
    }

    func test_purge_dryRun_skips_loginItems() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppPurger-\(UUID().uuidString)")
        let appURL = temp.appendingPathComponent("Applications/Tiny.app")
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let loginItems = SpyLoginItemsClient()
        let logger = try Logger(directory: temp.appendingPathComponent("logs"))
        _ = await AppPurger(
            deleter: SafeDeleter(mode: .dryRun, logger: logger),
            prefsDaemon: SpyPreferencesDaemon(),
            launchAgents: SpyLaunchAgentClient(),
            terminator: SpyAppTerminator(),
            loginItems: loginItems,
            launchServices: SpyLaunchServicesClient(),
            elevatedRemove: { _ in },
            logger: logger
        ).purge(
            bundleID: "com.example.Tiny",
            displayName: nil,
            appURL: appURL,
            homeDirectory: temp,
            systemRoot: temp,
            includeSystemPaths: false
        )

        XCTAssertTrue(loginItems.calls.isEmpty)
    }

    func test_purge_unregisters_bundle_from_launchservices_in_live_mode() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppPurger-\(UUID().uuidString)")
        let appURL = temp.appendingPathComponent("Applications/Tiny.app")
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let launchServices = SpyLaunchServicesClient()
        let logger = try Logger(directory: temp.appendingPathComponent("logs"))
        _ = await AppPurger(
            deleter: SafeDeleter(mode: .live, logger: logger),
            prefsDaemon: SpyPreferencesDaemon(),
            launchAgents: SpyLaunchAgentClient(),
            terminator: SpyAppTerminator(),
            loginItems: SpyLoginItemsClient(),
            launchServices: launchServices,
            elevatedRemove: { _ in },
            logger: logger
        ).purge(
            bundleID: "com.example.Tiny",
            displayName: "Tiny",
            appURL: appURL,
            homeDirectory: temp,
            systemRoot: temp,
            includeSystemPaths: false
        )

        XCTAssertEqual(launchServices.unregisterCalls, [appURL])
        XCTAssertEqual(launchServices.rebuildCalls, 0, "AppPurger must not call rebuild — that is a batch-level concern")
    }

    func test_purge_dryRun_skips_launchservices_unregister() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppPurger-\(UUID().uuidString)")
        let appURL = temp.appendingPathComponent("Applications/Tiny.app")
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let launchServices = SpyLaunchServicesClient()
        let logger = try Logger(directory: temp.appendingPathComponent("logs"))
        _ = await AppPurger(
            deleter: SafeDeleter(mode: .dryRun, logger: logger),
            prefsDaemon: SpyPreferencesDaemon(),
            launchAgents: SpyLaunchAgentClient(),
            terminator: SpyAppTerminator(),
            loginItems: SpyLoginItemsClient(),
            launchServices: launchServices,
            elevatedRemove: { _ in },
            logger: logger
        ).purge(
            bundleID: "com.example.Tiny",
            displayName: nil,
            appURL: appURL,
            homeDirectory: temp,
            systemRoot: temp,
            includeSystemPaths: false
        )

        XCTAssertTrue(launchServices.unregisterCalls.isEmpty)
    }

    final class OrderRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var events: [String] = []
        func record(_ event: String) {
            lock.lock(); defer { lock.unlock() }
            events.append(event)
        }
        func snapshot() -> [String] {
            lock.lock(); defer { lock.unlock() }
            return events
        }
    }

    func test_purge_runs_pre_deletion_steps_in_correct_order() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppPurger-\(UUID().uuidString)")
        let appURL = temp.appendingPathComponent("Applications/Tiny.app")
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let recorder = OrderRecorder()

        final class RecordingTerminator: AppTerminator, @unchecked Sendable {
            let r: OrderRecorder
            init(_ r: OrderRecorder) { self.r = r }
            func terminate(bundleID: String) async -> Bool {
                r.record("terminate"); return true
            }
        }
        final class RecordingLoginItems: LoginItemsClient, @unchecked Sendable {
            let r: OrderRecorder
            let appURL: URL
            init(_ r: OrderRecorder, appURL: URL) { self.r = r; self.appURL = appURL }
            func removeLoginItem(appName: String?, bundleID: String) {
                // Login Item wolno zdjąć dopiero, gdy bundle już zniknął (po punkcie przerwania).
                r.record(FileManager.default.fileExists(atPath: appURL.path) ? "loginItems(app present)" : "loginItems")
            }
        }
        final class RecordingLaunchServices: LaunchServicesClient, @unchecked Sendable {
            let r: OrderRecorder
            init(_ r: OrderRecorder) { self.r = r }
            func unregister(app: URL) { r.record("unregister") }
            func rebuild() { r.record("rebuild") }
        }

        let logger = try Logger(directory: temp.appendingPathComponent("logs"))
        _ = await AppPurger(
            deleter: SafeDeleter(mode: .live, logger: logger),
            prefsDaemon: SpyPreferencesDaemon(),
            launchAgents: SpyLaunchAgentClient(),
            terminator: RecordingTerminator(recorder),
            loginItems: RecordingLoginItems(recorder, appURL: appURL),
            launchServices: RecordingLaunchServices(recorder),
            elevatedRemove: { _ in },
            logger: logger
        ).purge(
            bundleID: "com.example.Tiny",
            displayName: "Tiny",
            appURL: appURL,
            homeDirectory: temp,
            systemRoot: temp,
            includeSystemPaths: false
        )

        // The deleter itself is not on the recorder; `loginItems` records whether the
        // bundle was already gone, i.e. whether it ran after the abort point.
        let events = recorder.snapshot()
        XCTAssertEqual(events, ["terminate", "unregister", "loginItems"])
        XCTAssertFalse(events.contains("rebuild"), "rebuild() is a batch concern, not per-app")
    }

    func test_purge_never_elevates_system_path_that_escapes_allowed_root() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppPurger-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temp) }
        let appURL = temp.appendingPathComponent("Applications/Tiny.app")
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        let precious = temp.appendingPathComponent("precious")
        try FileManager.default.createDirectory(at: precious, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 10).write(to: precious.appendingPathComponent("data"))
        // `/Library/Application Support/Tiny` jako symlink wychodzący poza dozwolony katalog.
        let support = temp.appendingPathComponent("Library/Application Support")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: support.appendingPathComponent("Tiny"), withDestinationURL: precious)
        // Prawidłowy leftover systemowy — ten może iść do elewacji.
        let helper = temp.appendingPathComponent("Library/PrivilegedHelperTools/com.example.Tiny")
        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 10).write(to: helper)

        let logger = try Logger(directory: temp.appendingPathComponent("logs"))
        var elevatedCalls: [URL] = []
        let purger = AppPurger(
            deleter: SafeDeleter(mode: .live, logger: logger),
            prefsDaemon: SpyPreferencesDaemon(),
            launchAgents: SpyLaunchAgentClient(),
            terminator: SpyAppTerminator(),
            loginItems: SpyLoginItemsClient(),
            launchServices: SpyLaunchServicesClient(),
            elevatedRemove: { url in
                elevatedCalls.append(url)
                try FileManager.default.removeItem(at: url)
            },
            logger: logger
        )

        let outcome = await purger.purge(
            bundleID: "com.example.Tiny",
            displayName: "Tiny",
            appURL: appURL,
            homeDirectory: temp.appendingPathComponent("home"),
            systemRoot: temp,
            includeSystemPaths: true
        )

        XCTAssertEqual(elevatedCalls.map(\.lastPathComponent), ["com.example.Tiny"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: precious.appendingPathComponent("data").path))
        XCTAssertTrue(outcome.failures.contains { $0.path.hasSuffix("Application Support/Tiny") })
    }
}
