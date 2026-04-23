import AppKit

final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?

    var onRunNow: (() -> Void)?
    var onShowLastLog: (() -> Void)?
    var onOpenConfig: (() -> Void)?
    var onOpenLogsFolder: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "🧹"
        item.button?.font = NSFont.systemFont(ofSize: 14)
        let menu = NSMenu()
        menu.addItem(withTitle: "Uruchom teraz",             action: #selector(runNow),      keyEquivalent: "").target = self
        menu.addItem(withTitle: "Pokaż ostatnie sprzątanie", action: #selector(showLastLog), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Otwórz konfigurację",       action: #selector(openConfig),  keyEquivalent: "").target = self
        menu.addItem(withTitle: "Otwórz folder logów",       action: #selector(openLogsDir), keyEquivalent: "").target = self
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Preferencje…",               action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Zakończ",                   action: #selector(quit),        keyEquivalent: "q").target = self
        item.menu = menu
        statusItem = item
    }

    @objc private func runNow()      { onRunNow?() }
    @objc private func showLastLog() { onShowLastLog?() }
    @objc private func openConfig()  { onOpenConfig?() }
    @objc private func openLogsDir() { onOpenLogsFolder?() }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func quit()        { onQuit?() }
}
