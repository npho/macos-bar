import AppKit
import ApplicationServices
import CoreGraphics

/// Dispatches user interactions to original status items safely.
@MainActor
public final class InteractionEngine {
    public static let shared = InteractionEngine()

    private init() {}

    /// Activates or opens the menu of a targeted MenuBarItem.
    /// Returns true if interaction dispatch was accepted.
    @discardableResult
    public func activate(item: MenuBarItem) -> Bool {
        // Preflight: Ensure target process is still alive
        guard let runningApp = NSRunningApplication(processIdentifier: item.ownerPID),
              !runningApp.isTerminated else {
            return false
        }

        // Try Accessibility Press first if process is trusted
        if AXIsProcessTrusted() {
            if pressViaAccessibility(pid: item.ownerPID, ordinal: item.ordinal) {
                return true
            }
        }

        // Fallback: Targeted CGEvent click at the verified current frame
        CurtainOverlayManager.shared.temporarilyPassThroughEvents(duration: 0.35)
        return clickViaCGEvent(at: CGPoint(x: item.frame.midX, y: item.frame.midY))
    }

    private func pressViaAccessibility(pid: pid_t, ordinal: Int) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)
        var barRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &barRef) == .success,
              let barElement = barRef as! AXUIElement? else {
            return false
        }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(barElement, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement],
              children.indices.contains(ordinal) else {
            return false
        }

        let targetChild = children[ordinal]
        let result = AXUIElementPerformAction(targetChild, kAXPressAction as CFString)
        return result == .success
    }

    private func clickViaCGEvent(at point: CGPoint) -> Bool {
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
            return false
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
