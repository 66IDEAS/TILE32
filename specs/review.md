# TILE32 - Review

## M0 Spike - accepted (2026-10-18)

Accepted by the owner on the Dell U4924DW (5120 x 1440) and the built-in display (3456 x 2234).

- [x] Only a menu-bar icon appears after launch, with no Dock icon and no window (US-1.1).
- [x] The menu shows the status line, "Tile now", "Windows" and "Quit TILE32" (US-1.2).
- [x] "Quit TILE32" leaves the windows where they are (US-1.3).
- [x] Without the permission, the alert explains it in plain words and opens System Settings (US-2.1, UX-8).
- [x] Without the permission, the status line says so and "Tile now" is grey (US-2.2, UX-5).
- [x] Granting the permission takes effect without a restart (US-2.3).
- [x] Only the Accessibility permission is ever requested (US-2.5).
- [x] The Windows submenu lists the windows of the shown Spaces by display, with floating windows separate (US-3.1, US-3.2).
- [x] Choosing a window in the submenu brings it to the front (US-3.4).
- [x] "Tile now" arranges equal columns, or two rows when columns would be narrower than 800 points, without moving windows between displays (US-4.1, US-4.2, L2).
- [x] After "Tile now", no two tiled windows overlap and the gap is even (US-4.3, L7).
- [x] Floating and full-screen windows are not moved (US-4.5).
- [x] With more windows than the limit, "Tile now" tiles the most recent ones and minimises the rest; the limit can be changed per display and is remembered (US-31.1 to US-31.3).
- [x] "Untile" restores every window, including windows minimised to make room (US-24, built early).

**Findings during the acceptance:** 12 columns on the Dell were too narrow (about 420 points), so 6 windows did not fit. Fixed with decision D-8 (two rows below 800 points per column) and rechecked by the owner.

**Spikes completed in M0:** S1 drag detection, S2 frame writing, S3 window listing, S5 signing and permission, S6 Space functions (details in `specs/spikes.md`). Open from S6: whether Space UUIDs survive a logout, checked after the owner's next logout.

**Statistics:** 26 M0 tasks done, 132 unit tests, all passing in debug and release.
