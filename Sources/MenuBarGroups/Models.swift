import AppKit
import CoreGraphics

/// Represents a detected status item in the macOS menu bar.
public struct MenuBarItem: Identifiable, Sendable {
    public let id: String // Stable key, e.g. "com.microsoft.OneDrive:0"
    public let name: String
    public let ownerPID: pid_t
    public let bundleIdentifier: String?
    public let ordinal: Int
    public let frame: CGRect
    public let appIcon: NSImage?
    public let cgWindowID: CGWindowID
    public let isAXOnly: Bool

    public init(
        id: String,
        name: String,
        ownerPID: pid_t,
        bundleIdentifier: String?,
        ordinal: Int,
        frame: CGRect,
        appIcon: NSImage?,
        cgWindowID: CGWindowID,
        isAXOnly: Bool
    ) {
        self.id = id
        self.name = name
        self.ownerPID = ownerPID
        self.bundleIdentifier = bundleIdentifier
        self.ordinal = ordinal
        self.frame = frame
        self.appIcon = appIcon
        self.cgWindowID = cgWindowID
        self.isAXOnly = isAXOnly
    }
}

/// Category for automatic dynamic item tracking.
public enum AutoTrackCategory: String, Codable, Sendable {
    case none
    case storage
}

/// A user-defined group of menu bar items (e.g. "Storage", "Utilities", "Hidden").
public struct MenuBarGroup: Codable, Identifiable, Equatable {
    public let id: UUID
    public var title: String
    public var symbolName: String
    public var itemIDs: [String] // Matched against MenuBarItem.id
    public var autoTrackCategory: AutoTrackCategory
    public var hideWhenInactive: Bool
    public var concealItems: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, symbolName, itemIDs, autoTrackCategory, hideWhenInactive, concealItems
    }

    public init(
        id: UUID = UUID(),
        title: String,
        symbolName: String,
        itemIDs: [String] = [],
        autoTrackCategory: AutoTrackCategory = .none,
        hideWhenInactive: Bool = false,
        concealItems: Bool = true
    ) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.itemIDs = itemIDs
        self.autoTrackCategory = autoTrackCategory
        self.hideWhenInactive = hideWhenInactive
        self.concealItems = concealItems
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        symbolName = try container.decode(String.self, forKey: .symbolName)
        itemIDs = try container.decode([String].self, forKey: .itemIDs)
        autoTrackCategory = try container.decodeIfPresent(AutoTrackCategory.self, forKey: .autoTrackCategory) ?? .none
        hideWhenInactive = try container.decodeIfPresent(Bool.self, forKey: .hideWhenInactive) ?? false
        concealItems = try container.decodeIfPresent(Bool.self, forKey: .concealItems) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(symbolName, forKey: .symbolName)
        try container.encode(itemIDs, forKey: .itemIDs)
        try container.encode(autoTrackCategory, forKey: .autoTrackCategory)
        try container.encode(hideWhenInactive, forKey: .hideWhenInactive)
        try container.encode(concealItems, forKey: .concealItems)
    }
}

/// Known storage and utility bundle identifiers for smart auto-grouping.
public enum KnownApps {
    public static let storageBundlePrefixes = [
        "com.microsoft.OneDrive",
        "com.getdropbox.dropbox",
        "com.google.drivefs",
        "com.google.GoogleDrive",
        "ch.protonmail.drive",
        "com.synology.CloudStationBackup",
        "com.synology.CloudStationUI",
        "com.synology.SynologyDrive",
        "com.box.desktop",
        "com.nextcloud.desktopclient",
        "com.owncloud.desktopclient",
        "com.pcloud.pcloudapp"
    ]

    public static func isStorageApp(bundleID: String?, name: String) -> Bool {
        if let bundleID {
            for prefix in storageBundlePrefixes where bundleID.localizedCaseInsensitiveContains(prefix) {
                return true
            }
        }
        let lower = name.lowercased()
        return lower.contains("onedrive") || lower.contains("dropbox") || lower.contains("google drive") ||
               lower.contains("proton drive") || lower.contains("synology") || lower.contains("nextcloud") ||
               lower.contains("owncloud") || lower.contains("pcloud") || lower.contains("box") ||
               lower.contains("drive")
    }
}
