import AppKit

private enum AppRuntime {
    static let delegate = AppDelegate()
}

let app = NSApplication.shared
app.delegate = AppRuntime.delegate
app.setActivationPolicy(.accessory) // no Dock icon
app.run()
