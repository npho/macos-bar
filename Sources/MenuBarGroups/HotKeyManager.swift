import Carbon
import Cocoa

/// Manages system-wide global hotkeys via Carbon HIToolbox without requiring Accessibility keystroke monitoring.
@MainActor
public final class HotKeyManager {
    public static let shared = HotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var action: (() -> Void)?

    private init() {}

    /// Registers a global hotkey (default: Command + Shift + Space).
    public func register(action: @escaping () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (handlerCallRef, eventRef, userData) -> OSStatus in
                Task { @MainActor in
                    HotKeyManager.shared.action?()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &handlerRef
        )

        guard status == noErr else { return }

        // Carbon modifiers: cmdKey (0x0100), shiftKey (0x0200)
        let hotKeyID = EventHotKeyID(signature: OSType(0x4D424750), id: 1) // 'MBGP'
        let modifiers = UInt32(cmdKey | shiftKey)
        let spaceKeyCode: UInt32 = 49 // Virtual key code for Space

        _ = RegisterEventHotKey(
            spaceKeyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    public func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }
}
