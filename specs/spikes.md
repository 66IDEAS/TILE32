# TILE32 - Spike results

Results of the spikes in `specs/architecture.md`, section 4. A feature builds on a spike only after its result is written here (constitution, process rule 2).

## S5 Signing and permission - passed (2026-10-18)

**Question:** does a stable signing identity keep the Accessibility permission across rebuilds?

**Method:** the owner granted the permission once to the development build (T-0.12). Claude then rebuilt and relaunched three times. Each build got its own build number, so every build was a different signed app (different code hash).

| Run | Build number | Code hash (start) | Status item after launch | Permission alert |
|---|---|---|---|---|
| 1 | 20261018124716 | f437f0e83721 | Tiling is paused (granted) | not shown |
| 2 | 20261018124726 | f3f26a8eb9da | Tiling is paused (granted) | not shown |
| 3 | 20261018124737 | 7a0fda10f383 | Tiling is paused (granted) | not shown |

**Result:** the permission survives rebuilds when the app is signed with "Apple Development: Alexander Ilg" at the fixed path `dev/build/TILE32.app`. TA-22 is confirmed. As expected, a Developer ID release build (T-3.8) will have a different signature and will need the permission once more.

**Also confirmed in the same round:**
- The first-run alert appears with the exact UX-8 text when the permission is missing.
- After granting, the icon changed from the warning triangle to the paused symbol without a restart (US-2.3, TA-8).
- "Quit TILE32" in the menu ends the app (owner check).

## S6 Space functions - first facts (2026-10-18, in progress)

The full S6 session with Space switches is task T-0.18. First facts from T-0.13:

- **All four functions are present** on macOS 27.0.1 (build 26A434), found under their SkyLight names: `SLSMainConnectionID`, `SLSCopyManagedDisplaySpaces`, `SLSCopySpacesForWindows`, `_AXUIElementGetWindow`. The older `CGS` names were not needed.
- **"Displays have separate Spaces" is switched off** on the owner's Mac (`com.apple.spaces spans-displays = 1`). The window server reports one entry named "Main", and both displays show the same Space (id 4, the second desktop). TILE32 maps that one Space to both displays and keeps one tree per display for it (TA-26), as designed for US-12.6.
- The owner has at least six desktops (Space ids 3 to 8 at the time of reading).

Still to answer in T-0.18: correct Space for every window across many Spaces, full-screen Spaces, moving windows between Spaces, the setting switched on, UUID stability after a logout, and writing frames to windows on hidden Spaces (S3).

## S3 Window listing - first facts (2026-10-18, in progress)

From the first full reading in T-0.14 (debug dump mode, no window moved). Window titles are not recorded here.

- **Speed:** 37 regular apps, 31 windows, 662 ms in total, read in parallel with one queue per app. Apps that answered took 42 to 651 ms each.
- **Apps that did not answer:** 8 of 37 apps (among them Mail, Word, PowerPoint, Xcode) returned `kAXErrorCannotComplete` (-25204) after the 0.5 second messaging timeout. TILE32 was not blocked. Likely causes: App Nap or apps busy on another Space. To check in T-0.18: whether a longer timeout (1 s) or a second attempt helps, and whether those apps have windows on the current Space at all.
- **Windows of other Spaces are probably not listed:** all 31 windows were on the current Space (id 4), except one minimised window that reported Space 8. Several apps with windows elsewhere listed none. This contradicts the assumption in TA-16 that `kAXWindowsAttribute` lists windows of all Spaces. If T-0.18 confirms it, TA-16 and TA-20 change: windows on hidden Spaces are known only through the window server list (window number, owner, Space), and their Accessibility element is read when their Space is shown. This does not affect the rule that TILE32 never writes to hidden Spaces.
- **Classification inputs work:** subroles `AXStandardWindow`, `AXDialog` and `AXUnknown` (small floating helper windows) appear as expected, and fixed-size windows are detected.
- One process reported pid -1 ("Device Hub"); apps without a valid pid are now skipped.

## Observation for open question Q-3 (2026-10-18)

The owner's current desktop holds **27 windows that would be tiled**, spread over both displays (most on the ultrawide). As equal columns, 25 windows on the 5120 point wide display would give tiles of about 200 points, the minimum of rule L8, which is not usable. Q-3 ("how many windows can one display hold") therefore matters before "Tile now" (T-0.24) arranges real windows. Options to put to the owner: tile only the windows of the frontmost apps, tile at most a fixed number per display and leave the rest floating, or fill a grid instead of columns when there are many windows.

## FakeWindows observations (2026-10-18)

- A floating tool panel (`NSPanel` with the utility style) reports the subrole `AXStandardWindow`, but it is not resizable, so it floats as "not resizable". The classification is right, the reason shown is not the most natural one; to revisit in T-3.1.
- A sheet is not listed as a window of its own; it belongs to its parent window, as TA-10 assumed.
- A save panel opened by `NSSavePanel.begin` did not appear in the window list during the reading. To check again in T-3.1.
- A frozen app is now given up after 0.5 to 1.5 seconds (task T-0.14).

## S3 and S6 - reading with the spike tools (2026-10-18, before session A)

First run of "Log Spaces" and "Log windows" (task T-0.17), on the current desktop only, without switching:

- **Space table:** one shared entry ("Main"), 7 desktops, no full-screen Space at the time. Both displays show Space 4 (desktop 2).
- **Window server:** 465 normal (layer 0) windows of regular apps in total, 36 on screen. 398 of them report no Space at all: windows that are not ordered in (hidden helpers, cached windows). Per Space: 43 on Space 4 (current), 10 on Space 5, 2 on Space 7, 4 on Space 8, 7 on Space 9, and 1 window on all seven Spaces.
- **Accessibility lists only the current Space:** 37 windows, all on Space 4 except one minimised window (Space 8). None of the windows on Spaces 5, 7, 8 and 9 was listed. This confirms the observation of T-0.14 on a larger sample.
- **Window server windows on the current Space that Accessibility does not list:** 10, all small or off screen (toolbars 20 points high, popups, small helper windows). None of them is a candidate for tiling.
- One app did not answer within the timeout.

**Consequence for the design (to confirm in session A, then update TA-16 and TA-20):** TILE32 learns about windows on hidden Spaces only through the window server list (number, owner, Space) and reads their Accessibility element when their Space is shown. Dormant trees therefore hold window numbers, which are stable while a window lives, and get matched to Accessibility elements on return. This fits the existing rule that TILE32 never writes to hidden Spaces.

## S2 Frame writing - FakeWindows only (2026-10-18, before session B)

The frame write tool (task T-0.19) was run on two FakeWindows windows only, so none of the owner's windows moved. The run with real apps is session B (T-0.20).

| Case | Normal window | Window with minimum size 1800 x 1000 |
|---|---|---|
| Smaller frame on the same display | matches, 5 ms | does not fit: stays 1800 x 1032 (content minimum plus 32 point title bar) |
| Left half of the ultrawide (2551 x 1341) | matches, 1 to 3 ms | matches, 4 to 13 ms |
| Moved to the laptop display (1000 x 700) | matches, 1 to 2 ms | does not fit, 1 to 30 ms |
| With the enhanced-UI workaround | same results | same results |

- **The write sequence size, position, size works**, also across displays with different scales (1x ultrawide, 2x laptop), and the read-back detects minimum sizes reliably (US-10, TA-11).
- **No errors** from any write (`AXError` 0 for size and position).
- The minimum-size window could not be put back to its original frame, because its minimum was set after it opened, so its original frame was below its own minimum. A real app cannot be in that state. Untile (T-3.3) must still expect it and keep such a window at its minimum.
- The workaround made no difference for FakeWindows, as expected for a simple AppKit app. Session B checks real apps.

## Session A, part 1: desktop switches and moves (2026-10-18, owner session)

Run with the debug build logging every Space switch. Window titles are not recorded.

- **Desktop switches:** every switch was reported at once (`activeSpaceDidChangeNotification`), and the Space table always named the right Space and desktop number. When the owner swiped quickly across several desktops, the desktops passed over were not reported as shown, which is fine: TILE32 only acts on the desktop where the user stops.
- **Window moved with Mission Control (MD22, desktop 2 to 3):** the window server reported the new Space correctly. TILE32's diagnostics only read on Space switches, so the move was seen when the owner switched to desktop 3. **Open for M1 (T-1.6, S4):** find out which notification, if any, tells TILE32 that a window left the shown desktop while the user stays there (candidates: `kAXUIElementDestroyed`, `kAXWindowMoved`, the window dropping out of the on-screen list). If there is none, check the shown desktop's windows when Mission Control closes.
- **Window carried while switching (Finder, title bar held, Ctrl + right arrow):** the Space switch came 1 second after the press, and the move was reported immediately. The drag tracker classified the gesture as a click, because the window did not move relative to the cursor. **Rule for TA-14:** a Space switch while the button is down ends the gesture without a drop; the move itself is handled by US-29.
- **Windows on all desktops:** an Xcode window that is on every Space was reported as "moved" on every switch, because the list of Spaces came back in a different order. Fixed: Spaces are compared as sets.
- **Apps that did not answer** in time varied from switch to switch (WhatsApp, ChatGPT, Outlook, WhichSpace); none blocked a reading.

## Session A, part 2: full screen and writing to a hidden desktop (2026-10-18, owner session)

- **Full screen:** entering full screen created a Space of type 4 (Space 903, no desktop number), reported at once; switching away, back, and leaving full screen were all reported correctly. TA-16 and US-30 are confirmed.
- **Writing to a window whose desktop is not shown:** a FakeWindows window was read while visible on desktop 2. When the owner opened Mission Control and desktop 3 came up, desktop 2 counted as not shown, and the test wrote a frame 200 points to the right and 100 points down. The write returned no error, Accessibility read the new frame back, and the window server later reported exactly that frame. **An element read while its window was visible stays valid, and frames can be written to it while its desktop is hidden.** The owner saw the window already at its new place when looking at desktop 3.
- **Mission Control:** while it is open, the window server reports scaled frames (here 562 x 397 for a 640 x 452 window). TILE32 must never take frames from the window server during Mission Control; it reads frames through Accessibility.

**Consequences for the design:**
1. The rule "TILE32 never writes to windows on hidden desktops" stays, as a product decision (nothing changes where the user cannot see it), not because writing is impossible.
2. "Untile" can restore windows on hidden desktops at once, as long as their Accessibility element was read while they were visible. US-24.7 ("restored on the next visit") becomes a fallback for windows TILE32 never saw.
3. Accessibility lists only the windows of the shown desktop (S3, confirmed again). Dormant layouts keep window numbers, and the elements are kept from the last visit.

## Space UUIDs before a logout (2026-10-18, for the S6 question "do UUIDs survive a logout")

| Space | Type | Desktop | UUID |
|---|---|---|---|
| 3 | desktop | 1 | (desktop UUID removed) |
| 4 | desktop | 2 | (desktop UUID removed) |
| 5 | desktop | 3 | (desktop UUID removed) |
| 6 | desktop | 4 | (desktop UUID removed) |
| 7 | desktop | 5 | (desktop UUID removed) |
| 8 | desktop | 6 | (desktop UUID removed) |
| 9 | desktop | 7 | (desktop UUID removed) |

After the owner's next logout or restart, "Log Spaces" is compared with this table.

## S2 Frame writing with the owner's windows - passed (2026-10-18, session B)

All tiled windows on desktop 2 (9 windows of ChatGPT, Claude, VS Code, Safari, Slack, Terminal, plus one FakeWindows window with a minimum size) were sized smaller, to half the Dell, and onto the laptop display, each with and without the enhanced-UI workaround, then put back. The whole run took 4 seconds.

| App | Result | Slowest write |
|---|---|---|
| ChatGPT, Claude, VS Code, Safari, Slack | every write landed exactly | 192 ms (Safari) |
| Terminal | lands within a few points: it sizes in character steps (+1 to +6 points) | 22 ms |
| FakeWindows, minimum size 1800 x 1000 | detected as "does not fit" | 14 ms |

- **Every window of the owner was restored exactly.** The only window not restored was the FakeWindows test window, whose original frame is below its own minimum size (expected, see the FakeWindows run).
- **The enhanced-UI workaround never made a difference.** TILE32 does not use it (TA-11 updated).
- **Size steps:** Terminal (and other apps that size in steps) must count as fitted, otherwise TILE32 would mark it as "does not fit" and retry. Fixed: a window counts as fitted within 16 points of the requested size (`FrameWriteResult.fits`); only a window more than 16 points larger counts as "does not fit". 4 new tests.
- No write returned an error.

## S1 Drag detection - passed (2026-10-18, session C and re-test)

The owner dragged, resized and clicked windows in Safari, Chrome, Slack, Teams, Finder and Terminal (VS Code was dragged but never logged, see below). TILE32 logged every gesture with app and classification, never titles.

| Gesture | Result |
|---|---|
| Title-bar drag, normal speed | recognised in every app |
| Title-bar drag, fast flick | first run: rejected 9 times as "not in lockstep" (mostly Slack and Chrome); the window trails the cursor by 40 to 50 percent of the travel in a flick. After two rule changes all recorded misses count as drags (see below) |
| Edge resize (left, right, top, bottom) | recognised every time, with the right edge |
| Corner resize | recognised every time; both edges reported by release |
| Single and double click on the title bar | never mistaken for a drag |
| Drag inside the content (text selection, scrollbar) | never mistaken for a drag |
| Escape during a drag | **works with the Accessibility permission alone** (OQ-1 answered: yes); holding Escape repeats the key, which is harmless |
| Click on the Dock | correctly finds no window |

**Final rule for "the window follows the cursor" (TA-14):** the window's movement since the press counts as a drag when it is within 12 points plus 35 percent of the cursor's travel, or when it points the same way (cosine at least 0.8) and covers between half and one and a half times the cursor's distance. A window that moves the same way but less than half as far is lagging and gets another reading. A window that moves while the cursor barely does (an app moving its own window) is not a drag. All three misses of the re-test are unit tests now.

**Window source:** the window under the cursor and its frame come from the window server's public list (front-to-back order, answers in milliseconds). This worked in every app and stays the source for the press hit test; the engine's tiled frames are added in M2 to decide whether the window under the cursor is tiled.

**Unexplained:** in the first run, no press at all was logged for Finder, Terminal and VS Code, although the owner dragged them. In a later check with the current build, Finder and Terminal worked perfectly (4 of 4 drags). Possibly the first presses happened while TILE32 was being restarted. To watch in M2 acceptance.

**Sample size:** fewer gestures than the planned 20 drags per app (owner's time); the result is clear enough to build M2 on.

## S4 Notifications and feedback - passed (2026-10-18, stress test)

Automatic tiling of FakeWindows windows only (`--auto-fakewindows`, limit 6), driven by a generated script of 254 actions over 5.7 minutes: open one window, open five at once, splash windows that close after 0.3 seconds, late windows, close, minimise, restore, hide and show the app. Run while the owner was away.

| Measure | Result |
|---|---|
| Changing reconcile runs | 69 |
| Arrivals / departures | 254 / 76 |
| Minimised to make room / brought back | 229 / 49 |
| Frames written | 265; 4 failed during animations and were corrected by the next run; 0 did not fit |
| Loops | none: at most 4 changing runs within any 3 seconds, matching the pace of the script; nothing changed after the script ended |
| End state | 124 test windows: 6 visible, exactly 6 equal columns on the Dell (limit 6, 846 points wide), 118 minimised; no window lost |
| Cost | 14.5 s of CPU time over 6 minutes of continuous churn, 36 MB of memory |

TA-9 and TA-12 are confirmed: observers plus the one-second window-list check catch every change, coalescing keeps runs few, and the settle time stops flapping.
