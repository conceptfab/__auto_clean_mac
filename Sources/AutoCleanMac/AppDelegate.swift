import AppKit
import SwiftUI
import AutoCleanMacCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var consoleWindow: ConsoleWindow?
    private var settingsWindow: NSWindow?
    private var logger: Logger!
    private var config: Config = .default
    private var isRunning = false

    private let logsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/AutoCleanMac")
    private let configPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/autoclean-mac/config.json")

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            logger = try Logger(directory: logsDir)
        } catch {
            NSLog("AutoCleanMac: failed to create logger at \(logsDir.path): \(error)")
            NSApp.terminate(nil)
            return
        }
        config = Config.loadOrDefault(from: configPath) { warn in
            self.logger.log(event: "config_warn", fields: ["msg": warn])
        }

        let menu = MenuBarController()
        menu.onRunNow        = { [weak self] in self?.runCleanup(source: "menu") }
        menu.onOpenSettings  = { [weak self] in self?.openSettings() }
        menu.onQuit          = { NSApp.terminate(nil) }
        menu.install()
        menuBar = menu

        runCleanup(source: "login")
    }

    private func runCleanup(source: String) {
        guard !isRunning else { return }
        isRunning = true
        logger.log(event: "start", fields: ["source": source])

        let window = ConsoleWindow()
        window.showCentered(fadeInMs: config.window.fadeInMs)
        consoleWindow = window

        let mode: SafeDeleter.Mode = {
            if ProcessInfo.processInfo.environment["AUTOCLEANMAC_DRY_RUN"] != nil { return .dryRun }
            switch config.deleteMode {
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
        let ctx = CleanupContext(retentionDays: config.retentionDays, deleter: deleter, logger: logger)
        let engine = CleanupEngine.makeDefault(config: config)

        Task {
            let summary = await engine.run(context: ctx) { event in
                DispatchQueue.main.async { self.handle(event, on: window.model) }
            }
            await MainActor.run {
                window.model.summary = Self.formatSummary(summary)
                window.model.finished = true
                window.fadeOutAndClose(holdMs: self.config.window.holdAfterMs, fadeOutMs: self.config.window.fadeOutMs) {
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
            model.lines.append(.init(prefix: "•", text: "\(name)…"))
        case .taskFinished(let name, let result):
            if let idx = model.lines.lastIndex(where: { $0.prefix == "•" && $0.text.hasPrefix(name) }) {
                model.lines.remove(at: idx)
            }
            if result.skipped {
                model.lines.append(.init(prefix: "·", text: "\(name) — pominięte (\(result.skipReason ?? "disabled"))"))
            } else {
                let prefix = result.warnings.isEmpty ? "✓" : "⚠"
                let size = Self.formatBytes(result.bytesFreed)
                var line = "\(name)  \(size)"
                if !result.warnings.isEmpty { line += "  (ostrzeżeń: \(result.warnings.count))" }
                model.lines.append(.init(prefix: prefix, text: line))
            }
        case .summary:
            break
        }
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private static func formatSummary(_ s: CleanupEngine.Summary) -> String {
        let bytes = formatBytes(s.bytesFreed)
        let secs = String(format: "%.1f", Double(s.durationMs) / 1000.0)
        return "Zwolniono: \(bytes) · \(secs)s"
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
              "window": { "fade_in_ms": 800, "hold_after_ms": 3000, "fade_out_ms": 800 },
              "tasks": {
                "user_caches": true,
                "system_temp": true,
                "trash": true,
                "ds_store": true,
                "user_logs": true,
                "dev_caches": true,
                "downloads": false
              },
              "browsers": {}
            }
            """
            try? defaultJson.write(to: url, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(url)
    }

    private func persistConfig(_ updated: Config) {
        do {
            try ConfigWriter.write(updated, to: self.configPath)
            self.config = updated
            self.logger.log(event: "config_saved", fields: ["source": "settings"])
            self.settingsWindow?.close()
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
            homeDirectory: home,
            onApply:     { [weak self] updated in self?.persistConfig(updated) },
            onApplyRun:  { [weak self] updated in
                guard let self else { return }
                self.persistConfig(updated)
                self.runCleanup(source: "settings")
            },
            onOpenLogsFolder: { [weak self] in
                guard let self else { return }
                NSWorkspace.shared.open(self.logsDir)
            },
            onShowLastLog: { [weak self] in self?.openMostRecentLog() }
        )
        let host = NSHostingController(rootView: SettingsView(model: model))
        let win = NSWindow(contentViewController: host)
        win.title = "AutoCleanMac — Preferencje"
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.isReleasedWhenClosed = false
        win.center()
        settingsWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
