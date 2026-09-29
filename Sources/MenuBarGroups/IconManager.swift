import AppKit
import CoreGraphics
import ScreenCaptureKit

/// Manages high-res Retina icons for menu bar items, combining ScreenCaptureKit snapshots with app icon fallbacks.
@MainActor
public final class IconManager {
    public static let shared = IconManager()

    private var imageCache: [String: NSImage] = [:]

    private init() {}

    /// Returns the best available icon for the item.
    public func icon(for item: MenuBarItem) -> NSImage {
        if let cached = imageCache[item.id] {
            return cached
        }
        let fallback = item.appIcon ?? NSImage(systemSymbolName: "circle.grid.2x2.fill", accessibilityDescription: item.name) ?? NSImage()
        return fallback
    }

    /// Attempts to capture the live menu bar item icon using ScreenCaptureKit asynchronously.
    public func captureLiveIcon(for item: MenuBarItem) async {
        guard item.cgWindowID != 0, CGPreflightScreenCaptureAccess() else { return }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let window = content.windows.first(where: { $0.windowID == item.cgWindowID }) else { return }

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            config.width = max(1, Int(ceil(filter.contentRect.width * CGFloat(filter.pointPixelScale))))
            config.height = max(1, Int(ceil(filter.contentRect.height * CGFloat(filter.pointPixelScale))))
            config.showsCursor = false

            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: filter.contentRect.width, height: filter.contentRect.height))
            self.imageCache[item.id] = nsImage
        } catch {
            // Silently fall back to app icon
        }
    }
}
