# OneDrive placement experiment — safety review (no-go)

**Status:** Design review only. No placement or hiding action is enabled. This document does not authorize retrying the removed spacer/Command-drag technique.

## Evidence so far

- On the test Mac (macOS 27), OneDrive has one visible `AXMenuBarItem` with a reported frame and `AXPress`. A pointer-hover comparison confirmed its AX bounds covered the original icon.
- The original icon opens its native menu. The popup's saved-row `AXPress` did not visibly do so. One explicitly confirmed CG mouse click at the verified *visible* icon did open it; this succeeded again after quit/relaunch. Neither test exercised moving or hiding.
- The previous spacer/Command-drag attempt did not hide OneDrive. Two historical reports show a Swift numeric-conversion trap in the removed positioning spike; several others show `EXC_BAD_ACCESS` in AppKit autorelease-pool cleanup, without an identified released object. Subsequent welcome-window close tests passed, but the old memory failures are not conclusively explained.

## Hard limits

No public AppKit API transfers, reorders, or hides a different process's `NSStatusItem`. AX bounds are observations, not proof of stable identity after a move or of the ability to restore original order. A successful CG event dispatch is not proof that the recipient handled it. Never click at the previous coordinates of a hidden or moved icon. Do not revive the failed spacer path, use private APIs, inject code, or manipulate OneDrive without explicit design approval.

## Recovery prerequisite — currently unmet

Before *any* placement action is written or exposed, demonstrate an independent, user-performed recovery that makes OneDrive's original icon visible and usable **without MenuBarGroups running**. Microsoft documents Control-clicking OneDrive's icon → **Pause syncing → Quit OneDrive**, then opening OneDrive from Spotlight to restart it. This temporarily interrupts syncing; it does **not** establish that restarting restores a moved/hidden icon or its prior order. Apple documents holding Command and dragging a status-menu icon to rearrange it, but that general instruction is not evidence the gesture works for OneDrive on this Mac; the previous Command-drag experiment failed. Neither option has been tested here as recovery. Record the exact steps and verify the resulting icon is present and its native menu opens. If no procedure reliably restores it, placement is **no-go**. Quitting MenuBarGroups removes only its own status items; it cannot be assumed to restore OneDrive.

Sources: [Microsoft — How to cancel or stop sync in OneDrive](https://support.microsoft.com/en-us/onedrive/how-to-cancel-or-stop-sync-in-onedrive); [Apple — What's in the menu bar on Mac?](https://support.apple.com/en-md/guide/mac-help/mchlp1446/mac).

## Requirements for a future, separately approved prototype

1. **Bounded scope:** one OneDrive item on one display, with one explicit confirmation per attempt; no automatic action at launch, no background repositioning, no other providers, and no hidden state in the first experiment.
2. **Preflight:** require already-granted Accessibility; verify exactly one OneDrive AX item with the expected PID, bundle identity, role, on-screen bounds, and unchanged geometry. Record the original bounds in memory before any action. The user must independently confirm the original icon and the app-owned control are visible. Denial, multiple matches, missing bounds, or a display-layout change blocks the attempt.
3. **Visible-only step:** keep both icons visible. If a supported and reversible positioning method is identified, verify the *actual* before/after AX bounds and that OneDrive's native menu still opens at its new visible position. An accepted AX/CG action or unchanged frame is not success.
4. **Immediate rollback:** offer an always-visible Restore control. After any failure or unexpected identity/bounds change, stop sending events. Never enlarge a spacer or click a stale coordinate as a fallback. Restore must be tested from the moved state, then verify OneDrive's original icon and native menu, including after MenuBarGroups quits.
5. **Crash recovery:** test the independently verified manual recovery procedure with MenuBarGroups terminated unexpectedly. Do not claim automatic crash recovery without a mechanism that operates independently of the crashed process. If original ordering cannot be verified, say so explicitly.
6. **Stop conditions:** any crash, missing icon, wrong-target event, failure to restore, permission loss, multi-display ambiguity, or menu that does not visibly open ends testing. No hiding/space-reclamation test until repeated visible-only move → menu → restore cycles and quit/crash recovery pass.

## Decision

**No-go for placement today.** Visible click-through is promising, but the recovery prerequisite is not demonstrated and the earlier failure mode is not sufficiently understood. The next safe activity is to identify and manually verify an independent OneDrive-icon recovery procedure; only then review a concrete, reversible *visible-only* placement design with the user. No new Accessibility or Screen Recording permission request is necessary for this document.
