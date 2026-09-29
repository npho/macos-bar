import AppKit
import ApplicationServices
import CoreGraphics
import ScreenCaptureKit

/// A visible status-item window owned by another process. This is not an NSStatusItem
/// owned by this application, and its app icon is not necessarily its menu-bar image.
struct MenuBarItemWindow {
    let id: CGWindowID
    let pid: pid_t
    let name: String
    let ownerKey: String? // Stable bundle identity when available; not a process ID.
    let ordinal: Int // Best-effort distinction between multiple items from one app.
    let frame: CGRect // Quartz display coordinates (origin at upper left)
    let appIcon: NSImage?

    static func visible() -> [MenuBarItemWindow] {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let found: [MenuBarItemWindow] = windows.compactMap { info -> MenuBarItemWindow? in
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  layer == Int(CGWindowLevelForKey(.statusWindow)),
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  pid != getpid(),
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  frame.width > 0, frame.height > 0,
                  frame.height < 80,
                  let app = NSRunningApplication(processIdentifier: pid) else { return nil }
            return MenuBarItemWindow(id: id, pid: pid,
                                     name: app.localizedName ?? (info[kCGWindowOwnerName as String] as? String ?? "Unknown"),
                                     ownerKey: app.bundleIdentifier ?? app.bundleURL?.path,
                                     ordinal: 0, frame: frame, appIcon: app.icon)
        }
        let sorted = found.sorted { lhs, rhs in
            // Group windows by owner, then retain spatial order for multiple items.
            if lhs.name != rhs.name { return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending }
            return lhs.frame.minX < rhs.frame.minX
        }
        var counts: [String: Int] = [:]
        var results = sorted.map { item in
            let key = item.ownerKey ?? "pid:\(item.pid)"
            let ordinal = counts[key, default: 0]
            counts[key] = ordinal + 1
            return MenuBarItemWindow(id: item.id, pid: item.pid, name: item.name,
                                     ownerKey: item.ownerKey, ordinal: ordinal,
                                     frame: item.frame, appIcon: item.appIcon)
        }
        // On newer macOS versions a real status item may be exposed via AX but
        // have no separately listed Core Graphics status-window record.
        if !results.contains(where: { $0.name.localizedCaseInsensitiveContains("OneDrive") ||
            ($0.ownerKey?.localizedCaseInsensitiveContains("OneDrive") ?? false) }) {
            results += accessibilityOneDriveItems().filter { $0.frame.maxX > 0 }
        }
        return results
    }

    static func accessibilityOneDriveItems() -> [MenuBarItemWindow] {
        guard AXIsProcessTrusted() else { return [] }
        return NSWorkspace.shared.runningApplications.filter { app in
            (app.bundleIdentifier?.localizedCaseInsensitiveContains("OneDrive") ?? false) ||
            (app.localizedName?.localizedCaseInsensitiveContains("OneDrive") ?? false)
        }.flatMap { app in
            let root = AXUIElementCreateApplication(app.processIdentifier)
            var bar: CFTypeRef?
            guard AXUIElementCopyAttributeValue(root, "AXExtrasMenuBar" as CFString, &bar) == .success,
                  let bar = bar as! AXUIElement? else { return [MenuBarItemWindow]() }
            var children: CFTypeRef?
            guard AXUIElementCopyAttributeValue(bar, kAXChildrenAttribute as CFString, &children) == .success,
                  let items = children as? [AXUIElement] else { return [MenuBarItemWindow]() }
            return items.enumerated().compactMap { index, element in
                guard accessibilityRole(of: element) == kAXMenuBarItemRole as String,
                      let frame = accessibilityFrame(of: element), frame.width > 0, frame.height > 0 else { return nil }
                return MenuBarItemWindow(id: 0, pid: app.processIdentifier,
                                         name: app.localizedName ?? "OneDrive",
                                         ownerKey: app.bundleIdentifier ?? app.bundleURL?.path,
                                         ordinal: index, frame: frame, appIcon: app.icon)
            }
        }
    }

    private static func accessibilityRole(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func accessibilityFrame(of element: AXUIElement) -> CGRect? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXFrame" as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    static func accessibilityFrame(pid: pid_t, ordinal: Int) -> CGRect? {
        guard let app = NSRunningApplication(processIdentifier: pid),
              let candidate = accessibilityOneDriveItems().first(where: { $0.pid == app.processIdentifier && $0.ordinal == ordinal }) else { return nil }
        return candidate.frame
    }

    static func pressAccessibilityItem(pid: pid_t, ordinal: Int) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let root = AXUIElementCreateApplication(pid)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, "AXExtrasMenuBar" as CFString, &bar) == .success,
              let bar = bar as! AXUIElement? else { return false }
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(bar, kAXChildrenAttribute as CFString, &children) == .success,
              let items = children as? [AXUIElement], items.indices.contains(ordinal) else { return false }
        return AXUIElementPerformAction(items[ordinal], kAXPressAction as CFString) == .success
    }

    /// Reports only Accessibility structure needed to investigate a user-initiated
    /// OneDrive press. It deliberately excludes menu titles and account content.
    static func oneDriveAccessibilityDiagnostic() -> String {
        guard AXIsProcessTrusted() else { return "Accessibility access: not granted" }
        let apps = NSWorkspace.shared.runningApplications.filter { app in
            (app.bundleIdentifier?.localizedCaseInsensitiveContains("OneDrive") ?? false) ||
            (app.localizedName?.localizedCaseInsensitiveContains("OneDrive") ?? false)
        }
        guard !apps.isEmpty else { return "No running OneDrive process found." }
        var lines = ["Accessibility access: granted"]
        for app in apps {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            var barValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(root, "AXExtrasMenuBar" as CFString, &barValue) == .success,
                  let bar = barValue as! AXUIElement? else {
                lines.append("pid \(app.processIdentifier): AXExtrasMenuBar unavailable")
                continue
            }
            var childrenValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(bar, kAXChildrenAttribute as CFString, &childrenValue) == .success,
                  let children = childrenValue as? [AXUIElement] else {
                lines.append("pid \(app.processIdentifier): no extras-menu-bar children")
                continue
            }
            lines.append("pid \(app.processIdentifier): \(children.count) extras-menu-bar children")
            for (index, child) in children.enumerated() {
                var actionsValue: CFArray?
                let actionsResult = AXUIElementCopyActionNames(child, &actionsValue)
                let actions = actionsResult == .success ? ((actionsValue as? [String])?.joined(separator: ", ") ?? "unreadable") : "unavailable (\(actionsResult.rawValue))"
                lines.append("  [\(index)] role=\(accessibilityRole(of: child) ?? "unknown"), frame=\(accessibilityFrame(of: child)?.debugDescription ?? "unavailable"), actions=\(actions)")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func diagnosticSummary() -> String {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let status = windows.filter { ($0[kCGWindowLayer as String] as? Int) == Int(CGWindowLevelForKey(.statusWindow)) }
        let candidates = windows.filter { info in
            let pid = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
            let app = NSRunningApplication(processIdentifier: pid)
            return (app?.localizedName?.localizedCaseInsensitiveContains("OneDrive") ?? false) ||
                (app?.bundleIdentifier?.localizedCaseInsensitiveContains("OneDrive") ?? false) ||
                ((info[kCGWindowOwnerName as String] as? String)?.localizedCaseInsensitiveContains("OneDrive") ?? false)
        }
        let owners = candidates.map { info in
            let pid = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
            let layer = info[kCGWindowLayer as String] as? Int ?? -1
            let name = NSRunningApplication(processIdentifier: pid)?.localizedName ??
                (info[kCGWindowOwnerName as String] as? String ?? "Unknown")
            return "\(name): PID \(pid), layer \(layer)"
        }
        return "Visible window records: \(windows.count)\nStatus-window records: \(status.count)\nOneDrive process windows: \(candidates.count)\nOneDrive Accessibility items: \(accessibilityOneDriveItems().count)\nAccessibility access: \(AXIsProcessTrusted() ? "granted" : "not granted")\n" +
            (owners.isEmpty ? "No OneDrive window owner found." : owners.prefix(8).joined(separator: "\n")) +
            "\nScreen Recording access: \(CGPreflightScreenCaptureAccess() ? "granted" : "not granted")"
    }

    /// Capture one original status window after an explicit user action. This may prompt
    /// for Screen Recording permission; no images are written to disk.
    func captureImage() async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == id }) else {
            throw CaptureError.windowUnavailable
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(ceil(filter.contentRect.width * CGFloat(filter.pointPixelScale))))
        configuration.height = max(1, Int(ceil(filter.contentRect.height * CGFloat(filter.pointPixelScale))))
        configuration.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    private enum CaptureError: LocalizedError {
        case windowUnavailable
        var errorDescription: String? { "OneDrive's status window is no longer visible. Refresh and try again." }
    }

    /// A bounded diagnostic suitable for local development logs. It excludes
    /// menus, account data, and captured image contents.
    var diagnosticDescription: String {
        "owner=\(ownerKey ?? "unknown"), pid=\(pid), ordinal=\(ordinal), id=\(id), frame=\(frame.debugDescription)"
    }

    /// Separate, explicitly confirmed test for OneDrive's AX-only item. The caller
    /// must confirm the original icon is visible; stale or changed AX bounds block
    /// the click. Dispatch success does not prove the native menu opened.
    func clickVisibleOneDriveWithMouse() -> Bool {
        guard id == 0, AXIsProcessTrusted() else { return false }
        let candidates = Self.accessibilityOneDriveItems().filter {
            $0.pid == pid && $0.ordinal == ordinal && $0.ownerKey == ownerKey
        }
        guard candidates.count == 1, candidates[0].frame == frame else { return false }
        return Self.postMouseClick(at: CGPoint(x: frame.midX, y: frame.midY))
    }

    private static func postMouseClick(at point: CGPoint) -> Bool {
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else { return false }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    /// Send a normal click to the *original visible window*, never to a guessed location.
    /// The OS may refuse or the target may move in the meantime; no attempt is made to
    /// interact with off-screen/hidden items.
    func clickIfStillVisible() -> Bool {
        if id == 0 {
            guard let current = Self.visible().first(where: { $0.id == 0 && $0.pid == pid && $0.ordinal == ordinal }),
                  current.frame == frame else { return false }
            return Self.pressAccessibilityItem(pid: pid, ordinal: ordinal)
        }
        guard AXIsProcessTrusted(),
              let current = Self.visible().first(where: { $0.id == id && $0.pid == pid }),
              current.frame == frame else { return false }
        return Self.postMouseClick(at: CGPoint(x: frame.midX, y: frame.midY))
    }
}
