import AppKit
import XCTest
import AutoCleanMacCore
@testable import AutoCleanMacFeature

@MainActor
final class AutoCleanControllerTests: XCTestCase {
    private var home: URL!

    override func setUp() async throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("AutoCleanControllerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let home { try? FileManager.default.removeItem(at: home) }
    }

    private var configURL: URL { home.appendingPathComponent(".config/autoclean-mac/config.json") }
    private var statisticsURL: URL { home.appendingPathComponent(".config/autoclean-mac/statistics.json") }

    /// Konfiguracja, przy której cleanup niczego nie dotyka: wszystkie zadania wyłączone, dry-run.
    private func inertConfig() -> Config {
        var config = Config.default
        config.tasks = Config.Tasks(
            userCaches: false, systemTemp: false, trash: false, dsStore: false,
            userLogs: false, devCaches: false, homebrewCleanup: false,
            projectArtifacts: false, downloads: false
        )
        config.browsers = [:]
        config.deleteMode = .dryRun
        config.retentionDays = 3
        return config
    }

    func test_init_withEmptyHome_usesDefaultsAndCreatesLogsDirectory() {
        let controller = AutoCleanController(home: home)

        XCTAssertEqual(controller.phase, .idle)
        XCTAssertEqual(controller.config, .default)
        XCTAssertEqual(controller.statistics, .empty)
        XCTAssertTrue(controller.isLoggerAvailable)
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: home.appendingPathComponent("Library/Logs/AutoCleanMac").path,
            isDirectory: &isDir
        ))
        XCTAssertTrue(isDir.boolValue)
    }

    func test_init_loadsConfigAndStatisticsFromHome() throws {
        try ConfigWriter.write(inertConfig(), to: configURL)
        let stats = AppStatistics(
            totalRuns: 4, totalItemsDeleted: 40, totalBytesFreed: 4_000,
            lastCleanupAt: nil, recentRuns: []
        )
        try AppStatisticsStore.write(stats, to: statisticsURL)

        let controller = AutoCleanController(home: home)

        XCTAssertEqual(controller.config.retentionDays, 3)
        XCTAssertEqual(controller.config.deleteMode, .dryRun)
        XCTAssertFalse(controller.config.tasks.userCaches)
        XCTAssertEqual(controller.statistics.totalRuns, 4)
        XCTAssertEqual(controller.statistics.totalBytesFreed, 4_000)
    }

    func test_runCleanup_recordsAndPersistsStatistics_andReturnsToIdle() async throws {
        try ConfigWriter.write(inertConfig(), to: configURL)
        let controller = AutoCleanController(home: home)
        var finished: [CleanupEngine.Summary] = []
        var changes = 0
        controller.onCleanupFinished = { finished.append($0) }
        controller.onChange = { changes += 1 }

        let ran = await controller.runCleanup(source: "test", showConsole: false)

        XCTAssertTrue(ran)
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertEqual(controller.statistics.totalRuns, 1)
        XCTAssertEqual(finished.count, 1)
        XCTAssertEqual(finished.first?.bytesFreed, 0)
        XCTAssertGreaterThan(changes, 0)
        let persisted = AppStatisticsStore.loadOrDefault(from: statisticsURL)
        XCTAssertEqual(persisted.totalRuns, 1)
    }

    func test_previewRun_doesNotRecordStatistics() async throws {
        try ConfigWriter.write(inertConfig(), to: configURL)
        let controller = AutoCleanController(home: home)

        let ran = await controller.performRun(
            source: "preview",
            configOverride: inertConfig(),
            forcedMode: .dryRun,
            presentation: .preview,
            showConsole: false
        )

        XCTAssertTrue(ran)
        XCTAssertEqual(controller.statistics.totalRuns, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: statisticsURL.path))
    }

    func test_runCleanup_withoutLogger_failsWithoutRunning() async throws {
        // `Library` jako zwykły plik uniemożliwia utworzenie katalogu logów.
        try Data().write(to: home.appendingPathComponent("Library"))
        let controller = AutoCleanController(home: home)
        XCTAssertFalse(controller.isLoggerAvailable)

        let ran = await controller.runCleanup(showConsole: false)

        XCTAssertFalse(ran)
        guard case .failed = controller.phase else {
            return XCTFail("expected .failed, got \(controller.phase)")
        }
        XCTAssertEqual(controller.statistics.totalRuns, 0)
    }

    func test_persistConfig_writesConfigAndNotifies() throws {
        let controller = AutoCleanController(home: home)
        var saved: Config?
        controller.onConfigSaved = { saved = $0 }
        var updated = inertConfig()
        updated.globalShortcutEnabled = true

        // Bez zmiany launch-at-login: nie dotykamy LaunchAgents w prawdziwym katalogu domowym.
        XCTAssertTrue(controller.persistConfig(updated, launchAtLogin: controller.launchAtLoginEnabled))

        XCTAssertEqual(controller.config, updated)
        XCTAssertEqual(saved, updated)
        let reloaded = Config.loadOrDefault(from: configURL) { _ in }
        XCTAssertEqual(reloaded.retentionDays, 3)
        XCTAssertTrue(reloaded.globalShortcutEnabled)
    }

    func test_makeSettingsModel_reflectsControllerState() throws {
        try ConfigWriter.write(inertConfig(), to: configURL)
        let controller = AutoCleanController(home: home)

        let model = controller.makeSettingsModel()

        XCTAssertEqual(model.currentConfig(), controller.config)
        XCTAssertEqual(model.statistics, controller.statistics)
        XCTAssertEqual(model.homeDirectory, home)
    }

    func test_settingsSection_hasElevenTabsAndParsesKeys() {
        XCTAssertEqual(SettingsSection.allCases.count, 11)
        XCTAssertEqual(SettingsSection(key: "uninstaller"), .uninstaller)
        XCTAssertEqual(SettingsSection(key: "Reminders"), .reminders)
        XCTAssertNil(SettingsSection(key: "nope"))
    }

    func test_openSettingsWindow_onSection_selectsThatTab() throws {
        _ = NSApplication.shared   // `swift test` nie tworzy NSApp
        try ConfigWriter.write(inertConfig(), to: configURL)
        let controller = AutoCleanController(home: home, launchAtLogin: fakeLaunchAtLogin())
        defer { controller.closeSettingsWindow() }

        controller.openSettingsWindow(section: .uninstaller)
        XCTAssertTrue(controller.isSettingsWindowOpen)
        XCTAssertEqual(controller.settingsSection, .uninstaller)
        let window = NSApp.windows.first { $0.identifier?.rawValue == AutoCleanController.settingsWindowID }
        XCTAssertNotNil(window)

        // Ponowne otwarcie przełącza zakładkę w już otwartym oknie.
        controller.openSettingsWindow(section: .reminders)
        XCTAssertEqual(controller.settingsSection, .reminders)
        controller.openSettingsWindow()
        XCTAssertEqual(controller.settingsSection, .reminders)
    }

    func test_launchAtLoginOption_isInjectedIntoModelAndPersist() throws {
        var stored = false
        var calls: [Bool] = []
        let option = AutoCleanController.LaunchAtLoginOption(
            title: "Sprzątaj po zalogowaniu",
            footer: "hub",
            isEnabled: { stored },
            setEnabled: { stored = $0; calls.append($0) }
        )
        let controller = AutoCleanController(home: home, launchAtLogin: option)
        controller.showsGlobalShortcutOption = false

        let model = controller.makeSettingsModel()
        XCTAssertEqual(model.launchAtLoginTitle, "Sprzątaj po zalogowaniu")
        XCTAssertFalse(model.launchAtLogin)
        XCTAssertFalse(model.showsGlobalShortcutOption)

        XCTAssertTrue(controller.persistConfig(inertConfig(), launchAtLogin: true))
        XCTAssertEqual(calls, [true])
        XCTAssertTrue(controller.makeSettingsModel().launchAtLogin)
    }

    private func fakeLaunchAtLogin() -> AutoCleanController.LaunchAtLoginOption {
        AutoCleanController.LaunchAtLoginOption(title: "t", footer: "f", isEnabled: { false }, setEnabled: { _ in })
    }

    func test_adminRemoveScript_usesSystemAdminPromptNotSudo() {
        let script = ElevatedUninstall.adminRemoveScript(for: URL(fileURLWithPath: "/Applications/Some \"App\".app"))
        XCTAssertTrue(script.hasSuffix("with administrator privileges"))
        XCTAssertFalse(script.contains("sudo"))
        XCTAssertTrue(script.contains("quoted form of \"/Applications/Some \\\"App\\\".app\""))
    }
}
