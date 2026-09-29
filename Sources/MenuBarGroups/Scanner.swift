import AppKit
import ApplicationServices
import CoreGraphics

/// Discovers and tracks third-party status bar items across macOS.
@MainActor
public final class MenuBarScanner {
    public static let shared = MenuBarScanner()

    private init() {}

    /// Scans the system for all visible status bar items.
    /// Combines CoreGraphics window inspection with Accessibility extras inspection.
    public func scan() -> [MenuBarItem] {
        let currentPID = getpid()
        var items: [MenuBarItem] = []

        // 1. CoreGraphics window inspection
        let cgItems = scanCoreGraphicsStatusWindows(currentPID: currentPID)

        // 2. Accessibility extras inspection (if granted)
        let axItems = AXIsProcessTrusted() ? scanAccessibilityExtras(currentPID: currentPID) : []

        // 3. Merge & Deduplicate
        var mergedByOwner: [String: [MenuBarItem]] = [:]

        // Add CG items first
        for item in cgItems {
            let owner = item.bundleIdentifier ?? "pid:\(item.ownerPID)"
            mergedByOwner[owner, default: []].append(item)
        }

        // Add AX items if not already covered by CG items for that process
        for axItem in axItems {
            let owner = axItem.bundleIdentifier ?? "pid:\(axItem.ownerPID)"
            let existing = mergedByOwner[owner] ?? []
            // If existing CG items have frame matching this AX item, keep the CG item
            let alreadyFound = existing.contains { cg in
                abs(cg.frame.midX - axItem.frame.midX) < 10 && abs(cg.frame.midY - axItem.frame.midY) < 10
            }
            if !alreadyFound {
                mergedByOwner[owner, default: []].append(axItem)
            }
        }

        // Normalize ordinals and assemble final list
        for (owner, ownerItems) in mergedByOwner {
            // Sort items belonging to the same app left-to-right
            let sorted = ownerItems.sorted { $0.frame.minX < $1.frame.minX }
            for (index, item) in sorted.enumerated() {
                let stableID = "\(owner):\(index)"
                items.append(MenuBarItem(
                    id: stableID,
                    name: item.name,
                    ownerPID: item.ownerPID,
                    bundleIdentifier: item.bundleIdentifier,
                    ordinal: index,
                    frame: item.frame,
                    appIcon: item.appIcon,
                    cgWindowID: item.cgWindowID,
                    isAXOnly: item.isAXOnly
                ))
            }
        }

        // Sort items spatially by their x position across the menu bar
        return items.sorted { $0.frame.minX < $1.frame.minX }
    }

    private func scanCoreGraphicsStatusWindows(currentPID: pid_t) -> [MenuBarItem] {
        guard let windowInfos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))

        return windowInfos.compactMap { info -> MenuBarItem? in
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  layer == statusLevel,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  pid != currentPID,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: boundsDict),
                  frame.width > 0, frame.height > 0,
                  frame.height < 100, // Status items are typically 22-30pt high
                  let app = NSRunningApplication(processIdentifier: pid)
            else { return nil }

            let name = app.localizedName ?? (info[kCGWindowOwnerName as String] as? String ?? "Unknown")
            let bundleID = app.bundleIdentifier

            return MenuBarItem(
                id: "\(bundleID ?? name):0",
                name: name,
                ownerPID: pid,
                bundleIdentifier: bundleID,
                ordinal: 0,
                frame: frame,
                appIcon: app.icon,
                cgWindowID: id,
                isAXOnly: false
            )
        }
    }

    private func scanAccessibilityExtras(currentPID: pid_t) -> [MenuBarItem] {
        var results: [MenuBarItem] = []
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != currentPID &&
            ($0.activationPolicy == .regular || $0.activationPolicy == .accessory)
        }

        for app in runningApps {
            let pid = app.processIdentifier
            let appElement = AXUIElementCreateApplication(pid)

            var barRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &barRef) == .success,
                  let barElement = barRef as! AXUIElement? else {
                continue
            }

            var childrenRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(barElement, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                  let children = childrenRef as? [AXUIElement] else {
                continue
            }

            for (index, child) in children.enumerated() {
                guard let frame = accessibilityFrame(of: child), frame.width > 0, frame.height > 0 else {
                    continue
                }
                let name = app.localizedName ?? "Status Item"
                let bundleID = app.bundleIdentifier

                results.append(MenuBarItem(
                    id: "\(bundleID ?? name):\(index)",
                    name: name,
                    ownerPID: pid,
                    bundleIdentifier: bundleID,
                    ordinal: index,
                    frame: frame,
                    appIcon: app.icon,
                    cgWindowID: 0,
                    isAXOnly: true
                ))
            }
        }

        return results
    }

    private func accessibilityFrame(of element: AXUIElement) -> CGRect? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXFrame" as CFString, &valueRef) == .success,
              let valueRef, CFGetTypeID(valueRef) == AXValueGetTypeID() else {
            return nil
        }
        var rect = CGRect.zero
        guard AXValueGetValue(valueRef as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }
}
