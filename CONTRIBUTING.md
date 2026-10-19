# Contributing to TILE32

Contributions are welcome to the product specifications, documentation, and
the implementation. Please keep each issue or pull request focused on one topic.

## Report a bug

Open a [GitHub issue](https://github.com/66IDEAS/TILE32/issues). Include:

- The TILE32 version and build (shown in "About TILE32"), macOS version, and Mac architecture
- Your displays (model, resolution, arrangement) and whether "Displays have
  separate Spaces" is on in System Settings
- The apps involved and the steps to reproduce, with expected and actual behavior
- The relevant lines from the TILE32 log, with private information removed

To capture the log, run this in Terminal while you reproduce the problem:

```bash
/usr/bin/log stream --level info --predicate 'subsystem == "com.66ideas.tile32"'
```

The log names apps and window numbers, never window titles. Remove anything
private before you post it.

Check the [task list](specs/tasks.md) first: known problems are recorded there
with each task. Do not upload screenshots of private windows, access tokens,
signing credentials, or unredacted logs.

## Propose a product change

Read the [functional specification](specs/specifications.md) and the
[UX specification](specs/ux.md). Explain the use case, affected user stories,
and proposed acceptance criteria in an issue or a focused specification PR.
Discuss substantial changes before investing in a large implementation.

Respect the principles of the specification: windows never overlap, everything
works with the mouse alone, and no keyboard shortcut is ever required. Keyboard
shortcuts, other layout types, and window animations are outside version 1.

## Change the implementation

The app is a Swift package in [`dev/`](dev/). Build and test with the command-line
tools; there is no Xcode project.

```bash
cd dev && swift test
```

```bash
cd dev && ./build-app.sh TILE32 dev
```

`build-app.sh` signs with the maintainer's Apple Development certificate. Set
`TILE32_DEV_IDENTITY` to the name of your own signing identity. Keep the app at
a fixed path and the identity stable, or macOS asks for the Accessibility
permission again after every build.

In your pull request:

- Link the issue or the relevant user story.
- Describe what changed and why.
- Add tests for `TileCore` and `TileEngine` changes, and state exactly which
  checks you ran. Manual checks with real windows belong in the description.
- Update the specifications and [the task list](specs/tasks.md) when behavior changes.
- Keep every user-visible text in line with the table in UX-15: sentence case,
  no exclamation marks, no em dashes.

Document checks you could not run instead of claiming they passed. Do not commit
application bundles, build caches, or credentials.

Keep TILE32 local and minimal: no network access, no telemetry, no accounts, and
no reading of window content. Undocumented macOS functions are allowed only
read-only, for Spaces and window numbers, resolved at runtime with a fallback.
Follow native macOS conventions and check VoiceOver for any menu or overlay change.

Test with the FakeWindows app (`./build-app.sh FakeWindows`), not with your own
windows, when a change moves windows.

## License

TILE32 is [MIT-licensed](LICENSE). Contribute only material you have the right to
share under that license. Code taken from other open-source projects must be
MIT-compatible, name its origin in a comment, and be listed in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
