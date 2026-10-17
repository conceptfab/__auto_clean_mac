import AppKit
import AutoCleanMacCore
import AutoCleanMacFeature

/// Cienka powłoka samodzielnej aplikacji: status item, argumenty CLI (`--run-cleanup`,
/// `--settings`, `--launch-agent`) i pojedyncza instancja. Logika jest w `AutoCleanController`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let openSettingsNotification = Notification.Name("com.micz.autocleanmac.openSettings")
    private static let runCleanupNotification = Notification.Name("com.micz.autocleanmac.runCleanup")

    enum LaunchContext: Equatable {
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
    private var controller: AutoCleanController?
    private var terminationRequested = false
    private let launchContext: LaunchContext

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        launchContext = LaunchContext(arguments: arguments)
        super.init()
    }

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

        let controller = AutoCleanController()
        guard controller.isLoggerAvailable else {
            terminateApplication()
            return
        }
        self.controller = controller
        controller.postsBackgroundNotification = launchContext == .launchAgent
        controller.onCleanupFinished = { [weak self] _ in
            guard let self, self.launchContext.isTransient else { return }
            self.terminateApplication()
        }
        controller.onSettingsWindowClosed = { [weak self] in
            guard let self, self.launchContext == .settingsOnly else { return }
            self.terminateApplication()
        }
        controller.onConfigSaved = { updated in
            if updated.globalShortcutEnabled {
                GlobalShortcutManager.shared.register()
            } else {
                GlobalShortcutManager.shared.unregister()
            }
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

        if launchContext == .manual {
            controller.startReminders()
            if controller.config.globalShortcutEnabled {
                GlobalShortcutManager.shared.register()
            }

            let menu = MenuBarController()
            menu.onRunNow        = { [weak self] in self?.runCleanup(source: "menu") }
            menu.onOpenSettings  = { [weak self] in self?.controller?.openSettingsWindow() }
            menu.onQuit          = { [weak self] in self?.terminateApplication() }
            menu.install()
            menuBar = menu
        }

        switch launchContext {
        case .launchAgent:
            runCleanup(source: "launch_agent")
        case .manual, .settingsOnly:
            controller.openSettingsWindow()
        case .cleanupOnly:
            runCleanup(source: "menu")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        launchContext.isTransient
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminationRequested {
            return .terminateNow
        }
        controller?.log(event: "termination_cancelled", fields: ["reason": "unexpected_request"])
        return .terminateCancel
    }

    private func runCleanup(source: String) {
        guard let controller else { return }
        Task { await controller.runCleanup(source: source) }
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

    @MainActor @objc private func handleOpenSettingsRequest(_ notification: Notification) {
        controller?.openSettingsWindow()
    }

    @MainActor @objc private func handleRunCleanupRequest(_ notification: Notification) {
        runCleanup(source: "launch_agent")
    }
}
