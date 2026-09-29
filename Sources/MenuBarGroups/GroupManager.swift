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
        } else {
            // First run: provision smart default groups
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
        let scanned = MenuBarScanner.shared.scan()
        var storageItemIDs: [String] = []

        for item in scanned {
            if KnownApps.isStorageApp(bundleID: item.bundleIdentifier, name: item.name) {
                storageItemIDs.append(item.id)
            }
        }

        let storageGroup = MenuBarGroup(
            title: "Storage",
            symbolName: "externaldrive.connected.to.line.below.fill",
            itemIDs: storageItemIDs
        )

        let utilitiesGroup = MenuBarGroup(
            title: "Utilities",
            symbolName: "slider.horizontal.3",
            itemIDs: []
        )

        groups = [storageGroup, utilitiesGroup]
        saveGroups()
    }

    // MARK: - Menu Bar Status Items

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

        let settingsItem = NSMenuItem(title: "Manage Groups…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Menu Bar Groups", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        mainStatusItem?.menu = menu
        mainStatusItem?.button?.performClick(nil)
        mainStatusItem?.menu = nil // Restore toggle behavior
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
        // Remove obsolete status items
        let activeIDs = Set(groups.map(\.id))
        for (id, item) in groupStatusItems where !activeIDs.contains(id) {
            NSStatusBar.system.removeStatusItem(item)
            groupStatusItems.removeValue(forKey: id)
        }

        // Add or update status items for each group
        for group in groups {
            let statusItem = groupStatusItems[group.id] ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            groupStatusItems[group.id] = statusItem

            guard let button = statusItem.button else { continue }
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            button.image = NSImage(systemSymbolName: group.symbolName, accessibilityDescription: group.title)?.withSymbolConfiguration(config)
            button.imagePosition = .imageLeading
            button.title = " \(group.title)"
            button.toolTip = "\(group.title) Group"

            objc_setAssociatedObject(button, "groupID", group.id, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            button.target = self
            button.action = #selector(groupButtonClicked(_:))
        }
    }

    @objc private func groupButtonClicked(_ sender: NSStatusBarButton) {
        guard let groupID = objc_getAssociatedObject(sender, "groupID") as? UUID,
              let group = groups.first(where: { $0.id == groupID }) else { return }

        if secondaryBar.isVisible {
            secondaryBar.orderOut(nil)
            return
        }

        let allScanned = MenuBarScanner.shared.scan()
        let matchingItems = allScanned.filter { group.itemIDs.contains($0.id) }

        secondaryBar.update(items: matchingItems) { selectedItem in
            InteractionEngine.shared.activate(item: selectedItem)
        }
        secondaryBar.show(beneath: sender)
    }

    // MARK: - Group Mutation API

    public func addGroup(title: String, symbolName: String) {
        let newGroup = MenuBarGroup(title: title, symbolName: symbolName, itemIDs: [])
        groups.append(newGroup)
        saveGroups()
    }

    public func removeGroup(id: UUID) {
        groups.removeAll { $0.id == id }
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
