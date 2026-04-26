import AppKit
import SwiftUI
import AutoCleanMacCore
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let openSettingsNotification = Notification.Name("com.micz.autocleanmac.openSettings")
    private static let runCleanupNotification = Notification.Name("com.micz.autocleanmac.runCleanup")

    private enum RunPresentation {
        case cleanup
        case preview
    }

    private enum LaunchContext {
        case launchAgent
        case manual

        init(arguments: [String]) {
            self = arguments.contains("--launch-agent") ? .launchAgent : .manual
        }
    }

    private var menuBar: MenuBarController?
    private var consoleWindow: ConsoleWindow?
    private var settingsWindow: NSWindow?
    private var settingsModel: SettingsModel?
    private var logger: Logger!
    private var reminderScheduler: ReminderScheduler?
    private var config: Config = .default
    private var statistics: AppStatistics = .empty
    private var launchAtLoginEnabled = false
    private var isRunning = false
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
            NSApp.terminate(nil)
            return
        }
        if Self.otherRunningInstance() != nil, launchContext == .launchAgent {
            DistributedNotificationCenter.default().postNotificationName(
                Self.runCleanupNotification,
                object: nil
            )
            NSApp.terminate(nil)
            return
        }

        do {
            logger = try Logger(directory: logsDir)
        } catch {
            NSLog("AutoCleanMac: failed to create logger at \(logsDir.path): \(error)")
            NSApp.terminate(nil)
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
        reminderScheduler = ReminderScheduler(logger: logger) { [weak self] in
            self?.runCleanup(source: "reminder_auto")
        }
        reminderScheduler?.update(with: config.reminder)
        
        if config.globalShortcutEnabled {
            GlobalShortcutManager.shared.register()
        }

        let menu = MenuBarController()
        menu.onRunNow        = { [weak self] in self?.runCleanup(source: "menu") }
        menu.onOpenSettings  = { [weak self] in self?.openSettings() }
        menu.onQuit          = { NSApp.terminate(nil) }
        menu.install()
        menuBar = menu

        switch launchContext {
        case .launchAgent:
            runCleanup(source: "launch_agent")
        case .manual:
            openSettings()
        }
    }

    private static func otherRunningInstance() -> NSRunningApplication? {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.first { app in
            app.bundleIdentifier == Bundle.main.bundleIdentifier && app.processIdentifier != currentPID
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
            switch effectiveConfig.deleteMode {
            case .trash:  return .trash
            case .live:   return .live
            case .dryRun: return .dryRun
            }
        }()
        let modeString: String
        switch mode {
        case .live:   modeString = "live"
        case .dryRun: modeString = "dry_run"
        case .trash:  modeString = "trash"
        }
        logger.log(event: "mode", fields: ["mode": modeString])
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
                model.finished = true
                window.fadeOutAndClose(holdMs: effectiveConfig.window.holdAfterMs, fadeOutMs: effectiveConfig.window.fadeOutMs) {
                    self.consoleWindow = nil
                    self.isRunning = false
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
            model.lines.append(.init(prefix: "•", text: "\(name)…"))
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
                model.lines.append(.init(prefix: "·", text: "\(name) — pominięte (\(result.skipReason ?? "disabled"))"))
            } else {
                let prefix = result.warnings.isEmpty ? "✓" : "⚠"
                let size = Self.formatBytes(result.bytesFreed)
                var line = "\(name)  \(size)  ·  \(result.itemsDeleted) plik."
                if !result.warnings.isEmpty { line += "  (ostrzeżeń: \(result.warnings.count))" }
                model.lines.append(.init(prefix: prefix, text: line))
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
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
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
        model.finished = false
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
                model.statusColor = .green
            case .live:
                model.statusBadge = "live"
                model.statusColor = .orange
            case .dryRun:
                model.statusBadge = "dry-run"
                model.statusColor = .blue
            }
        case .preview:
            model.title = "Preview Cleanup"
            model.subtitle = "Symulacja na aktualnych ustawieniach"
            model.statusBadge = "preview"
            model.statusColor = .blue
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

    private func openInDefaultEditor(_ url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let defaultJson = """
            {
              "retention_days": 7,
              "delete_mode": "trash",
              "reminder": { "interval_hours": 24, "mode": "remind" },
              "window": { "fade_in_ms": 800, "hold_after_ms": 3000, "fade_out_ms": 800 },
              "excluded_paths": [],
              "whitelisted_cache_apps": [],
              "tasks": {
                "user_caches": true,
                "system_temp": true,
                "trash": true,
                "ds_store": true,
                "user_logs": true,
                "dev_caches": true,
                "homebrew_cleanup": false,
                "downloads": false
              },
              "browsers": {}
            }
            """
            try? defaultJson.write(to: url, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(url)
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
                let deleter = SafeDeleter(mode: mode, logger: self.logger)
                let fileManager = FileManager.default
                var freed: Int64 = 0
                var succeeded = 0
                var failures: [UninstallFailure] = []

                for app in apps {
                    let appRoot = app.url.deletingLastPathComponent()
                    var appRemovedBytes: Int64 = 0
                    var appRemoved = false

                    do {
                        let metrics = try deleter.deleteMeasured(app.url, withinRoot: appRoot)
                        appRemovedBytes = metrics.bytesFreed
                        appRemoved = true
                    } catch {
                        let initialReason = (error as NSError).localizedDescription
                        self.logger.log(event: "uninstall_failed", fields: [
                            "app": app.name,
                            "path": app.url.path,
                            "reason": initialReason,
                        ])

                        let stillExists = fileManager.fileExists(atPath: app.url.path)
                        if stillExists, mode != .dryRun {
                            let measuredBytes = (try? SafeDeleter.recursiveMetrics(at: app.url).bytesFreed) ?? 0
                            let elevationResult = await self.attemptElevatedRemoval(
                                app: app,
                                mode: mode
                            )
                            switch elevationResult {
                            case .success(let usedFallback):
                                appRemovedBytes = measuredBytes
                                appRemoved = true
                                self.logger.log(event: "uninstall_elevated", fields: [
                                    "app": app.name,
                                    "path": app.url.path,
                                    "size": "\(measuredBytes)",
                                    "mode": "\(mode)",
                                    "fallback_to_admin_rm": "\(usedFallback)",
                                ])
                            case .cancelled:
                                failures.append(UninstallFailure(
                                    appName: app.name,
                                    reason: "Anulowano przez użytkownika."
                                ))
                            case .failed(let reason):
                                failures.append(UninstallFailure(appName: app.name, reason: reason))
                            }
                        } else {
                            failures.append(UninstallFailure(appName: app.name, reason: initialReason))
                        }
                    }

                    guard appRemoved else { continue }
                    freed += appRemovedBytes
                    succeeded += 1

                    let libRoot = home.appendingPathComponent("Library")
                    for leftover in app.leftoverPaths where fileManager.fileExists(atPath: leftover.path) {
                        do {
                            let metrics = try deleter.deleteMeasured(leftover, withinRoot: libRoot)
                            freed += metrics.bytesFreed
                        } catch {
                            self.logger.log(event: "uninstall_leftover_failed", fields: [
                                "app": app.name,
                                "path": leftover.path,
                                "reason": (error as NSError).localizedDescription,
                            ])
                        }
                    }
                }
                return UninstallOutcome(freedBytes: freed, succeeded: succeeded, failures: failures)
            }
        )
        let host = NSHostingController(rootView: SettingsView(model: model))
        let win = NSWindow(contentViewController: host)
        win.title = "AutoCleanMac — Preferencje"
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.isReleasedWhenClosed = false
        win.center()
        settingsModel = model
        settingsWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    fileprivate enum ElevatedRemovalResult {
        case success(usedFallback: Bool)
        case cancelled
        case failed(reason: String)
    }

    /// Próbuje usunąć element z elewacją uprawnień. W trybie .trash najpierw próbuje
    /// Findera (TCC/Automation), jeśli to zawiedzie z innego powodu niż anulowanie —
    /// fallback na admin rm. W trybie .live od razu admin rm.
    fileprivate func attemptElevatedRemoval(
        app: AppInfo,
        mode: SafeDeleter.Mode
    ) async -> ElevatedRemovalResult {
        let url = app.url
        let fileManager = FileManager.default

        if mode == .trash {
            do {
                try await MainActor.run {
                    try ElevatedUninstall.trashViaFinder(url)
                }
                if !fileManager.fileExists(atPath: url.path) {
                    return .success(usedFallback: false)
                }
            } catch ElevatedUninstallError.userCancelled {
                return .cancelled
            } catch {
                self.logger.log(event: "uninstall_finder_failed", fields: [
                    "app": app.name,
                    "reason": "\(error)",
                ])
            }
        }

        do {
            try await MainActor.run {
                try ElevatedUninstall.removeWithAdmin(url)
            }
        } catch ElevatedUninstallError.userCancelled {
            return .cancelled
        } catch let elevErr as ElevatedUninstallError {
            return .failed(reason: "\(elevErr)")
        } catch {
            return .failed(reason: (error as NSError).localizedDescription)
        }

        if fileManager.fileExists(atPath: url.path) {
            return .failed(reason: "Plik nadal istnieje po próbie usunięcia.")
        }
        return .success(usedFallback: mode == .trash)
    }
}
