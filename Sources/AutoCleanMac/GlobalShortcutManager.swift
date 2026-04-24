import Cocoa
import Carbon

public final class GlobalShortcutManager {
    public static let shared = GlobalShortcutManager()
    
    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    
    private init() {}
    
    public func register() {
        guard hotKeyRef == nil else { return }
        
        let keyCode = UInt32(kVK_ANSI_C)
        let modifiers = UInt32(cmdKey | shiftKey)
        
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = "ACMC".fourCharCode
        hotKeyID.id = 1
        
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        let handler: EventHandlerUPP = { (_, _, _) -> OSStatus in
            // Post notification to open settings
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("com.micz.autocleanmac.openSettings"),
                object: nil
            )
            return noErr
        }
        
        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            nil,
            &eventHandler
        )
        
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }
    
    public func unregister() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
}

extension String {
    fileprivate var fourCharCode: UInt32 {
        var result: UInt32 = 0
        if let data = self.data(using: .macOSRoman) {
            for (i, byte) in data.enumerated() where i < 4 {
                result = (result << 8) | UInt32(byte)
            }
        }
        return result
    }
}
