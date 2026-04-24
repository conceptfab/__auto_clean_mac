import AppKit
import SwiftUI

final class ConsoleWindow: NSObject {
    private var panel: NSPanel?
    let model = ConsoleViewModel()

    func showCentered(fadeInMs: Int) {
        let view = ConsoleView(model: model)
        let hosting = NSHostingView(rootView: view)
        let size = NSSize(width: 600, height: 500)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true

        let visual = NSVisualEffectView()
        visual.material = .hudWindow
        visual.blendingMode = .behindWindow
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 14
        visual.layer?.masksToBounds = true
        visual.frame = NSRect(origin: .zero, size: size)
        visual.autoresizingMask = [.width, .height]

        hosting.frame = visual.bounds
        hosting.autoresizingMask = [.width, .height]
        visual.addSubview(hosting)

        panel.contentView = visual
        panel.center()
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Double(fadeInMs) / 1000.0
            panel.animator().alphaValue = 1.0
        }
        self.panel = panel
    }

    func fadeOutAndClose(holdMs: Int, fadeOutMs: Int, completion: @escaping () -> Void) {
        let deadline = DispatchTime.now() + .milliseconds(holdMs)
        DispatchQueue.main.asyncAfter(deadline: deadline) { [weak self] in
            guard let panel = self?.panel else { completion(); return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = Double(fadeOutMs) / 1000.0
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
                self?.panel = nil
                completion()
            })
        }
    }
}
