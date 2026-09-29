# Agent Guide

## Project

`MenuBarGroups` is a native macOS menu-bar management utility built with Swift Package Manager. It is dependency-free and targets modern macOS (macOS 14 and later, including macOS 27).

The application provides a modern, open-source alternative to Bartender 7:
- Multi-group menu bar management (e.g. Storage, Utilities, Media) directly in `NSStatusBar`.
- Floating native secondary sub-bar (`SecondaryBarWindow`) positioned beneath active group icons.
- Keyboard-first Command Bar (`CommandBarWindow`) summoned globally via `⌘ + Shift + Space`.
- Universal status item discovery across CoreGraphics and Accessibility (`AXExtrasMenuBar`).
- In-process group coordination and native settings management (`SettingsWindowController`).

## Useful commands

```sh
swift build                         # Debug build
swift run                           # Run debug executable
scripts/build-app.sh                # Build .build/MenuBarGroups.app
MENU_BAR_GROUPS_SIGN_IDENTITY="<Apple Development identity>" scripts/build-app.sh  # Build with stable code signing
open .build/MenuBarGroups.app       # Launch application bundle
pkill -f MenuBarGroups              # Terminate running instances
```

Run `swift build` after every Swift change to ensure compilation. Verify UI behavior on an interactive macOS desktop.

## Code layout

- `Sources/MenuBarGroups/main.swift` — Application entry point, `NSApplication` setup, and AppKit lifecycle.
- `Sources/MenuBarGroups/Models.swift` — Core data structures (`MenuBarItem`, `MenuBarGroup`, `KnownApps`).
- `Sources/MenuBarGroups/Scanner.swift` — Unified discovery engine querying CoreGraphics status windows and Accessibility `AXExtrasMenuBar`.
- `Sources/MenuBarGroups/InteractionEngine.swift` — Action dispatch via `kAXPressAction` or targeted `CGEvent` mouse clicks with pre-flight bounds validation.
- `Sources/MenuBarGroups/IconManager.swift` — High-resolution Retina icon caching with optional ScreenCaptureKit snapshotting and app icon fallbacks.
- `Sources/MenuBarGroups/SecondaryBarWindow.swift` — Floating vibrancy `NSPanel` rendering the sub-bar beneath status items.
- `Sources/MenuBarGroups/CommandBarWindow.swift` — Spotlight/Raycast-style search palette with keyboard navigation.
- `Sources/MenuBarGroups/HotKeyManager.swift` — Carbon `RegisterEventHotKey` global hotkey management.
- `Sources/MenuBarGroups/GroupManager.swift` — Central in-process coordinator for groups, persistence (`UserDefaults`), and `NSStatusItem` instances.
- `Sources/MenuBarGroups/SettingsWindow.swift` — Preferences window for group configuration, item assignments, Launch at Login (`SMAppService`), and permission tracking.
- `Package.swift` — Swift Package Manager specification.
- `Info.plist` — Application bundle metadata (`LSUIElement` enabled).
- `scripts/build-app.sh` — App bundle packaging script with optional code signing.

## Implementation conventions

- **AppKit & Concurrency**: The application state is `@MainActor`. UI updates, status item manipulation, and window management must remain on the main actor.
- **Process Model**: Single-process architecture. All groups, windows, and status items run within one lightweight process managed by `GroupManager.shared`.
- **Platform Boundaries**: AppKit cannot transfer ownership of or reparent another application's `NSStatusItem`. The app organizes and proxies interactions rather than adopting foreign items.
- **Permissions**:
  - Accessibility is used for `AXExtrasMenuBar` item inspection and `kAXPressAction` execution.
  - Screen Recording is purely optional for live Retina icon snapshots via ScreenCaptureKit.
  - Carbon `RegisterEventHotKey` is used for global hotkeys without requiring input monitoring permissions.
- **Documentation**: Update `README.md` whenever user-visible behavior, setup, or platform constraints change.

## Version control and commit standards

All contributors and assistants must adhere to the following git conventions:
- **Modular commits**: Commit distinct, logical changes independently (e.g. separate data model updates from UI or build script changes).
- **Plain, concise commit titles**: Use a brief sentence or imperative subject line (maximum 72 characters) summarizing the changes without any type prefixes or classification tags (do not use "feat:", "fix:", "docs:", "refactor:", "chore:", etc.).
- **Complete-sentence bullet points**: Use bulleted lists in the commit message body where each bullet point is a complete, well-formed sentence ending with a period. Summarize:
  - What was added, changed, or removed.
  - Technical rationale or platform context.
  - Sufficient detail for subsequent contributors or assistants to understand and continue the work.
- **No AI attribution**: Commit messages, PR descriptions, and code comments must contain no AI-generated badges, co-author attribution tags, or disclaimers.
