# TILE32 - UX design

Status: draft for review
Date: 2026-10-11, revised 2026-10-18
Inputs: `specs/specifications.md` (US-1..US-31), `specs/architecture.md` (TA-15 overlay, TA-17 menu-bar layer, TA-25 resizing), prototype `prototype/index.html` (look of the drop preview)

TILE32 is a small utility with almost no interface. There is no main window and no Dock icon. The whole UI is: the menu-bar icon, its menu, the drop-zone overlay shown while dragging, one first-run explanation, and the look of the tiled windows. Each entry below has a number (UX-n), a title, a description, and a "Serves" line with the user stories (US) it supports.

---

## 1. Entries

### UX-1 Interaction principles

**Description:**
1. **The user is never surprised.** Nothing moves without a reason the user can see. Switching Spaces never moves a window: every Space looks exactly as the user left it. TILE32 starts paused on its first run, and the user starts tiling with "Resume tiling" (US-23.5). A drag always shows what will happen before the mouse is released.
2. **The user can always undo.** Cancel a drag, pause tiling, or untile, each in one step from the menu bar.
3. **Quiet by default.** No pop-ups, no sounds, no notifications, no animation, no Dock icon, no focus stealing. Information lives in the menu and in the icon.
4. **Everything with the mouse.** Every action is a click or a drag. No shortcut is shown or required.
5. **Honest status.** The top line of the menu always tells the truth in plain words, and anything that is not available says why.

**Serves:** US-1, US-17, US-23, US-24, N-6, N-7

### UX-2 Menu-bar icon and its states

**Description:** The icon is a monochrome template image, so it follows light mode, dark mode and the wallpaper tint of the menu bar. It never uses colour. States differ by shape, not by colour, so they stay readable for colour-blind users and with Increase Contrast.

| State | When | Symbol (SF Symbols) | Looks like |
|---|---|---|---|
| Active | Permission granted, tiling on | `rectangle.split.2x2` | A window divided into four tiles |
| Paused | The user paused tiling, or after Untile | `rectangle.dashed` | The same window outline, dashed and undivided: "nothing is managed" |
| Warning | The macOS permission is missing or was withdrawn | `exclamationmark.triangle` | A warning triangle |

Details:
- Size: 15 point symbol, regular weight, in the standard 22 point menu-bar height.
- When some windows cannot be made small enough (US-10), the active icon gets a small number next to it, for example "1", showing how many windows do not fit. Nothing is shown when the count is zero. This is the only badge.
- While the mouse button is pressed on the icon (menu open), the system highlights it as for any menu-bar item.
- No animation, and no flashing, in any state.

**Serves:** US-1, US-2, US-10, US-23, US-27

### UX-3 Menu: tiling active

**Description:** The menu has these items, top to bottom. Separators are shown as lines. The menu is rebuilt every time it opens, so it always shows the current state (US-3.3).

```
+-----------------------------------------------+
| Tiling 5 windows on 2 displays                |   status line, grey, not clickable
+-----------------------------------------------+
| Tile now                                      |
| Make sizes equal                              |
| Windows                                     > |
+-----------------------------------------------+
| Don't tile Safari                             |
| Excluded apps                               > |
| Window limit                                > |
+-----------------------------------------------+
| Pause tiling                                  |
| Untile                                        |
+-----------------------------------------------+
| [ ] Start at login                            |
+-----------------------------------------------+
| About TILE32                                  |
| TILE32 Help                                   |
+-----------------------------------------------+
| Quit TILE32                                   |
+-----------------------------------------------+
```

- The status line is the first item. It is grey and has no action (see UX-9 for its texts).
- The groups are: arranging (Tile now, Make sizes equal, Windows), per-app control, stopping (Pause, Untile), app settings (Start at login), information (About, Help, see UX-18), and Quit. The order goes from the most common to the least common.
- Menu items use standard system styling, so they follow the system font, size and appearance. TILE32 draws no custom menu content.
- A checkbox item shows a check mark when on: "Start at login". If macOS asks the user to approve the login item in System Settings, the text becomes "Start at login (approve in System Settings)", and choosing it opens that screen.
- In debug builds only, a "Debug" submenu appears below "Start at login" with "Dump layout trees" and "Copy diagnostics".

**Serves:** US-1, US-3, US-4, US-22, US-23, US-24, US-25

### UX-4 Menu: tiling paused

**Description:** Same menu, with these differences. Items that cannot work while paused are shown grey, never removed, so the user can see they exist. The status line says why.

```
+-----------------------------------------------+
| Tiling paused                                 |
+-----------------------------------------------+
| Tile now                          (grey)      |
| Make sizes equal                  (grey)      |
| Windows                                     > |
+-----------------------------------------------+
| Don't tile Safari                             |
| Excluded apps                               > |
| Window limit                                > |
+-----------------------------------------------+
| Resume tiling                                 |
| Untile                                        |
+-----------------------------------------------+
| [ ] Start at login                            |
+-----------------------------------------------+
| About TILE32                                  |
| TILE32 Help                                   |
+-----------------------------------------------+
| Quit TILE32                                   |
+-----------------------------------------------+
```

- "Tile now" and "Make sizes equal" are grey, because they would move windows while the user asked for them to be left alone.
- "Untile" stays available (US-24.6): pausing leaves the windows in their tiled positions, and the user may still want them back where they were.
- "Don't tile <app>" and "Excluded apps" stay available. Changes take effect when tiling resumes.
- On the very first run, before the user has ever resumed, the status line reads "Tiling paused - choose Resume tiling to start", so the first step is obvious.
- After "Untile" the same menu is shown, the status line reads "Windows restored - tiling paused", and "Untile" is grey until tiling has moved a window again, because there is nothing left to restore.

**Serves:** US-23, US-24

### UX-5 Menu: permission missing

**Description:** When macOS permission is missing or withdrawn, the menu leads with the one thing the user can do. All window-related items stay visible but grey.

```
+-----------------------------------------------+
| TILE32 needs permission to move windows       |   status line, grey
+-----------------------------------------------+
| Open Accessibility settings...                |   the one active item at the top
+-----------------------------------------------+
| Tile now                          (grey)      |
| Make sizes equal                  (grey)      |
| Windows                           (grey)      |
+-----------------------------------------------+
| Don't tile an app                 (grey)      |
| Excluded apps                     (grey)      |
| Window limit                      (grey)      |
+-----------------------------------------------+
| Pause tiling                      (grey)      |
| Untile                            (grey)      |
+-----------------------------------------------+
| [ ] Start at login                            |
+-----------------------------------------------+
| About TILE32                                  |
| TILE32 Help                                   |
+-----------------------------------------------+
| Quit TILE32                                   |
+-----------------------------------------------+
```

Choosing "Open Accessibility settings..." opens the Accessibility pane of System Settings. As soon as the permission is granted, the menu returns to the active state by itself (UX-3), and the icon changes from the warning triangle to the active symbol, with no restart and no extra pop-up.

**Serves:** US-2, US-27

### UX-6 Windows submenu

**Description:** The submenu lists what TILE32 sees on the Spaces currently shown, grouped by display, so the user can check it. Display names are the names macOS shows in System Settings, followed by the Space as Mission Control numbers it ("Desktop 3"). Each group has a small, grey, non-clickable header.

```
+-----------------------------------------------+
| Dell U4924DW - Desktop 3                      |   header
|   Mail - Inbox                        50%     |
|   Safari - Apple                      25%     |
|   Code - tile32                       25%     |
| Color LCD - Desktop 1                         |   header
|   Terminal - zsh                              |
|   Slack - General     (does not fit)          |
| Floating                                      |   header
|   Safari - Downloads  (floating: panel)       |
|   Preview - Open      (floating: dialog)      |
| 14 windows on other Spaces                    |   grey, not clickable
+-----------------------------------------------+
```

- Each tiled window shows its share of the display's width on the right, rounded to whole percent, when a display has more than one window.
- Windows on Spaces that are not shown are not listed one by one, only counted, so the menu stays short with many Spaces.

- Each entry is "App - window title". Long titles are cut in the middle with "...", at about 48 characters.
- Choosing an entry brings that window to the front (US-3.4).
- A window that cannot be made small enough shows "(does not fit)" after its name.
- Floating windows are listed together under "Floating", each with the reason in brackets: dialog, panel, pop-up window, excluded app, full screen, too small, not resizable.
- With no windows the submenu shows one grey line: "No windows to arrange".
- The submenu stays available while tiling is paused, and is grey while the permission is missing.

**Serves:** US-3, US-10, US-12, US-21

### UX-7 Per-app controls

**Description:** Two items let the user keep an app out of tiling.

- **"Don't tile <app>"** names the app that was in front when the menu opened, for example "Don't tile Safari". Choosing it takes all that app's windows out of the layout at once, and the others re-flow. If that app is already excluded, the item reads "Tile <app> again" and does the opposite. If no app applies, the item reads "Don't tile an app" and is grey.
- **"Excluded apps"** is a submenu that lists the excluded apps by name, most recently added last. A grey header says "Click an app to tile it again". Clicking an entry removes it from the list and brings its windows back into the layout. An empty list shows one grey line: "No excluded apps".

**Serves:** US-21, US-22

### UX-8 First-run permission explanation

**Description:** On the first start without permission, TILE32 shows one standard macOS alert. It uses plain words, says what is needed and why, says what is not done, and tells the user what happens next. It has one main button and one way out.

```
+--------------------------------------------------------+
|  TILE32 needs permission to move windows               |
|                                                        |
|  To arrange your windows, macOS must let TILE32        |
|  control them. TILE32 only reads window positions,     |
|  sizes and titles. It never records your screen,       |
|  reads what is in a window, or uses the internet.      |
|                                                        |
|  In System Settings, open Privacy & Security >         |
|  Accessibility and switch on TILE32. You do not        |
|  need to restart it.                                   |
|                                                        |
|  TILE32 starts paused. When you are ready, choose      |
|  Resume tiling from its menu.                          |
|                                                        |
|            [ Not now ]      [ Open System Settings ]   |
+--------------------------------------------------------+
```

- "Open System Settings" is the default button. It triggers the macOS permission request, which adds TILE32 to the Accessibility list and shows the system's own short dialog with its "Open System Settings" button. That second dialog comes from macOS and cannot be skipped without losing the automatic listing (architecture TA-8).
- "Not now" closes the alert. TILE32 stays in the menu bar in the warning state (UX-5). The alert is shown once per launch while the permission is missing, never more often.
- The alert is the only window TILE32 ever opens on its own.

**Serves:** US-2, N-4

### UX-9 Status line and quiet notices

**Description:** Information reaches the user through the status line at the top of the menu and through the icon (UX-2). There are no notification pop-ups, banners or sounds in version 1. The status line is the quietest way that still works: it is always one click away, it never interrupts, and it stays correct because it reflects the current state.

| State | Status line |
|---|---|
| Active, no problems | "Tiling 5 windows on 2 displays" (singular: "Tiling 1 window on 1 display") |
| Active, nothing to tile | "No windows to arrange" |
| Active, some do not fit | "Tiling 5 windows on 1 display - 1 does not fit" |
| Active, some minimised to make room | "Tiling 18 windows on 2 displays - 15 minimised to make room" |
| Paused, never resumed yet (first run) | "Tiling paused - choose Resume tiling to start" |
| Paused by the user | "Tiling paused" |
| After Untile | "Windows restored - tiling paused" |
| Permission missing | "TILE32 needs permission to move windows" |
| Space detection unavailable (US-12.7) | "Spaces not detected - only visible windows are arranged" |

A status line text stays until the state changes. It is not timed, so there is nothing to miss.

**Serves:** US-2, US-10, US-23, US-24, US-27

### UX-10 Drop-zone overlay: appearance

**Description:** While the user drags a window over another one, a highlight shows where the dragged window will go. It matches the prototype.

- **Colour:** the system accent colour. Border at full colour, fill at the same colour with transparency (about 18 percent in light mode and 25 percent in dark mode), so the window underneath stays visible.
- **Border:** 3 points wide, the same on every display and on Retina (points, not pixels).
- **Corners:** rounded with a 10 point radius. The highlight is inset by 3 points from the tile's raw share, which is half the 6 point gap, so it lines up with the window edge underneath and neighbouring highlights never touch.
- **Label:** one short text in 13 point semibold type, centred in the highlighted area, in the accent colour when it has a contrast of at least 4.5:1 against the pill (in practice: dark mode), otherwise in the primary text colour (UQ-3), on a small rounded pill (8 point radius, 6 point vertical and 12 point horizontal padding) filled with the window background colour at 90 percent opacity. The pill keeps the text readable over any window content, light or dark.
- **What is highlighted:** the whole tile for a swap, the half of the tile on the chosen side for a split, or the whole usable area of a display that has no tiled window.
- **Very wide and very tall tiles:** nothing scales with size. On a full-width tile on the 5120x1440 ultrawide, the label stays 13 points and is centred in its area, and the highlight simply gets wider. If a highlighted area is narrower than the label plus 16 points, the label wraps to two lines, and if it still does not fit, only the highlight is shown.
- **Increase Contrast:** the label text uses the primary text colour instead of the accent colour, and the border grows to 4 points.
- No animation: the highlight appears, moves and disappears instantly. This also respects Reduce Motion.

```
 Swap (centre)           Left                    Right
+---------------+     +---------------+      +---------------+
|###############|     |########|      |      |      |########|
|#  Swap       #|     |# Place #      |      |      |# Place #|
|#  places     #|     |# on the#      |      |      |# on the#|
|###############|     |# left  #      |      |      |# right #|
+---------------+     |########|      |      |      |########|
                      +---------------+      +---------------+

 Top                     Bottom
+---------------+     +---------------+
|###############|     |               |
|# Place above #|     |---------------|
|###############|     |###############|
|               |     |# Place below #|
+---------------+     |###############|
                      +---------------+

 # = highlight (accent border and light fill), label centred inside
```

**Serves:** US-14, US-15, US-16, N-2, N-10

### UX-11 Drop-zone overlay: behaviour and wording

**Description:**
- The highlight is shown while the mouse is over a tiled window other than the dragged one, in the band along the left or right display edge, or over a display that has no tiled window at all (then the whole usable area is highlighted). Anywhere else nothing is shown, and releasing there cancels the drag (US-17).
- The highlight follows the mouse continuously and switches at once when the mouse crosses from one zone to another or from one window to another, also across displays.
- The overlay never takes mouse clicks and never takes keyboard focus, and it appears above normal windows but not above menus.
- The eight labels, exactly: "Swap places", "Place on the left", "Place on the right", "Place above", "Place below", "Move to this display", "Full height on the left", "Full height on the right".
- Within 40 points of the left or right edge of a display, the highlight shows the full-height column the window would get (US-32). This band wins over the zones of the window below it.
- The centre zone is the middle 44 percent of the tile in both directions, as in the prototype. Its size is a single constant that can be adjusted after real use (spec question Q-10).

**Serves:** US-14, US-15, US-16, US-17, US-18, US-32

### UX-12 Look of tiled windows

**Description:** TILE32 does not draw anything on or around tiled windows. Windows keep their own look. The only thing the user sees is the layout itself: tiles separated by an even 6 point gap, and the same 6 point gap between the windows and the display edge, so window borders and shadows remain visible. There is no focus outline and no title-bar decoration in version 1.

**Serves:** L7, US-4, US-6

### UX-13 How a drag feels

**Description:** While dragging, the window under the mouse moves like any normal window, because that movement belongs to macOS and TILE32 does not interfere. The other windows stay still. On release the result is applied at once: the windows change places in one step, with no animation. A cancelled drag, or a drop where nothing is highlighted, returns the dragged window to its tile at once. Dragging the outer edge of a window, the one at the display border, also returns the window to its tile after release. Dragging an edge that faces another window resizes both (UX-16). Clicking, double-clicking and the standard title-bar buttons behave as in any other window.

**Serves:** US-13, US-17, US-19, US-20

### UX-14 Accessibility of TILE32 itself

**Description:**
- **VoiceOver, status item:** the icon's label is "TILE32". Its value follows the state: "Tiling is on", "Tiling is paused" or "Needs permission". Its help text is "Opens the TILE32 menu".
- **VoiceOver, menu:** all items are standard system menu items, so VoiceOver reads them as usual. Group headers in the "Windows" submenu are real section headers. Checkboxes announce their state ("Start at login, on").
- **VoiceOver, overlay:** the overlay is hidden from VoiceOver. When the label changes during a drag, its text is announced once, politely, for example "Place above". This is a small improvement that can be dropped (UQ-2).
- **Contrast:** the label sits on an opaque-enough pill, and with Increase Contrast it switches to the primary text colour and a thicker border (UX-10).
- **Colour independence:** the icon states differ by shape (UX-2), and the overlay's meaning is carried by the label text and the highlighted area, not by colour alone.
- **Motion:** no animation anywhere, so Reduce Motion needs no special handling.
- **Keyboard:** the whole app is reachable by mouse. Standard macOS menu keyboard navigation still works because the menus are system menus.

**Serves:** N-7, US-1, US-16

### UX-15 User-visible text

**Description:** All text is English, in sentence case, with actions starting with a verb, no exclamation marks and no em dashes. This table lists every text the user can see.

| Text | Where it appears |
|---|---|
| TILE32 | Status item accessibility label, alert titles of the app |
| Tiling 5 windows on 2 displays | Status line (UX-9) |
| Tiling 1 window on 1 display | Status line, singular |
| No windows to arrange | Status line and empty "Windows" submenu |
| Spaces not detected - only visible windows are arranged | Status line, fallback mode |
| <display name> - Desktop <n> | Header in the "Windows" submenu |
| <n> windows on other Spaces | Grey line in the "Windows" submenu |
| <n>% | Share in the "Windows" submenu, and resize label (UX-16) |
| Tiling 5 windows on 1 display - 1 does not fit | Status line |
| Tiling paused | Status line |
| Tiling paused - choose Resume tiling to start | Status line on the first run, before the user ever resumed |
| Windows restored - tiling paused | Status line after Untile |
| TILE32 needs permission to move windows | Status line, and title of the first-run alert |
| Open Accessibility settings... | Menu item, permission missing |
| Tile now | Menu item |
| Make sizes equal | Menu item |
| Windows | Menu item (submenu) |
| Don't tile <app> | Menu item |
| Tile <app> again | Menu item, when the app is already excluded |
| Don't tile an app | Menu item, grey, when no app applies |
| Excluded apps | Menu item (submenu) |
| Click an app to tile it again | Header in the "Excluded apps" submenu |
| No excluded apps | Grey line in the empty "Excluded apps" submenu |
| Pause tiling | Menu item |
| Resume tiling | Menu item |
| Untile | Menu item |
| Start at login | Menu item (checkbox) |
| Start at login (approve in System Settings) | Menu item, when macOS needs approval |
| About TILE32 | Menu item (UX-18) |
| TILE32 Help | Menu item (UX-18) |
| Your windows side by side, arranged with the mouse. | About panel, below the 66ideas logo |
| Quit TILE32 | Menu item |
| Dump layout trees, Log Spaces, Log windows, Frame write test (moves windows), Copy diagnostics | Debug builds only |
| (does not fit) | Suffix in the "Windows" submenu |
| (minimised to make room) | Suffix in the "Windows" submenu |
| Window limit | Menu item (submenu) |
| Tiling 18 windows on 2 displays - 15 minimised to make room | Status line |
| Floating | Header in the "Windows" submenu |
| (floating: dialog), (floating: panel), (floating: excluded app), (floating: full screen), (floating: too small), (floating: not resizable), (floating: pop-up window) | Suffixes in the "Windows" submenu |
| Swap places | Overlay label |
| Place on the left | Overlay label |
| Place on the right | Overlay label |
| Place above | Overlay label |
| Place below | Overlay label |
| Move to this display | Overlay label, display without a tiled window |
| Full height on the left, Full height on the right | Overlay labels, band at the left or right display edge (US-32) |
| To arrange your windows, macOS must let TILE32 control them. TILE32 only reads window positions, sizes and titles. It never records your screen, reads what is in a window, or uses the internet. | First-run alert, first paragraph |
| In System Settings, open Privacy & Security > Accessibility and switch on TILE32. You do not need to restart it. | First-run alert, second paragraph |
| TILE32 starts paused. When you are ready, choose Resume tiling from its menu. | First-run alert, third paragraph |
| Open System Settings | First-run alert, default button |
| Not now | First-run alert, other button |
| Tiling is on, Tiling is paused, Needs permission | Status item accessibility value |
| Opens the TILE32 menu | Status item accessibility help |

**Serves:** all UX entries

### UX-16 Resizing by dragging an edge

**Description:** The user resizes with the normal macOS gesture: dragging a window's edge or corner. TILE32 adds only two things.

- **Neighbours follow.** While the user drags, the window on the other side of the edge shrinks or grows at the same time, so the result is visible before the mouse is released. For an app that redraws too slowly, its windows jump into place on release instead.
- **A percentage label.** In the centre of the resized window's tile, a pill shows the window's share of its split, for example "50%". It uses the same pill style as the drop-zone label (UX-10): 13 point semibold, accent colour, on the window background colour at 90 percent opacity. There is no highlight rectangle.
- **Snapping.** When the edge is within 1 percent of a quarter or a third, the label already shows the value it will snap to (25%, 33%, 50%, 67%, 75%), and on release the edge jumps there. The user can reach exact 50, 25, 25 without precise mouse work.
- **Limits.** When a tile reaches its minimum size, the edge stops following and the label stays at its value.
- On release, the label disappears and all affected windows line up with the 6 point gap.

```
 While dragging A's right edge:

+---------------------+----------+----------+
|                     |          |          |
|          A          |    B     |    C     |
|       ( 50% )       |          |          |
|                     |          |          |
+---------------------+----------+----------+
            edge  ---->|
```

**Serves:** US-28, L8

### UX-17 Window limit

**Description:** A "Window limit" submenu sits below "Excluded apps". It has one group per display, with the display name as a section header and the numbers 2 to 16 as choices; the current limit has a check mark. Choosing a number takes effect at once (US-31.7).

```
+-----------------------------------------------+
| Dell U4924DW                                  |   header
|   2  3  4  ...  11                            |
|   12                                       ✓  |
|   13  ...  16                                 |
| Built-in Retina Display                       |   header
|   6                                        ✓  |
|   ...                                         |
+-----------------------------------------------+
```

- In the "Windows" submenu, windows that TILE32 minimised because of the limit appear under their display with "(minimised to make room)". Choosing one swaps it in (US-31.4).
- The status line counts them: "Tiling 18 windows on 2 displays - 15 minimised to make room".
- Nothing else is shown when a window is swapped: the usual macOS minimise and restore animations are the only feedback.

**Serves:** US-31, US-3.5

### UX-18 About and Help

**Description:** Two items above "Quit TILE32" give information about the app.

- "About TILE32" opens the standard macOS About panel, brought to the front: the app icon, the name, the version and build number from the bundle, the copyright line, and in the credits the 66ideas logo (light or dark variant for the current appearance) with the line "Your windows side by side, arranged with the mouse."
- "TILE32 Help" opens the TILE32 website in the default browser once it exists (`AppLinks.website`). Until then it opens a short help page bundled with the app, in the default browser, in light or dark mode following the system.
- The app icon (the blue "32" on a dark square) and the 66ideas logo come from the 66ideas brand kit. `dev/sync-brand.sh` copies them into `dev/Resources/Brand/` under stable names. The icon also appears in Finder, System Settings (Accessibility, Login Items) and notarization dialogs.

**Serves:** US-1

---

## 2. Decisions taken during review

- **First run:** TILE32 starts paused and nothing moves until the user chooses "Resume tiling" (US-23.5). This replaces the earlier idea of waiting for a first "Tile now".
- **"Tile now" stays** after automatic tiling exists. It is the "start over" command: it replaces each display's arrangement with equal columns (US-4.6).
- **"Make sizes equal"** resets proportions but keeps the arrangement (US-28.9). Both commands act on the Spaces currently shown.
- **Resizing** uses the normal macOS edge drag, with live neighbours, a percentage label and snapping (UX-16).

## 3. Open questions

Numbered UQ-n to keep them apart from the specification's Q-n and the architecture's OQ-n.

| # | Question | Suggested default |
|---|---|---|
| UQ-1 | Should the menu offer a "Tiling is on" check item instead of the "Pause tiling" and "Resume tiling" wording? | Keep the verb pair, because it matches the rule that actions start with a verb. |
| UQ-2 | Is the VoiceOver announcement of the overlay label during a drag worth building? | Yes if it is cheap, otherwise drop it. |
| UQ-3 | (Answered 2026-10-18.) Measured on the owner's Mac: in light mode no accent colour reaches 4.5:1 against the pill (blue 3.5, yellow 1.5); in dark mode all do (4.6 to 11.8). The label uses the accent colour only when it reaches 4.5:1, otherwise the primary text colour, so in light mode it is always the text colour. | Answered |
| UQ-4 | Should "does not fit" show a number next to the icon (current proposal), or only the status line? | Show the number, because it is the only sign of a problem the user would otherwise not notice. |
| UQ-5 | Should the gap (6 points) be adjustable from the menu? | Not in version 1. A fixed gap keeps the menu short. |
| UQ-6 | Does the user want a visual indication of which window has focus (for example a thin outline)? | Not in version 1. The window's own active title bar is enough. |

---

## 4. Traceability: user story to UX entries

| Story | Entries |
|---|---|
| US-1 Menu-bar presence | UX-1, UX-2, UX-3, UX-14 |
| US-2 Permission request and status | UX-2, UX-5, UX-8, UX-9 |
| US-3 See my windows | UX-3, UX-6 |
| US-4 Tile now | UX-3, UX-12 |
| US-5 One layout per display | UX-6 |
| US-6 New windows join | UX-12 |
| US-10 Windows that cannot shrink | UX-2, UX-6, UX-9 |
| US-12 One layout per Space | UX-1, UX-6, UX-9 |
| US-13 Drag by the title bar | UX-13 |
| US-14 Drop to swap | UX-10, UX-11 |
| US-15 Drop to split | UX-10, UX-11 |
| US-16 Preview before release | UX-10, UX-11, UX-14 |
| US-17 Cancel a drag | UX-11, UX-13 |
| US-18 Drag to another display | UX-11 |
| US-19 Snap back | UX-13 |
| US-20 Separate from other title-bar uses | UX-13 |
| US-21 Dialogs and panels stay floating | UX-6, UX-7 |
| US-22 Exclude apps | UX-3, UX-7 |
| US-23 Pause and resume | UX-2, UX-3, UX-4 |
| US-24 Untile | UX-3, UX-4, UX-9 |
| US-25 Start at login | UX-3 |
| US-27 Permission revoked or lost | UX-2, UX-5, UX-9 |
| US-28 Resize by dragging an edge | UX-6, UX-13, UX-16 |
| US-31 Window limit per display | UX-6, UX-9, UX-17 |
| US-32 Full-height column at the display edge | UX-10, UX-11 |

Stories that have no visible interface of their own (US-7, US-8, US-9, US-11, US-26, US-29, US-30) are not listed: their behaviour shows only through the layout itself.
