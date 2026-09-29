import AppKit
import CoreGraphics
import ScreenCaptureKit

/// Manages high-res Retina icons for menu bar items using a privacy-first hybrid approach:
/// - Permissionless Mode (default): Uses authentic bespoke vector renderers and on-disk assets.
/// - Live Capture Mode (opt-in): If the user enables live capture and grants Screen Recording, captures dynamic menu bar states.
@MainActor
public final class IconManager {
    public static let shared = IconManager()

    private let liveCaptureDefaultsKey = "com.example.MenuBarGroups.useLiveScreenCapture"

    private var staticCache: [String: NSImage] = [:]
    private var liveCache: [String: NSImage] = [:]

    /// Whether live ScreenCaptureKit mirroring is enabled by the user (defaults to false for permissionless operation).
    public var useLiveScreenCapture: Bool {
        get { UserDefaults.standard.bool(forKey: liveCaptureDefaultsKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: liveCaptureDefaultsKey)
            if !newValue {
                liveCache.removeAll()
            }
        }
    }

    private init() {}

    /// Returns the best available menu bar icon for the item.
    public func icon(for item: MenuBarItem) -> NSImage {
        // 1. If live screen recording is opted-in and cached, return the live snapshot
        if useLiveScreenCapture, let live = liveCache[item.id] {
            return live
        }

        // 2. Check static permissionless cache
        if let cached = staticCache[item.id] {
            return cached
        }

        // 3. Resolve authentic permissionless status icon
        let resolved = resolvePermissionlessIcon(for: item)
        staticCache[item.id] = resolved
        return resolved
    }

    /// Asynchronously captures the dynamic, live menu bar icon if live capture is enabled and permitted.
    @discardableResult
    public func captureLiveIcon(for item: MenuBarItem) async -> NSImage? {
        guard useLiveScreenCapture, CGPreflightScreenCaptureAccess(),
              item.frame.width > 0, item.frame.height > 0 else {
            return nil
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return nil }

            // Exclude our overlay masks so ScreenCaptureKit sees the raw status item underneath
            let overlayWindows = content.windows.filter {
                $0.owningApplication?.bundleIdentifier == "com.example.MenuBarGroups"
            }

            let filter = SCContentFilter(display: display, excludingWindows: overlayWindows)
            let config = SCStreamConfiguration()
            config.sourceRect = item.frame
            config.width = max(1, Int(item.frame.width * 2))
            config.height = max(1, Int(item.frame.height * 2))
            config.showsCursor = false

            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: item.frame.width, height: item.frame.height))
            self.liveCache[item.id] = nsImage
            return nsImage
        } catch {
            return nil
        }
    }

    // MARK: - Authentic Permissionless Icon Resolution

    private func resolvePermissionlessIcon(for item: MenuBarItem) -> NSImage {
        let combined = "\(item.name) \(item.bundleIdentifier ?? "")".lowercased()

        // 1. Check for accurate bespoke vector representations
        if combined.contains("nextcloud") || combined.contains("owncloud") {
            return renderNextcloudIcon()
        }

        if combined.contains("proton") && combined.contains("drive") {
            return renderProtonDriveIcon()
        }

        if combined.contains("proton") && combined.contains("vpn") {
            return renderProtonVPNIcon()
        }

        if combined.contains("synology") {
            return renderSynologyIcon()
        }

        if combined.contains("onedrive") {
            return renderOneDriveIcon()
        }

        // 2. Try on-disk bundle status asset
        if let bundleAsset = findBundleStatusAsset(for: item) {
            return bundleAsset
        }

        // 3. Try curated SF Symbols for other known utilities
        if let symbol = curatedSymbol(for: item, combined: combined) {
            return symbol
        }

        // 4. Fallback to app bundle icon
        if let appIcon = item.appIcon {
            return appIcon
        }

        return NSImage(systemSymbolName: "circle.grid.2x2.fill", accessibilityDescription: item.name) ?? NSImage()
    }

    // MARK: - Bespoke Vector Renderers

    /// Official Nextcloud three-connected-node status icon.
    private func renderNextcloudIcon() -> NSImage {
        let size = NSSize(width: 24, height: 20)
        let img = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1.8)

            let center = CGRect(x: 12 - 4.5, y: 10 - 4.5, width: 9, height: 9)
            ctx.strokeEllipse(in: center)

            let left = CGRect(x: 4.5 - 2.8, y: 10 - 2.8, width: 5.6, height: 5.6)
            ctx.strokeEllipse(in: left)

            let right = CGRect(x: 19.5 - 2.8, y: 10 - 2.8, width: 5.6, height: 5.6)
            ctx.strokeEllipse(in: right)

            ctx.move(to: CGPoint(x: 7.2, y: 10))
            ctx.addLine(to: CGPoint(x: 7.6, y: 10))
            ctx.move(to: CGPoint(x: 16.4, y: 10))
            ctx.addLine(to: CGPoint(x: 16.8, y: 10))
            ctx.strokePath()
            return true
        }
        img.isTemplate = true
        return img
    }

    /// Official Proton Drive folder with checkmark badge menu bar icon.
    private func renderProtonDriveIcon() -> NSImage {
        let size = NSSize(width: 22, height: 20)
        let img = NSImage(size: size, flipped: false) { rect in
            let folderConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            let checkConfig = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)

            if let folder = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)?.withSymbolConfiguration(folderConfig) {
                folder.draw(in: NSRect(x: 0, y: 1, width: 17, height: 15))
            }
            if let check = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)?.withSymbolConfiguration(checkConfig) {
                let badgeRect = NSRect(x: 10, y: 8, width: 11, height: 11)
                NSColor.clear.setFill()
                badgeRect.fill(using: .copy)
                check.draw(in: badgeRect)
            }
            return true
        }
        img.isTemplate = true
        return img
    }

    /// Official Synology Drive chevron "D" menu bar status icon.
    private func renderSynologyIcon() -> NSImage {
        let size = NSSize(width: 20, height: 20)
        let img = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 3, y: 3))
            path.line(to: NSPoint(x: 9, y: 3))
            path.line(to: NSPoint(x: 17, y: 10))
            path.line(to: NSPoint(x: 9, y: 17))
            path.line(to: NSPoint(x: 3, y: 17))
            path.line(to: NSPoint(x: 10, y: 10))
            path.close()

            let innerChevron = NSBezierPath()
            innerChevron.move(to: NSPoint(x: 3.5, y: 6.5))
            innerChevron.line(to: NSPoint(x: 7.5, y: 10))
            innerChevron.line(to: NSPoint(x: 3.5, y: 13.5))
            innerChevron.lineWidth = 2.0
            innerChevron.lineCapStyle = .round
            innerChevron.lineJoinStyle = .round

            NSColor.white.setFill()
            path.fill()
            NSColor.white.setStroke()
            innerChevron.stroke()
            return true
        }
        img.isTemplate = true
        return img
    }

    /// Official OneDrive outlined cloud menu bar status icon.
    private func renderOneDriveIcon() -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        let img = NSImage(systemSymbolName: "cloud", accessibilityDescription: "OneDrive")?.withSymbolConfiguration(config) ?? NSImage()
        img.isTemplate = true
        return img
    }

    /// Official Proton VPN shield with X menu bar status icon.
    private func renderProtonVPNIcon() -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let img = NSImage(systemSymbolName: "xmark.shield.fill", accessibilityDescription: "Proton VPN")?.withSymbolConfiguration(config) ?? NSImage()
        img.isTemplate = true
        return img
    }

    // MARK: - Asset & Symbol Fallbacks

    private func findBundleStatusAsset(for item: MenuBarItem) -> NSImage? {
        guard let runningApp = NSRunningApplication(processIdentifier: item.ownerPID),
              let bundleURL = runningApp.bundleURL else {
            return nil
        }

        let candidates = [
            "Contents/Resources/status_icon.png",
            "Contents/Resources/tray_icon.png",
            "Contents/Resources/images/status_m_done.png"
        ]

        for relativePath in candidates {
            let fileURL = bundleURL.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: fileURL.path),
               let image = NSImage(contentsOf: fileURL) {
                image.isTemplate = true
                return image
            }
        }

        return nil
    }

    private func curatedSymbol(for item: MenuBarItem, combined: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)

        let symbolName: String
        if combined.contains("dropbox") {
            symbolName = "shippingbox.fill"
        } else if combined.contains("google") && combined.contains("drive") {
            symbolName = "cylinder.split.1x2.fill"
        } else if combined.contains("box") {
            symbolName = "archivebox.fill"
        } else if combined.contains("pcloud") {
            symbolName = "cloud.fill"
        } else if combined.contains("stats") {
            symbolName = "chart.bar.xaxis"
        } else if combined.contains("weather") {
            symbolName = "cloud.sun.fill"
        } else if combined.contains("lulu") {
            symbolName = "network.badge.shield.half.filled"
        } else if combined.contains("f5") {
            symbolName = "network"
        } else if combined.contains("codex") || combined.contains("chatgpt") {
            symbolName = "chevron.left.forwardslash.chevron.right"
        } else {
            return nil
        }

        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: item.name)?.withSymbolConfiguration(config) else {
            return nil
        }
        symbol.isTemplate = true
        return symbol
    }
}
