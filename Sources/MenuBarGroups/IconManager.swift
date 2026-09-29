import AppKit
import CoreGraphics
import ScreenCaptureKit

/// Manages high-res Retina icons for menu bar items using a privacy-first hybrid approach:
/// - Permissionless Mode (default): Extracts monochrome status assets from on-disk bundles and curated SF Symbols.
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

        // 3. Resolve permissionless status icon
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

    // MARK: - Permissionless Icon Resolution

    private func resolvePermissionlessIcon(for item: MenuBarItem) -> NSImage {
        // Try on-disk bundle status asset first
        if let bundleAsset = findBundleStatusAsset(for: item) {
            return bundleAsset
        }

        // Try curated SF Symbol matching the app purpose
        if let symbol = curatedSymbol(for: item) {
            return symbol
        }

        // Fallback to app bundle icon
        if let appIcon = item.appIcon {
            return appIcon
        }

        return NSImage(systemSymbolName: "circle.grid.2x2.fill", accessibilityDescription: item.name) ?? NSImage()
    }

    private func findBundleStatusAsset(for item: MenuBarItem) -> NSImage? {
        guard let runningApp = NSRunningApplication(processIdentifier: item.ownerPID),
              let bundleURL = runningApp.bundleURL else {
            return nil
        }

        let candidates = [
            "Contents/Resources/images/darkTheme/cloud.svg",
            "Contents/Resources/cloud32.png",
            "Contents/Resources/images/status_tray_done.png",
            "Contents/Resources/images/app_icon/Drive_24.png",
            "Contents/Resources/status_icon.png",
            "Contents/Resources/tray_icon.png"
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

    private func curatedSymbol(for item: MenuBarItem) -> NSImage? {
        let combined = "\(item.name) \(item.bundleIdentifier ?? "")".lowercased()
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)

        let symbolName: String
        if combined.contains("onedrive") {
            symbolName = "cloud.fill"
        } else if combined.contains("proton") && combined.contains("drive") {
            symbolName = "lock.icloud.fill"
        } else if combined.contains("proton") && combined.contains("vpn") {
            symbolName = "shield.checkerboard"
        } else if combined.contains("synology") {
            symbolName = "externaldrive.connected.to.line.below.fill"
        } else if combined.contains("nextcloud") || combined.contains("owncloud") {
            symbolName = "cloud.sun.fill"
        } else if combined.contains("dropbox") {
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
