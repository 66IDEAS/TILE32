# TILE32 - Functional specification

Status: draft for review
Owner: Alex (Alexander Ilg)
Date: 2026-10-11, revised 2026-10-18

## 1. Purpose

TILE32 is a macOS menu-bar app that keeps the windows on each display from overlapping and lets the user arrange them with the mouse. It is for a user who finds keyboard-driven tiling tools too complex and snap-only tools too loose, because snapping never prevents windows from stacking on top of each other.

The name comes from the 32:9 aspect ratio of the user's ultrawide display (5120x1440). The user also works on the built-in 3456x2234 laptop display, so both displays must work well.

## 2. Principles

1. Windows never overlap, except in the one documented case where an app refuses to shrink (US-10).
2. Everything can be done with the mouse. No keyboard shortcut is ever required.
3. The user is always in control: pausing and untiling are one click away, and the user's windows are never left unreachable.
4. The app does as little as possible without being asked: it never changes a window it should not tile.

## 3. Glossary

- **Display**: one physical screen.
- **Space**: one macOS desktop, as shown in Mission Control. The user can have many Spaces on each display and switch between them.
- **Layout**: the arrangement of all tiled windows of one Space on one display. Every Space has its own layout on every display.
- **Tile**: the screen area occupied by one window in a layout.
- **Split**: dividing one tile into two tiles, side by side (horizontal split) or one above the other (vertical split). A new split starts as two equal halves.
- **Proportion**: the share of a split that one part takes, for example 50 percent. The user changes proportions by dragging a window edge (US-28).
- **Drop zone**: the part of a target window that decides what happens when a dragged window is released on it (swap, or split on one of four sides).
- **Floating window**: a window the app deliberately leaves alone, for example a dialog.
- **Tiled window**: a normal app window that the app places and sizes.
- **Untile**: give every window back the position and size it had before TILE32 touched it.
- **Current Space**: the Space shown on a display at this moment. Each display shows one Space at a time.

## 4. Layout rules (apply to all stories)

These rules define how a layout behaves. They match the interactive reference prototype (`/Users/alexanderilg/dev/vibe/tiling-window-demo/index.html`, mode 2, drag-to-split).

- **L1. Shape.** A layout is a set of nested splits. Each tile holds exactly one window. Every split divides its space among its parts by proportions that add up to 100 percent. Proportions belong to the tiles, not to the windows: when two windows swap places, each takes the other's size.
- **L2. Default layout.** When a layout has several windows and no arrangement yet, they are placed side by side as equal columns.
- **L3. New window.** A newly opened tiled window is added as one more column at the right end of the layout's top level. It gets an equal share, 1 / (number of columns), and the existing columns shrink in proportion. Example: columns at 50, 25 and 25 percent plus a new window become 37.5, 18.75, 18.75 and 25 percent.
- **L4. Closing.** When a window closes, its tile disappears and its neighbours in the same split grow in proportion to fill the space. Example: 50, 25 and 25 percent, then the 50 percent window closes, gives 50 and 50 percent.
- **L5. Tidying.** A split that ends up with a single window is removed. Two splits of the same direction nested inside each other are merged into one, and every window keeps its size on screen. Example: A, B and C side by side at a third each, then D dropped on the right of B, gives A, B, D, C at 33, 17, 17 and 33 percent, because D takes half of B's tile.
- **L6. Drop zones.** When a window is dropped on a target window, the target is divided into a centre zone and four edge zones. The centre zone is the middle 44 percent of the target in both directions (from 28 to 72 percent). Anywhere else, the edge zone is the target's nearest edge.
  - Centre zone: the two windows swap places.
  - Left or right edge zone: the target is split side by side, and the dragged window takes the left or right half respectively.
  - Top or bottom edge zone: the target is split one above the other, and the dragged window takes the top or bottom half respectively.
- **L7. Gaps.** Tiles have a small even gap between them and to the display edge, so window borders stay visible.
- **L8. Resizing.** Dragging a window edge moves the boundary between that window's tile and its neighbour in the same split. Only the two tiles on either side of the boundary change size; all other tiles keep theirs. No tile becomes smaller than 10 percent of its split or 200 points, whichever is larger. Boundaries snap to quarters and thirds of their split (25, 33, 50, 67, 75 percent) when released within 1 percent of one, so exact sizes such as 50, 25, 25 are easy to reach.

## 5. User stories

Stories are grouped by release slice. A slice is finished when all its stories pass their acceptance criteria. Story numbers are stable identifiers: stories added during review (US-28 to US-30) keep their numbers and are placed in the milestone where they belong.

---

### Milestone 0 - Spike

Goal: prove that TILE32 can see and arrange windows of other apps.

#### US-1 Menu-bar presence

**Description:** As a user, I want TILE32 to live in the menu bar and not in the Dock, so that it stays out of my way.

**Acceptance criteria:**
1. After launch, a TILE32 icon appears in the menu bar. No Dock icon and no app window appear.
2. Clicking the icon opens a menu with at least: status line, "Tile now", and "Quit TILE32".
3. "Quit TILE32" closes the app. Windows stay where they are at that moment.

#### US-2 Permission request and status

**Description:** As a user, I want TILE32 to ask me for the macOS permission it needs and tell me clearly whether it has it, so that I know why nothing happens when it is missing.

**Acceptance criteria:**
1. On first launch without permission, TILE32 explains in plain words what access it needs and why, and offers a button that opens the correct macOS settings screen.
2. While the permission is missing, the menu status line says so, and "Tile now" is not available.
3. As soon as the user grants the permission, TILE32 starts working without a restart, and the status line says it is active.
4. If the permission is withdrawn later, TILE32 stops moving any windows within a few seconds and shows the missing-permission status again (see US-27).
5. TILE32 asks for no other permission. In particular it does not ask to record the screen.

#### US-3 See my windows

**Description:** As a user, I want to see which windows TILE32 recognises, grouped by display, so that I can trust what it is going to arrange.

**Acceptance criteria:**
1. The menu has a "Windows" submenu listing every recognised tiled window on the Spaces currently shown, grouped under its display and Space, showing app name and window title. Windows on other Spaces are counted, not listed.
2. Floating windows are listed separately, marked as floating (see US-21).
3. The list reflects the current state each time the menu is opened.
4. Clicking a window in the list brings that window to the front.

#### US-4 Tile now

**Description:** As a user, I want one menu command that arranges all my windows, so that I can see TILE32 work before any automatic behaviour is switched on.

**Acceptance criteria:**
1. Choosing "Tile now" places the tiled windows of each display side by side as equal columns on that display (layout rule L2).
2. Windows are placed on the display where they currently are. No window moves to another display.
3. After the command, no two tiled windows overlap.
4. Choosing "Tile now" again re-arranges the windows into equal columns again.
5. Floating windows and native full-screen windows are not moved.
6. From Milestone 1 on, "Tile now" is the way to start over: it replaces each display's arrangement, including any splits built by dragging, with equal columns. It is not available while tiling is paused (US-23).

---

### Milestone 1 - Auto-tiling

Goal: windows arrange themselves as they come and go, with a separate, remembered layout for every Space on every display.

#### US-5 One layout per display

**Description:** As a user with an ultrawide and a laptop screen, I want each display to have its own independent layout, so that the two screens never interfere with each other.

**Acceptance criteria:**
1. Each connected display has its own layout for each Space (US-12). Changing the layout on one display never moves a window on another display.
2. Windows are tiled within the usable area of their display, which excludes the menu bar and the Dock.
3. A window that the user moves to another display (see US-18) leaves the first display's layout and joins the second display's layout.
4. Each display's layout follows the rules in section 4 independently.

#### US-6 New windows join automatically

**Description:** As a user, I want a window that I open to join the layout by itself, so that I never have to place it by hand.

**Acceptance criteria:**
1. When a new tiled window appears on a display, it is added following rule L3 without any action from the user.
2. The existing windows resize to make room, and no two tiled windows overlap afterwards.
3. The new window ends up on the display where it opened.
4. The layout is complete within one second of the window appearing (see N-1).

#### US-7 Closing a window re-flows the rest

**Description:** As a user, I want the remaining windows to fill the space when I close a window, so that no hole is left on the screen.

**Acceptance criteria:**
1. When a tiled window closes, the remaining windows on that display resize to fill the display following rules L4 and L5.
2. The positions of the remaining windows relative to each other do not change, only their sizes.
3. When the last window on a display closes, the display's layout is empty and the next window opened there fills the whole display.

#### US-8 Hidden and minimised windows

**Description:** As a user, I want windows I minimise or hide to stop taking up space, and to come back into the layout when I bring them back.

**Acceptance criteria:**
1. When a window is minimised or its app is hidden, the remaining windows re-flow as if the window had closed.
2. When the window comes back, it rejoins the layout next to the window it was beside before, on the same side, if that window is still in the layout. Otherwise it is added at the right end (rule L3).
3. A minimised window is not listed as an error and does not block other windows.

#### US-9 Connecting and disconnecting displays

**Description:** As a user who plugs a display in and out, I want TILE32 to cope without me doing anything.

**Acceptance criteria:**
1. When a display is connected, it gets its own empty layout. Windows are not moved onto it automatically.
2. When a display is disconnected, its windows move to a remaining display and join that display's layout following rule L3.
3. When the same display is reconnected, windows do not jump back on their own.
4. A display change never leaves a window off-screen or unreachable.

#### US-10 Windows that cannot shrink

**Description:** As a user, I want TILE32 to deal sensibly with an app whose window refuses to get smaller than a certain size.

**Acceptance criteria:**
1. When a window cannot be made as small as its tile, TILE32 keeps that window at its smallest possible size, anchored at the top-left of its tile, and lays out all other windows as usual.
2. This is the only case in which windows may overlap. The overlap is limited to the area that the oversized window needs beyond its tile.
3. The menu shows a note, for example "1 window does not fit", and the "Windows" submenu marks the affected window.
4. TILE32 does not repeatedly fight the app: after one retry it stops trying to resize that window until the layout changes.
5. When the layout changes so that the window fits again, the mark and the note disappear.

#### US-11 Several or slow windows

**Description:** As a user who starts an app that opens several windows, or whose windows take a while to appear, I want the layout to settle calmly.

**Acceptance criteria:**
1. When several windows appear within a short time, all of them join the layout, in the order in which they became visible.
2. A window that appears late, for example a few seconds after the app launched, joins the layout when it appears.
3. Windows that appear and vanish again within a moment, such as splash screens, do not leave a gap and do not make other windows jump around.
4. The layout never gets stuck in a loop of resizing.

#### US-12 One layout per Space

**Description:** As a user who works with many Spaces, I want every Space to keep its own arrangement, so that each desktop looks exactly as I left it when I come back.

**Acceptance criteria:**
1. Every Space has its own layout on every display, with its own splits and proportions. Changing the layout of one Space never changes another Space.
2. Switching Spaces moves no window. When the user returns to a Space, its windows are exactly where they were, including splits and sizes.
3. TILE32 only moves windows of the Spaces currently shown. Windows on other Spaces are never touched.
4. A Space that has windows but no layout yet (for example a Space the user just created, or the first visit after tiling was resumed) gets equal columns (rule L2) when it is first shown.
5. This works with any number of Spaces, and is tested with at least 16 Spaces on the ultrawide display.
6. It works with the macOS setting "Displays have separate Spaces" switched on (the default, where each display switches its Spaces on its own) and switched off.
7. If a macOS update stops TILE32 from finding out which Space is shown, TILE32 falls back to arranging only the visible windows, says so in the menu status line, and still never moves windows on other Spaces. Remembered arrangements may then be lost, but no window is.

#### US-29 Move a window to another Space

**Description:** As a user, I want a window that I move to another Space with macOS to leave the old layout and join the new one, so that both Spaces stay tidy.

**Acceptance criteria:**
1. The user moves windows between Spaces with macOS itself: by dragging the window in Mission Control, or by dragging it by the title bar and switching Space while holding it. TILE32 does not offer its own way to move windows between Spaces (it would require changing system security settings).
2. The moved window leaves the old Space's layout. The remaining windows there re-flow (rule L4), at the latest the next time that Space is shown.
3. The moved window joins the new Space's layout as a new window (rule L3), on the display where that Space is.
4. All other windows on both Spaces keep their tiles, apart from the re-flow in criterion 2.

#### US-30 Full-screen windows

**Description:** As a user of full-screen apps, I want TILE32 to leave full-screen windows alone and bring them back into the layout when I leave full screen.

**Acceptance criteria:**
1. Windows in native macOS full-screen mode are never moved or resized, and they do not take a tile. macOS shows each one in its own full-screen Space, which has no layout.
2. When the window enters full screen, its old tile is removed and its neighbours re-flow (rule L4).
3. When the user leaves full screen, the window returns to the layout of the Space it goes back to, next to the window it was beside before if that window is still there, otherwise as a new window (rule L3).
4. Switching to and from a full-screen app does not change the arrangement of any other Space (US-12.2).

---

### Milestone 2 - Drag-to-split

Goal: the user arranges windows by dragging them, as in the interactive prototype.

#### US-13 Drag by the title bar

**Description:** As a user, I want to pick up a window by its title bar and drag it, so that I can rearrange my layout with the mouse.

**Acceptance criteria:**
1. Pressing on a tiled window's title bar and moving the mouse starts a layout drag.
2. Dragging by the window content, scrollbars or resize edges does not start a layout drag and keeps its normal behaviour.
3. During the drag, the window follows the mouse like any normal window move, and the other windows stay where they are.
4. A click on the title bar without moving (including double-click) does not change the layout.

#### US-14 Drop to swap places

**Description:** As a user, I want to swap two windows by dropping one on the middle of the other.

**Acceptance criteria:**
1. Releasing a dragged window while the mouse is in the centre zone of another tiled window (rule L6) swaps the two windows. Each takes the other's tile.
2. All other windows stay where they are.
3. The result is visible within one second of releasing the mouse.

#### US-15 Drop to split

**Description:** As a user, I want to drop a window on an edge of another window to split that window in two, so that I can build any arrangement, for example one column with two windows above each other.

**Acceptance criteria:**
1. Releasing a dragged window in the left, right, top or bottom edge zone of a target window divides the target's tile in two equal halves, following rule L6.
2. The dragged window takes the half on the side where it was dropped, and the target takes the other half.
3. The dragged window leaves its old tile, and its old neighbours fill the freed space (rules L4 and L5).
4. Scenario from the prototype: three windows A, B, C side by side. A new window D opens at the right end. The user drags D onto the bottom edge of A. Result: A on top and D below it in the left column, with B and C unchanged.
5. A window can be dropped on a window that is itself already part of a split. The split is applied to that window only.

#### US-16 Preview before release

**Description:** As a user, I want to see what will happen before I let go of the mouse.

**Acceptance criteria:**
1. While dragging over a target window, a highlighted area shows where the dragged window will go: the whole target for a swap, or the half of the target for a split.
2. A short label names the action: "Swap places", "Place on the left", "Place on the right", "Place above" or "Place below".
3. The highlight and label update continuously as the mouse moves between zones and between windows.
4. When the mouse is over a display that has no tiled window at all, the whole usable area of that display is highlighted with the label "Move to this display" (see US-18).
5. Otherwise, when the mouse is not over any tiled window, no highlight is shown.
6. The highlight does not block the mouse or hide the windows underneath.

#### US-17 Cancel a drag

**Description:** As a user, I want to take back a drag when I change my mind.

**Acceptance criteria:**
1. Pressing Escape during a drag cancels it, and the window returns to its tile. This criterion applies only if Escape can be detected with the Accessibility permission alone (architecture OQ-1). If not, it is dropped and criterion 2 is the only way to cancel.
2. Releasing the mouse when no highlight is shown cancels the drag in the same way.
3. After a cancel, the layout is exactly as it was before the drag.
4. Escape is the only key used by TILE32, and only while a drag is in progress. Cancelling also always works with the mouse alone (criterion 2).

#### US-18 Drag to another display

**Description:** As a user with two displays, I want to drag a window from one display to the other and have it join that display's layout.

**Acceptance criteria:**
1. Dropping a window on a tiled window of another display applies the swap or split rules (US-14, US-15) in that display's layout.
2. For a swap across displays, both windows change display: each takes the other's tile on the other display.
3. Dropping a window on a display that has no tiled window (highlight "Move to this display", US-16.4) makes it the only window there, filling the whole display.
4. When a window leaves a display, that display's remaining windows re-flow (rule L4).
5. Dropping a window on empty space of its own display (no highlight shown) is a cancel (US-17).

#### US-19 Snap back

**Description:** As a user, I want a window that I moved by hand and dropped somewhere meaningless to return to its place.

**Acceptance criteria:**
1. A tiled window that is moved by its title bar and released without a valid drop (US-17) returns to its tile.
2. A tiled window whose outer edge (the edge that touches the display border) the user drags returns to its tile, because there is no neighbour to give space to. Resizing between two windows is described in US-28.
3. A tiled window that its app resizes by itself, without the user dragging, returns to its tile once (see US-10 for windows that refuse).
4. The return happens within one second of release.

#### US-28 Resize by dragging an edge

**Description:** As a user, I want to give one window more room than the others by dragging its edge, for example one window at 50 percent and two at 25 percent each.

**Acceptance criteria:**
1. Dragging the edge of a tiled window that faces another tile moves the boundary between them (rule L8). The window grows or shrinks, and the neighbour on the other side of the boundary shrinks or grows by the same amount. All other tiles keep their size.
2. If the neighbour is a group (for example a column of two windows above each other), the whole group changes size together.
3. Dragging a corner moves the vertical and the horizontal boundary at the same time.
4. While dragging, the neighbouring windows follow the edge, so the user sees the result before releasing. A small label shows the resized window's share of its split, for example "50%".
5. On release, the boundary snaps to a quarter or a third of its split when it is within 1 percent of one (rule L8), and all affected windows are aligned to their tiles with the normal gap.
6. Scenario: three windows A, B, C side by side at a third each on the ultrawide. The user drags A's right edge to the middle of the display, then B's right edge to three quarters. Result: A 50 percent, B 25 percent, C 25 percent.
7. No tile can be made smaller than the minimum in rule L8. Dragging further has no effect.
8. The new proportions stay when windows are swapped, opened, closed, minimised or moved by drag-to-split, following rules L1 to L5.
9. The menu offers "Make sizes equal", which sets every split in the layouts currently shown back to equal proportions without changing the arrangement. "Tile now" (US-4) additionally rebuilds the arrangement as equal columns.

#### US-20 Separate from other title-bar uses

**Description:** As a user, I want TILE32 not to interfere with normal title-bar behaviour.

**Acceptance criteria:**
1. Floating windows can be moved and resized freely and are never snapped back or tiled.
2. The traffic-light buttons (close, minimise, zoom) and any buttons in the title bar work as usual.
3. Clicking the green button enters native full screen, which US-30 handles. Option-clicking it (zoom) only resizes the window, and TILE32 returns the window to its tile afterwards, as for any resize made by an app (US-19.3).
4. If TILE32 is paused (US-23), no title-bar drag does anything special.

---

### Milestone 3 - Polish

Goal: make TILE32 safe and pleasant for every day use.

#### US-21 Dialogs and panels stay floating

**Description:** As a user, I want dialogs, sheets and small panels to stay where the app puts them, so that they do not get squeezed into a tile.

**Acceptance criteria:**
1. Dialogs, sheets, popovers, alerts, open and save panels, inspector and tool panels, and other small helper windows are not tiled.
2. They stay floating, in front of their parent window, and never cause a re-layout when they appear or close.
3. The decision is made automatically for each window, without the user doing anything.
4. A window that is wrongly treated as floating can be forced into the layout, and a window that is wrongly tiled can be floated, through the per-app exclude list (US-22).

#### US-22 Exclude apps

**Description:** As a user, I want to tell TILE32 to leave certain apps alone, so that apps that do not suit tiling, for example a video call or a settings app, stay free.

**Acceptance criteria:**
1. The menu offers "Don't tile <app name>" for the app that is currently in front, and an "Excluded apps" submenu listing all excluded apps.
2. Excluding an app makes all its windows floating immediately, and the remaining windows re-flow.
3. Removing an app from the "Excluded apps" submenu makes its windows join the layout again (rule L3).
4. The exclude list is remembered after quitting and restarting TILE32.
5. The excluded list is easy to review: each entry shows the app name and can be removed with one click.

#### US-23 Pause and resume

*Note: this story is built in Milestone 1 (task T-1.1), because the first-run pause of criterion 5 is needed as soon as tiling becomes automatic.*

**Description:** As a user, I want to switch TILE32 off temporarily without quitting, so that I can arrange windows freely for a while.

**Acceptance criteria:**
1. The menu has a "Pause tiling" item. While paused, TILE32 does not move or resize any window and shows the paused state on its menu-bar icon.
2. Resuming re-applies each display's stored layout. Windows opened while paused are added (rule L3) and windows closed while paused are removed (rule L4). A display without a stored layout gets equal columns (rule L2).
3. The paused state is remembered after restarting TILE32.
4. The pause switch is always reachable from the menu bar.
5. On the very first start, TILE32 is paused. Nothing moves until the user chooses "Resume tiling", so the user is never surprised by windows moving on their own after granting the permission.

#### US-24 Untile

**Description:** As a user, I want to give all my windows back their original positions and sizes, so that I can undo everything TILE32 did.

**Acceptance criteria:**
1. The menu has an "Untile" item. Choosing it stops tiling and moves every window it arranged back to the position and size it had before TILE32 first moved it.
2. A window that opened while TILE32 was running returns to the position and size it had when it first appeared, before TILE32 moved it.
3. If a window's original position is no longer on any connected display, it is moved to a visible position on a connected display.
4. After "Untile", TILE32 is paused. The user resumes with "Resume tiling" (US-23).
5. "Untile" works even when many windows are open and takes effect within two seconds.
6. "Untile" is also available while tiling is paused, because pausing leaves the windows in their tiled positions. It is unavailable only when there is nothing to restore, for example right after an "Untile".
7. Windows on Spaces that are not shown are restored the next time their Space is shown, because TILE32 never moves windows on hidden Spaces (US-12.3).

#### US-25 Start at login

**Description:** As a user, I want TILE32 to start when I log in, if I choose so.

**Acceptance criteria:**
1. The menu has a "Start at login" checkbox, off by default.
2. When switched on, TILE32 starts in the menu bar after the next login.
3. When switched off, it no longer starts at login.

#### US-26 Remember my layout

**Description:** As a user, I want my arrangement to survive a restart of TILE32 for windows that are still open.

**Acceptance criteria:**
1. When TILE32 is quit and started again while the same windows are open, the layout of each Space and display is restored, including proportions, as far as the windows can be recognised.
2. Windows that cannot be recognised are added following rule L3.
3. Entries for windows that no longer exist are dropped silently.

*Note: this story is a candidate. See open question Q-4.*

#### US-27 Permission revoked or lost

**Description:** As a user, I want TILE32 to fail safely and say what is wrong if macOS withdraws its permission.

**Acceptance criteria:**
1. When the permission is revoked, TILE32 does not move any further windows, and the menu-bar icon shows a warning state.
2. The menu status line says that permission is missing and offers the same button as US-2 to open the macOS settings screen.
3. Windows stay in the positions they had at that moment.
4. When the permission returns, TILE32 resumes without a restart.

## 6. Non-functional requirements

- **N-1. Responsiveness.** A new or closed window is reflected in the layout within one second. A swap or split after dropping a window is visible within one second. Untile takes effect within two seconds.
- **N-2. Smoothness.** While the user drags a window, the window follows the mouse without visible lag. The highlight appears within a fraction of a second after entering a zone.
- **N-3. Light on resources.** When nothing changes on screen, TILE32 uses a negligible amount of processor time and memory.
- **N-4. Privacy.** TILE32 does not use the network, does not send any data anywhere, does not record the screen, and does not read the content of windows. It uses only window positions, sizes, titles and app names.
- **N-5. Safe fallback.** If TILE32 quits, crashes or loses its permission, every window stays where it is and stays usable. No window is ever left off-screen.
- **N-6. Control is always one click away.** Pause, Untile and Quit are reachable from the menu bar at all times.
- **N-7. Mouse only.** All features are available with the mouse alone. Any optional shortcut must use at most two keys at the same time and must work on a German keyboard layout, where Option plus a letter produces special characters.
- **N-8. Platform.** TILE32 runs on the user's Mac (macOS 27) and does not require changes to system security settings.
- **N-11. Distribution.** TILE32 can be signed with a Developer ID and notarized by Apple, so it can be given to other people outside the Mac App Store. The Mac App Store is not a target, because its required sandbox does not allow an app to control other apps' windows.
- **N-12. App identifier.** The app identifier is `com.66ideas.tile32`. It never changes, because macOS ties the permission, the settings and the login item to it.
- **N-9. Language.** The user interface text is in English.
- **N-10. Both displays.** Everything works on the 5120x1440 ultrawide and on the 3456x2234 built-in display, including very wide and very tall tiles.

## 7. Constraints and assumptions

- **C-1. System permission.** TILE32 needs the macOS permission to control other apps' windows (the Accessibility permission). Without it nothing can be arranged.
- **C-2. Detecting a drag.** macOS tells an app only that a window moved, not who moved it or why. TILE32 therefore needs to tell a user dragging a title bar from a window moved by an app. This affects the reliability of US-13 and has to be validated early.
- **C-3. Minimum sizes.** Some apps set a minimum window size and refuse to shrink. US-10 describes the behaviour.
- **C-4. Timing of windows.** Some apps open windows slowly or several at once. US-11 describes the behaviour.
- **C-5. Spaces.** macOS has no public interface that tells an app which Space is shown or which Space a window is on. TILE32 uses a small set of undocumented, read-only macOS functions for this one purpose. They only ask questions and change nothing, and they do not prevent notarization. A future macOS update could change them, which is why US-12.7 defines a safe fallback.
- **C-6. Full-screen.** Native full-screen windows are managed by macOS and are left alone.
- **C-7. Displays.** A display can be connected or disconnected at any time (US-9).
- **C-8. Permission.** The permission can be denied or revoked at any time (US-2, US-27).
- **C-9. Scope.** Version 1 uses public macOS interfaces, plus the read-only undocumented functions of C-5. No change to system security settings is made, and nothing is injected into other apps.
- **C-10. Moving between Spaces.** Only macOS can move a window to another Space without changing system security settings, so TILE32 follows such moves instead of making them (US-29).

## 8. Out of scope for version 1

- Keyboard shortcuts for any layout action.
- Tabbed or stacked layouts, a floating layer for extra windows, or window animations.
- Moving windows between Spaces by TILE32 itself (C-10). macOS does it, and TILE32 follows.
- Creating, removing or renaming Spaces.
- Window rules per window title, per-app default positions, or scripting.
- Anything on iPhone, iPad or other platforms.

## 9. Decisions

| # | Decision | Date |
|---|---|---|
| D-1 | Tiles have adjustable proportions. The user drags window edges to resize (US-28, rule L8). Replaces the earlier "equal shares only" proposal (former Q-1 and Q-5). | 2026-10-18 |
| D-2 | Every Space has its own remembered layout on every display (US-12). Replaces the earlier "current Space only" proposal (former Q-11). | 2026-10-18 |
| D-3 | Spaces are detected with read-only undocumented macOS functions (C-5). Notarization stays possible (N-11). | 2026-10-18 |
| D-4 | macOS moves windows between Spaces, and TILE32 follows (US-29, C-10). | 2026-10-18 |
| D-5 | TILE32 starts paused on the first run (US-23.5). | 2026-10-18 |
| D-6 | App identifier `com.66ideas.tile32` (N-12). | 2026-10-18 |

## 10. Open questions

| # | Question | Suggested default |
|---|---|---|
| Q-2 | Where should a new window go: always at the right end (as in the prototype), or next to the window that has focus? | Right end, as in the prototype. |
| Q-3 | How many windows can one display hold before tiles become too small to use? Should extra windows stay floating, or go to a second layer? | No limit in version 1. Windows that cannot fit follow US-10. |
| Q-4 | Should the layout be remembered across restarts of TILE32 (US-26), and how well can windows be recognised after a restart? | Keep US-26 as a candidate for the end of Milestone 3. |
| Q-6 | Should "Quit TILE32" offer to untile first? | No. Windows stay where they are, and the user can use "Untile" before quitting. |
| Q-7 | Should pause be per display or global? | Global. |
| Q-8 | Should an app with several windows get one tile per window, or one tile per app? | One tile per window. |
| Q-9 | Is a visual animation when windows move desirable? The prototype animates for a quarter of a second. | No animation in version 1, so tiles snap into place. |
| Q-10 | Is the 44 percent centre zone the right size on very wide tiles (a window spanning the full ultrawide)? | Keep the proportions, and review after trying on the real display. |
| Q-12 | When proportions are unequal, should a new window take an equal share and shrink the others in proportion (rule L3, current proposal), or take half of the largest tile? | Equal share with proportional shrinking. Review after real use. |
| Q-13 | Should the neighbours follow a dragged edge live (US-28.4) even for apps that redraw slowly, or update only on release for those apps? | Live for all apps, with an automatic switch to update-on-release for an app that cannot keep up. Decided after spike S7. |
