import AppKit

final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?

    var onRunNow: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let image = Self.loadStatusIcon() {
                button.image = image
                button.imagePosition = .imageOnly
            } else {
                button.title = "🧹"
                button.font = NSFont.systemFont(ofSize: 14)
            }
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "Uruchom teraz",    action: #selector(runNow),      keyEquivalent: "").target = self
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Preferencje…",     action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Zakończ",          action: #selector(quit),         keyEquivalent: "q").target = self
        item.menu = menu
        statusItem = item
    }

    @objc private func runNow()       { onRunNow?() }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func quit()         { onQuit?() }

    /// Loads the status-bar icon. Tries a bundled PNG first (supports @2x),
    /// falls back to an SF Symbol. Returns nil only if both fail.
    private static func loadStatusIcon() -> NSImage? {
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            return image
        }
        if let symbol = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "AutoCleanMac") {
            symbol.isTemplate = true
            return symbol
        }
        return nil
    }
}
