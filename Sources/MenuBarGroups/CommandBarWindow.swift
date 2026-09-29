import AppKit

/// A Spotlight/Raycast-style Command Bar for searching and triggering menu bar items by keyboard.
@MainActor
public final class CommandBarWindow: NSPanel, NSTextFieldDelegate, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    public static let shared = CommandBarWindow()

    private let visualEffectView = NSVisualEffectView()
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private var allItems: [MenuBarItem] = []
    private var filteredItems: [MenuBarItem] = []

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 260),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .modalPanel
        isMovableByWindowBackground = true

        setupView()
    }

    private func setupView() {
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 14
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.25).cgColor
        visualEffectView.layer?.borderWidth = 1

        searchField.placeholderString = "Search menu bar items..."
        searchField.font = .systemFont(ofSize: 15)
        searchField.focusRingType = .none
        searchField.bezelStyle = .roundedBezel
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("itemColumn"))
        column.isEditable = false
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowHeight = 36
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(tableRowDoubleClicked)

        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        visualEffectView.addSubview(searchField)
        visualEffectView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: visualEffectView.topAnchor, constant: 14),
            searchField.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 14),
            searchField.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -14),
            searchField.heightAnchor.constraint(equalToConstant: 32),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 10),
            scrollView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -10),
            scrollView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor, constant: -12)
        ])

        contentView = visualEffectView
    }

    /// Shows the Command Bar centered on screen with fresh items.
    public func toggle() {
        if isVisible {
            orderOut(nil)
        } else {
            show()
        }
    }

    public func show() {
        allItems = MenuBarScanner.shared.scan()
        searchField.stringValue = ""
        filterItems()
        center()
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        makeFirstResponder(searchField)
    }

    private func filterItems() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            filteredItems = allItems
        } else {
            filteredItems = allItems.filter {
                $0.name.lowercased().contains(query) ||
                ($0.bundleIdentifier?.lowercased().contains(query) ?? false)
            }
        }
        tableView.reloadData()
        if !filteredItems.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    public func controlTextDidChange(_ obj: Notification) {
        filterItems()
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            triggerSelected()
            return true
        } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            orderOut(nil)
            return true
        } else if commandSelector == #selector(NSResponder.moveDown(_:)) {
            let next = min(tableView.selectedRow + 1, filteredItems.count - 1)
            if next >= 0 { tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false) }
            return true
        } else if commandSelector == #selector(NSResponder.moveUp(_:)) {
            let prev = max(tableView.selectedRow - 1, 0)
            if prev < filteredItems.count { tableView.selectRowIndexes(IndexSet(integer: prev), byExtendingSelection: false) }
            return true
        }
        return false
    }

    @objc private func tableRowDoubleClicked() {
        triggerSelected()
    }

    private func triggerSelected() {
        let index = tableView.selectedRow
        guard filteredItems.indices.contains(index) else { return }
        let selectedItem = filteredItems[index]
        orderOut(nil)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            InteractionEngine.shared.activate(item: selectedItem)
        }
    }

    public func numberOfRows(in tableView: NSTableView) -> Int {
        filteredItems.count
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard filteredItems.indices.contains(row) else { return nil }
        let item = filteredItems[row]

        let cellIdentifier = NSUserInterfaceItemIdentifier("CommandBarCell")
        var cellView = tableView.makeView(withIdentifier: cellIdentifier, owner: nil) as? NSTableCellView

        if cellView == nil {
            cellView = NSTableCellView()
            cellView?.identifier = cellIdentifier

            let iconView = NSImageView()
            iconView.imageScaling = .scaleProportionallyDown
            iconView.translatesAutoresizingMaskIntoConstraints = false
            cellView?.addSubview(iconView)
            cellView?.imageView = iconView

            let textField = NSTextField(labelWithString: "")
            textField.font = .systemFont(ofSize: 13, weight: .medium)
            textField.translatesAutoresizingMaskIntoConstraints = false
            cellView?.addSubview(textField)
            cellView?.textField = textField

            NSLayoutConstraint.activate([
                iconView.leadingAnchor.constraint(equalTo: cellView!.leadingAnchor, constant: 6),
                iconView.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 22),
                iconView.heightAnchor.constraint(equalToConstant: 22),

                textField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
                textField.trailingAnchor.constraint(equalTo: cellView!.trailingAnchor, constant: -6),
                textField.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor)
            ])
        }

        cellView?.imageView?.image = IconManager.shared.icon(for: item)
        cellView?.textField?.stringValue = item.name + (item.ordinal > 0 ? " (\(item.ordinal + 1))" : "")
        return cellView
    }

    public override func resignKey() {
        super.resignKey()
        orderOut(nil)
    }
}
