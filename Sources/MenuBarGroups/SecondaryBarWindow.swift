import AppKit

/// A sleek floating sub-bar that appears beneath the menu bar to show grouped items,
/// with direct controls to add/remove items and manage group labels.
@MainActor
public final class SecondaryBarWindow: NSPanel {
    private let visualEffectView = NSVisualEffectView()
    private let stackView = NSStackView()
    private var onSelect: ((MenuBarItem) -> Void)?
    private var onToggleItem: ((String) -> Void)?
    private var onRenameGroup: (() -> Void)?
    private var onDeleteGroup: (() -> Void)?
    private var onNewGroup: (() -> Void)?

    private var currentGroup: MenuBarGroup?
    private var currentItems: [MenuBarItem] = []
    private var allAvailableItems: [MenuBarItem] = []

    public init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 42),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.transient, .ignoresCycle]

        setupView()
    }

    private func setupView() {
        visualEffectView.material = .popover
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 10
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.2).cgColor
        visualEffectView.layer?.borderWidth = 1

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 8
        stackView.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        visualEffectView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor)
        ])

        contentView = visualEffectView
    }

    /// Updates the items and controls displayed in the secondary sub-bar.
    public func update(
        group: MenuBarGroup,
        items: [MenuBarItem],
        allAvailableItems: [MenuBarItem],
        onSelect: @escaping (MenuBarItem) -> Void,
        onToggleItem: @escaping (String) -> Void,
        onRenameGroup: @escaping () -> Void,
        onDeleteGroup: @escaping () -> Void,
        onNewGroup: @escaping () -> Void
    ) {
        self.currentGroup = group
        self.currentItems = items
        self.allAvailableItems = allAvailableItems
        self.onSelect = onSelect
        self.onToggleItem = onToggleItem
        self.onRenameGroup = onRenameGroup
        self.onDeleteGroup = onDeleteGroup
        self.onNewGroup = onNewGroup

        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        // 1. Group Label & Icon
        let groupLabel = NSTextField(labelWithString: group.title)
        groupLabel.font = .systemFont(ofSize: 12, weight: .bold)
        groupLabel.textColor = .secondaryLabelColor
        stackView.addArrangedSubview(groupLabel)

        // Subtle divider
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 18).isActive = true
        stackView.addArrangedSubview(divider)

        // 2. Active Items or Placeholder
        if items.isEmpty {
            let label = NSTextField(labelWithString: "No items (click + to add)")
            label.font = .systemFont(ofSize: 12)
            label.textColor = .tertiaryLabelColor
            stackView.addArrangedSubview(label)
        } else {
            for item in items {
                let button = createItemButton(for: item)
                stackView.addArrangedSubview(button)
            }
        }

        // 3. Quick "+" Add Button
        let addButton = NSButton(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        addButton.bezelStyle = .inline
        addButton.title = "+"
        addButton.font = .systemFont(ofSize: 14, weight: .medium)
        addButton.toolTip = "Add / remove items in \(group.title)"
        addButton.target = self
        addButton.action = #selector(addButtonClicked(_:))
        addButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            addButton.widthAnchor.constraint(equalToConstant: 24),
            addButton.heightAnchor.constraint(equalToConstant: 24)
        ])
        stackView.addArrangedSubview(addButton)

        // 4. Group Options "•••" Button
        let optionsButton = NSButton(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        optionsButton.bezelStyle = .inline
        optionsButton.title = "•••"
        optionsButton.font = .systemFont(ofSize: 11, weight: .regular)
        optionsButton.toolTip = "Group options (rename, new group, settings)"
        optionsButton.target = self
        optionsButton.action = #selector(optionsButtonClicked(_:))
        optionsButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            optionsButton.widthAnchor.constraint(equalToConstant: 24),
            optionsButton.heightAnchor.constraint(equalToConstant: 24)
        ])
        stackView.addArrangedSubview(optionsButton)

        stackView.layoutSubtreeIfNeeded()
        let fitting = stackView.fittingSize
        setContentSize(NSSize(width: max(fitting.width, 140), height: 42))
    }

    private func createItemButton(for item: MenuBarItem) -> NSButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        button.isBordered = false
        button.image = IconManager.shared.icon(for: item)
        button.imageScaling = .scaleProportionallyDown
        button.imagePosition = .imageOnly
        button.toolTip = "\(item.name)\nClick to open menu\nRight-click for options"
        button.target = self
        button.action = #selector(itemClicked(_:))

        // Hover styling
        button.wantsLayer = true
        button.layer?.cornerRadius = 6

        objc_setAssociatedObject(button, "menuBarItem", item, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 28)
        ])

        return button
    }

    @objc private func itemClicked(_ sender: NSButton) {
        if let item = objc_getAssociatedObject(sender, "menuBarItem") as? MenuBarItem {
            orderOut(nil)
            onSelect?(item)
        }
    }

    @objc private func addButtonClicked(_ sender: NSButton) {
        guard let group = currentGroup else { return }
        let menu = NSMenu(title: "Add to Group")

        let header = NSMenuItem(title: "Items in \(group.title):", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(NSMenuItem.separator())

        for item in allAvailableItems {
            let isInGroup = currentItems.contains(where: { $0.id == item.id })
            let title = item.name + (item.ordinal > 0 ? " (\(item.ordinal + 1))" : "")
            let menuItem = NSMenuItem(title: title, action: #selector(toggleItemClicked(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.state = isInGroup ? .on : .off
            if let icon = IconManager.shared.icon(for: item).copy() as? NSImage {
                icon.size = NSSize(width: 16, height: 16)
                menuItem.image = icon
            }
            objc_setAssociatedObject(menuItem, "itemID", item.id, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            menu.addItem(menuItem)
        }

        if allAvailableItems.isEmpty {
            let emptyItem = NSMenuItem(title: "No menu bar items detected (grant Accessibility in Settings)", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func toggleItemClicked(_ sender: NSMenuItem) {
        guard let itemID = objc_getAssociatedObject(sender, "itemID") as? String else { return }
        onToggleItem?(itemID)
    }

    @objc private func optionsButtonClicked(_ sender: NSButton) {
        let menu = NSMenu(title: "Group Options")

        let renameItem = NSMenuItem(title: "Rename Group…", action: #selector(renameClicked), keyEquivalent: "")
        renameItem.target = self
        menu.addItem(renameItem)

        let newGroupItem = NSMenuItem(title: "Create New Group…", action: #selector(newGroupClicked), keyEquivalent: "")
        newGroupItem.target = self
        menu.addItem(newGroupItem)

        let deleteItem = NSMenuItem(title: "Delete Group", action: #selector(deleteClicked), keyEquivalent: "")
        deleteItem.target = self
        menu.addItem(deleteItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Manage All Groups…", action: #selector(openSettingsClicked), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func renameClicked() {
        orderOut(nil)
        onRenameGroup?()
    }

    @objc private func newGroupClicked() {
        orderOut(nil)
        onNewGroup?()
    }

    @objc private func deleteClicked() {
        orderOut(nil)
        onDeleteGroup?()
    }

    @objc private func openSettingsClicked() {
        orderOut(nil)
        SettingsWindowController.shared.show()
    }

    /// Positions the sub-bar beneath an anchor status item button.
    public func show(beneath button: NSStatusBarButton) {
        guard let window = button.window else { return }
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = window.convertToScreen(buttonRect)

        let barSize = frame.size
        let screen = window.screen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? .zero

        let preferredX = screenRect.midX - (barSize.width / 2)
        let clampedX = min(max(preferredX, visibleFrame.minX + 8), visibleFrame.maxX - barSize.width - 8)
        let targetY = screenRect.minY - barSize.height - 4

        setFrameOrigin(NSPoint(x: clampedX, y: targetY))
        makeKeyAndOrderFront(nil)
    }

    public override func resignKey() {
        super.resignKey()
        orderOut(nil)
    }
}
