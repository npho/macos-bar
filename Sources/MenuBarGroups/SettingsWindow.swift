import AppKit
import ApplicationServices
import ServiceManagement

/// Settings and Group Configuration window.
@MainActor
public final class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    public static let shared = SettingsWindowController()

    private let groupTableView = NSTableView()
    private let itemTableView = NSTableView()
    private let addItemPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let concealCheckbox = NSButton(checkboxWithTitle: "Conceal grouped items in menu bar (camouflages original icons)", target: nil, action: nil)
    private let accessibilityStatusLabel = NSTextField(labelWithString: "")
    private let screenRecordingStatusLabel = NSTextField(labelWithString: "")

    private var selectedGroup: MenuBarGroup? {
        let index = groupTableView.selectedRow
        guard GroupManager.shared.groups.indices.contains(index) else { return nil }
        return GroupManager.shared.groups[index]
    }

    private var availableItems: [MenuBarItem] = []
    private var allScannedItems: [MenuBarItem] = []

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Menu Bar Groups Settings"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)

        setupUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func show() {
        refreshData()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupUI() {
        guard let window else { return }

        let tabView = NSTabView()
        tabView.tabViewType = .topTabsBezelBorder

        // Tab 1: Groups & Items
        let groupsTab = NSTabViewItem(identifier: "groups")
        groupsTab.label = "Groups & Items"
        groupsTab.view = createGroupsTabView()
        tabView.addTabViewItem(groupsTab)

        // Tab 2: General & Permissions
        let generalTab = NSTabViewItem(identifier: "general")
        generalTab.label = "General & Permissions"
        generalTab.view = createGeneralTabView()
        tabView.addTabViewItem(generalTab)

        window.contentView = tabView
    }

    private func createGroupsTabView() -> NSView {
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        // Left Pane: Groups List
        let leftView = NSView()
        let leftScroll = NSScrollView()
        leftScroll.documentView = groupTableView
        leftScroll.hasVerticalScroller = true
        leftScroll.translatesAutoresizingMaskIntoConstraints = false

        let groupCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("groupCol"))
        groupCol.title = "Groups"
        groupTableView.addTableColumn(groupCol)
        groupTableView.headerView = nil
        groupTableView.dataSource = self
        groupTableView.delegate = self
        groupTableView.rowHeight = 28

        let buttonBar = NSStackView()
        buttonBar.orientation = .horizontal
        buttonBar.spacing = 4
        buttonBar.translatesAutoresizingMaskIntoConstraints = false

        let addGroupButton = NSButton(title: "+", target: self, action: #selector(addGroupClicked))
        addGroupButton.bezelStyle = .smallSquare
        let removeGroupButton = NSButton(title: "-", target: self, action: #selector(removeGroupClicked))
        removeGroupButton.bezelStyle = .smallSquare
        buttonBar.addArrangedSubview(addGroupButton)
        buttonBar.addArrangedSubview(removeGroupButton)
        buttonBar.addArrangedSubview(NSView())

        leftView.addSubview(leftScroll)
        leftView.addSubview(buttonBar)
        NSLayoutConstraint.activate([
            leftScroll.topAnchor.constraint(equalTo: leftView.topAnchor),
            leftScroll.leadingAnchor.constraint(equalTo: leftView.leadingAnchor),
            leftScroll.trailingAnchor.constraint(equalTo: leftView.trailingAnchor),
            leftScroll.bottomAnchor.constraint(equalTo: buttonBar.topAnchor, constant: -4),

            buttonBar.leadingAnchor.constraint(equalTo: leftView.leadingAnchor, constant: 6),
            buttonBar.trailingAnchor.constraint(equalTo: leftView.trailingAnchor, constant: -6),
            buttonBar.bottomAnchor.constraint(equalTo: leftView.bottomAnchor, constant: -6),
            buttonBar.heightAnchor.constraint(equalToConstant: 24)
        ])

        // Right Pane: Items in selected group
        let rightView = NSView()
        let rightScroll = NSScrollView()
        rightScroll.documentView = itemTableView
        rightScroll.hasVerticalScroller = true
        rightScroll.translatesAutoresizingMaskIntoConstraints = false

        let itemCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("itemCol"))
        itemCol.title = "Assigned Items"
        itemTableView.addTableColumn(itemCol)
        itemTableView.dataSource = self
        itemTableView.delegate = self
        itemTableView.rowHeight = 32

        addItemPopUp.target = self
        addItemPopUp.action = #selector(addItemPopUpSelected(_:))
        addItemPopUp.translatesAutoresizingMaskIntoConstraints = false

        rightView.addSubview(rightScroll)
        rightView.addSubview(addItemPopUp)
        NSLayoutConstraint.activate([
            addItemPopUp.topAnchor.constraint(equalTo: rightView.topAnchor, constant: 8),
            addItemPopUp.leadingAnchor.constraint(equalTo: rightView.leadingAnchor, constant: 8),
            addItemPopUp.trailingAnchor.constraint(equalTo: rightView.trailingAnchor, constant: -8),

            rightScroll.topAnchor.constraint(equalTo: addItemPopUp.bottomAnchor, constant: 8),
            rightScroll.leadingAnchor.constraint(equalTo: rightView.leadingAnchor),
            rightScroll.trailingAnchor.constraint(equalTo: rightView.trailingAnchor),
            rightScroll.bottomAnchor.constraint(equalTo: rightView.bottomAnchor)
        ])

        splitView.addSubview(leftView)
        splitView.addSubview(rightView)
        splitView.setPosition(180, ofDividerAt: 0)

        return splitView
    }

    private func createGeneralTabView() -> NSView {
        let view = NSView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let launchHeading = NSTextField(labelWithString: "Startup")
        launchHeading.font = .boldSystemFont(ofSize: 13)

        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(toggleLaunchAtLogin(_:))
        launchAtLoginCheckbox.state = (SMAppService.mainApp.status == .enabled) ? .on : .off

        let behaviorHeading = NSTextField(labelWithString: "Menu Bar Behavior")
        behaviorHeading.font = .boldSystemFont(ofSize: 13)

        concealCheckbox.target = self
        concealCheckbox.action = #selector(toggleConcealmentSetting(_:))
        concealCheckbox.state = CurtainOverlayManager.shared.isEnabled ? .on : .off

        let shortcutHeading = NSTextField(labelWithString: "Global Shortcuts")
        shortcutHeading.font = .boldSystemFont(ofSize: 13)

        let shortcutLabel = NSTextField(labelWithString: "Command Bar: ⌘ + Shift + Space")
        shortcutLabel.textColor = .secondaryLabelColor

        let permissionsHeading = NSTextField(labelWithString: "System Permissions")
        permissionsHeading.font = .boldSystemFont(ofSize: 13)

        let openAXButton = NSButton(title: "Open Accessibility Settings…", target: self, action: #selector(openAXSettings))
        openAXButton.bezelStyle = .rounded

        let openScreenButton = NSButton(title: "Open Screen Recording Settings…", target: self, action: #selector(openScreenSettings))
        openScreenButton.bezelStyle = .rounded

        stack.addArrangedSubview(launchHeading)
        stack.addArrangedSubview(launchAtLoginCheckbox)
        stack.addArrangedSubview(behaviorHeading)
        stack.addArrangedSubview(concealCheckbox)
        stack.addArrangedSubview(shortcutHeading)
        stack.addArrangedSubview(shortcutLabel)
        stack.addArrangedSubview(permissionsHeading)
        stack.addArrangedSubview(accessibilityStatusLabel)
        stack.addArrangedSubview(openAXButton)
        stack.addArrangedSubview(screenRecordingStatusLabel)
        stack.addArrangedSubview(openScreenButton)

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        updatePermissionLabels()
        return view
    }

    @objc private func toggleConcealmentSetting(_ sender: NSButton) {
        CurtainOverlayManager.shared.isEnabled = (sender.state == .on)
        GroupManager.shared.refreshConcealmentOverlays()
    }

    private func updatePermissionLabels() {
        let axGranted = AXIsProcessTrusted()
        accessibilityStatusLabel.stringValue = "Accessibility (for opening menus & status items): " + (axGranted ? "✓ Granted" : "⚠️ Not Granted")
        accessibilityStatusLabel.textColor = axGranted ? .systemGreen : .systemOrange

        let screenGranted = CGPreflightScreenCaptureAccess()
        screenRecordingStatusLabel.stringValue = "Screen Recording (optional, for live status icons): " + (screenGranted ? "✓ Granted" : "Not Granted (uses app icons)")
        screenRecordingStatusLabel.textColor = screenGranted ? .systemGreen : .secondaryLabelColor
    }

    @objc private func openAXSettings() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openScreenSettings() {
        _ = CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSButton) {
        do {
            if sender.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            sender.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        }
    }

    private func refreshData() {
        allScannedItems = MenuBarScanner.shared.scan()
        groupTableView.reloadData()
        if groupTableView.selectedRow < 0 && !GroupManager.shared.groups.isEmpty {
            groupTableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        concealCheckbox.state = CurtainOverlayManager.shared.isEnabled ? .on : .off
        refreshItemsView()
        updatePermissionLabels()
    }

    private func refreshItemsView() {
        itemTableView.reloadData()
        updateAddItemPopUp()
    }

    private var selectedGroupItems: [MenuBarItem] {
        guard let group = selectedGroup else { return [] }
        return GroupManager.shared.resolvedItems(for: group, allScanned: allScannedItems)
    }

    private func updateAddItemPopUp() {
        addItemPopUp.removeAllItems()
        addItemPopUp.addItem(withTitle: "Add item to this group…")

        guard selectedGroup != nil else {
            addItemPopUp.isEnabled = false
            return
        }

        let currentIDs = Set(selectedGroupItems.map(\.id))
        availableItems = allScannedItems.filter { !currentIDs.contains($0.id) }
        addItemPopUp.isEnabled = !availableItems.isEmpty

        for item in availableItems {
            addItemPopUp.addItem(withTitle: item.name + (item.ordinal > 0 ? " (\(item.ordinal + 1))" : ""))
        }
    }

    @objc private func addItemPopUpSelected(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem - 1
        guard availableItems.indices.contains(index), let group = selectedGroup else { return }
        let selectedItem = availableItems[index]
        GroupManager.shared.addItem(selectedItem.id, toGroupID: group.id)
        refreshData()
    }

    @objc private func addGroupClicked() {
        let alert = NSAlert()
        alert.messageText = "Create New Menu Bar Group"
        alert.informativeText = "Enter a name for the group:"
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        input.stringValue = "New Group"
        alert.accessoryView = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        GroupManager.shared.addGroup(title: name, symbolName: "folder.fill")
        refreshData()
        let newIndex = GroupManager.shared.groups.count - 1
        groupTableView.selectRowIndexes(IndexSet(integer: newIndex), byExtendingSelection: false)
    }

    @objc private func removeGroupClicked() {
        guard let group = selectedGroup else { return }
        GroupManager.shared.removeGroup(id: group.id)
        refreshData()
    }

    // MARK: - NSTableView Delegate & DataSource

    public func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === groupTableView {
            return GroupManager.shared.groups.count
        } else {
            return selectedGroupItems.count
        }
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === groupTableView {
            let group = GroupManager.shared.groups[row]
            let cell = NSTableCellView()
            let label = NSTextField(labelWithString: " \(group.title)")
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        } else {
            let items = selectedGroupItems
            guard items.indices.contains(row) else { return nil }
            let item = items[row]

            let cell = NSTableCellView()
            let iconView = NSImageView()
            iconView.image = IconManager.shared.icon(for: item)
            iconView.translatesAutoresizingMaskIntoConstraints = false

            let label = NSTextField(labelWithString: item.name + (item.ordinal > 0 ? " (\(item.ordinal + 1))" : ""))
            label.translatesAutoresizingMaskIntoConstraints = false

            let removeButton = NSButton(title: "×", target: self, action: #selector(removeItemFromGroup(_:)))
            removeButton.bezelStyle = .inline
            removeButton.tag = row
            removeButton.translatesAutoresizingMaskIntoConstraints = false

            cell.addSubview(iconView)
            cell.addSubview(label)
            cell.addSubview(removeButton)

            NSLayoutConstraint.activate([
                iconView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                iconView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 20),
                iconView.heightAnchor.constraint(equalToConstant: 20),

                label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),

                removeButton.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                removeButton.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                removeButton.widthAnchor.constraint(equalToConstant: 20)
            ])
            return cell
        }
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        if (notification.object as? NSTableView) === groupTableView {
            refreshItemsView()
        }
    }

    @objc private func removeItemFromGroup(_ sender: NSButton) {
        guard let group = selectedGroup else { return }
        let items = selectedGroupItems
        guard items.indices.contains(sender.tag) else { return }
        let item = items[sender.tag]
        GroupManager.shared.removeItem(item.id, fromGroupID: group.id)
        refreshData()
    }
}
