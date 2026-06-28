import AppKit
import SwiftUI
import AutoCleanMacCore
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private static let openSettingsNotification = Notification.Name("com.micz.autocleanmac.openSettings")
    private static let runCleanupNotification = Notification.Name("com.micz.autocleanmac.runCleanup")

    private enum RunPresentation {
        case cleanup
        case preview
    }

    private enum LaunchContext {
        case launchAgent
        case manual
        case settingsOnly
        case cleanupOnly

        init(arguments: [String]) {
            if arguments.contains("--settings") {
                self = .settingsOnly
            } else if arguments.contains("--run-cleanup") {
                self = .cleanupOnly
            } else if arguments.contains("--launch-agent") {
                self = .launchAgent
            } else {
                self = .manual
            }
        }

        var isTransient: Bool {
            switch self {
            case .settingsOnly, .cleanupOnly, .launchAgent:
                return true
            case .manual:
                return false
            }
        }
    }

    private var menuBar: MenuBarController?
    private var consoleWindow: ConsoleWindow?
    private var settingsWindow: NSWindow?
    private var settingsModel: SettingsModel?
    private var settingsCloseObserver: NSObjectProtocol?
    private var logger: Logger!
    private var reminderScheduler: ReminderScheduler?
    private var config: Config = .default
    private var statistics: AppStatistics = .empty
    private var launchAtLoginEnabled = false
    private var isRunning = false
    private var terminationRequested = false
    private let launchContext = LaunchContext(arguments: ProcessInfo.processInfo.arguments)

    private let logsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/AutoCleanMac")
    private let configPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/autoclean-mac/config.json")
    private let statisticsPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/autoclean-mac/statistics.json")

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let existingApp = Self.otherRunningInstance(), launchContext == .manual {
            DistributedNotificationCenter.default().postNotificationName(
                Self.openSettingsNotification,
                object: nil
            )
            existingApp.activate(options: [.activateIgnoringOtherApps])
            terminateApplication()
            return
        }
        if Self.otherRunningInstance() != nil, launchContext == .launchAgent {
            DistributedNotificationCenter.default().postNotificationName(
                Self.runCleanupNotification,
                object: nil
            )
            terminateApplication()
            return
        }

        do {
            logger = try Logger(directory: logsDir)
        } catch {
            NSLog("AutoCleanMac: failed to create logger at \(logsDir.path): \(error)")
            terminateApplication()
            return
        }

        let distributedCenter = DistributedNotificationCenter.default()
        distributedCenter.addObserver(
            self,
            selector: #selector(handleOpenSettingsRequest),
            name: Self.openSettingsNotification,
            object: nil
        )
        distributedCenter.addObserver(
            self,
            selector: #selector(handleRunCleanupRequest),
            name: Self.runCleanupNotification,
            object: nil
        )

        config = Config.loadOrDefault(from: configPath) { warn in
            self.logger.log(event: "config_warn", fields: ["msg": warn])
        }
        statistics = AppStatisticsStore.loadOrDefault(from: statisticsPath, logger: logger)
        launchAtLoginEnabled = LaunchAgentManager.isEnabled()
        if launchContext == .manual {
            reminderScheduler = ReminderScheduler(logger: logger) { [weak self] in
                self?.runCleanup(source: "reminder_auto")
            }
            reminderScheduler?.update(with: config.reminder)

            if config.globalShortcutEnabled {
                GlobalShortcutManager.shared.register()
            }
        }

        if launchContext == .manual {
            let menu = MenuBarController()
            menu.onRunNow        = { [weak self] in self?.runCleanup(source: "menu") }
            menu.onOpenSettings  = { [weak self] in self?.openSettings() }
            menu.onQuit          = { [weak self] in self?.terminateApplication() }
            menu.install()
            menuBar = menu
        }

        switch launchContext {
        case .launchAgent:
            runCleanup(source: "launch_agent")
        case .manual:
            openSettings()
        case .settingsOnly:
            openSettings()
        case .cleanupOnly:
            runCleanup(source: "menu")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        launchContext.isTransient
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminationRequested {
            return .terminateNow
        }
        logger?.log(event: "termination_cancelled", fields: ["reason": "unexpected_request"])
        return .terminateCancel
    }

    private func terminateApplication() {
        terminationRequested = true
        NSApp.terminate(nil)
    }

    private static func otherRunningInstance() -> NSRunningApplication? {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let uiExecutableNames: Set<String> = ["AutoCleanMacUI"]
        return NSWorkspace.shared.runningApplications.first { app in
            guard app.bundleIdentifier == Bundle.main.bundleIdentifier,
                  app.processIdentifier != currentPID,
                  let executableName = app.executableURL?.lastPathComponent
            else {
                return false
            }
            return uiExecutableNames.contains(executableName)
        }
    }

    @objc private func handleOpenSettingsRequest(_ notification: Notification) {
        openSettings()
    }

    @objc private func handleRunCleanupRequest(_ notification: Notification) {
        runCleanup(source: "launch_agent")
    }

    private func runCleanup(
        source: String,
        configOverride: Config? = nil,
        forcedMode: SafeDeleter.Mode? = nil,
        presentation: RunPresentation = .cleanup
    ) {
        guard !isRunning else { return }
        isRunning = true
        logger.log(event: "start", fields: ["source": source])

        let effectiveConfig = configOverride ?? config
        let window = ConsoleWindow()
        window.showCentered(fadeInMs: effectiveConfig.window.fadeInMs)
        consoleWindow = window

        let mode: SafeDeleter.Mode = {
            if let forcedMode { return forcedMode }
            if ProcessInfo.processInfo.environment["AUTOCLEANMAC_DRY_RUN"] != nil { return .dryRun }
            return effectiveConfig.deleteMode.safeDeleterMode
        }()
        logger.log(event: "mode", fields: ["mode": mode.label])
        let deleter = SafeDeleter(mode: mode, logger: logger)
        let ctx = CleanupContext(
            retentionDays: effectiveConfig.retentionDays,
            deleter: deleter,
            deletionMode: mode,
            logger: logger,
            excludedPaths: effectiveConfig.resolvedExcludedPathURLs()
        )
        let engine = CleanupEngine.makeDefault(config: effectiveConfig)
        let model = window.model
        let delegate = self
        configure(
            model,
            presentation: presentation,
            mode: mode,
            totalTasks: engine.taskNames.count,
            statistics: statistics
        )

        Task {
            let summary = await engine.run(context: ctx) { [delegate, model] event in
                await MainActor.run {
                    delegate.handle(event, on: model)
                }
            }
            await MainActor.run {
                if presentation == .cleanup {
                    let updatedStatistics = self.statistics.recording(summary)
                    self.statistics = updatedStatistics
                    self.settingsModel?.statistics = updatedStatistics
                    model.lifetimeRuns = updatedStatistics.totalRuns
                    model.lifetimeItemsDeleted = updatedStatistics.totalItemsDeleted
                    model.lifetimeBytesFreed = updatedStatistics.totalBytesFreed
                    do {
                        try AppStatisticsStore.write(updatedStatistics, to: self.statisticsPath)
                    } catch {
                        self.logger.log(event: "statistics_save_failed", fields: ["error": "\(error)"])
                    }
                    
                    if self.launchContext == .launchAgent && summary.bytesFreed > 0 {
                        self.sendBackgroundCleanupNotification(freed: summary.bytesFreed, items: summary.itemsDeleted)
                    }
                }
                model.currentTask = nil
                model.subtitle = presentation == .preview
                    ? "Podgląd zakończony"
                    : "Cleanup zakończony"
                model.summary = Self.formatSummary(summary, presentation: presentation)
                window.fadeOutAndClose(holdMs: effectiveConfig.window.holdAfterMs, fadeOutMs: effectiveConfig.window.fadeOutMs) {
                    self.consoleWindow = nil
                    self.isRunning = false
                    if self.launchContext.isTransient {
                        self.terminateApplication()
                    }
                }
            }
        }
    }

    @MainActor
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
        case .summary:
            break
        }
    }

    private func sendBackgroundCleanupNotification(freed: Int64, items: Int) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
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
                    self?.logger.log(event: "background_notification_failed", fields: ["error": "\(error)"])
                } else {
                    self?.logger.log(event: "background_notification_sent")
                }
            }
        }
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        ByteFormatting.string(bytes)
    }

    private static func localizedSkipReason(_ skipReason: String?) -> String {
        switch skipReason {
        case "full_disk_access_required":
            return "wymaga Full Disk Access"
        case "browser running":
            return "przeglądarka ma otwarte okna"
        case "no browser profile directories":
            return "brak katalogów profilu"
        case "disabled":
            return "wyłączone"
        default:
            return skipReason ?? "disabled"
        }
    }

    private func configure(
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

    private static func formatSummary(_ s: CleanupEngine.Summary, presentation: RunPresentation) -> String {
        let bytes = formatBytes(s.bytesFreed)
        let secs = String(format: "%.1f", Double(s.durationMs) / 1000.0)
        switch presentation {
        case .cleanup:
            return "Zwolniono: \(bytes) · \(s.itemsDeleted) plik. · \(secs)s"
        case .preview:
            return "Do usunięcia: \(bytes) · \(s.itemsDeleted) plik. · \(secs)s"
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

    @MainActor
    @discardableResult
    private func persistConfig(_ updated: Config, launchAtLogin: Bool) -> Bool {
        do {
            try ConfigWriter.write(updated, to: self.configPath)
            if launchAtLogin != launchAtLoginEnabled {
                try LaunchAgentManager.setEnabled(launchAtLogin)
                launchAtLoginEnabled = launchAtLogin
                self.logger.log(event: "launch_at_login_changed", fields: [
                    "enabled": launchAtLogin ? "true" : "false",
                ])
            }
            self.config = updated
            reminderScheduler?.update(with: updated.reminder)
            
            if updated.globalShortcutEnabled {
                GlobalShortcutManager.shared.register()
            } else {
                GlobalShortcutManager.shared.unregister()
            }
            
            self.logger.log(event: "config_saved", fields: ["source": "settings"])
            self.settingsWindow?.close()
            return true
        } catch {
            self.logger.log(event: "config_save_failed", fields: ["error": "\(error)"])
            let alert = NSAlert()
            alert.messageText = "Nie udało się zapisać preferencji"
            alert.informativeText = "\(error)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            if let win = self.settingsWindow {
                alert.beginSheetModal(for: win, completionHandler: nil)
            } else {
                alert.runModal()
            }
            return false
        }
    }

    private func openSettings() {
        if let win = settingsWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let model = SettingsModel(
            initial: config,
            statistics: statistics,
            launchAtLogin: launchAtLoginEnabled,
            homeDirectory: home,
            onApply:     { [weak self] updated, launchAtLogin in
                Task { @MainActor in
                    self?.persistConfig(updated, launchAtLogin: launchAtLogin)
                }
            },
            onApplyRun:  { [weak self] updated, launchAtLogin in
                Task { @MainActor in
                    guard let self else { return }
                    if self.persistConfig(updated, launchAtLogin: launchAtLogin) {
                        self.runCleanup(source: "settings")
                    }
                }
            },
            onPreview: { [weak self] updated in
                self?.runCleanup(
                    source: "preview",
                    configOverride: updated,
                    forcedMode: .dryRun,
                    presentation: .preview
                )
            },
            onOpenLogsFolder: { [weak self] in
                guard let self else { return }
                NSWorkspace.shared.open(self.logsDir)
            },
            onShowLastLog: { [weak self] in self?.openMostRecentLog() },
            onUninstall: { [weak self] apps, mode in
                guard let self else {
                    return UninstallOutcome(freedBytes: 0, succeeded: 0, failures: [])
                }
                let launchServices = ShellLaunchServicesClient()
                let purger = AppPurger(
                    deleter: SafeDeleter(mode: mode, logger: self.logger),
                    prefsDaemon: ShellPreferencesDaemonClient(),
                    launchAgents: ShellLaunchAgentClient(),
                    terminator: ShellAppTerminator(),
                    loginItems: ShellLoginItemsClient(),
                    launchServices: launchServices,
                    elevatedRemove: { url in
                        try await MainActor.run {
                            if mode == .trash {
                                do {
                                    try ElevatedUninstall.trashViaFinder(url)
                                    if !FileManager.default.fileExists(atPath: url.path) { return }
                                } catch ElevatedUninstallError.userCancelled {
                                    throw ElevatedUninstallError.userCancelled
                                } catch {
                                    // fallback to admin rm
                                }
                            }
                            try ElevatedUninstall.removeWithAdmin(url)
                        }
                    },
                    logger: self.logger
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
                guard let self else { return UninstallOutcome(freedBytes: 0, succeeded: 0, failures: []) }
                let logger: Logger = self.logger
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
                                let metrics = try deleter.deleteMeasured(path.url, withinRoot: userLib)
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
        let host = NSHostingController(rootView: SettingsView(model: model))
        let win = NSWindow(contentViewController: host)
        win.title = "AutoCleanMac — Preferencje"
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.isReleasedWhenClosed = true
        win.animationBehavior = .none
        win.delegate = self
        win.center()
        settingsModel = model
        settingsWindow = win
        settingsCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: win,
            queue: .main
        ) { [weak self] _ in
            self?.releaseSettingsWindow()
        }
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func releaseSettingsWindow() {
        if let token = settingsCloseObserver {
            NotificationCenter.default.removeObserver(token)
        }
        settingsCloseObserver = nil
        settingsWindow?.delegate = nil
        settingsWindow?.contentViewController = nil
        settingsModel = nil
        settingsWindow = nil
        if launchContext == .settingsOnly {
            terminateApplication()
        }
    }

}
