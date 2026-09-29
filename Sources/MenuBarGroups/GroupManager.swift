import AppKit
import ServiceManagement

/// Central state manager for menu bar groups and status items.
@MainActor
public final class GroupManager {
    public static let shared = GroupManager()

    public private(set) var groups: [MenuBarGroup] = []

    private var groupStatusItems: [UUID: NSStatusItem] = [:]
    private var mainStatusItem: NSStatusItem?

    private let secondaryBar = SecondaryBarWindow()
    private let defaultsKey = "com.example.MenuBarGroups.groups"

    private init() {
        loadGroups()
    }

    public func start() {
        setupMainStatusItem()
        setupGroupStatusItems()

        // Register global hotkey for Command Bar (⌘⇧Space)
        HotKeyManager.shared.register {
            CommandBarWindow.shared.toggle()
        }
    }

    // MARK: - Persistence & Setup

    private func loadGroups() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode([MenuBarGroup].self, from: data) {
            groups = saved
            for i in groups.indices {
                if groups[i].title.localizedCaseInsensitiveContains("storage") && groups[i].autoTrackCategory == .none {
                    groups[i].autoTrackCategory = .storage
                }
            }
        } else {
            provisionDefaultGroups()
        }
    }

    public func saveGroups() {
        if let data = try? JSONEncoder().encode(groups) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
        setupGroupStatusItems()
    }

    private func provisionDefaultGroups() {
        let storageGroup = MenuBarGroup(
            title: "Storage",
            symbolName: "externaldrive.connected.to.line.below.fill",
            itemIDs: [],
            autoTrackCategory: .storage
        )

        let utilitiesGroup = MenuBarGroup(
            title: "Utilities",
            symbolName: "slider.horizontal.3",
            itemIDs: [],
            autoTrackCategory: .none
        )

        groups = [storageGroup, utilitiesGroup]
        saveGroups()
    }

    // MARK: - Item Resolution

    /// Resolves all items belonging to a group, taking auto-tracking into account.
    public func resolvedItems(for group: MenuBarGroup, allScanned: [MenuBarItem]) -> [MenuBarItem] {
        var items: [MenuBarItem] = []
        var seenIDs = Set<String>()

        if group.autoTrackCategory == .storage {
            for item in allScanned {
                if KnownApps.isStorageApp(bundleID: item.bundleIdentifier, name: item.name) {
                    items.append(item)
                    seenIDs.insert(item.id)
                }
            }
        }

        for itemID in group.itemIDs {
            if !seenIDs.contains(itemID), let item = allScanned.first(where: { $0.id == itemID }) {
                items.append(item)
                seenIDs.insert(itemID)
            }
        }

        return items
    }

    // MARK: - Primary Status Item

    private func setupMainStatusItem() {
        if mainStatusItem == nil {
            mainStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }
        guard let button = mainStatusItem?.button else { return }

        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        button.image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: "Menu Bar Groups")?.withSymbolConfiguration(symbolConfig)
        button.toolTip = "Menu Bar Groups (Click for Menu, ⌘⇧Space for Command Bar)"
        button.target = self
        button.action = #selector(mainStatusItemClicked)
    }

    @objc private func mainStatusItemClicked() {
        let menu = NSMenu()
        let commandBarItem = NSMenuItem(title: "Command Bar…", action: #selector(openCommandBar), keyEquivalent: " ")
        commandBarItem.keyEquivalentModifierMask = [.command, .shift]
        commandBarItem.target = self
        menu.addItem(commandBarItem)

        let refreshItem = NSMenuItem(title: "Refresh Menu Bar Items", action: #selector(refreshAll), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())

        let newGroupItem = NSMenuItem(title: "Create New Group…", action: #selector(promptNewGroup), keyEquivalent: "n")
        newGroupItem.target = self
        menu.addItem(newGroupItem)

        let settingsItem = NSMenuItem(title: "Manage Groups…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Menu Bar Groups", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        mainStatusItem?.menu = menu
        mainStatusItem?.button?.performClick(nil)
        mainStatusItem?.menu = nil
    }

    @objc private func openCommandBar() {
        CommandBarWindow.shared.show()
    }

    @objc private func refreshAll() {
        _ = MenuBarScanner.shared.scan()
        setupGroupStatusItems()
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Individual Group Status Items

    private func setupGroupStatusItems() {
        let activeIDs = Set(groups.map(\.id))
        for (id, item) in groupStatusItems where !activeIDs.contains(id) {
            NSStatusBar.system.removeStatusItem(item)
            groupStatusItems.removeValue(forKey: id)
        }

        for group in groups {
            let statusItem = groupStatusItems[group.id] ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            groupStatusItems[group.id] = statusItem

            guard let button = statusItem.button else { continue }
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            button.image = NSImage(systemSymbolName: group.symbolName, accessibilityDescription: group.title)?.withSymbolConfiguration(config)
            button.imagePosition = .imageLeading
            button.title = " \(group.title)"
            button.toolTip = "\(group.title) (Click to show items, right-click for options)"

            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            objc_setAssociatedObject(button, "groupID", group.id, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            button.target = self
            button.action = #selector(groupButtonClicked(_:))
        }
    }

    @objc private func groupButtonClicked(_ sender: NSStatusBarButton) {
        guard let groupID = objc_getAssociatedObject(sender, "groupID") as? UUID,
              let group = groups.first(where: { $0.id == groupID }) else { return }

        let currentEvent = NSApp.currentEvent
        if currentEvent?.type == .rightMouseUp || (currentEvent?.modifierFlags.contains(.control) ?? false) {
            showGroupContextMenu(for: group, in: sender)
            return
        }

        if secondaryBar.isVisible {
            secondaryBar.orderOut(nil)
            return
        }

        displaySecondaryBar(for: group, beneath: sender)
    }

    private func displaySecondaryBar(for group: MenuBarGroup, beneath button: NSStatusBarButton) {
        let allScanned = MenuBarScanner.shared.scan()
        let matchingItems = resolvedItems(for: group, allScanned: allScanned)

        secondaryBar.update(
            group: group,
            items: matchingItems,
            allAvailableItems: allScanned,
            onSelect: { selectedItem in
                InteractionEngine.shared.activate(item: selectedItem)
            },
            onToggleItem: { [weak self, weak button] itemID in
                guard let self, let button else { return }
                self.toggleItem(itemID, inGroupID: group.id)
                if let updatedGroup = self.groups.first(where: { $0.id == group.id }) {
                    self.displaySecondaryBar(for: updatedGroup, beneath: button)
                }
            },
            onRenameGroup: { [weak self] in
                self?.promptRenameGroup(id: group.id)
            },
            onDeleteGroup: { [weak self] in
                self?.removeGroup(id: group.id)
            },
            onNewGroup: { [weak self] in
                self?.promptNewGroup()
            }
        )
        secondaryBar.show(beneath: button)
    }

    private func showGroupContextMenu(for group: MenuBarGroup, in button: NSStatusBarButton) {
        let menu = NSMenu(title: group.title)

        let titleItem = NSMenuItem(title: "\(group.title) Group", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())

        let renameItem = NSMenuItem(title: "Rename Group…", action: #selector(contextRenameClicked(_:)), keyEquivalent: "")
        renameItem.target = self
        objc_setAssociatedObject(renameItem, "groupID", group.id, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        menu.addItem(renameItem)

        let newGroupItem = NSMenuItem(title: "Create New Group…", action: #selector(promptNewGroup), keyEquivalent: "")
        newGroupItem.target = self
        menu.addItem(newGroupItem)

        let deleteItem = NSMenuItem(title: "Delete Group", action: #selector(contextDeleteClicked(_:)), keyEquivalent: "")
        deleteItem.target = self
        objc_setAssociatedObject(deleteItem, "groupID", group.id, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        menu.addItem(deleteItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Manage All Groups…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 2), in: button)
    }

    @objc private func contextRenameClicked(_ sender: NSMenuItem) {
        guard let groupID = objc_getAssociatedObject(sender, "groupID") as? UUID else { return }
        promptRenameGroup(id: groupID)
    }

    @objc private func contextDeleteClicked(_ sender: NSMenuItem) {
        guard let groupID = objc_getAssociatedObject(sender, "groupID") as? UUID else { return }
        removeGroup(id: groupID)
    }

    // MARK: - Interactive Dialogs

    public func promptRenameGroup(id: UUID) {
        guard let group = groups.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = "Rename Group"
        alert.informativeText = "Enter a new label for “\(group.title)”:"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        input.stringValue = group.title
        alert.accessoryView = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newName = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newName.isEmpty {
            renameGroup(id: id, newTitle: newName)
        }
    }

    @objc public func promptNewGroup() {
        let alert = NSAlert()
        alert.messageText = "Create New Menu Bar Group"
        alert.informativeText = "Enter a label for the new group (e.g. Media, Network, Dev):"
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        input.stringValue = "New Group"
        alert.accessoryView = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            addGroup(title: name, symbolName: "folder.fill")
        }
    }

    // MARK: - Group Mutation API

    public func addGroup(title: String, symbolName: String) {
        let newGroup = MenuBarGroup(title: title, symbolName: symbolName, itemIDs: [])
        groups.append(newGroup)
        saveGroups()
    }

    public func renameGroup(id: UUID, newTitle: String) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].title = newTitle
        saveGroups()
    }

    public func removeGroup(id: UUID) {
        groups.removeAll { $0.id == id }
        saveGroups()
    }

    public func toggleItem(_ itemID: String, inGroupID groupID: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        if groups[index].itemIDs.contains(itemID) {
            groups[index].itemIDs.removeAll { $0 == itemID }
        } else {
            groups[index].itemIDs.append(itemID)
        }
        saveGroups()
    }

    public func addItem(_ itemID: String, toGroupID groupID: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        if !groups[index].itemIDs.contains(itemID) {
            groups[index].itemIDs.append(itemID)
            saveGroups()
        }
    }

    public func removeItem(_ itemID: String, fromGroupID groupID: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[index].itemIDs.removeAll { $0 == itemID }
        saveGroups()
    }
}
