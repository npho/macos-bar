# Agent Guide

## Project

`MenuBarGroups` is a small macOS AppKit prototype built with Swift Package Manager. It is intentionally dependency-free and targets macOS 14 or later.

The current code is a popup proof of concept: each process owns one shortcut group, and the popup lets users add visible third-party status-item windows to a saved list with owning-app icon placeholders and opt-in click-through. A OneDrive-only spacer experiment was attempted on macOS 27; it failed to hide OneDrive and the app crashed afterward. The current UI pauses that experiment. Do not expose or retry the spacer path without an explicit safety review and recovery plan. The product direction is a custom popup-based menu-bar manager, with storage-provider groupings as an initial use case. See `docs/menu-bar-manager.md` for stages and platform constraints.

## Useful commands

```sh
swift build                         # Debug build
swift run                           # Run the debug executable
scripts/build-app.sh                # Build .build/MenuBarGroups.app
MENU_BAR_GROUPS_SIGN_IDENTITY="<Apple Development identity>" scripts/build-app.sh  # Stable TCC identity
open -n .build/MenuBarGroups.app    # Start another app-bundle instance
pkill -f MenuBarGroups              # Stop prototype instances
```

Run `swift build` after every Swift change. This project has no automated tests yet; verify the UI manually on an interactive macOS desktop.

## Code layout

- `Sources/MenuBarGroups/main.swift` — application entry point, AppKit UI, drag/drop, persistence, and process spawning.
- `Sources/MenuBarGroups/MenuBarItems.swift` — status-item discovery (Core Graphics, with a OneDrive Accessibility fallback), capture, and opt-in click-through.
- The unsuccessful OneDrive-only positioning spike was removed from the source tree; do not restore it without the safety review described above.
- `Package.swift` — Swift package configuration.
- `Info.plist` — app-bundle metadata. `LSUIElement` makes it a menu-bar utility and `LSMultipleInstancesProhibited` must remain `false`.
- `scripts/build-app.sh` — produces the local `.app` bundle; set `MENU_BAR_GROUPS_SIGN_IDENTITY` to a stable Apple Development certificate when testing Device Control/Accessibility access across builds. Rebuilding without it changes the app's signing identity and may invalidate macOS privacy grants.

## Implementation notes

- `MenuBarGroupsMain` explicitly creates `NSApplication`, installs `AppDelegate`, and enters `app.run()`. Do not replace it with a bare process entry point: AppKit lifecycle callbacks and status items require the application run loop.
- AppKit state is `@MainActor`; keep UI work on the main actor.
- A group ID arrives as `--group <UUID>`. Without the argument it uses `default`, so saved selections survive relaunch. Its `UserDefaults` suite is `com.example.MenuBarGroups.<groupID>`.
- **New Group** launches a second process with a new ID. Do not change this to a single-instance activation flow.
- The temporary welcome window is a visual launch confirmation. Closing it must not terminate the status-item application.

## Platform boundary and permissions

AppKit cannot transfer ownership of, reparent, or nest another process's `NSStatusItem` in our popup. The new goal is to **visually organize and reveal** existing items, not claim ownership of them. Accessibility and screen capture may be investigated and implemented with explicit, informed user consent, minimal scope, and a useful permission-denied fallback. Document what each permission enables; do not silently request either. Prefer public APIs and reversible behavior; do not use private APIs, process injection, or undocumented cross-process manipulation without an explicit design review and user approval. No claims of App Store eligibility without checking the actual implementation. See `docs/menu-bar-manager.md`.

The discovery/click-through preview is not consolidation; the OneDrive spacer experiment is paused after failure and a crash, and must not be re-enabled casually. Click-through is only for verified, visible windows after temporary reveal. Never click a hidden item's old coordinates. The OneDrive-only ScreenCaptureKit action captures a single still image with explicit consent, not a live status item. Do not mistake other owning-app icons for live menu-bar icons or local disk usage for cloud quota.

## Editing conventions

- Keep the app native AppKit unless a change has a clear reason to introduce another framework.
- Prefer small, focused changes. Preserve the prototype's multi-instance behavior until the manager lifecycle is deliberately redesigned; a future manager may be single-instance.
- Update `README.md` whenever user-visible behavior, setup, or platform constraints change.
