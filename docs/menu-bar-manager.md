# Menu-bar manager: status and plan

## Product goal

Reduce menu-bar crowding by placing selected **existing** third-party status items behind one compact popup. First target: OneDrive; later NextDrive, Synology Drive, and Proton Drive. A popup shortcut that launches an `.app`, or an overlay that merely paints over an icon while it still occupies space, does **not** satisfy this goal. The user prefers no expanded row of icons along the menu bar; a brief temporary reveal of the one clicked original may be acceptable if proven in practice.

Cloud-quota bars are a separate feature requiring a supported account integration (or clearly labelled manual data). Neither a local synced folder nor an application icon provides account quota.

## What exists today

- Native AppKit menu-bar popup, saved selections, and legacy `.app` shortcuts; independent groups are still supported.
- Core Graphics window-metadata discovery for some visible items. On this test Mac (macOS 27), OneDrive's real item is **not** published as a Core Graphics status window. With Device Control/Accessibility permission it **is** exposed as an `AXExtrasMenuBar` child with `AXMenuBarItem` role, bounds, and `AXPress`. The app includes a OneDrive-specific Accessibility fallback. **A user test found that invoking `AXPress` from the popup did not visibly open OneDrive's native menu, even though the original icon remained usable.** A later hover check verified that the AX bounds covered the original icon, and explicitly confirmed CG mouse clicks at that visible icon opened its native menu twice, including after relaunch. This proves only the visible-item activation path; do not progress to hiding or placement before investigating the prior crash and designing a reversible recovery path.
- Optional one-shot ScreenCaptureKit image capture for an item with a capturable window. OneDrive does not expose such a window here, so its capture control is disabled. App icons in the popup are placeholders, not replicas of live status icons.
- The `.app` bundle can be built with a stable Apple Development signing identity; rebuilding ad hoc had resulted in an untrusted running process despite an enabled-looking permission entry. Check `AXIsProcessTrusted()` in the running app, not just the System Settings switch.
- **No working hiding/reveal feature.** The OneDrive spacer/Command-drag experiment failed: OneDrive stayed visible. Two early crash reports show a Swift numeric-conversion trap in the removed OneDrive positioning spike (`OneDriveExperiment.frame(of:)`, negative AppKit window number converted to unsigned `CGWindowID`). Multiple other reports show `EXC_BAD_ACCESS` in `objc_release` during AppKit autorelease-pool cleanup, including one after Continue; the exact released object is not identified. The welcome window now sets `isReleasedWhenClosed = false`, and both Continue and title-bar close passed subsequent user tests. Do not attribute every historical memory crash to the spacer or declare the cleanup issue conclusively fixed. The hide action is **disabled** in the current UI. The user must not be asked to retry that build's positioning technique.

## Safe baseline check (interactive desktop)

Use the existing signed app identity when testing permissions; do not replace a signed bundle with an ad-hoc build. No hide or placement action is part of this check.

1. Open the signed app, confirm the welcome window appears, click **Continue**, and verify **Items** remains in the menu bar. Open and dismiss the popup twice. Repeat with the title-bar close button on a fresh launch. A September 26 crash report showed `EXC_BAD_ACCESS` during AppKit autorelease-pool draining after Continue; `isReleasedWhenClosed = false` was added to the retained welcome window as a suspected ownership fix; both close paths have since passed interactive user tests, but the historical `objc_release` crashes have not been conclusively explained.
2. Confirm OneDrive's original icon remains visible and usable before and after **Refresh items**. If it is missing from the popup, use **OneDrive not detected — why?** to copy bounded diagnostics. Do not grant new permissions solely to complete this baseline.
3. If Accessibility is already granted, copy **OneDrive AX diagnostics** and confirm the reported item count, role, and bounds correspond to the visible OneDrive icon. A reported `AXPress` success is only an accepted action, **not** evidence that its native menu opened. If testing click-through, visually verify the native menu and stop if it does not open.
4. Quit from the popup, verify OneDrive is still usable, relaunch, and repeat the popup open/close check. Record any crash report and the step that triggered it; do not proceed to placement tests after a crash.

## Platform boundaries

`NSStatusBar` manages this app's items, not OneDrive's. There is no public AppKit API to transfer ownership of OneDrive's `NSStatusItem`, hide its item by setting a property from this process, or embed its native menu directly in our popup. A genuine manager needs its own strategy for safe positioning and activation of the original, with macOS permissions and OS-specific behavior. A copied icon is not the original. Avoid private APIs, process injection, and unauthorized automation. Never synthesize a click at a hidden item's *old* coordinates.

The [OneDrive placement safety review](onedrive-placement-safety-review.md) is currently **no-go**: an independent recovery procedure has not been demonstrated. Do not expose a placement action on the strength of visible click-through alone.

## Next milestones and gates

1. **Stabilize the prototype.** The failed hide/spacer code and UI have been removed. Confirm the signed app can launch, close, and reopen without crashing. Click-through now logs only the chosen item's identity, bounds, and result—never account details or screen images. Add own-status-item bounds if a future placement test needs them. Keep the original usable after every failure. No new automatic dragging on launch.
2. **Prove OneDrive identity and action while visible.** The app found one OneDrive `AXMenuBarItem`, and a read-only four-second hover check confirmed its AX bounds covered the original visible icon. The saved-row `AXPress` action did **not** visibly open the native menu. A separate, explicitly confirmed **Test visible OneDrive mouse click…** action revalidates the AX identity and unchanged bounds before dispatch; two user tests, including one after quit/relaunch, confirmed that this CG click opened the native menu and left the original icon and Items control usable. No Screen Recording is needed for these checks. Permission-denied behavior and safe placement/restore remain unproven. Do not hide or reposition the item on the strength of this test alone.
3. **Prove reversible placement *without hiding*.** In a separate, explicitly confirmed test, reposition only OneDrive relative to a small app-owned anchor. Capture before/after AX bounds and verify where it actually went. Keep both icons visible. Provide an immediate Restore action; on failure do not enlarge any status item. Investigate the prior crash before trying this, and verify the app survives normal failure and quit paths. Do not claim original order is restored unless tested.
4. **Test space reclamation, one item only.** Only after milestone 3 succeeds, try an offscreen/hidden arrangement with a visible Items control. Verify OneDrive disappears **and releases usable menu-bar space**, while all other items remain available. Do not use an overlay as a substitute. Automatically abort/restore when the expected AX geometry or target identity changes. Quit/crash recovery must leave OneDrive visible.
5. **Test popup activation from the hidden state.** Temporarily reveal *only* OneDrive, invoke its native menu, and re-hide only after the interaction has ended. Verify that the brief reveal is acceptable to the user. Only then consider live icon artwork, additional providers, and grouping. If macOS 27 cannot meet these gates reliably without unacceptable permissions or unsupported APIs, document that result and reconsider the architecture rather than pretending shortcuts solve crowding.

**Release gate:** no general manager or storage-quota promises until the one-item hide → popup click → native menu → restore path passes repeatedly on the user's interactive desktop (including app relaunch and permission-denied cases).

## References

- [Apple: NSStatusBar](https://developer.apple.com/documentation/appkit/nsstatusbar) — app-owned status items.
- [Apple: AXUIElement](https://developer.apple.com/documentation/applicationservices/axuielement_h) — Accessibility elements and actions.
- [Apple: ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit) — optional icon representation; separate permission.
- [Bartender: Permissions](https://www.macbartender.com/Bartender5/PermissionInfo/) — describes its Accessibility and Screen Recording permissions, not a public status-item transfer API.
- [Ice: overview](https://github.com/jordanbaird/Ice) and [frequent issues](https://github.com/jordanbaird/Ice/blob/main/FREQUENT_ISSUES.md) — an existing section/secondary-bar design with documented item-management limitations.
