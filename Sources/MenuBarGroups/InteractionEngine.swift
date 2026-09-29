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

        // Microsoft OneDrive ignores kAXPressAction and requires an authentic mouse click.
        let isOneDrive = (item.bundleIdentifier?.localizedCaseInsensitiveContains("onedrive") ?? false)
            || item.name.localizedCaseInsensitiveContains("onedrive")

        // Try Accessibility Press first for non-OneDrive apps if process is trusted
        if !isOneDrive && AXIsProcessTrusted() {
            if pressViaAccessibility(pid: item.ownerPID, ordinal: item.ordinal) {
                return true
            }
        }

        // Targeted CGEvent click at the verified live frame
        return performTargetedClick(for: item)
    }

    private func performTargetedClick(for item: MenuBarItem) -> Bool {
        // 1. Temporarily order out concealment overlays so click lands on the true status item
        CurtainOverlayManager.shared.temporarilyHide(duration: 2.0)

        // 2. Expand menu bar carrot if collapsed
        ensureCarrotExpandedIfNeeded()

        // 3. Give WindowServer a brief moment to commit window hierarchy
        usleep(80000)

        // 4. Query the fresh live frame of the item right now
        let clickPoint: CGPoint
        if let liveFrame = fetchLiveFrame(pid: item.ownerPID, ordinal: item.ordinal),
           liveFrame.width > 0 && liveFrame.height > 0 {
            clickPoint = CGPoint(x: liveFrame.midX, y: liveFrame.midY)
        } else {
            clickPoint = CGPoint(x: item.frame.midX, y: item.frame.midY)
        }
        NSLog("InteractionEngine: activating item %@ (pid: %d), target clickPoint: (%f, %f)", item.name, item.ownerPID, clickPoint.x, clickPoint.y)
        return clickViaCGEvent(at: clickPoint)
    }

    private func fetchLiveFrame(pid: pid_t, ordinal: Int) -> CGRect? {
        let appElement = AXUIElementCreateApplication(pid)
        var barRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &barRef) == .success,
              let barElement = barRef as! AXUIElement? else {
            return nil
        }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(barElement, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement],
              children.indices.contains(ordinal) else {
            return nil
        }
        var valueRef: CFTypeRef?
        var frame = CGRect.zero
        if AXUIElementCopyAttributeValue(children[ordinal], "AXFrame" as CFString, &valueRef) == .success,
           let valueRef, CFGetTypeID(valueRef) == AXValueGetTypeID() {
            AXValueGetValue(valueRef as! AXValue, .cgRect, &frame)
            if frame.width > 0 && frame.height > 0 {
                return frame
            }
        }
        return nil
    }

    private func ensureCarrotExpandedIfNeeded() {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == "com.apple.MenuBarAgent" }
        guard let agent = apps.first else { return }
        let appElement = AXUIElementCreateApplication(agent.processIdentifier)
        var barRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &barRef) == .success,
              let bar = barRef as! AXUIElement? else { return }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(bar, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return }

        for child in children {
            var descRef: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(child, kAXDescriptionAttribute as CFString, &descRef)
            if (descRef as? String) == "Show Hidden Menu Bar Items" {
                var valRef: CFTypeRef?
                var frame = CGRect.zero
                if AXUIElementCopyAttributeValue(child, "AXFrame" as CFString, &valRef) == .success,
                   let val = valRef, CFGetTypeID(val) == AXValueGetTypeID() {
                    AXValueGetValue(val as! AXValue, .cgRect, &frame)
                    let p = CGPoint(x: frame.midX, y: frame.midY)
                    _ = clickViaCGEvent(at: p)
                    usleep(150000)
                }
                break
            }
        }
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
        CGWarpMouseCursorPosition(point)
        usleep(15000)

        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
            return false
        }
        down.post(tap: .cghidEventTap)
        usleep(50000)
        up.post(tap: .cghidEventTap)
        return true
    }
}
