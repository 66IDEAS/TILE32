# TILE32 - Tasks

Status: ready to start
Date: 2026-10-18
Sources: `specs/specifications.md` (US-1..US-30, L1-L8, N-1..N-12, C-1..C-10), `specs/architecture.md` (TA-1..TA-26, spikes S1-S7), `specs/ux.md` (UX-1..UX-16), `specs/constitution.md`

## How to read this list

- Tasks are grouped in four phases, one per milestone: **M0 Spike**, **M1 Auto-tiling**, **M2 Drag-to-split and resize**, **M3 Polish and notarization**.
- Within a phase, tasks are in working order. Risky spikes come before the features that depend on them. S1 (drag detection) and S6 (Space functions) are the two highest risks and both start in M0.
- Each task has: what to do, traces to requirements, a "done when" criterion, and dependencies.
- **[owner]** marks a task that needs the owner at the machine. The owner performs all manual tests (drags, resizes, Space switches) personally, and Claude reads the logs.
- Spike results are written to `specs/spikes.md` before any feature builds on them (constitution, process rule 2).
- Status markers: `[ ]` open, `[~]` in progress, `[x]` done.

## Working agreements

1. **Windows only move when the owner agrees.** The owner works on the same Mac in parallel. Any task that moves real windows (S2, "Tile now", acceptance runs) is started only after the owner says it is a good moment.
2. **Permission.** Claude never changes security settings. The owner grants the Accessibility permission (T-0.12) and enters any password or credential (T-3.8).
3. **No commits without asking** (constitution, process rule 5).
4. **Tests first for the core.** `swift test` must pass before a task that changes `TileCore` or `TileEngine` is marked done.

---

## Phase M0 - Spike

Goal: prove that TILE32 can see and arrange windows, answer the two highest risks (S1, S6), and build the pure layout core with its tests.

### [ ] T-0.1 Scaffold the repository
- **Do:** Create `dev/Package.swift` (package `TileKit`) with library targets `TileCore`, `TileGeometry`, `TileSpaces`, `TileAX`, `TileEngine`, `TileInput`, `TileUI`, executable targets `TILE32` and `FakeWindows`, and test targets `TileCoreTests`, `TileEngineTests`. Swift 6 language mode, strict concurrency, macOS 27 deployment target. Add `dev/Resources/Info.plist` (`CFBundleIdentifier` `com.66ideas.tile32`, `LSUIElement` YES, version 0.1.0), `dev/Resources/TILE32.entitlements` (hardened runtime, no exceptions), `dev/THIRD_PARTY_NOTICES.md` (empty template), and extend the root `.gitignore` with `dev/.build/` and `dev/build/`.
- **Traces:** TA-1, TA-2, TA-21, TA-22, N-8, N-12, constitution technical rules 4, 10, 11
- **Done when:** `swift build` in `dev/` succeeds with empty targets, and the folder layout matches architecture section 5.
- **Depends on:** -

### [ ] T-0.2 Build and signing script
- **Do:** Write `dev/build-app.sh`. It builds in release mode, assembles `dev/build/TILE32.app` (or `FakeWindows.app` with bundle id `com.66ideas.tile32.FakeWindows`), copies `Info.plist`, and signs with "Apple Development: Alexander Ilg" plus the hardened runtime. Keep a `release` mode stub for T-3.8.
- **Traces:** TA-22, S5, N-11, N-12
- **Done when:** `codesign --verify --strict` passes, and `codesign -dv` shows identifier `com.66ideas.tile32`, the Apple Development authority and the runtime flag.
- **Depends on:** T-0.1

### [ ] T-0.3 TileCore: data model and normalisation
- **Do:** Implement `WindowID`, `SplitDirection`, `SplitChild` (with weight), `LayoutNode`, `LayoutTree`, `DropZone`, and `normalized()` with weight multiplication when flattening and rescaling to a sum of 1. Port from the prototype's `norm`.
- **Traces:** TA-3, TA-4, L1, L5
- **Done when:** unit tests pass for empty split, single-child split, nested same-direction splits, deep nesting, and weights summing to 1 within 1e-9.
- **Depends on:** T-0.1

### [ ] T-0.4 TileCore: tree operations
- **Do:** Implement `removing`, `appending`, `swapping`, `splitting(target:with:zone:)` and `flat`, all with weights as described in TA-4. Port from `without`, `addWin`, `swapIds`, `applyDrop` and `repl`.
- **Traces:** TA-4, TA-24, L2-L6, US-6, US-7, US-14, US-15
- **Done when:** tests pass for the prototype scenarios (D on the bottom of A gives `[vertical[A, D], B, C]`; D right of B gives 1/3, 1/6, 1/6, 1/3), the weight examples of L3 and L4, swaps across branches, dropping on itself, unknown targets, and one-window trees.
- **Depends on:** T-0.3

### [ ] T-0.5 TileCore: frame computation
- **Do:** Implement `frames(in:gap:)` with weighted boundaries, the gap rule (inset by gap/2 twice) and edge-based rounding, plus `rawShares(in:)`.
- **Traces:** TA-5, L7, N-10
- **Done when:** tests show no overlap, an even gap, no one-point seams on odd sizes, and correct results on 5120x1440 and on a tall 1440x5120 rectangle.
- **Depends on:** T-0.4

### [ ] T-0.6 TileCore: drop zones and drop targets
- **Do:** Implement `zone(at:in:)` (0.28 / 0.72 constants in one place, tie order left, right, top, bottom), `dropTarget(...)` returning `.window(id, zone, rect)` or `.emptyDisplay(rect)`, and `previewRect(target)`.
- **Traces:** TA-6, L6, US-14, US-15, US-16, US-18
- **Done when:** boundary tests at 0.279, 0.28, 0.72, 0.721 pass, corner ties resolve as specified, and the empty-display case is covered.
- **Depends on:** T-0.5

### [ ] T-0.7 TileCore: resizing, snapping and equalizing
- **Do:** Implement `resizing(window:edge:to:in:)` (nearest ancestor split with a neighbour, only two weights change, minimum of 10 percent or 200 points), `snapped(boundary:)` (1/4, 1/3, 1/2, 2/3, 3/4 within 0.01 of the cumulative position) and `equalized()`.
- **Traces:** TA-4, TA-25, L8, US-28
- **Done when:** tests pass for the US-28.6 scenario (thirds to 0.5, 0.25, 0.25), a resize inside a nested column, an outer edge (no change), the minimum clamp, and snapping at 0.49 and 0.51.
- **Depends on:** T-0.5

### [ ] T-0.8 TileGeometry
- **Do:** Build the display table from `NSScreen` with `DisplayID` (display UUID), usable area in AX coordinates, `display(containing:)`, and the only coordinate conversion functions `axRect(fromAppKit:)` and `appKitRect(fromAX:)`. Rebuild on `didChangeScreenParameters`.
- **Traces:** TA-7, US-5, US-9, N-10, constitution technical rule 9
- **Done when:** conversion tests pass for the owner's arrangement (ultrawide and laptop side by side, with different heights), and a debug log lists both displays with correct usable areas.
- **Depends on:** T-0.1

### [ ] T-0.9 Logging and debug menu
- **Do:** Add `os.Logger` with subsystem `com.66ideas.tile32` and categories `engine`, `ax`, `drag`, `resize`, `spaces`, `layout`, `ui`. Titles are logged only in debug builds. Add the debug-only "Debug" submenu with "Dump layout trees" and "Copy diagnostics" placeholders.
- **Traces:** TA-23
- **Done when:** `log stream --predicate 'subsystem == "com.66ideas.tile32"'` shows messages from a debug build, and none of them contain window titles in a release build.
- **Depends on:** T-0.1

### [ ] T-0.10 Menu-bar shell
- **Do:** Create the status item with the three icon states (`rectangle.split.2x2`, `rectangle.dashed`, `exclamationmark.triangle`, template images), and a menu rebuilt in `menuNeedsUpdate` with the status line, "Tile now", "Windows" (empty for now) and "Quit TILE32". No Dock icon. VoiceOver label "TILE32" with the state as its value.
- **Traces:** US-1, TA-17, UX-2, UX-3, UX-14
- **Done when:** launching `TILE32.app` shows only the menu-bar icon, the menu opens, "Quit TILE32" quits, and VoiceOver reads the label and state.
- **Depends on:** T-0.2, T-0.9

### [ ] T-0.11 Permission flow
- **Do:** Check `AXIsProcessTrustedWithOptions` without prompting. Show the first-run alert with the exact UX-8 wording. "Open System Settings" calls the prompting variant. Show the missing-permission menu (UX-5) with "Open Accessibility settings..." using the settings URL. Poll every 2 seconds, observe `com.apple.accessibility.api`, and switch states without a restart.
- **Traces:** US-2, TA-8, UX-5, UX-8, UX-9
- **Done when:** with permission removed, the alert and the warning icon appear; after granting, the icon and status line change within 2 seconds, without a restart.
- **Depends on:** T-0.10

### [ ] T-0.12 [owner] Grant the permission and check it survives rebuilds (spike S5)
- **Do:** The owner switches on TILE32 under Privacy & Security > Accessibility. Claude rebuilds and relaunches three times.
- **Traces:** S5, TA-22, C-1
- **Done when:** the app stays trusted after three rebuilds, and the result is in `specs/spikes.md`.
- **Depends on:** T-0.11

### [ ] T-0.13 TileSpaces: Space service
- **Do:** Define the `SpaceService` protocol and `SpaceInfo`. Implement the SkyLight version that resolves exactly the four functions of TA-26 with `dlsym` at start (`SLS` names first, then `CGS` names), reads the display-to-Space table, the Spaces of a list of windows, and the window number of an AX element. Set `isAvailable` to false if any function is missing. Add a fake for tests. Log the macOS version and which functions were found.
- **Traces:** TA-26, TA-20, C-5, US-12.7, constitution technical rule 1
- **Done when:** a debug build logs all four functions as found, prints the current Space of each display, and the fake is usable in `TileEngineTests`.
- **Depends on:** T-0.8, T-0.9

### [ ] T-0.14 TileAX: access layer and window registry
- **Do:** Implement the AX observer thread with its own run loop, one serial queue per app, `AXUIElementSetMessagingTimeout` (0.5 s), the `@unchecked Sendable` element box, discovery of regular apps, reading windows and their attributes (role, subrole, title, frame, minimised, full screen, modal, size settable), and a registry keyed by `CGWindowID` (from T-0.13), with `CFEqual` as the fallback key.
- **Traces:** TA-9, TA-13, TA-20, N-3, N-5
- **Done when:** "Dump layout trees" lists every window of the running apps with its `CGWindowID`, display and Space, and a deliberately hung test app does not freeze TILE32.
- **Depends on:** T-0.12, T-0.13

### [ ] T-0.15 Window classification, first version
- **Do:** Implement rules 1 to 5 of TA-10 (regular app, `AXStandardWindow`, resizable, not minimised, full screen or modal, minimum 200x120) with a floating reason for each rejected window. The exclude list (rule 6) follows in T-3.2.
- **Traces:** TA-10, US-21 (partly)
- **Done when:** with Finder, Safari, a save panel and a settings window open, the log shows the standard windows as tiled and the others as floating with the right reason.
- **Depends on:** T-0.14

### [ ] T-0.16 FakeWindows test app
- **Do:** Build the SwiftUI test app with buttons that open: a normal window, a window with a minimum size, a window that appears after a delay, five windows at once, a dialog, a sheet, a window that resizes itself, and a full-screen toggle.
- **Traces:** TA-24, US-10, US-11, US-21, US-30
- **Done when:** `./build-app.sh FakeWindows` produces a signed app, and each button behaves as labelled.
- **Depends on:** T-0.2

### [ ] T-0.17 Spike tools for Spaces and window listing (S6, S3)
- **Do:** Add the debug items "Log Spaces" (the display-to-Space table, each Space's type and UUID, and the Space of every window) and "Log windows" (AX windows per app, including those on hidden Spaces, plus the public on-screen list for the fallback). Log automatically on every Space change.
- **Traces:** S6, S3, TA-16, TA-26
- **Done when:** both items produce readable output for the current setup.
- **Depends on:** T-0.13, T-0.14

### [ ] T-0.18 [owner] Spike session A: Spaces (S6, S3)
- **Do:** The owner, following a short script from Claude: creates up to 16 Spaces on the ultrawide, switches between them, moves a window to another Space through Mission Control and through drag plus Ctrl+arrow, puts one window into full screen and out again, turns "Displays have separate Spaces" off and on (this needs a logout), and logs out and in once to check the UUIDs. Claude reads the logs. One step also tests whether a frame can be written to a window on a hidden Space.
- **Traces:** S6, S3, US-12, US-29, US-30, C-5
- **Done when:** every question of S6 and S3 has an answer in `specs/spikes.md`, and TA-16 and TA-26 are confirmed or a revision is proposed to the owner. The question about a notarized build is carried over to T-3.8.
- **Depends on:** T-0.17

### [ ] T-0.19 Spike tool for frame writing (S2)
- **Do:** Add the debug item "Frame write test": for each tiled window, write size, position, size to a test frame, read it back, and log differences and timings. Include a move from the ultrawide to the laptop display, and try the `AXEnhancedUserInterface` workaround for apps that respond slowly.
- **Traces:** S2, TA-11
- **Done when:** the tool runs on demand and restores each window to its previous frame afterwards.
- **Depends on:** T-0.14

### [ ] T-0.20 [owner] Spike session B: frame writing (S2)
- **Do:** At a moment the owner chooses (windows will move), run the frame write test with Safari, Chrome, VS Code, Terminal, Slack, Teams, Zoom and FakeWindows (minimum-size window).
- **Traces:** S2, TA-11, US-10
- **Done when:** `specs/spikes.md` lists which apps accept frames, which have minimum sizes, which are slow, and whether the enhanced-UI workaround is needed.
- **Depends on:** T-0.19, T-0.16

### [ ] T-0.21 Drag and resize tracker, logging only (S1)
- **Do:** Implement the `MouseDragTracker` state machine (Idle, Pressed, Dragging, Resizing) with listen-only global monitors for mouse events, the press hit test against the engine's frame snapshot (frames enlarged by 6 points, a 40 point title band), the lockstep rule on `Moved` notifications, and the switch to `Resizing` on `Resized` notifications. Add the Escape key monitor, active only while dragging. In this task the tracker only logs transitions; it changes nothing.
- **Traces:** S1, TA-14, OQ-1, US-13, US-17
- **Done when:** a debug build logs every transition with the window and the reason.
- **Depends on:** T-0.14

### [ ] T-0.22 [owner] Spike session C: drag detection (S1)
- **Do:** Following Claude's script, the owner performs in Finder, Safari, Chrome, Terminal, VS Code, Slack and Teams: 20 title-bar drags, 5 edge resizes, 5 corner resizes, 5 clicks and double-clicks on the title bar, 5 content drags (text selection, scrolling), and 3 Escape presses during a drag. Claude reads the log.
- **Traces:** S1, OQ-1, C-2
- **Done when:** `specs/spikes.md` records the classification accuracy per app, the false positives, and whether Escape works with the Accessibility permission alone (OQ-1 answered).
- **Depends on:** T-0.21

### [ ] T-0.23 Windows submenu
- **Do:** Fill the "Windows" submenu: headers "<display name> - Desktop <n>", entries "App - title" (cut in the middle at about 48 characters), a "Floating" group with reasons, "<n> windows on other Spaces", and "No windows to arrange". Choosing an entry brings the window to the front.
- **Traces:** US-3, UX-6, UX-15
- **Done when:** the submenu matches UX-6 for the current setup, and choosing an entry raises that window.
- **Depends on:** T-0.15, T-0.13

### [ ] T-0.24 Tile now (first engine)
- **Do:** Create the `LayoutEngine` actor with trees keyed by `LayoutKey` (Space and display). "Tile now" builds `flat` trees for the Spaces currently shown, ordered by each window's current left edge, computes frames, and writes them in one batch per app (size, position, size, then read back). Add the expected-frame suppression of TA-12.
- **Traces:** US-4, US-5, TA-3, TA-11, TA-12, TA-17, UX-12
- **Done when:** with the owner's agreement, "Tile now" arranges the windows of both displays as equal columns with a 6 point gap, no window moves to another display, floating and full-screen windows stay put, and no second layout pass is logged.
- **Depends on:** T-0.5, T-0.15, T-0.20

### [ ] T-0.25 [owner] M0 acceptance
- **Do:** Go through the M0 checklist at the end of this file on both displays.
- **Traces:** US-1 to US-4
- **Done when:** all M0 items are ticked, or the failures are written down with a decision.
- **Depends on:** T-0.1 to T-0.24

---

## Phase M1 - Auto-tiling

Goal: windows arrange themselves, every Space on every display keeps its own arrangement, and the first run starts paused.

### [ ] T-1.1 Engine run states and pause
- **Do:** Add the run states `.running`, `.paused` and `.noPermission`. "Pause tiling" and "Resume tiling" in the menu, with the paused icon (UX-4). The paused flag is stored in `UserDefaults` with default `true`, so a fresh install starts paused and shows "Tiling paused - choose Resume tiling to start". Resume re-applies stored trees and adds or removes windows that changed while paused. US-23 is built here instead of M3, because the first-run pause (US-23.5) is needed as soon as tiling becomes automatic.
- **Traces:** US-23, TA-17, TA-19, UX-4, UX-9, constitution product rule 5
- **Done when:** a fresh install moves nothing until "Resume tiling", the paused state survives a restart, and resuming restores the stored layouts.
- **Depends on:** T-0.24

### [ ] T-1.2 Observers and event coalescing
- **Do:** Register the AX observers of TA-9 for every regular app and the workspace notifications for launch, terminate, hide and unhide. Feed every event into the engine's coalescing queue (120 ms quiet time, 400 ms maximum).
- **Traces:** TA-9, TA-12, TA-13
- **Done when:** opening, closing, minimising and hiding windows in three apps produces exactly one layout pass per burst in the log.
- **Depends on:** T-1.1

### [ ] T-1.3 New windows join, closed windows re-flow
- **Do:** On a new tiled window, record its original frame, find its display and Space, and call `appending`. On close, call `removing`. Write only the affected layout.
- **Traces:** US-6, US-7, L3, L4, TA-18 (recording only)
- **Done when:** opening a fourth window gives four columns with proportional shrinking, closing one restores the proportions of L4, and the last window on a display fills it.
- **Depends on:** T-1.2

### [ ] T-1.4 Minimise and hide with return hint
- **Do:** Before removing a minimised window or a hidden app's windows, store the return hint (nearest sibling and side). On return, use `splitting` with the hint if the sibling is still there, otherwise `appending`.
- **Traces:** US-8, TA-9
- **Done when:** a window minimised from a column of two comes back into the same column on the same side.
- **Depends on:** T-1.3

### [ ] T-1.5 Per-Space layouts
- **Do:** On `activeSpaceDidChange`, ask `TileSpaces` for the shown Spaces. Leave the trees of hidden Spaces untouched, never write to their windows, reconcile the trees of shown Spaces (windows that left or arrived), and build a `flat` tree for a Space shown for the first time. Write frames only if a tree changed. Support "Displays have separate Spaces" on and off.
- **Traces:** US-12, TA-3, TA-16, TA-26, flow 3.6, constitution product rule 6
- **Done when:** engine tests with the fake Space service pass for switching between 16 Spaces with no write to a hidden Space, and on the real machine two Spaces with different arrangements keep them across ten switches.
- **Depends on:** T-1.3, T-0.18

### [ ] T-1.6 Moving windows between Spaces
- **Do:** Detect a window whose Space no longer matches its tree. Remove it from the old tree (re-flow now if that Space is shown, otherwise when it is next shown) and append it to the new Space's tree.
- **Traces:** US-29, TA-16, C-10
- **Done when:** moving a window with Mission Control and with drag plus Ctrl+arrow leaves both Spaces tidy, and no other window changes its tile.
- **Depends on:** T-1.5

### [ ] T-1.7 Full-screen windows
- **Do:** On entering full screen, remove the window with a return hint. On leaving, put it back through the hint into the layout of the Space it returns to. Full-screen Spaces get no tree.
- **Traces:** US-30, TA-10, TA-16
- **Done when:** a window in a column of two goes to full screen and back and lands in the same place, and the other Spaces' arrangements are unchanged.
- **Depends on:** T-1.5, T-1.4

### [ ] T-1.8 Fallback mode without Space information
- **Do:** When `SpaceService.isAvailable` is false, use the public on-screen window list, keep one tree per display, never write to windows that are not on screen, and show "Spaces not detected - only visible windows are arranged".
- **Traces:** US-12.7, TA-16, UX-9
- **Done when:** with the fake service set to unavailable, engine tests pass and the status line shows the fallback text; on the real machine a debug switch forces fallback mode without errors.
- **Depends on:** T-1.5

### [ ] T-1.9 Displays connected and disconnected
- **Do:** On a display change, give a new display empty trees, move a removed display's windows to the remaining display with `appending`, and bring any window outside all displays into view.
- **Traces:** US-9, TA-16, flow 3.5, N-5
- **Done when:** unplugging and replugging the ultrawide leaves every window visible, and windows do not jump back on their own.
- **Depends on:** T-1.5

### [ ] T-1.10 Windows that cannot shrink
- **Do:** After writing, compare the read-back size. Mark windows that stay larger as "does not fit", anchor them at the top-left of the tile, retry once, then leave them alone until their tile changes. Show the count next to the icon and in the status line, and "(does not fit)" in the Windows submenu.
- **Traces:** US-10, TA-11, TA-12, UX-2, UX-6, UX-9
- **Done when:** the FakeWindows minimum-size window in a small tile is marked, the count appears, no resize loop is logged, and the mark disappears when the tile grows.
- **Depends on:** T-1.3, T-0.16

### [ ] T-1.11 Several and slow windows (spike S4)
- **Do:** Test with FakeWindows (five windows at once, delayed window, splash-like window that closes quickly) and real apps. Tune coalescing, and make sure short-lived windows never enter a tree.
- **Traces:** US-11, S4, TA-12
- **Done when:** 10 minutes of the FakeWindows stress mode show no layout loop and no lost window, and the result is in `specs/spikes.md`.
- **Depends on:** T-1.10

### [ ] T-1.12 Engine test coverage for M1
- **Do:** Complete `TileEngineTests` with fakes for AX, geometry and Spaces for every M1 behaviour listed in TA-24 level 2.
- **Traces:** TA-24
- **Done when:** `swift test` passes and covers each M1 story with at least one test.
- **Depends on:** T-1.1 to T-1.11

### [ ] T-1.13 [owner] M1 acceptance
- **Do:** Go through the M1 checklist on both displays, with several Spaces.
- **Traces:** US-5 to US-12, US-23, US-29, US-30
- **Done when:** all M1 items are ticked, or the failures are written down with a decision.
- **Depends on:** T-1.12

---

## Phase M2 - Drag-to-split and resize

Goal: the user arranges windows by dragging them and sizes them by dragging edges, as in the prototype.

### [ ] T-2.1 Drag tracker connected to the engine
- **Do:** Turn the logging tracker of T-0.21 into the real one: on `Dragging`, ask the engine for a snapshot of the layout under the cursor, compute `dropTarget`, and on release send `applyDrop`, `moveToEmptyDisplay` or `snapBack`. Add the optional element-at-position refinement on the app's AX queue if S1 showed it is needed.
- **Traces:** US-13, TA-14, flow 3.4
- **Done when:** title-bar drags are recognised in all S1 apps, and clicks, content drags and resizes are not.
- **Depends on:** T-0.22, T-1.5

### [ ] T-2.2 Drop-zone overlay
- **Do:** One click-through, non-activating panel per display at `.floating` level, drawing the highlight (accent colour, 18 or 25 percent fill, 3 point border, 10 point radius, 3 point inset) and the label pill (13 point semibold). The six labels, wrapping and hiding rules, Increase Contrast variant, no animation, updates throttled to the display refresh rate.
- **Traces:** US-16, TA-15, UX-10, UX-11
- **Done when:** dragging over windows on both displays shows the correct zone and label instantly, the overlay never takes clicks or focus, and it looks right in light and dark mode.
- **Depends on:** T-2.1

### [ ] T-2.3 Apply drops: swap, split, other display, cancel
- **Do:** Implement the engine side of drops: `swapping`, `removing` plus `splitting`, cross-display and empty-display drops, and the snap back for drops without a target. Drops are applied immediately, without the coalescing wait.
- **Traces:** US-14, US-15, US-17.2, US-17.3, US-18, US-19.1, TA-4, TA-14
- **Done when:** the US-15.4 scenario works on the real machine, swaps keep the proportions in place (L1), cross-display drops work in both directions, and every cancel restores the exact layout.
- **Depends on:** T-2.2

### [ ] T-2.4 Escape cancel
- **Do:** If OQ-1 was answered positively in T-0.22, wire the Escape monitor: mark the drag as cancelled, hide the overlay, and snap back on release. Otherwise remove the monitor and note it in the specification (US-17.1).
- **Traces:** US-17.1, US-17.4, TA-14, OQ-1
- **Done when:** Escape cancels a drag, or the decision to drop it is recorded.
- **Depends on:** T-2.3

### [ ] T-2.5 Leave other title-bar behaviour alone
- **Do:** Make sure the traffic-light buttons, toolbar buttons, double-clicks and floating windows behave as usual. An Option-click zoom and any resize made by an app are put back into the tile once. Paused means no drag handling at all.
- **Traces:** US-19.3, US-20, TA-12, TA-14
- **Done when:** each item of US-20 is checked in Safari, Finder and VS Code.
- **Depends on:** T-2.3

### [ ] T-2.6 Resize by dragging an edge
- **Do:** Implement TA-25: active edges from the first resize notification, live updates of the neighbours at up to 30 per second (never writing the window being held), the 50 ms slow-app rule, snapping and full write on release, the minimum clamp, outer edges snapping back, and the percentage label in the overlay.
- **Traces:** US-28, US-19.2, TA-25, UX-16, L8, flow 3.7
- **Done when:** the US-28.6 scenario gives exactly 50, 25, 25 on the ultrawide, a corner drag moves two boundaries, and an outer edge drag snaps back.
- **Depends on:** T-2.3, T-0.7

### [ ] T-2.7 Make sizes equal and shares in the menu
- **Do:** Add "Make sizes equal" (uses `equalized()` on the layouts shown) and the percentage column in the Windows submenu.
- **Traces:** US-28.9, UX-3, UX-6
- **Done when:** after building 50, 25, 25, "Make sizes equal" gives thirds without changing the arrangement, and the submenu shows the shares.
- **Depends on:** T-2.6

### [ ] T-2.8 [owner] Spike session D: live resize (S7)
- **Do:** The owner resizes edges between Safari, Chrome, VS Code, Terminal and Slack on the ultrawide. Claude reads the timings per app.
- **Traces:** S7, Q-13, OQ-9
- **Done when:** `specs/spikes.md` lists which apps follow live, which switch to update-on-release, and whether 30 per second and 50 ms are the right values.
- **Depends on:** T-2.6

### [ ] T-2.9 [owner] M2 acceptance
- **Do:** Go through the M2 checklist on both displays, including drags across displays and resizes.
- **Traces:** US-13 to US-20, US-28
- **Done when:** all M2 items are ticked, or the failures are written down with a decision.
- **Depends on:** T-2.1 to T-2.8

---

## Phase M3 - Polish and notarization

Goal: safe and pleasant for every day use, and ready to be given to others.

### [ ] T-3.1 Classification complete
- **Do:** Re-run classification when a window's title, subrole or size changes; handle sheets and windows that change nature after creation; show all floating reasons from UX-6.
- **Traces:** US-21, TA-10, UX-6
- **Done when:** the FakeWindows dialog, sheet and tool window never take a tile, and their reasons are shown correctly.
- **Depends on:** T-1.12

### [ ] T-3.2 Exclude apps
- **Do:** Add "Don't tile <app>" / "Tile <app> again" / "Don't tile an app", and the "Excluded apps" submenu with its header and empty state. Store bundle identifiers in `UserDefaults`.
- **Traces:** US-22, TA-10, TA-19, UX-7
- **Done when:** excluding Zoom floats its windows at once and the rest re-flow, removing it brings them back, and the list survives a restart.
- **Depends on:** T-3.1

### [ ] T-3.3 Untile
- **Do:** Restore the recorded original frames, clamp them to visible display areas, restore windows on hidden Spaces when their Space is next shown, then pause. "Untile" is available while running and paused, and grey only when there is nothing to restore.
- **Traces:** US-24, TA-18, UX-4, UX-9
- **Done when:** after tiling and rearranging, "Untile" puts every window back within two seconds on the visible Spaces, the status line reads "Windows restored - tiling paused", and windows on other Spaces are restored on their next visit.
- **Depends on:** T-1.5

### [ ] T-3.4 Start at login
- **Do:** The "Start at login" checkbox with `SMAppService.mainApp`, showing the system's real state and the "(approve in System Settings)" variant.
- **Traces:** US-25, TA-17, UX-3
- **Done when:** after switching it on and logging out and in, TILE32 is in the menu bar.
- **Depends on:** T-0.10

### [ ] T-3.5 Permission revoked
- **Do:** When the permission disappears: stop all writes, reset the tracker, hide the overlay, release the observers, and show the warning menu. Resume without a restart when it returns.
- **Traces:** US-27, TA-8, flow 3.8, UX-5
- **Done when:** removing TILE32 from the Accessibility list while it runs leaves all windows in place and shows the warning within 2 seconds, and re-adding it resumes tiling.
- **Depends on:** T-1.1

### [ ] T-3.6 Accessibility of TILE32 itself
- **Do:** Check the VoiceOver labels and values, section headers in the Windows submenu, and the polite announcement of overlay labels if it is cheap (UQ-2). Check the label contrast with every macOS accent colour (UQ-3).
- **Traces:** UX-14, N-7
- **Done when:** VoiceOver reads the whole menu correctly, and the contrast check is recorded.
- **Depends on:** T-2.2

### [ ] T-3.7 Text audit
- **Do:** Compare every visible string in the app with the table in UX-15, and check sentence case, no exclamation marks and no em dashes.
- **Traces:** UX-15, N-9, constitution writing rules
- **Done when:** every string matches the table, and a search of the sources finds no em dash.
- **Depends on:** T-3.1 to T-3.6

### [ ] T-3.8 [owner] Release build and notarization
- **Do:** Complete `./build-app.sh release`: sign with "Developer ID Application: Alexander Ilg (AHBM4Y6VPX)" with secure timestamp and hardened runtime, submit with `xcrun notarytool submit --wait`, and staple. The owner stores the notarization credentials once with `notarytool store-credentials` (Claude never handles the password). Check that the notarized build still finds the four Space functions (carried over from S6).
- **Traces:** N-11, TA-22, TA-26, S6
- **Done when:** `spctl --assess --type execute` accepts the stapled app, it runs on a clean user account, and the Space functions are reported as found.
- **Depends on:** T-3.7

### [ ] T-3.9 Remember layouts across restarts (candidate)
- **Do:** Store each layout (with weights) per Space UUID and display, with window descriptors (bundle id, title, index). On start, match windows and rebuild trees; unmatched windows are appended. Decide with the owner whether to keep it (OQ-7).
- **Traces:** US-26, TA-19, TA-20, OQ-7
- **Done when:** after quitting and restarting TILE32 with the same windows open, the arrangement of each Space comes back for the windows that can be matched, or the owner decides to drop US-26.
- **Depends on:** T-1.5

### [ ] T-3.10 [owner] M3 acceptance and release check
- **Do:** Go through the M3 checklist, then the full checklist of all milestones once more on the notarized build.
- **Traces:** US-21 to US-27, N-1 to N-12
- **Done when:** all items are ticked, or the failures are written down with a decision.
- **Depends on:** T-3.1 to T-3.9

---

## Manual acceptance checklists

To be copied into `specs/review.md` when a milestone is reviewed. Run on both displays: the Dell U4924DW (5120x1440) and the built-in Color LCD (3456x2234).

### M0
- [ ] Only a menu-bar icon appears after launch, with no Dock icon and no window (US-1.1).
- [ ] The menu shows the status line, "Tile now", "Windows" and "Quit TILE32" (US-1.2).
- [ ] "Quit TILE32" leaves the windows where they are (US-1.3).
- [ ] Without the permission, the alert explains it in plain words and opens System Settings (US-2.1, UX-8).
- [ ] Without the permission, the status line says so and "Tile now" is grey (US-2.2, UX-5).
- [ ] Granting the permission takes effect without a restart (US-2.3).
- [ ] Only the Accessibility permission is ever requested (US-2.5).
- [ ] The Windows submenu lists the windows of the shown Spaces by display, with floating windows separate (US-3.1, US-3.2).
- [ ] Choosing a window in the submenu brings it to the front (US-3.4).
- [ ] "Tile now" arranges equal columns on each display without moving windows between displays (US-4.1, US-4.2).
- [ ] After "Tile now", no two tiled windows overlap and the gap is even (US-4.3, L7).
- [ ] Floating and full-screen windows are not moved (US-4.5).

### M1
- [ ] A fresh install starts paused, and nothing moves until "Resume tiling" (US-23.5).
- [ ] Pause and resume work, and the paused state survives a restart (US-23.1 to US-23.4).
- [ ] A new window joins at the right end and the others shrink in proportion (US-6, L3).
- [ ] Closing a window lets its neighbours grow in proportion (US-7, L4).
- [ ] A minimised window comes back next to its former neighbour (US-8).
- [ ] Each display has its own layout, within its usable area (US-5).
- [ ] Unplugging and replugging the ultrawide leaves every window reachable (US-9).
- [ ] A window that cannot shrink is marked, counted, and not fought (US-10).
- [ ] Several or slow windows settle calmly, without loops (US-11).
- [ ] Two Spaces with different arrangements keep them over ten switches, and no window moves on switching (US-12.1, US-12.2).
- [ ] A new Space gets equal columns when first shown (US-12.4).
- [ ] It works with 16 Spaces and with "Displays have separate Spaces" on and off (US-12.5, US-12.6).
- [ ] A window moved to another Space with Mission Control or drag plus Ctrl+arrow leaves the old layout and joins the new one (US-29).
- [ ] Full screen in and out returns the window to its place without changing other Spaces (US-30).

### M2
- [ ] Title-bar drags are recognised, and content drags, clicks and double-clicks are not (US-13).
- [ ] Dropping on the centre swaps two windows, and their sizes stay with the tiles (US-14, L1).
- [ ] Dropping on an edge splits the target in two halves, and the US-15.4 scenario gives A over D (US-15).
- [ ] The highlight and label show the result before release, on both displays (US-16).
- [ ] Releasing with no highlight cancels and restores the exact layout (US-17.2, US-17.3).
- [ ] Escape cancels a drag, or its removal is recorded (US-17.1).
- [ ] Drags to the other display swap, split or move to an empty display correctly (US-18).
- [ ] An outer edge drag and an app's own resize snap back (US-19).
- [ ] Traffic lights, toolbar buttons and floating windows behave as usual (US-20).
- [ ] Dragging an edge between two windows resizes both, live, with a percentage label (US-28.1, US-28.4).
- [ ] The scenario thirds to 50, 25, 25 works exactly through snapping (US-28.5, US-28.6).
- [ ] A corner drag moves two boundaries; the minimum size holds (US-28.3, US-28.7).
- [ ] "Make sizes equal" resets proportions without changing the arrangement (US-28.9).

### M3
- [ ] Dialogs, sheets and panels never take a tile (US-21).
- [ ] Excluding and including an app works at once and survives a restart (US-22).
- [ ] "Untile" restores every window within two seconds, then pauses; windows on other Spaces follow on their next visit (US-24).
- [ ] "Start at login" works after a logout (US-25).
- [ ] Layouts survive a restart of TILE32, or US-26 was dropped by decision (US-26).
- [ ] Removing the permission while running leaves windows in place and shows the warning; re-adding resumes (US-27).
- [ ] VoiceOver reads the icon and the whole menu (UX-14).
- [ ] The notarized build is accepted by `spctl`, runs on a clean user account, and finds the Space functions (N-11).
- [ ] Re-layout times meet N-1, and idle processor use is negligible (N-1, N-3).

---

## Coverage

Every requirement maps to at least one task.

| Requirement | Tasks |
|---|---|
| US-1 Menu-bar presence | T-0.10 |
| US-2 Permission request and status | T-0.11, T-0.12 |
| US-3 See my windows | T-0.23, T-2.7, T-3.1 |
| US-4 Tile now | T-0.24 |
| US-5 One layout per display | T-0.24, T-1.5 |
| US-6 New windows join | T-1.3 |
| US-7 Closing re-flows | T-1.3 |
| US-8 Hidden and minimised | T-1.4 |
| US-9 Displays connect and disconnect | T-1.9 |
| US-10 Windows that cannot shrink | T-1.10 |
| US-11 Several or slow windows | T-1.11 |
| US-12 One layout per Space | T-1.5, T-1.8 |
| US-13 Drag by the title bar | T-0.21, T-2.1 |
| US-14 Drop to swap | T-2.3 |
| US-15 Drop to split | T-2.3 |
| US-16 Preview before release | T-2.2 |
| US-17 Cancel a drag | T-2.3, T-2.4 |
| US-18 Drag to another display | T-2.3 |
| US-19 Snap back | T-2.3, T-2.5, T-2.6 |
| US-20 Separate from other title-bar uses | T-2.5 |
| US-21 Dialogs and panels stay floating | T-0.15, T-3.1 |
| US-22 Exclude apps | T-3.2 |
| US-23 Pause and resume | T-1.1 |
| US-24 Untile | T-3.3 |
| US-25 Start at login | T-3.4 |
| US-26 Remember my layout | T-3.9 |
| US-27 Permission revoked or lost | T-3.5 |
| US-28 Resize by dragging an edge | T-0.7, T-2.6, T-2.7 |
| US-29 Move a window to another Space | T-1.6 |
| US-30 Full-screen windows | T-1.7 |
| TA-1, TA-2 Platform and packaging | T-0.1 |
| TA-3 to TA-6 Core | T-0.3 to T-0.6 |
| TA-7 Geometry | T-0.8 |
| TA-8 Permission lifecycle | T-0.11, T-3.5 |
| TA-9 Discovery and tracking | T-0.14, T-1.2, T-1.4 |
| TA-10 Classification | T-0.15, T-3.1, T-3.2 |
| TA-11 Applying frames | T-0.19, T-0.24, T-1.10 |
| TA-12 Suppression and coalescing | T-0.24, T-1.2, T-1.11 |
| TA-13 Concurrency | T-0.14 |
| TA-14 Drag state machine | T-0.21, T-2.1, T-2.4 |
| TA-15 Overlay | T-2.2 |
| TA-16 Displays and Spaces | T-1.5 to T-1.9 |
| TA-17 Menu layer | T-0.10, T-0.23 |
| TA-18 Original frames and Untile | T-1.3, T-3.3 |
| TA-19 Persistence | T-1.1, T-3.2, T-3.9 |
| TA-20 Window identity | T-0.13, T-0.14 |
| TA-21 Privacy | T-0.1, T-3.7 |
| TA-22 Build, signing, notarization | T-0.2, T-0.12, T-3.8 |
| TA-23 Logging | T-0.9 |
| TA-24 Testing | T-0.3 to T-0.7, T-0.16, T-1.12 |
| TA-25 Resizing by edge | T-0.7, T-2.6 |
| TA-26 Space information | T-0.13, T-0.17, T-0.18 |
| UX-1 Principles | all tasks |
| UX-2 Icon states | T-0.10, T-1.10 |
| UX-3 to UX-5 Menus | T-0.10, T-0.11, T-1.1 |
| UX-6 Windows submenu | T-0.23, T-2.7 |
| UX-7 Per-app controls | T-3.2 |
| UX-8 First-run alert | T-0.11 |
| UX-9 Status line | T-0.11, T-1.1, T-1.8, T-1.10 |
| UX-10, UX-11 Overlay | T-2.2 |
| UX-12 Look of tiles | T-0.24 |
| UX-13 How a drag feels | T-2.3, T-2.5 |
| UX-14 Accessibility | T-0.10, T-3.6 |
| UX-15 Text | T-3.7 |
| UX-16 Resizing | T-2.6 |
| S1 to S7 Spikes | T-0.12 (S5), T-0.18 (S6, S3), T-0.20 (S2), T-0.22 (S1), T-1.11 (S4), T-2.8 (S7) |
