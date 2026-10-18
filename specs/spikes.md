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
