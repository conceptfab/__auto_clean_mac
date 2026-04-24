import AppKit
let symbols = ["macwindow.badge.minus", "minus.rectangle", "app.dashed", "macwindow", "square.grid.2x2", "app"]
for s in symbols {
    if NSImage(systemSymbolName: s, accessibilityDescription: nil) != nil {
        print("\(s): YES")
    } else {
        print("\(s): NO")
    }
}
