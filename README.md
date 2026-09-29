# Menu Bar Groups

**Current build:** a popup proof of concept that detects currently visible third-party menu-bar item windows, lets you add selected items to a persistent list, and can click through to their original location with Accessibility permission. A OneDrive-only hiding test was attempted and **paused after it failed** on macOS 27; the current build does not hide existing icons. A separate optional test captures the status-icon image with Screen Recording only when macOS exposes a capturable window. It also retains the older `.app` shortcut-group prototype. **It does not yet remove any original icons from the menu bar or display live item artwork.**

**Product direction:** a custom manager for a crowded macOS menu bar, inspired by tools that keep existing third-party status items reachable behind a compact control. Storage apps are the first intended group. See [the design and research plan](docs/menu-bar-manager.md) and the [OneDrive placement safety review](docs/onedrive-placement-safety-review.md) (currently no-go pending independent recovery).

> **Prototype behavior:** A short setup window confirms that the app started. Close it to use the popup. The status item is labelled **Items** and lives on the right side of the macOS menu bar. A welcome-window ownership fix addresses a crash reported when clicking Continue; closing the window and using Items still need interactive verification.

## Requirements

- macOS 14 or later
- Xcode Command Line Tools or Xcode, including Swift

## Run from source

From this directory:

```sh
swift run
```

A setup window should appear. Close it, then click **Items** in the top-right menu bar.

## Build an app bundle

```sh
chmod +x scripts/build-app.sh
scripts/build-app.sh
open .build/MenuBarGroups.app
```

For persistent macOS Device Control/Accessibility permission during development, build with a **stable Apple Development signing identity** from your keychain:

```sh
security find-identity -v -p codesigning
MENU_BAR_GROUPS_SIGN_IDENTITY="<certificate SHA-1 or name>" scripts/build-app.sh
open .build/MenuBarGroups.app
```

This is optional and local to your machine; the unsigned/ad-hoc prototype remains buildable without a certificate. After switching signing identity, grant **Menu Bar Groups** permission again in System Settings → Privacy & Security → Device Control and Data Access and restart it. Rebuilding an ad-hoc app can invalidate its previous macOS privacy grant.

To start a second, independent group:

```sh
open -n .build/MenuBarGroups.app
```

Each group stores its own list of applications and selected menu-bar items. The default group now keeps its selections across restarts; **New Group** creates a separate group ID. Existing selections from older runs without a group ID were stored under a temporary ID and cannot be migrated automatically.

## Try the menu-bar-item preview

1. Run from the app bundle for consistent macOS privacy settings, and click **Items**. Choose **Add menu-bar item…** to select one of the *currently visible* third-party status-item windows. Click **Refresh items** to rescan. Remove a saved row with **×**.
2. Saved rows survive restarts of the default group. If an app is closed or its item cannot be found, its row says **unavailable** until it reappears. Rows normally use the owning app's icon. **Capture OneDrive status icon (Screen Recording)…** is an explicit, optional test that captures the actual visible OneDrive status window once and shows that image in the popup. macOS may require granting Screen Recording in System Settings and restarting. The capture is kept only in memory, is not live-updated, and is lost on restart. Other apps continue to use app-icon placeholders. Multiple items from the same app are numbered by current position; if the app changes their order, a saved entry may point to a different item. Some items may not be discoverable.
3. To test clicking an original item through the popup, choose **Enable Device Control / Accessibility…** and grant permission to Menu Bar Groups in System Settings. You may have to restart the app for the permission to take effect. Clicking a saved row invokes only an original item whose visible bounds have just been revalidated; it does not launch an app or recreate its menu. The popup and diagnostic log distinguish action dispatch from a visibly opened native menu. The OneDrive `AXPress` test did not visibly open its native menu on the test Mac. A separate, explicitly confirmed mouse-click test on the verified visible original icon **did** open its native menu in two user tests, including after quit/relaunch. This is not hiding or consolidation. Use **Copy OneDrive AX diagnostics** to collect roles, actions, and bounds only. The button changes to **Copied OneDrive AX diagnostics** when the text reaches the clipboard; paste it into a message to inspect it. Do not use this preview for sensitive clicks. To check whether OneDrive's reported Accessibility bounds really match the original icon, click **Check OneDrive icon location (hover)…** and move the pointer over the original icon within four seconds. The app compares the pointer and AX bounds without clicking, capturing the screen, or moving any icon. If the original OneDrive icon is still visible, **Test visible OneDrive mouse click…** is a separate, explicitly confirmed test: it rechecks the AX item's identity and bounds and sends one mouse click to the original icon. It may move the pointer; dispatch success alone does not prove that the native menu opened. Cancel if the icon is not visible, and report whether its native menu visibly opens.
4. To revoke permissions, use **System Settings → Privacy & Security → Device Control and Data Access (Accessibility on older macOS) / Screen Recording**. Screen Recording is requested only if you click the OneDrive capture button.

## OneDrive hide experiment — paused

The opt-in spacer experiment failed on the test Mac (macOS 27): OneDrive stayed visible, and the app subsequently crashed. **The hide action is disabled in the current build.** Do not rely on it to remove OneDrive from the menu bar. The saved OneDrive entry can still test Accessibility `AXPress` while its real icon is visible, but that action did not visibly open its menu in the user test. The separate confirmed visible-icon mouse-click test opened it twice, including after relaunch. Quitting this app removes any app-owned status items.

OneDrive is exposed to this app through Accessibility (`AXExtrasMenuBar`), but not as a separate Core Graphics status window on this Mac. Accordingly, the optional image-capture button is disabled when there is no capturable OneDrive window. This preview does not hide anything. If click-through fails, the original OneDrive icon remains usable.

## Use the older shortcut group

1. Click **Items** in the menu bar.
2. In Finder, locate an application bundle—for example, `/Applications/Safari.app`.
3. Drag that `.app` bundle into the rounded group window.
4. Click its name in the group to open or focus it.
5. Use **New Group** to create another independent menu-bar group.

To stop all development instances:

```sh
pkill -f MenuBarGroups
```

## Existing items versus shortcuts

AppKit does **not** let an app take ownership of or embed another app's `NSStatusItem` in its own popup. However, menu-bar managers can organize the *presentation* of existing items, for example by hiding/revealing a region of the real menu bar and showing visual representations in a secondary bar. Such implementations may need Accessibility and Screen Recording permission and can have OS-version and app-specific limitations. A visual copy is not the original item; we will prototype and document the precise behavior before promising it.

The current build discovers visible item windows (with a OneDrive Accessibility fallback) and attempts click-through only after confirming the original item is still visible and stationary. The removed OneDrive hiding experiment does not reduce menu-bar crowding and is not part of this build. It does not read cloud storage quotas. See [the design plan](docs/menu-bar-manager.md) for the proposed stages, permissions, recovery requirements, and references.

## Project files

- `Sources/MenuBarGroups/main.swift` — the AppKit popup and shortcut prototype
- `Sources/MenuBarGroups/MenuBarItems.swift` — status-item-window discovery, optional capture, and click-through
- `Package.swift` — Swift Package Manager configuration
- `Info.plist` — application metadata
- `scripts/build-app.sh` — local app-bundle build script
