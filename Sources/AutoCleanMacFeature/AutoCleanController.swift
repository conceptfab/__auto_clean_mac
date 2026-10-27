import AppKit
import SwiftUI
@preconcurrency import UserNotifications
import AutoCleanMacCore

/// Logika AutoCleanMac niezależna od powłoki aplikacji: wczytanie `Config`/`AppStatistics`,
/// uruchamianie cleanupu (okno konsoli + zapis statystyk), przypominacz i okno ustawień.
/// `AppDelegate` (samodzielna aplikacja) i hub korzystają z tego samego typu.
@MainActor
public final class AutoCleanController {
    public enum Phase: Equatable { case idle, running(progress: Double?), failed(String) }

    /// Identyfikatory okien (`NSWindow.identifier`): preferencje i konsola cleanupu.
    public nonisolated static let settingsWindowID = "autoclean.main"
    public nonisolated static let consoleWindowID = "autoclean.console"

    /// Co steruje przełącznikiem autostartu w zakładce Ogólne. Domyślnie LaunchAgent
    /// `com.micz.autocleanmac` (samodzielna aplikacja); hub podstawia własną opcję.
    public struct LaunchAtLoginOption {
        public var title: String
        public var footer: String
        public var isEnabled: @MainActor () -> Bool
        public var setEnabled: @MainActor (Bool) throws -> Void

        public init(
            title: String,
            footer: String,
            isEnabled: @escaping @MainActor () -> Bool,
            setEnabled: @escaping @MainActor (Bool) throws -> Void
        ) {
            self.title = title
            self.footer = footer
            self.isEnabled = isEnabled
            self.setEnabled = setEnabled
        }

        /// Dotychczasowe zachowanie: LaunchAgent z `--launch-agent`.
        public static var launchAgent: LaunchAtLoginOption {
            LaunchAtLoginOption(
                title: "Uruchamiaj przy logowaniu",
                footer: "To podstawowa opcja dla komputerów, które rzadko są restartowane. Steruje LaunchAgentem, więc AutoCleanMac może uruchamiać się po zalogowaniu i działać w tle.",
                isEnabled: { LaunchAgentManager.isEnabled() },
                setEnabled: { try LaunchAgentManager.setEnabled($0) }
            )
        }
    }

    enum RunPresentation {
        case cleanup
        case preview
    }

    public private(set) var phase: Phase = .idle {
        didSet { if phase != oldValue { onChange?() } }
    }
    public private(set) var config: Config
    public private(set) var statistics: AppStatistics
    public var onChange: (() -> Void)?

    /// Wywoływane po zakończeniu każdego uruchomienia (po zamknięciu okna konsoli).
    public var onCleanupFinished: ((CleanupEngine.Summary) -> Void)?
    /// Wywoływane po zapisaniu preferencji (np. żeby powłoka przerejestrowała skrót globalny).
    public var onConfigSaved: ((Config) -> Void)?
    /// Wywoływane po zamknięciu okna ustawień.
    public var onSettingsWindowClosed: (() -> Void)?
    /// Gdy `true`, cleanup zwalniający miejsce wysyła powiadomienie systemowe (uruchomienie w tle).
    public var postsBackgroundNotification = false
    /// Tytuł okna preferencji.
    public var settingsWindowTitle = "AutoCleanMac — Preferencje"
    /// `false` ukrywa w zakładce Ogólne przełącznik skrótu ⌘⇧C (hub go nie przenosi).
    public var showsGlobalShortcutOption = true

    /// `false`, gdy nie udało się utworzyć katalogu logów — cleanup nie wystartuje.
    public var isLoggerAvailable: Bool { logger != nil }

    private let home: URL
    private let configURL: URL
    private let statisticsURL: URL
    private let logsDir: URL
    private let logger: Logger?
    private let launchAtLogin: LaunchAtLoginOption

    private(set) var launchAtLoginEnabled: Bool
    private var isRunning = false
    private var consoleWindow: ConsoleWindow?
    private var reminderScheduler: ReminderScheduler?
    private var settingsWindow: NSWindow?
    private var settingsModel: SettingsModel?
    private var embeddedSettingsModel: SettingsModel?
    private var settingsCloseObserver: NSObjectProtocol?

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        launchAtLogin: LaunchAtLoginOption = .launchAgent
    ) {
        self.home = home
        self.launchAtLogin = launchAtLogin
        configURL = home.appendingPathComponent(".config/autoclean-mac/config.json")
        statisticsURL = home.appendingPathComponent(".config/autoclean-mac/statistics.json")
        logsDir = home.appendingPathComponent("Library/Logs/AutoCleanMac")

        let logger: Logger?
        do {
            logger = try Logger(directory: logsDir)
        } catch {
            NSLog("AutoCleanMac: failed to create logger at \(logsDir.path): \(error)")
            logger = nil
        }
        self.logger = logger

        config = Config.loadOrDefault(from: configURL) { warn in
            logger?.log(event: "config_warn", fields: ["msg": warn])
        }
        statistics = AppStatisticsStore.loadOrDefault(from: statisticsURL, logger: logger)
        launchAtLoginEnabled = launchAtLogin.isEnabled()
    }

    /// Zapis zdarzenia do logu aplikacji (dla powłoki, np. AppDelegate).
    public func log(event: String, fields: [String: String] = [:]) {
        logger?.log(event: event, fields: fields)
    }

    // MARK: - Cleanup

    /// Uruchamia cleanup na bieżącej konfiguracji (okno konsoli + zapis statystyk).
    /// Zwraca `false`, gdy inny cleanup już trwa albo logger jest niedostępny.
    @discardableResult
    public func runCleanup(source: String = "menu", showConsole: Bool = true) async -> Bool {
        await performRun(source: source, showConsole: showConsole)
    }

    @discardableResult
    func performRun(
        source: String,
        configOverride: Config? = nil,
        forcedMode: SafeDeleter.Mode? = nil,
        presentation: RunPresentation = .cleanup,
        showConsole: Bool = true
    ) async -> Bool {
        guard !isRunning else { return false }
        guard let logger else {
            phase = .failed("Nie udało się utworzyć katalogu logów: \(logsDir.path)")
            return false
        }
        isRunning = true
        phase = .running(progress: nil)
        logger.log(event: "start", fields: ["source": source])

        let effectiveConfig = configOverride ?? config
        let window = ConsoleWindow()
        if showConsole {
            window.showCentered(fadeInMs: effectiveConfig.window.fadeInMs)
            consoleWindow = window
        }

        let mode: SafeDeleter.Mode = {
            if let forcedMode { return forcedMode }
            if ProcessInfo.processInfo.environment["AUTOCLEANMAC_DRY_RUN"] != nil { return .dryRun }
            return effectiveConfig.deleteMode
        }()
        logger.log(event: "mode", fields: ["mode": mode.label])
        let deleter = SafeDeleter(mode: mode, logger: logger)
        let ctx = CleanupContext(
            retentionDays: effectiveConfig.retentionDays,
            deleter: deleter,
            logger: logger,
            excludedPaths: effectiveConfig.resolvedExcludedPathURLs()
        )
        let engine = CleanupEngine.makeDefault(config: effectiveConfig)
        let model = window.model
        Self.configure(
            model,
            presentation: presentation,
            mode: mode,
            totalTasks: engine.taskNames.count,
            statistics: statistics
        )

        let summary = await engine.run(context: ctx) { [weak self, model] event in
            await MainActor.run {
                self?.handle(event, on: model)
            }
        }

        if presentation == .cleanup {
            let updatedStatistics = statistics.recording(summary)
            statistics = updatedStatistics
            settingsModel?.statistics = updatedStatistics
            embeddedSettingsModel?.statistics = updatedStatistics
            model.lifetimeRuns = updatedStatistics.totalRuns
            model.lifetimeItemsDeleted = updatedStatistics.totalItemsDeleted
            model.lifetimeBytesFreed = updatedStatistics.totalBytesFreed
            do {
                try AppStatisticsStore.write(updatedStatistics, to: statisticsURL)
            } catch {
                logger.log(event: "statistics_save_failed", fields: ["error": "\(error)"])
            }

            if postsBackgroundNotification && summary.bytesFreed > 0 {
                sendBackgroundCleanupNotification(freed: summary.bytesFreed, items: summary.itemsDeleted)
            }
        }
        model.currentTask = nil
        model.subtitle = presentation == .preview
            ? "Podgląd zakończony"
            : "Cleanup zakończony"
        model.summary = Self.formatSummary(summary, presentation: presentation)

        if showConsole {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                window.fadeOutAndClose(
                    holdMs: effectiveConfig.window.holdAfterMs,
                    fadeOutMs: effectiveConfig.window.fadeOutMs
                ) {
                    continuation.resume()
                }
            }
            consoleWindow = nil
        }
        isRunning = false
        phase = .idle
        onCleanupFinished?(summary)
        return true
    }

    private func handle(_ event: CleanupEngine.Event, on model: ConsoleViewModel) {
        switch event {
        case .started:
            break
        case .taskStarted(let name):
            model.currentTask = name
            model.subtitle = "Wykonywanie kolejnych kroków"
            model.appendLine(.init(prefix: "•", text: "\(name)…"))
        case .taskFinished(let name, let result):
            model.completedTasks += 1
            model.warningsCount += result.warnings.count
            model.currentRunItemsDeleted += result.itemsDeleted
            model.currentRunBytesFreed += result.bytesFreed
            if let idx = model.lines.lastIndex(where: { $0.prefix == "•" && $0.text.hasPrefix(name) }) {
                model.lines.remove(at: idx)
            }
            if result.skipped {
                model.skippedCount += 1
                let reason = Self.localizedSkipReason(result.skipReason)
                model.appendLine(.init(prefix: "·", text: "\(name) — pominięte (\(reason))"))
            } else {
                let prefix = result.warnings.isEmpty ? "✓" : "⚠"
                let size = Self.formatBytes(result.bytesFreed)
                var line = "\(name)  \(size)  ·  \(result.itemsDeleted) plik."
                if !result.warnings.isEmpty { line += "  (ostrzeżeń: \(result.warnings.count))" }
                model.appendLine(.init(prefix: prefix, text: line))
            }
            if model.totalTasks > 0 {
                phase = .running(progress: model.progressValue)
            }
        case .summary:
            break
        }
    }

    private func sendBackgroundCleanupNotification(freed: Int64, items: Int) {
        let logger = self.logger
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Czyszczenie zakończone"
            content.body = "AutoCleanMac zwolnił w tle \(Self.formatBytes(freed)) (usunięto \(items) plików)."
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "autocleanmac.background.\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            center.add(request) { error in
                if let error {
                    logger?.log(event: "background_notification_failed", fields: ["error": "\(error)"])
                } else {
                    logger?.log(event: "background_notification_sent")
                }
            }
        }
    }

    nonisolated static func formatBytes(_ bytes: Int64) -> String {
        ByteFormatting.string(bytes)
    }

    static func localizedSkipReason(_ skipReason: String?) -> String {
        switch skipReason {
        case "full_disk_access_required":
            return "wymaga Full Disk Access"
        case "browser running":
            return "przeglądarka jest uruchomiona"
        case "no browser profile directories":
            return "brak katalogów profilu"
        case "disabled":
            return "wyłączone"
        default:
            return skipReason ?? "disabled"
        }
    }

    private static func configure(
        _ model: ConsoleViewModel,
        presentation: RunPresentation,
        mode: SafeDeleter.Mode,
        totalTasks: Int,
        statistics: AppStatistics
    ) {
        model.totalTasks = totalTasks
        model.completedTasks = 0
        model.currentRunItemsDeleted = 0
        model.currentRunBytesFreed = 0
        model.warningsCount = 0
        model.skippedCount = 0
        model.lines = []
        model.summary = nil
        model.lifetimeRuns = statistics.totalRuns
        model.lifetimeItemsDeleted = statistics.totalItemsDeleted
        model.lifetimeBytesFreed = statistics.totalBytesFreed

        switch presentation {
        case .cleanup:
            model.title = "Cleanup w toku"
            model.subtitle = "Przygotowywanie bezpiecznego czyszczenia"
            switch mode {
            case .trash:
                model.statusBadge = "trash"
            case .live:
                model.statusBadge = "live"
            case .dryRun:
                model.statusBadge = "dry-run"
            }
        case .preview:
            model.title = "Preview Cleanup"
            model.subtitle = "Symulacja na aktualnych ustawieniach"
            model.statusBadge = "preview"
        }
    }

    static func formatSummary(_ s: CleanupEngine.Summary, presentation: RunPresentation) -> String {
        let bytes = formatBytes(s.bytesFreed)
        let secs = String(format: "%.1f", Double(s.durationMs) / 1000.0)
        switch presentation {
        case .cleanup:
            return "Zwolniono: \(bytes) · \(s.itemsDeleted) plik. · \(secs)s"
        case .preview:
            return "Do usunięcia: \(bytes) · \(s.itemsDeleted) plik. · \(secs)s"
        }
    }

    // MARK: - Reminders

    /// Uruchamia przypominacz wg `config.reminder` (ponowne wywołanie odświeża harmonogram).
    public func startReminders() {
        guard let logger else { return }
        if reminderScheduler == nil {
            reminderScheduler = ReminderScheduler(logger: logger) { [weak self] in
                guard let self else { return }
                Task { await self.runCleanup(source: "reminder_auto") }
            }
        }
        reminderScheduler?.update(with: config.reminder)
    }

    public func stopReminders() {
        reminderScheduler?.stop()
        reminderScheduler = nil
    }

    // MARK: - Settings window

    /// Otwiera okno preferencji (albo przywołuje otwarte), opcjonalnie na wskazanej zakładce.
    public func openSettingsWindow(section: SettingsSection? = nil) {
        if let win = settingsWindow {
            if let section { settingsModel?.selectedSection = section }
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let model = makeSettingsModel()
        if let section { model.selectedSection = section }
        let host = NSHostingController(rootView: SettingsView(model: model))
        let win = NSWindow(contentViewController: host)
        win.identifier = NSUserInterfaceItemIdentifier(Self.settingsWindowID)
        win.title = settingsWindowTitle
        win.styleMask = [.titled, .closable, .miniaturizable]
        // The controller owns the window (`settingsWindow`, released in `releaseSettingsWindow`);
        // AppKit's own release on close on top of that is a double release under ARC.
        win.isReleasedWhenClosed = false
        win.animationBehavior = .none
        win.center()
        settingsModel = model
        settingsWindow = win
        settingsCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: win,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.releaseSettingsWindow()
            }
        }
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Okno preferencji jest otwarte.
    public var isSettingsWindowOpen: Bool { settingsWindow != nil }

    /// Zakładka otwartego okna preferencji (`nil`, gdy okno jest zamknięte).
    public var settingsSection: SettingsSection? { settingsModel?.selectedSection }

    public func closeSettingsWindow() {
        settingsWindow?.close()
    }

    /// Model ustawień podpięty pod ten kontroler (zapis, cleanup, deinstalator, sieroty).
    public func makeSettingsModel() -> SettingsModel {
        if let embeddedSettingsModel { return embeddedSettingsModel }
        launchAtLoginEnabled = launchAtLogin.isEnabled()
        let model = makeBareSettingsModel()
        model.launchAtLoginTitle = launchAtLogin.title
        model.launchAtLoginFooter = launchAtLogin.footer
        model.showsGlobalShortcutOption = showsGlobalShortcutOption
        return model
    }

    /// The hub's pages and the standalone tool window share a draft while embedded.
    public func makeSharedSettingsModel() -> SettingsModel {
        if let embeddedSettingsModel { return embeddedSettingsModel }
        let model = settingsModel ?? makeSettingsModel()
        embeddedSettingsModel = model
        return model
    }

    private func makeBareSettingsModel() -> SettingsModel {
        let home = self.home
        return SettingsModel(
            initial: config,
            statistics: statistics,
            launchAtLogin: launchAtLoginEnabled,
            homeDirectory: home,
            onApply: { [weak self] updated, launchAtLogin in
                Task { @MainActor in
                    self?.persistConfig(updated, launchAtLogin: launchAtLogin)
                }
            },
            onApplyRun: { [weak self] updated, launchAtLogin in
                Task { @MainActor in
                    guard let self else { return }
                    if self.persistConfig(updated, launchAtLogin: launchAtLogin) {
                        await self.performRun(source: "settings")
                    }
                }
            },
            onPreview: { [weak self] updated in
                Task { @MainActor in
                    await self?.performRun(
                        source: "preview",
                        configOverride: updated,
                        forcedMode: .dryRun,
                        presentation: .preview
                    )
                }
            },
            onOpenLogsFolder: { [weak self] in
                guard let self else { return }
                NSWorkspace.shared.open(self.logsDir)
            },
            onShowLastLog: { [weak self] in self?.openMostRecentLog() },
            onUninstall: { [weak self] apps, mode in
                guard let self, let logger = self.logger else {
                    return UninstallOutcome(freedBytes: 0, succeeded: 0, failures: [])
                }
                let launchServices = ShellLaunchServicesClient()
                let purger = AppPurger(
                    deleter: SafeDeleter(mode: mode, logger: logger),
                    prefsDaemon: ShellPreferencesDaemonClient(),
                    launchAgents: ShellLaunchAgentClient(),
                    terminator: ShellAppTerminator(),
                    loginItems: ShellLoginItemsClient(),
                    launchServices: launchServices,
                    elevatedRemove: { url in
                        try await ElevatedUninstall.remove(url, mode: mode)
                    },
                    excludedPaths: self.config.resolvedExcludedPathURLs(),
                    logger: logger
                )

                var freed: Int64 = 0
                var succeeded = 0
                var failures: [UninstallFailure] = []
                for app in apps {
                    let outcome = await purger.purge(
                        bundleID: app.bundleIdentifier,
                        displayName: app.name,
                        appURL: app.url,
                        homeDirectory: home,
                        includeSystemPaths: app.url.path.hasPrefix("/Applications/")
                    )
                    if outcome.appRemoved {
                        freed += outcome.bytesFreed
                        succeeded += 1
                    }
                    for f in outcome.failures {
                        failures.append(UninstallFailure(appName: app.name, reason: f.reason))
                    }
                }

                if mode != .dryRun, succeeded > 0 {
                    // Fire-and-forget: LaunchServices rebuild can take ~5–15s. The UI
                    // already shows the uninstall summary; we don't want to block on it.
                    Task.detached(priority: .utility) {
                        launchServices.rebuild()
                    }
                }

                return UninstallOutcome(freedBytes: freed, succeeded: succeeded, failures: failures)
            },
            onScanOrphans: {
                let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
                // `detached` is required: the enclosing closure is @MainActor-isolated, so a
                // plain `Task {}` would inherit that isolation and run this back on the main
                // thread, reintroducing the Settings-window freeze this fix removed.
                return await Task.detached(priority: .userInitiated) {
                    var installed = InstalledAppRegistry().installedBundleIDs(
                        searchRoots: InstalledAppRegistry.defaultSearchRoots(homeDirectory: home)
                    )
                    installed.formUnion(running)
                    return await OrphanScanner().scan(homeDirectory: home, installedBundleIDs: installed)
                }.value
            },
            onRemoveOrphans: { [weak self] groups, mode in
                guard let logger = self?.logger, let excluded = self?.config.resolvedExcludedPathURLs() else {
                    return UninstallOutcome(freedBytes: 0, succeeded: 0, failures: [])
                }
                // `detached` is required: the enclosing closure is @MainActor-isolated, so a
                // plain `Task {}` would inherit that isolation and run this back on the main
                // thread, reintroducing the Settings-window freeze this fix removed.
                return await Task.detached(priority: .userInitiated) {
                    let deleter = SafeDeleter(mode: mode, logger: logger)
                    let userLib = home.appendingPathComponent("Library")
                    var freed: Int64 = 0
                    var succeeded = 0
                    var failures: [UninstallFailure] = []
                    for group in groups {
                        var groupOk = true
                        for path in group.paths where FileManager.default.fileExists(atPath: path.url.path) {
                            do {
                                let metrics = try deleter.deleteMeasured(path.url, withinRoot: userLib, excluding: excluded)
                                freed += metrics.bytesFreed
                            } catch {
                                groupOk = false
                                failures.append(UninstallFailure(appName: group.bundleID, reason: (error as NSError).localizedDescription))
                            }
                        }
                        if groupOk { succeeded += 1 }
                    }
                    return UninstallOutcome(freedBytes: freed, succeeded: succeeded, failures: failures)
                }.value
            }
        )
    }

    @discardableResult
    func persistConfig(_ updated: Config, launchAtLogin: Bool) -> Bool {
        do {
            try ConfigWriter.write(updated, to: configURL)
            if launchAtLogin != launchAtLoginEnabled {
                try self.launchAtLogin.setEnabled(launchAtLogin)
                launchAtLoginEnabled = launchAtLogin
                logger?.log(event: "launch_at_login_changed", fields: [
                    "enabled": launchAtLogin ? "true" : "false",
                ])
            }
            config = updated
            reminderScheduler?.update(with: updated.reminder)
            onConfigSaved?(updated)
            onChange?()

            logger?.log(event: "config_saved", fields: ["source": "settings"])
            settingsWindow?.close()
            return true
        } catch {
            logger?.log(event: "config_save_failed", fields: ["error": "\(error)"])
            let alert = NSAlert()
            alert.messageText = "Nie udało się zapisać preferencji"
            alert.informativeText = "\(error)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            if let win = settingsWindow {
                alert.beginSheetModal(for: win, completionHandler: nil)
            } else {
                alert.runModal()
            }
            return false
        }
    }

    private func openMostRecentLog() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let newest = files
            .filter { $0.pathExtension == "log" }
            .sorted { (a, b) in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da > db
            }
            .first
        if let newest { NSWorkspace.shared.open(newest) }
    }

    private func releaseSettingsWindow() {
        if let token = settingsCloseObserver {
            NotificationCenter.default.removeObserver(token)
        }
        settingsCloseObserver = nil
        settingsWindow?.contentViewController = nil
        settingsModel = nil
        settingsWindow = nil
        onSettingsWindowClosed?()
    }
}
