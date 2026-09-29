import AppKit

/// A floating, frameless overlay window that conceals grouped menu bar status items.
@MainActor
public final class CurtainOverlayWindow: NSPanel {
    private let backgroundView = NSVisualEffectView()
    private let colorFillView = NSView()
    public var onClicked: (() -> Void)?
    public var onRightClicked: (() -> Void)?

    private var passThroughTask: Task<Void, Never>?

    public init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        setupViews()
    }

    private func setupViews() {
        let container = NSView()
        container.wantsLayer = true

        backgroundView.blendingMode = .behindWindow
        backgroundView.material = .headerView
        backgroundView.state = .active
        backgroundView.autoresizingMask = [.width, .height]

        colorFillView.wantsLayer = true
        colorFillView.autoresizingMask = [.width, .height]
        updateFillColor()

        container.addSubview(backgroundView)
        container.addSubview(colorFillView)
        contentView = container
    }

    public func updateFillColor() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if isDark {
            // Near black (#010101) to match dark mode and MacBook camera notch horns
            colorFillView.layer?.backgroundColor = NSColor(calibratedRed: 0.0039, green: 0.0039, blue: 0.0039, alpha: 1.0).cgColor
        } else {
            // Native light translucency
            colorFillView.layer?.backgroundColor = NSColor(calibratedWhite: 0.95, alpha: 1.0).cgColor
        }
    }

    public func setTemporarilyPassThrough(duration: TimeInterval) {
        passThroughTask?.cancel()
        ignoresMouseEvents = true
        passThroughTask = Task { @MainActor in
            let ms = UInt64(max(0.1, duration) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ms)
            self.ignoresMouseEvents = false
        }
    }

    public override func mouseDown(with event: NSEvent) {
        if let onClicked {
            onClicked()
        } else {
            super.mouseDown(with: event)
        }
    }

    public override func rightMouseDown(with event: NSEvent) {
        if let onRightClicked {
            onRightClicked()
        } else {
            super.rightMouseDown(with: event)
        }
    }
}

/// Central manager coordinating concealment overlays over grouped menu bar items.
@MainActor
public final class CurtainOverlayManager {
    public static let shared = CurtainOverlayManager()

    private let defaultsKey = "com.example.MenuBarGroups.concealEnabled"
    private var panelsByGroup: [UUID: [CurtainOverlayWindow]] = [:]
    private var observers: [NSObjectProtocol] = []
    private var periodicTask: Task<Void, Never>?

    public var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: defaultsKey) == nil {
                return true // Enabled by default
            }
            return UserDefaults.standard.bool(forKey: defaultsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
            if !newValue {
                removeAll()
            } else {
                triggerUpdate()
            }
        }
    }

    private init() {
        setupObservers()
        startPeriodicSync()
    }

    private func setupObservers() {
        let center = NSWorkspace.shared.notificationCenter

        // When user switches apps, menu items shift as app menus expand or contract
        let appObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.triggerUpdate()
            }
        }
        observers.append(appObserver)

        let spaceObserver = center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.triggerUpdate()
            }
        }
        observers.append(spaceObserver)

        let screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.triggerUpdate()
            }
        }
        observers.append(screenObserver)
    }

    private func startPeriodicSync() {
        periodicTask?.cancel()
        periodicTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                self.triggerUpdate()
            }
        }
    }

    private func triggerUpdate() {
        guard isEnabled else { return }
        GroupManager.shared.refreshConcealmentOverlays()
    }

    /// Temporarily allows mouse clicks to pass through the overlay to underlying status items.
    public func temporarilyPassThroughEvents(duration: TimeInterval = 0.35) {
        for panels in panelsByGroup.values {
            for panel in panels {
                panel.setTemporarilyPassThrough(duration: duration)
            }
        }
    }

    /// Updates concealment overlay masks for the given groups and scanned items.
    public func update(
        groups: [MenuBarGroup],
        scannedItems: [MenuBarItem],
        onSummonGroup: @escaping (UUID) -> Void,
        onContextMenu: @escaping (UUID, NSPoint) -> Void
    ) {
        guard isEnabled else {
            removeAll()
            return
        }

        let activeGroupIDs = Set(groups.filter(\.concealItems).map(\.id))

        // Clean up panels for removed or unconcealed groups
        for (groupID, panels) in panelsByGroup where !activeGroupIDs.contains(groupID) {
            panels.forEach { $0.orderOut(nil) }
            panelsByGroup.removeValue(forKey: groupID)
        }

        // Process each concealed group
        for group in groups where group.concealItems {
            let matchingItems = GroupManager.shared.resolvedItems(for: group, allScanned: scannedItems)
            let validItems = matchingItems.filter { $0.frame.width > 0 && $0.frame.height > 0 && $0.frame.origin.x > 0 }

            if validItems.isEmpty {
                panelsByGroup[group.id]?.forEach { $0.orderOut(nil) }
                panelsByGroup[group.id] = []
                continue
            }

            // Convert items' AX frames into Cocoa screen frames
            let cocoaFrames = validItems.compactMap { item -> NSRect? in
                let screen = NSScreen.screens.first(where: {
                    $0.frame.minX <= item.frame.minX && item.frame.maxX <= $0.frame.maxX
                }) ?? NSScreen.main ?? NSScreen.screens.first

                guard let screen else { return nil }

                let menuBarHeight = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
                let cocoaY = screen.visibleFrame.maxY
                return NSRect(
                    x: item.frame.origin.x,
                    y: cocoaY,
                    width: item.frame.width,
                    height: menuBarHeight
                )
            }

            // Cluster contiguous/touching rects to avoid excessive windows
            let mergedRects = clusterAdjacentRects(cocoaFrames)

            var existingPanels = panelsByGroup[group.id] ?? []

            // Adjust panel pool count to match mergedRects
            while existingPanels.count < mergedRects.count {
                let panel = CurtainOverlayWindow()
                existingPanels.append(panel)
            }

            while existingPanels.count > mergedRects.count {
                let extra = existingPanels.removeLast()
                extra.orderOut(nil)
            }

            for (index, rect) in mergedRects.enumerated() {
                let panel = existingPanels[index]
                panel.updateFillColor()
                panel.setFrame(rect, display: true)
                panel.onClicked = {
                    onSummonGroup(group.id)
                }
                panel.onRightClicked = {
                    let mouseLoc = NSEvent.mouseLocation
                    onContextMenu(group.id, mouseLoc)
                }
                panel.orderFrontRegardless()
            }

            panelsByGroup[group.id] = existingPanels
        }
    }

    /// Merges horizontally adjacent or slightly overlapping rectangles into contiguous blocks.
    private func clusterAdjacentRects(_ rects: [NSRect]) -> [NSRect] {
        guard !rects.isEmpty else { return [] }
        let sorted = rects.sorted { $0.origin.x < $1.origin.x }
        var merged: [NSRect] = [sorted[0]]

        for current in sorted.dropFirst() {
            let lastIndex = merged.count - 1
            let last = merged[lastIndex]

            // If contiguous within 4 pixels
            if current.minX <= last.maxX + 4 && current.minY == last.minY {
                let newWidth = max(last.maxX, current.maxX) - last.minX
                merged[lastIndex] = NSRect(x: last.minX, y: last.minY, width: newWidth, height: last.height)
            } else {
                merged.append(current)
            }
        }

        return merged
    }

    public func removeAll() {
        for panels in panelsByGroup.values {
            panels.forEach { $0.orderOut(nil) }
        }
        panelsByGroup.removeAll()
    }
}
