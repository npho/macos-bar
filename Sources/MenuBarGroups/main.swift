import AppKit
import ApplicationServices

@main
struct MenuBarGroupsMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

private struct SavedMenuItem: Codable, Equatable {
    let ownerKey: String
    let ordinal: Int
    let name: String

    func matches(_ item: MenuBarItemWindow) -> Bool {
        ownerKey == item.ownerKey && ordinal == item.ordinal
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let groupID: String
    private let store: UserDefaults
    private var apps: [URL] = []
    private var menuBarItems: [MenuBarItemWindow] = []
    private var selectedItems: [SavedMenuItem] = []
    private var availableItems: [MenuBarItemWindow] = []
    private var capturedOneDrive: (windowID: CGWindowID, image: NSImage)?
    private let scrollView = NSScrollView()
    private let scrollContent = FlippedView()
    // Use a variable-width item and text as well as an icon so the prototype is
    // immediately visible even if a particular SF Symbol cannot be rendered.
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popupWindow = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 310, height: 180),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    private let stack = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "Drop applications here")
    private var welcomeWindow: NSWindow?

    override init() {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--group"), arguments.indices.contains(index + 1) {
            groupID = arguments[index + 1]
        } else {
            groupID = "default"
        }
        store = UserDefaults(suiteName: "com.example.MenuBarGroups.\(groupID)")!
        super.init()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // The welcome window is only launch confirmation; this is a menu-bar app.
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("MenuBarGroups: applicationDidFinishLaunching")
        // This keeps the application out of the Dock even when it is run by `swift run`. 
        NSApp.setActivationPolicy(.accessory)

        statusItem.button?.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Menu-bar item preview")
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.title = " Items"
        statusItem.button?.toolTip = "Menu-bar items preview"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopup)

        configurePopupWindow()
        loadApps()
        showWelcomeWindow()
    }

    /// A first-run visual confirmation. Closing this window leaves the app as a
    /// menu-bar-only application.
    private func showWelcomeWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 185),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        // We retain this window in welcomeWindow. AppKit must not release it
        // again when the user closes it (Continue or the title-bar button).
        window.isReleasedWhenClosed = false
        window.title = "Menu Bar Groups"
        window.center()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let heading = NSTextField(labelWithString: "Menu Bar Groups is running")
        heading.font = .boldSystemFont(ofSize: 18)
        let message = NSTextField(wrappingLabelWithString: "Close this window, then click “Items”. Use Add menu-bar item to save a visible item's shortcut in the popup. Original icons remain visible. Click-through requires Accessibility permission.")
        message.maximumNumberOfLines = 0
        let close = NSButton(title: "Continue", target: self, action: #selector(closeWelcome))
        close.bezelStyle = .rounded
        stack.addArrangedSubview(heading)
        stack.addArrangedSubview(message)
        stack.addArrangedSubview(close)

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        window.contentView = content
        welcomeWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        print("MenuBarGroups: welcome window requested")
    }

    @objc private func closeWelcome() {
        welcomeWindow?.close()
        welcomeWindow = nil
    }

    private func configurePopupWindow() {
        popupWindow.delegate = self
        popupWindow.isOpaque = false
        popupWindow.backgroundColor = .clear
        popupWindow.hasShadow = true
        popupWindow.level = .statusBar
        popupWindow.collectionBehavior = [.transient, .ignoresCycle]

        let view = DropView()
        view.onDrop = { [weak self] urls in self?.add(urls) }
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view.layer?.cornerRadius = 10
        view.layer?.masksToBounds = true

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollContent.frame = NSRect(x: 0, y: 0, width: 310, height: 1)
        scrollContent.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scrollContent.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollContent.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollContent.topAnchor)
        ])
        scrollView.documentView = scrollContent
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        popupWindow.contentView = view
    }

    @objc private func togglePopup() {
        if popupWindow.isVisible {
            popupWindow.orderOut(nil)
        } else {
            showPopup()
        }
    }

    private func showPopup() {
        menuBarItems = MenuBarItemWindow.visible()
        redraw()
        guard let button = statusItem.button, let buttonWindow = button.window else { return }

        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)
        let popupSize = popupWindow.frame.size
        let screen = buttonWindow.screen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? .zero
        let x = min(max(screenRect.midX - popupSize.width / 2, visibleFrame.minX), visibleFrame.maxX - popupSize.width)
        let y = max(visibleFrame.minY, screenRect.minY - popupSize.height - 6)
        popupWindow.setFrameOrigin(NSPoint(x: x, y: y))
        popupWindow.makeKeyAndOrderFront(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        if notification.object as? NSWindow === popupWindow {
            popupWindow.orderOut(nil)
        }
    }

    private func loadApps() {
        apps = (store.array(forKey: "apps") as? [String] ?? []).map { URL(fileURLWithPath: $0) }
        if let data = store.data(forKey: "selectedMenuItems") {
            selectedItems = (try? JSONDecoder().decode([SavedMenuItem].self, from: data)) ?? []
        }
        redraw()
    }

    private func add(_ urls: [URL]) {
        let newApps = urls.filter { $0.pathExtension == "app" && !apps.contains($0) }
        guard !newApps.isEmpty else { return }
        apps.append(contentsOf: newApps)
        saveAndRedraw()
    }

    private func saveAndRedraw() {
        store.set(apps.map(\.path), forKey: "apps")
        redraw()
    }

    private func redraw() {
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }

        let title = NSTextField(labelWithString: "My menu-bar items")
        title.font = .boldSystemFont(ofSize: 13)
        stack.addArrangedSubview(title)

        let caption = NSTextField(wrappingLabelWithString: "Saved item shortcuts. App icons are placeholders; original icons remain visible. A click-through action may be accepted without opening the native menu.")
        caption.font = .systemFont(ofSize: 11)
        caption.textColor = .secondaryLabelColor
        caption.maximumNumberOfLines = 2
        caption.widthAnchor.constraint(lessThanOrEqualToConstant: 280).isActive = true
        stack.addArrangedSubview(caption)

        let hideNotice = NSTextField(wrappingLabelWithString: "OneDrive hide test paused: the spacer failed to hide the icon and the app crashed. No icons are changed by this build.")
        hideNotice.font = .systemFont(ofSize: 11)
        hideNotice.textColor = .secondaryLabelColor
        hideNotice.maximumNumberOfLines = 3
        hideNotice.widthAnchor.constraint(lessThanOrEqualToConstant: 280).isActive = true
        stack.addArrangedSubview(hideNotice)
        if !menuBarItems.contains(where: isOneDrive) {
            let diagnostic = NSButton(title: "OneDrive not detected — why?", target: self, action: #selector(explainMissingOneDrive))
            diagnostic.bezelStyle = .inline
            stack.addArrangedSubview(diagnostic)
        }

        for (index, saved) in selectedItems.enumerated() {
            let item = menuBarItems.first(where: saved.matches)
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 6
            let artwork = item.flatMap { current in
                current.id == capturedOneDrive?.windowID ? capturedOneDrive?.image : nil
            }
            let icon = NSImageView(image: artwork ?? item?.appIcon ?? NSImage(systemSymbolName: "questionmark.square", accessibilityDescription: "Unavailable")!)
            icon.imageScaling = .scaleProportionallyDown
            icon.widthAnchor.constraint(equalToConstant: 20).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 20).isActive = true
            row.addArrangedSubview(icon)
            let label = saved.name + (saved.ordinal > 0 ? " (item \(saved.ordinal + 1))" : "")
            let button = NSButton(title: item == nil ? "\(label) — unavailable" : label,
                                  target: self, action: #selector(clickMenuBarItem(_:)))
            button.bezelStyle = .inline
            button.isEnabled = item != nil
            button.tag = index
            row.addArrangedSubview(button)
            let remove = NSButton(title: "×", target: self, action: #selector(removeMenuBarItem(_:)))
            remove.bezelStyle = .inline
            remove.tag = index
            row.addArrangedSubview(remove)
            stack.addArrangedSubview(row)
        }
        if selectedItems.isEmpty {
            stack.addArrangedSubview(NSTextField(labelWithString: "No items added yet"))
        }
        availableItems = menuBarItems.filter { item in
            item.ownerKey != nil && !selectedItems.contains(where: { $0.matches(item) })
        }
        let addItem = NSPopUpButton(frame: .zero, pullsDown: false)
        addItem.addItem(withTitle: "Add menu-bar item…")
        for item in availableItems {
            addItem.addItem(withTitle: item.name + (item.ordinal > 0 ? " (item \(item.ordinal + 1))" : ""))
        }
        addItem.target = self
        addItem.action = #selector(addMenuBarItem(_:))
        addItem.isEnabled = !availableItems.isEmpty
        stack.addArrangedSubview(addItem)
        let capture = NSButton(title: "Capture OneDrive status icon (Screen Recording)…", target: self, action: #selector(captureOneDrive))
        capture.bezelStyle = .inline
        capture.isEnabled = menuBarItems.contains { isOneDrive($0) && $0.id != 0 }
        if !capture.isEnabled {
            capture.toolTip = "This macOS session exposes OneDrive through Accessibility, but not as a capturable window."
        }
        stack.addArrangedSubview(capture)
        let diagnostics = NSButton(title: "Copy OneDrive AX diagnostics", target: self, action: #selector(copyOneDriveAccessibilityDiagnostics))
        diagnostics.bezelStyle = .inline
        diagnostics.isEnabled = menuBarItems.contains(where: isOneDrive) && AXIsProcessTrusted()
        diagnostics.toolTip = diagnostics.isEnabled ? "Copies roles, supported actions, and bounds; no menu or account content." : "Refresh after granting Accessibility to enable this diagnostic."
        stack.addArrangedSubview(diagnostics)
        let locate = NSButton(title: "Check OneDrive icon location (hover)…", target: self, action: #selector(checkOneDriveLocation(_:)))
        locate.bezelStyle = .inline
        locate.isEnabled = diagnostics.isEnabled
        locate.toolTip = "Move the pointer over the original OneDrive icon after clicking; no click or screen capture is performed."
        stack.addArrangedSubview(locate)
        let mouseTest = NSButton(title: "Test visible OneDrive mouse click…", target: self, action: #selector(testVisibleOneDriveMouseClick))
        mouseTest.bezelStyle = .inline
        mouseTest.isEnabled = AXIsProcessTrusted() && menuBarItems.contains { isOneDrive($0) && $0.id == 0 }
        mouseTest.toolTip = "Explicit one-click test of the original visible icon; never use for a hidden item."
        stack.addArrangedSubview(mouseTest)
        if availableItems.isEmpty && selectedItems.isEmpty {
            stack.addArrangedSubview(NSTextField(labelWithString: "No visible third-party items detected"))
        }
        if !AXIsProcessTrusted() {
            let permission = NSButton(title: "Enable Device Control / Accessibility…", target: self, action: #selector(requestAccessibility))
            permission.bezelStyle = .inline
            stack.addArrangedSubview(permission)
        }
        let refresh = NSButton(title: "Refresh items", target: self, action: #selector(refreshItems))
        refresh.bezelStyle = .inline
        stack.addArrangedSubview(refresh)

        let shortcutTitle = NSTextField(labelWithString: "Application shortcuts (existing prototype)")
        shortcutTitle.font = .boldSystemFont(ofSize: 13)
        stack.addArrangedSubview(shortcutTitle)

        if apps.isEmpty {
            emptyLabel.textColor = .secondaryLabelColor
            stack.addArrangedSubview(emptyLabel)
        } else {
            for url in apps {
                let row = NSStackView()
                row.orientation = .horizontal
                row.alignment = .centerY
                row.spacing = 6

                let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: url.path))
                icon.imageScaling = .scaleProportionallyDown
                icon.setFrameSize(NSSize(width: 20, height: 20))
                let launch = NSButton(title: url.deletingPathExtension().lastPathComponent, target: self, action: #selector(openApp(_:)))
                launch.bezelStyle = .inline
                launch.tag = apps.firstIndex(of: url)!
                let remove = NSButton(title: "×", target: self, action: #selector(removeApp(_:)))
                remove.bezelStyle = .inline
                remove.tag = launch.tag
                row.addArrangedSubview(icon)
                row.addArrangedSubview(launch)
                row.addArrangedSubview(NSView())
                row.addArrangedSubview(remove)
                stack.addArrangedSubview(row)
            }
        }

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.distribution = .fillEqually
        let newGroup = NSButton(title: "New Group", target: self, action: #selector(newGroup(_:)))
        let quit = NSButton(title: "Quit", target: self, action: #selector(quit(_:)))
        footer.addArrangedSubview(newGroup)
        footer.addArrangedSubview(quit)
        stack.addArrangedSubview(footer)
        var frame = popupWindow.frame
        stack.layoutSubtreeIfNeeded()
        let contentHeight = ceil(stack.fittingSize.height) + 2
        scrollContent.frame = NSRect(x: 0, y: 0, width: 310, height: contentHeight)
        let maxHeight = (statusItem.button?.window?.screen ?? NSScreen.main)?.visibleFrame.height ?? 650
        frame.size.height = min(max(210, contentHeight), max(210, maxHeight - 60))
        popupWindow.setFrame(frame, display: popupWindow.isVisible)
    }

    @objc private func refreshItems() {
        menuBarItems = MenuBarItemWindow.visible()
        redraw()
    }

    @objc private func requestAccessibility() {
        // Only prompt after an explicit click; discovery needs no Accessibility permission.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        refreshItems()
    }

    private func isOneDrive(_ item: MenuBarItemWindow) -> Bool {
        item.name.localizedCaseInsensitiveContains("OneDrive") ||
        (item.ownerKey?.localizedCaseInsensitiveContains("OneDrive") ?? false)
    }

    @objc private func captureOneDrive() {
        guard let item = menuBarItems.first(where: isOneDrive), let key = item.ownerKey else { return }
        Task { @MainActor in
            do {
                let image = try await item.captureImage()
                // Confirm that the same original item is still present before saving the image.
                guard MenuBarItemWindow.visible().contains(where: { $0.id == item.id && $0.pid == item.pid }) else { return }
                capturedOneDrive = (item.id, NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))
                if !selectedItems.contains(where: { $0.matches(item) }) {
                    selectedItems.append(SavedMenuItem(ownerKey: key, ordinal: item.ordinal, name: item.name))
                    saveMenuBarItems()
                } else {
                    redraw()
                }
            } catch {
                let alert = NSAlert()
                alert.messageText = "Could not capture OneDrive's status icon"
                alert.informativeText = "Allow Screen Recording for Menu Bar Groups in System Settings, then restart the app and try again. \(error.localizedDescription)"
                alert.runModal()
            }
        }
    }

    @objc private func addMenuBarItem(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem - 1
        guard availableItems.indices.contains(index), let key = availableItems[index].ownerKey else { return }
        let item = availableItems[index]
        selectedItems.append(SavedMenuItem(ownerKey: key, ordinal: item.ordinal, name: item.name))
        saveMenuBarItems()
    }

    @objc private func removeMenuBarItem(_ sender: NSButton) {
        guard selectedItems.indices.contains(sender.tag) else { return }
        selectedItems.remove(at: sender.tag)
        saveMenuBarItems()
    }

    private func saveMenuBarItems() {
        if let data = try? JSONEncoder().encode(selectedItems) {
            store.set(data, forKey: "selectedMenuItems")
        }
        menuBarItems = MenuBarItemWindow.visible()
        redraw()
    }

    @objc private func copyOneDriveAccessibilityDiagnostics(_ sender: NSButton) {
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(MenuBarItemWindow.oneDriveAccessibilityDiagnostic(), forType: .string) {
            sender.title = "Copied OneDrive AX diagnostics"
            sender.toolTip = "Paste the diagnostics to share them. No menu or account content is included."
        } else {
            let alert = NSAlert()
            alert.messageText = "Could not copy OneDrive diagnostics"
            alert.informativeText = "The pasteboard did not accept the diagnostic text. Try again."
            alert.runModal()
        }
    }

    @objc private func checkOneDriveLocation(_ sender: NSButton) {
        sender.isEnabled = false
        popupWindow.orderOut(nil)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            let point = CGEvent(source: nil)?.location
            let items = MenuBarItemWindow.accessibilityOneDriveItems()
            let alert = NSAlert()
            alert.messageText = "OneDrive icon location check"
            if let point, items.count == 1 {
                let match = items[0].frame.contains(point)
                alert.informativeText = "Pointer: \(point). OneDrive AX bounds: \(items[0].frame). \(match ? "Pointer is inside the reported bounds." : "Pointer is outside the reported bounds.") No click was sent."
            } else {
                alert.informativeText = "Could not compare the pointer with exactly one OneDrive Accessibility item. No click was sent. Refresh items and check Accessibility access."
            }
            alert.runModal()
            refreshItems()
        }
    }

    @objc private func testVisibleOneDriveMouseClick() {
        let candidates = menuBarItems.filter { isOneDrive($0) && $0.id == 0 }
        guard candidates.count == 1 else { return }
        let item = candidates[0]
        let confirmation = NSAlert()
        confirmation.messageText = "Test one click on the original OneDrive icon?"
        confirmation.informativeText = "Only continue if OneDrive's original icon is currently visible. The app will recheck its Accessibility identity and bounds, then send one mouse click at its center. This may move your pointer and open OneDrive's menu. No icon will be hidden or moved."
        confirmation.addButton(withTitle: "Send one click")
        confirmation.addButton(withTitle: "Cancel")
        guard confirmation.runModal() == .alertFirstButtonReturn else { return }
        popupWindow.orderOut(nil)
        Task { @MainActor in
            // Allow the popup and confirmation to leave the menu bar before
            // revalidating the original icon and sending the click.
            try? await Task.sleep(for: .milliseconds(250))
            let dispatched = item.clickVisibleOneDriveWithMouse()
            print("MenuBarGroups: visible OneDrive mouse click \(item.diagnosticDescription), dispatch=\(dispatched ? "accepted (native menu not verified)" : "blocked")")
            if !dispatched {
                let alert = NSAlert()
                alert.messageText = "OneDrive click was not sent"
                alert.informativeText = "The original item's identity or bounds changed, or Accessibility access is unavailable. No click was sent."
                alert.runModal()
            }
        }
    }

    @objc private func explainMissingOneDrive() {
        let diagnostics = MenuBarItemWindow.diagnosticSummary()
        let alert = NSAlert()
        alert.messageText = "OneDrive status item not detected"
        alert.informativeText = "No icons were changed. Click Copy diagnostics and paste the result into our conversation so we can identify why this app cannot see OneDrive."
        alert.addButton(withTitle: "Copy diagnostics")
        alert.addButton(withTitle: "Close")
        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(diagnostics, forType: .string)
        }
    }

    @objc private func clickMenuBarItem(_ sender: NSButton) {
        guard selectedItems.indices.contains(sender.tag) else { return }
        let selected = selectedItems[sender.tag]
        popupWindow.orderOut(nil)
        guard let item = menuBarItems.first(where: selected.matches) else { return }
        // This user-initiated preview only invokes an item after revalidating that
        // its original visible bounds have not moved. It never targets hidden items.
        let didDispatch = item.clickIfStillVisible()
        print("MenuBarGroups: click-through \(item.diagnosticDescription), dispatch=\(didDispatch ? "accepted (native menu not verified)" : "blocked")")
        if !didDispatch {
            let alert = NSAlert()
            alert.messageText = "Could not open the original menu-bar item"
            alert.informativeText = "The item moved, disappeared, or Accessibility access is unavailable. Its original icon was not changed. Refresh Items and try again while it is visible."
            alert.runModal()
        }
        refreshItems()
    }

    @objc private func openApp(_ sender: NSButton) {
        guard apps.indices.contains(sender.tag) else { return }
        NSWorkspace.shared.openApplication(at: apps[sender.tag], configuration: .init()) { _, error in
            if let error {
                Task { @MainActor in NSApp.presentError(error) }
            }
        }
    }

    @objc private func removeApp(_ sender: NSButton) {
        guard apps.indices.contains(sender.tag) else { return }
        apps.remove(at: sender.tag)
        saveAndRedraw()
    }

    @objc private func newGroup(_ sender: Any?) {
        // Starting the executable directly works both under `swift run` and inside the app bundle.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = ["--group", UUID().uuidString]
        do { try process.run() }
        catch { NSApp.presentError(error) }
    }

    @objc private func quit(_ sender: Any?) { NSApp.terminate(nil) }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class DropView: NSView {
    var onDrop: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ? .copy : []
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        onDrop?(urls)
        return !urls.isEmpty
    }
}
