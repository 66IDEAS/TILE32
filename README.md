<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="dev/Resources/Brand/tile32-dark.svg">
    <img src="dev/Resources/Brand/tile32-light.svg" alt="TILE32" width="380">
  </picture>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-2E62E8" alt="MIT license"></a>
  <a href="specs/specifications.md"><img src="https://img.shields.io/badge/spec-complete-2E62E8" alt="Specification complete"></a>
  <a href="https://github.com/66IDEAS/TILE32/releases/latest"><img src="https://img.shields.io/github/v/release/66IDEAS/TILE32?color=2E62E8" alt="Latest release"></a>
  <a href="https://66ideas.com"><img src="https://img.shields.io/badge/by-66IDEAS-16181D" alt="By 66IDEAS"></a>
</p>

**TILE32 is a tiling window manager for macOS that you use with the mouse.**
It keeps the windows on each display side by side, without overlapping, and you
rearrange them by dragging a window onto another one. No keyboard shortcuts to
learn, no configuration file.

It is for anyone who finds keyboard-driven tiling tools too complex and
snap-only tools too loose, because snapping never stops windows from piling up.
The name comes from the 32:9 ultrawide display it was designed on, and it works
just as well on a laptop screen.

## What TILE32 does

- **Automatic tiling:** new windows join the layout, closed windows leave a gap
  the others fill, and narrow columns turn into a second row.
- **Drag to split:** drag a window by its title bar and drop it on another
  window. The centre swaps the two, the edges split the target. A highlight
  shows the result before you let go, and Escape cancels.
- **Adjustable sizes:** drag the edge between two windows to resize both. Sizes
  snap to quarters, thirds and halves; "Make sizes equal" resets them.
- **Every display and every Space:** each desktop on each display has its own
  layout, and TILE32 follows when macOS moves a window between them.
- **Window limit:** set how many windows share a display. Extra windows are
  minimised and come back when you use them.
- **Always in control:** pause with one click, or "Untile" to put every window
  back where it was. Dialogs, panels and apps you exclude stay floating.

## Get started

### Use the Mac app

Requires **macOS 27 or later on an Apple-silicon Mac**.

Download the signed and notarized DMG from the
[latest GitHub Release](https://github.com/66IDEAS/TILE32/releases/latest).
Open it and drag TILE32 into Applications. TILE32 does not check for updates
itself; new versions appear on the releases page.

TILE32 needs the Accessibility permission to move windows, and it starts paused.
Choose "Resume tiling" in its menu bar menu to begin, and "TILE32 Help" for a
short guide.

### Build a local copy

You need Xcode 27 and an Apple Development signing identity.

```bash
cd dev && TILE32_DEV_IDENTITY="Apple Development: Your Name" ./build-app.sh TILE32 dev
```

The app lands in `dev/build/TILE32.app`. Run the tests with `swift test` in
`dev/`. [CONTRIBUTING.md](CONTRIBUTING.md) has the details.

## Repository layout

| Path | Purpose |
| --- | --- |
| [`specs/`](specs/) | Functional requirements, UX, architecture, spikes, and implementation tracking |
| [`dev/`](dev/) | The Swift package: the app, its modules, tests, and the build script |
| [`dev/Sources/FakeWindows/`](dev/Sources/FakeWindows/) | A test app with windows of every kind, for checks that move windows |
| [`prototype/`](prototype/) | The interactive HTML prototype of drag-to-split |

## The specification

- [Functional specification](specs/specifications.md): user stories, layout
  rules, decisions, and what is out of scope for version 1.
- [UX specification](specs/ux.md): the menu, the drop overlay, and every
  user-visible text.
- [Architecture](specs/architecture.md): modules, the layout engine, Spaces,
  and the macOS APIs used.
- [Task list](specs/tasks.md) and [spike results](specs/spikes.md):
  implementation progress, problems found, and how they were solved.

## Privacy

TILE32 has no accounts, analytics, telemetry, or network access. It reads window
positions and sizes to arrange them and never reads window content. Release
builds do not log window titles, and remembered layouts store only a hash of
each title.

## Contributing

Issues and pull requests are welcome for the specifications, documentation, and
the implementation. Start with [CONTRIBUTING.md](CONTRIBUTING.md) for bug
reports, proposed behavior changes, and building and testing.

## License

[MIT](LICENSE). Free to use, modify, and distribute, including commercially,
under the terms of the license. The app icon and the TILE32 and 66ideas logos are
brand assets and are not covered by the license, see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

---

<p align="center"><sub>A <a href="https://66ideas.com">66IDEAS</a> product · WENIGER. ABER BESSER.</sub></p>
