# Menu Bar Groups

An open-source macOS menu bar manager and organizer inspired by Bartender 7, tailored for modern macOS (including macOS 27 "Golden Gate").

---

## Features

- **Multi-Group Menu Bar Management**: Group related status items into customizable categories (e.g. *Storage*, *Utilities*, *Media*) with custom SF Symbols and titles.
- **Native Concealment Overlay**: Automatically camouflages original menu bar icons for grouped items behind seamless system vibrancy masks (`CurtainOverlayWindow`), eliminating clutter from the main menu bar without relying on obsolete spacer tricks.
- **Floating Secondary Sub-Bar**: Clicking any group's menu bar icon reveals a sleek, native vibrancy floating bar (`NSPanel`) displaying all grouped items directly underneath. Avoids MacBook notch clipping.
- **Command Bar (Keyboard-First Search)**: Press **⌘ + Shift + Space** from anywhere in macOS to summon a Spotlight/Raycast-style Command Bar. Fuzzy-search through all active menu bar items and press `Enter` to open its native menu immediately.
- **Universal Status Item Discovery**: Discovers both standard CoreGraphics status windows and modern sandboxed application items (`AXExtrasMenuBar`) across the entire operating system without hardcoding.
- **Smart Group Provisioning**: Automatically detects storage providers (OneDrive, Dropbox, Google Drive, Synology, Nextcloud, Box, Proton Drive, pCloud) and provisions a dedicated **Storage** group on first launch.
- **Single-Process Native Architecture**: Runs entirely within a single lightweight AppKit process; no multi-process forks.
- **Preferences & Group Manager**: Native Settings window to create/edit groups, assign/unassign items, configure Launch at Login (`SMAppService`), and inspect system permissions.
- **Privacy-First**: Operates seamlessly without mandatory Screen Recording permissions. ScreenCaptureKit is purely an opt-in enhancement for capturing pixel-perfect live icons.

---

## Requirements

- **macOS 14 or later** (tested on macOS 27 Golden Gate)
- Swift 6.0+ / Xcode Command Line Tools

---

## Getting Started

### Run from Source

```sh
swift run
```

### Build the Application Bundle

```sh
scripts/build-app.sh
open .build/MenuBarGroups.app
```

To sign with your Apple Development identity for persistent macOS permissions across builds:

```sh
security find-identity -v -p codesigning
MENU_BAR_GROUPS_SIGN_IDENTITY="<Your Certificate SHA-1 or Name>" scripts/build-app.sh
open .build/MenuBarGroups.app
```

---

## Keyboard Shortcuts & Navigation

| Action | Shortcut | Description |
| :--- | :--- | :--- |
| **Command Bar** | `⌘ + Shift + Space` | Opens the floating search palette from anywhere in macOS. |
| **Search Filter** | Type letters | Fuzzy matches active menu bar items. |
| **Select / Open** | `Enter` or double-click | Opens the targeted status item's native menu. |
| **Dismiss** | `Escape` or click outside | Closes the Command Bar or Secondary Bar. |
| **Preferences** | `⌘ + ,` (from Menu) | Opens the Group Management & Settings window. |

---

## Permissions

Menu Bar Groups respects macOS security and privacy boundaries:

- **Accessibility** (Required for menu activation): Needed to inspect `AXExtrasMenuBar` for sandboxed apps and trigger menu actions (`kAXPressAction` / event dispatch).
  - Open **System Settings → Privacy & Security → Accessibility** to enable.
- **Screen Recording** (Optional): Used solely in-memory by ScreenCaptureKit to snapshot live status icons with Retina fidelity. If not granted, Menu Bar Groups gracefully falls back to high-resolution application icons.

---

## Architecture

- **`Models.swift`**: Data definitions for `MenuBarItem`, `MenuBarGroup`, and smart app identifiers.
- **`Scanner.swift`**: Unified scanner combining `CGWindowListCopyWindowInfo` and Accessibility `AXUIElement` (`AXExtrasMenuBar`).
- **`InteractionEngine.swift`**: Dispatches click actions and menu activation via `kAXPressAction` or targeted `CGEvent` dispatch.
- **`CurtainOverlay.swift`**: Borderless floating vibrancy masks (`CurtainOverlayWindow` and `CurtainOverlayManager`) concealing original status icons.
- **`SecondaryBarWindow.swift`**: Floating `NSPanel` with `NSVisualEffectView` providing the sub-bar beneath clicked group status items.
- **`CommandBarWindow.swift`**: Floating Spotlight-style fuzzy search palette.
- **`HotKeyManager.swift`**: System-wide Carbon `RegisterEventHotKey` registration without requiring keylogger permissions.
- **`GroupManager.swift`**: Manages `NSStatusItem` instances for each group and primary menu bar control.
- **`SettingsWindow.swift`**: Preferences window for group configuration and permission onboarding.
- **`main.swift`**: AppKit application lifecycle and delegate.

---

## License

Open source under the [MIT License](LICENSE).
