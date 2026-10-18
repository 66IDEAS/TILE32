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
