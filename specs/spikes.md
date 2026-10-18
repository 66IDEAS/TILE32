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
