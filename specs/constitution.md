# TILE32 - Project constitution

Status: draft for review
Date: 2026-10-11, revised 2026-10-18

These rules apply to every change in this project, by people and by AI assistants. A change that breaks a rule is not finished.

## Product rules

1. **Mouse first.** Every feature works with the mouse alone. No keyboard shortcut is ever required. An optional shortcut uses at most two simultaneous keys and must work on a German keyboard layout (where Option plus a letter types characters such as @ and ~).
2. **No overlap.** Windows never overlap, except in the one documented case of a window that cannot shrink (US-10).
3. **Never leave a window unreachable.** After any action, crash, display change or permission loss, every window is fully visible on some display. Pause, Untile and Quit are always reachable from the menu bar.
4. **Do not touch what should not be touched.** Dialogs, sheets, panels, excluded apps and native full-screen windows are never moved or resized.
5. **Nothing moves unasked on first run.** A fresh install starts paused. The user starts tiling with one menu action.
6. **Every Space keeps its arrangement.** Switching Spaces never moves a window, and TILE32 never writes to a window on a Space that is not shown.

## Technical rules

1. **Public APIs, with one listed exception.** Only the four read-only undocumented functions named in architecture TA-26 may be used, only inside `TileSpaces`, resolved at runtime, with a working fallback when they are missing. Adding any other undocumented function needs the owner's decision and an update of TA-26. Never: SIP changes, code injection, scripting additions, or undocumented functions that change state.
2. **One permission.** The app asks only for the Accessibility permission. Screen Recording is never requested. A feature that would need a second permission is dropped instead (Escape cancel is the known case, architecture OQ-1), unless the owner decides otherwise and the specification is changed.
3. **No network, no telemetry.** The app makes no network calls and sends no data anywhere. It never reads window content. Window titles are not logged in release builds.
4. **The core stays pure.** `TileCore` imports no AppKit, no Accessibility and no other system framework beyond Foundation and CoreGraphics value types. All layout decisions live there as pure functions.
5. **Core logic is tested.** Every operation in `TileCore` has unit tests before it is used by the app, including empty and single-window cases and the scenarios ported from the prototype. `swift test` passes before any milestone is called done.
6. **One owner of state.** Only the layout engine changes trees, the window registry and original frames. UI and input code send events and display state. They make no layout decisions.
7. **Accessibility calls never block the UI.** AX reads and writes run off the main thread, on per-app queues, with a messaging timeout. A slow app must never freeze TILE32 or other apps' windows.
8. **No fighting loops.** Frame writes made by TILE32 are recognised and ignored when they come back as notifications. A window that does not accept its frame is retried once and then left alone until the layout changes.
9. **One place for coordinates.** Conversion between Accessibility and AppKit coordinates happens in `TileGeometry` only.
10. **Stable signing.** Builds are signed with a stable identity and a fixed output path so the Accessibility permission survives rebuilds. The app identifier is `com.66ideas.tile32` and never changes.
11. **Always notarizable.** Every build uses the hardened runtime and no entitlement exceptions, so a release can be signed with Developer ID and notarized at any time.

## Process rules

1. **Traceable.** Every behaviour traces to a user story in `specs/specifications.md`, and every architecture entry names the stories it serves. New behaviour needs a story first.
2. **Small milestones, riskiest first.** Work follows M0 to M3 in the specification. The spikes in `specs/architecture.md` (section 4) are done before the features that depend on them. A spike's result is written down before building on it.
3. **Verify on the real machine.** A story is done when its acceptance criteria pass on the owner's Mac, on both the ultrawide and the laptop display. Unit tests alone are not enough for anything that touches windows.
4. **Clean origin.** The project starts from scratch. No code or design from any earlier project of the owner is used. Code taken from open-source projects must be MIT-compatible, marked with its origin in the file, and listed in `THIRD_PARTY_NOTICES.md`.
5. **Ask before committing.** No commits, remotes, branches or pushes unless the owner asks.
6. **Temporary files** go in `tmp/` at the project root, which is listed in `.gitignore`. Never use system temporary folders such as `/tmp`.

## Writing rules

1. All text, in code comments, documents, user interface and logs, is in English.
2. The em dash character is never used. Use a plain hyphen.
3. User-facing text uses sentence case, short verbs for actions, and no exclamation marks.
4. Comments explain why, not what. Names are descriptive. New code matches the style of the surrounding code.
