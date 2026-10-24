# TILE32 - Technical architecture

Status: draft for review
Date: 2026-10-11, revised 2026-10-18
Inputs: `specs/specifications.md` (US-1..US-31, layout rules L1-L9, N-1..N-12, C-1..C-10), `specs/constitution.md`
Reference prototype for the layout logic: `prototype/index.html` (functions `norm`, `without`, `repl`, `swapIds`, `layoutTree`, `zoneOf`, `applyDrop`)

Each entry has a number (TA-n), a title, a description, and a "Serves" line that lists the user stories (US), layout rules (L), non-functional requirements (N) and constraints (C) it supports. Section 9 maps every user story back to the entries.

## 1. Overview and module diagram

TILE32 is split into one pure core and several thin layers that touch the operating system. All decisions about layout are made in the pure core, so they can be unit tested without a screen.

```
+---------------------------------------------------------------------+
| TILE32.app  (menu-bar app, LSUIElement)                             |
|                                                                     |
|  TileUI  (@MainActor)            TileInput (@MainActor)             |
|  - MenuBarController             - MouseDragTracker                 |
|  - OverlayController             - EscapeMonitor                    |
|  - PermissionGuide               - (NSEvent global monitors)        |
|        |  commands/state                |  drag events              |
|        v                                v                           |
|  +---------------------------------------------------------------+  |
|  | TileEngine  (actor LayoutEngine)                              |  |
|  | - owns: window registry, one LayoutTree per Space and display,|  |
|  |   original frames, exclude list, paused/permission state      |  |
|  | - coalesces events, decides, asks AX layer to apply frames    |  |
|  +-------------------------------+-------------------------------+  |
|           pure calls |                         | async commands/events |
|                      v                         v                      |
|  +---------------------------+   +--------------------------------+  |
|  | TileCore (pure, no OS)    |   | TileAX (AXWorker)              |  |
|  | - LayoutTree, operations  |   | - AXObserver thread (run loop) |  |
|  | - frames(in:gap:)         |   | - per-app serial queues        |  |
|  | - zone(at:in:), dropTarget|   | - read attributes, set frames  |  |
|  +---------------------------+   +--------------------------------+  |
|                                                                     |
|  TileGeometry (display + coordinate conversion, uses AppKit types)  |
|  TileSpaces   (which Space is shown, which Space a window is on;    |
|                read-only undocumented functions, loaded at runtime) |
+---------------------------------------------------------------------+
        |                       |                        |
   macOS: NSWorkspace,     macOS: Accessibility     macOS: SkyLight /
          NSScreen                API                CoreGraphics (private,
                                                     read-only)
```

Dependency rule: `TileCore` imports only Foundation and CoreGraphics value types. `TileAX`, `TileInput`, `TileUI` and `TileSpaces` import system frameworks. `TileEngine` imports `TileCore` and talks to the OS only through protocols that `TileAX`, `TileGeometry` and `TileSpaces` implement, so the engine can be tested with fakes. All undocumented functions live in `TileSpaces` and nowhere else (TA-26).

---

## 2. Entries

### TA-1 Platform, language and deployment target

**Description:** The app is written in Swift (Swift 6.4 toolchain, Xcode 27.0) with the Swift 6 language mode and strict concurrency checking switched on. It is an AppKit menu-bar app that uses SwiftUI only where it saves effort (for the test app). It runs on Apple Silicon under macOS 27. The deployment target is macOS 27.0 for version 1, because the only machine in use is the owner's Mac. All APIs used are public, with one documented exception: a small list of undocumented, read-only functions for Spaces and window numbers (TA-26). Version 1 uses no SIP change, no code injection, no scripting addition and no screen recording. The app must stay notarizable (TA-22).

**Serves:** N-8, N-11, C-5, C-9, US-2

### TA-2 Packaging and module structure

**Description:** The code lives in one Swift package, `TileKit`, with library targets `TileCore`, `TileLog`, `TileGeometry`, `TileSpaces`, `TileAX`, `TileEngine`, `TileInput` and `TileUI`, plus test targets for `TileCore`, `TileGeometry` and `TileEngine`. `TileLog` holds the loggers of TA-23, so that `TileCore` never imports `os`. The app itself is a thin executable target `TILE32` that wires the modules together and is assembled into a `.app` bundle by a build script (see TA-22). A second executable target `FakeWindows` is a small SwiftUI app used only for testing (see TA-24). Keeping the package SwiftPM-only avoids a hand-edited Xcode project file; Xcode can still open `Package.swift` for debugging.

**Serves:** N-3, N-5 (via testability), all stories (structure)

### TA-3 Layout data model

**Description:** The layout of one Space on one display is a value type with no references to windows other than an opaque identifier.

```swift
public struct WindowID: Hashable, Sendable { public let raw: UInt64 }   // issued by the engine

public enum SplitDirection: Sendable { case horizontal, vertical }      // horizontal = side by side

public struct SplitChild: Equatable, Sendable {
    public var node: LayoutNode
    public var weight: Double                  // share of the split, 0 < weight <= 1; siblings sum to 1
}

public indirect enum LayoutNode: Equatable, Sendable {
    case leaf(WindowID)
    case split(SplitDirection, [SplitChild])   // count >= 2 after normalisation
}

public struct LayoutTree: Equatable, Sendable {
    public var root: LayoutNode?               // nil = empty layout
}

public enum DropZone: Sendable { case center, left, right, top, bottom }

public struct LayoutKey: Hashable, Sendable {  // one layout per Space and display
    public let space: SpaceID
    public let display: DisplayID
}
```

The engine keeps `[LayoutKey: LayoutTree]`. Only the trees whose Space is currently shown are applied to windows; all others are dormant and never cause a write (US-12.3). `DisplayID` is the display's UUID (from `CGDisplayCreateUUIDFromDisplayID`), which stays the same across reconnects, unlike the numeric display number. `SpaceID` comes from `TileSpaces` (TA-26). Weights sit on the parent's child entries, so a weight belongs to a position in the tree, not to a window (rule L1).

**Serves:** L1, L2, US-5, US-12

### TA-4 Layout tree operations and normalisation

**Description:** All changes to a tree are pure functions that return a new tree. They are ported from the prototype, with the same names where possible.

| Function | Behaviour | Prototype origin | Rule |
|---|---|---|---|
| `normalized()` | Drops empty parts, collapses a split with one child into that child (the child takes over the parent's weight), and flattens a split whose child is a split of the same direction. When flattening, each grandchild's weight is multiplied by its parent's weight, so every window keeps its size on screen. Finally the weights of every split are rescaled to sum to 1 | `norm` + weights | L5 |
| `removing(_ id)` | Removes the leaf and divides its siblings' weights by `1 - removedWeight`, then normalises | `without` + `norm` | L4 |
| `appending(_ id, availableWidth:)` | When another column would be narrower than 800 points, puts the leaf below the leftmost single-window column (a vertical pair, D-9). Otherwise: if the root is a horizontal split with `n` children, multiplies their weights by `n / (n + 1)` and adds the leaf with weight `1 / (n + 1)`. If the root is a leaf or a vertical split, wraps it in a new horizontal split of two children at 0.5 each. If the tree is empty, the leaf becomes the root | `addWin` | L3 |
| `swapping(_ a, _ b)` | Exchanges the two window ids; all weights stay where they are | `swapIds` | L1, US-14 |
| `splitting(target:, with:, zone:)` | Removes the dragged leaf (`removing`), then replaces the target leaf with a split of two children at 0.5 each, in the target's position and with the target's weight (horizontal for left/right, vertical for top/bottom; dragged window first for left/top, last for right/bottom), then normalises | `applyDrop` + `repl` | L6, US-15 |
| `flat(_ ids: [WindowID])` | Builds a horizontal split of equal columns from an ordered list | initial state | L2, US-4 |
| `arranged(_:availableWidth:)` | The default arrangement of "Tile now": `flat` columns, or two rows of columns (a horizontal split of vertical pairs) when columns would be narrower than 800 points | new | L2, D-8, US-4 |
| `resizing(window:, edge:, to:, in rect:)` | Finds the nearest ancestor split in the edge's direction in which the window's branch has a neighbour on that side, and moves the boundary between the two to the given screen coordinate: only those two weights change. Clamps to the minimum of rule L8 (10 percent of the split, at least 200 points). Returns the tree unchanged for an outer edge, which has no neighbour | new | L8, US-28 |
| `snap: true` on `resizing`, with `snappedRatio(_:)` | Moves the boundary to the nearest of 1/4, 1/3, 1/2, 2/3, 3/4 of its split when within 0.01, measured on the cumulative position of the boundary. Used on release, not while dragging | new | L8, US-28.5 |
| `dropping(_:on:zone:)` | Dispatches a drop: `swapping` for the centre zone, `splitting` for an edge zone | `applyDrop` | L6 |
| `equalized()` | Sets every weight in every split to `1 / n` without changing the structure | new | US-28.9 |
| `replacing(_ old:, with new:)` | Puts a window in the place of another one; the arrangement and the weights stay the same | new | L9, US-31 |

Edge cases that must be covered by tests: dragging the only window, dropping a window on itself (no-op), a target that is not in the tree (no-op), a tree that shrinks to one leaf, weights that drift through many operations (they must always sum to 1 within 1e-9), resizing at the minimum, resizing an outer edge, and dropping onto a window of a different display or Space (handled by the engine as remove from tree A plus insert into tree B, see TA-14).

**Serves:** L1-L6, L8, US-4, US-6, US-7, US-14, US-15, US-18, US-28

### TA-5 Frame computation, gaps and rounding

**Description:** `frames(in rect: CGRect, gap: CGFloat) -> [WindowID: CGRect]` is a pure function. It divides the rectangle recursively according to the weights: each boundary sits at the cumulative sum of the weights before it. The gap rule L7 is met by insetting the display rectangle by `gap/2` and every resulting tile by `gap/2`, which gives a gap of `gap` between tiles and at the display edge.

To avoid one-point seams, rounding is done on tile edges, not on sizes: each boundary position is computed in exact arithmetic and rounded to a whole point once, and both neighbours use the same rounded boundary. AX works in points, so mixed-DPI displays need no extra scaling. The default gap is 6 points and is a constant in version 1.

The same module exposes `rawShares(in:)`, which returns the tiles without gaps and rounding. It is used for hit testing and for the overlay, as in the prototype, so a drop zone never depends on the gap size.

**Serves:** L1, L7, US-4, US-6, N-10

### TA-6 Drop zones and drop-target hit testing

**Description:** Two pure functions in `TileCore`:

- `zone(at point: CGPoint, in rect: CGRect) -> DropZone`, ported from `zoneOf`. With `rx` and `ry` as the relative position inside the tile: the zone is `.center` when `0.28 < rx < 0.72` and `0.28 < ry < 0.72`, otherwise the edge with the smallest distance among `rx` (left), `1 - rx` (right), `ry` (top), `1 - ry` (bottom). Ties resolve in the order left, right, top, bottom, as the prototype does through `Object.keys` ordering.
- `dropTarget(in tree, display rect, at point, excluding dragged) -> DropTarget?`, which finds the tile under the cursor using `rawShares`, skips the dragged window, and returns `.window(WindowID, DropZone, tileRect)`. If the tree holds no window other than the dragged one, and the cursor is inside the display rectangle, it returns `.emptyDisplay(displayRect)` instead, which the overlay shows as "Move to this display" (US-16.4, US-18.3). A second helper `previewRect(target)` returns the area that the overlay highlights: the whole tile for `.center`, the half on that side for an edge zone, and the whole usable area for `.emptyDisplay`.

The centre-zone constants (0.28 and 0.72) live in one place so that open question Q-10 can be answered by changing two numbers.

**Serves:** L6, US-14, US-15, US-16

### TA-7 Coordinate systems and displays

**Description:** The Accessibility API reports and accepts positions in global screen coordinates with the origin at the top-left of the primary display and y growing downward. AppKit (`NSScreen`, `NSEvent.mouseLocation`, `NSWindow`) uses the origin at the bottom-left of the primary display with y growing upward. There is exactly one conversion point, the `TileGeometry` module, with two functions: `axRect(fromAppKit:)` and `appKitRect(fromAX:)`, both using the primary display's height. No other module converts coordinates.

For each display, `TileGeometry` provides: the `DisplayID` (UUID), the usable area (`NSScreen.visibleFrame` converted to AX coordinates, which excludes the menu bar and Dock and respects their auto-hide), and a lookup `display(containing point:)`. The two expected displays are a 5120x1440 ultrawide (32:9) and a 3456x2234 built-in Retina display. All geometry is in points, so Retina scaling needs no special handling, and tests include very wide and very tall tiles.

**Serves:** US-5, US-9, N-10

### TA-8 Accessibility access and permission lifecycle

**Description:** All window control uses the Accessibility API (`AXUIElement`, `AXObserver`). At launch the app calls `AXIsProcessTrustedWithOptions` without the prompt option and shows its own explanation first (US-2.1). The explanation's button calls it again with the prompt option. That call is what registers TILE32 in the Accessibility list of System Settings, and macOS shows its own short dialog with an "Open System Settings" button. The system dialog cannot be avoided without losing the automatic registration, so the UX accepts it (UX-8). The later menu item "Open Accessibility settings..." (UX-5) opens the pane directly through the `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` URL. While the permission is missing the engine is in state `.noPermission` and performs no AX writes.

The permission state is polled on a timer (every 2 seconds, one cheap call). In addition the app observes the distributed notification `com.apple.accessibility.api` to react sooner, but nothing depends on that notification. Granting the permission moves the engine to `.running` and starts discovery. Revoking it moves the engine to `.noPermission`, stops all frame writes, shows the warning icon, and leaves windows where they are (US-27). Only the Accessibility permission is requested. Escape detection (TA-14) must work without any further permission, or it is dropped (see open question OQ-1).

**Serves:** US-2, US-27, N-5, C-1, C-8

### TA-9 Window discovery and tracking

**Description:** On start and when permission is granted, the engine discovers all running apps with `activationPolicy == .regular` (`NSWorkspace.shared.runningApplications`). For each one, the AX layer creates an application element (`AXUIElementCreateApplication(pid)`), reads its windows, and registers an `AXObserver` for:

- on the application element: `kAXWindowCreatedNotification`;
- on each window element: `kAXUIElementDestroyedNotification`, `kAXWindowMiniaturizedNotification`, `kAXWindowDeminiaturizedNotification`, `kAXWindowMovedNotification`, `kAXWindowResizedNotification`.

New apps are picked up through `NSWorkspace.didLaunchApplicationNotification`, and gone or hidden apps through `didTerminateApplicationNotification`, `didHideApplicationNotification` and `didUnhideApplicationNotification`. The workspace notifications cover app hide and show, so the equivalent AX application notifications are not subscribed. All observer run-loop sources are attached to one dedicated run-loop thread (TA-13). The callbacks do nothing but post a small `Sendable` event to the engine.

A newly created window is often not fully set up when `kAXWindowCreated` fires (empty title, no subrole yet). The engine therefore waits for the debounce interval of TA-12 and then reads and classifies the window.

**Return hint (US-8.2):** when a window leaves the layout because it was minimised, its app was hidden, or it entered full screen (not closed), the engine stores a return hint before removing it: the `WindowID` of its nearest sibling leaf and the side it was on (`DropZone`). When the window comes back, the engine applies `splitting(target: sibling, with: window, zone:)` if the sibling is still in that layout's tree, otherwise `appending`. The returning window takes half of the sibling's tile, as for any split. The hint is dropped when the window closes.

**Serves:** US-3, US-6, US-7, US-8, US-11

### TA-10 Window classification

**Description:** A window is tiled only if all of these are true, otherwise it is floating (with a reason that the menu can show):

1. The owning app has `activationPolicy == .regular`.
2. Role is `AXWindow` and subrole is `AXStandardWindow`.
3. The `AXSize` attribute is settable (`AXUIElementIsAttributeSettable`), so the window can be resized.
4. The window is not minimised, not in native full-screen (the `AXFullScreen` attribute), and not modal (`AXModal`).
5. Its size is at least a minimum (default 200x120 points), so tiny helper windows are not tiled.
6. The app's bundle identifier is not in the exclude list.

Dialogs, sheets, open and save panels, floating tool windows and popovers normally have another subrole (`AXDialog`, `AXFloatingWindow`, `AXSystemDialog`) or are sheets attached to a parent window, so they fall out at rule 2. Classification is re-run when a window's title, subrole, size or the exclude list changes, because some apps change a window's nature after creation. A window can switch between floating and tiled at any time, and the engine treats this as a close or a new window.

**Serves:** US-12, US-21, US-22

### TA-11 Applying frames to windows

**Description:** The AX layer applies a frame through the attributes `AXSize` and `AXPosition`. To work reliably at display edges and when growing or shrinking across displays, the write sequence is size, position, size. After the writes, the frame is read back. If the resulting size is more than 16 points larger than requested in either dimension, the window has a minimum size: the engine marks it "does not fit", anchors it at the top-left of its tile, retries once, and stops trying until its tile or the layout changes (US-10).

Some apps are said to animate or react slowly when the app-level `AXEnhancedUserInterface` attribute is true; the usual workaround is to switch it off around a write. Spike S2 (session B) showed no difference for any of the owner's apps, so TILE32 does not use it; the option stays in `FrameWriter` for apps that may need it later.

Apps such as Terminal size their windows in steps (character cells) and end a few points away from the request. A window within 16 points of the requested size counts as fitted and is not retried; only a window more than 16 points larger counts as "does not fit" (spike S2).

Writes for different apps run in parallel; writes for the same app run in order. Frame writes for one layout pass are issued as one batch so the screen changes in one visual step as far as the OS allows.

**Serves:** US-4, US-6, US-7, US-10, US-14, US-15, US-19, N-1

### TA-12 Feedback suppression and coalescing

**Description:** Moving a window ourselves triggers `Moved` and `Resized` notifications, which would trigger another layout pass and possibly a loop. Two mechanisms prevent this:

1. **Expected frames:** before writing, the engine stores for each window the frame it expects, a generation number, and a deadline (500 ms). A notification whose actual frame is within 2 points of the expected frame, or that arrives before the deadline for the same generation, is ignored.
2. **Coalescing:** events that can change the layout (window created, destroyed, minimised, display changed, Space changed, classification changed) are put into a queue. The engine waits until no new event has arrived for 120 ms, but at most 400 ms from the first event, and then runs a single layout pass over the final state. Drop events from the drag tracker (TA-14) skip the wait and run immediately.

A resize made by the user with the mouse is handled by TA-25 and changes proportions. A window that moves or resizes while the mouse button is up (an app resizing itself, or Option-clicking the green button) is put back into its tile once. Repeated disagreements are counted per window, and after one retry the window is marked "does not fit" (TA-11) so TILE32 never fights an app in a loop.

**Serves:** US-10, US-11, US-19, N-1, N-2

### TA-13 Concurrency model

**Description:** Swift concurrency is used throughout, with these units:

- **Main actor:** all UI (`TileUI`), the `NSEvent` monitors (`TileInput`), and the status item. It never calls AX functions in a loop and never waits for a reply.
- **`actor LayoutEngine`:** the only owner of trees, the window registry, original frames, exclude list and run state. It is the single place where decisions are made. Everything else sends it events and receives commands.
- **AX observer thread:** one dedicated thread with its own run loop, hosting all `AXObserver` sources. Callbacks only forward events.
- **Per-app AX queues:** one serial dispatch queue per target process for blocking AX reads and writes. A hung or slow app blocks only its own queue. Each application element and each window element gets a messaging timeout (`AXUIElementSetMessagingTimeout`, default 0.5 seconds), because window elements do not reliably inherit it from their application. On top of that, nothing waits longer than 1.5 seconds for one app: the waiting side gives up and treats the app as unavailable, while the app's own queue stays busy until it answers. A timeout counts as "window unavailable" without crashing or stalling.

`AXUIElement` is not `Sendable`, so it is wrapped in an `@unchecked Sendable` box that is only used on the owning app's queue. Events and commands crossing actor boundaries are small immutable structs.

**Serves:** N-1, N-2, N-3, N-5, C-4

### TA-14 Mouse drag detection and the drag state machine

**Description:** macOS reports only that a window moved (`kAXWindowMovedNotification`), not who moved it. TILE32 identifies a user drag from three signals together:

1. **Mouse state:** a listen-only global monitor `NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp])`. It cannot change or block events and needs no permission beyond the one TILE32 already has. (The monitor sees events sent to other apps, which is what we need.)
2. **Hit test on press:** on `leftMouseDown` the tracker converts the cursor position and checks it against the frames of tiled windows that the engine published in a snapshot. No AX call is made here, so the check is instant. If the press is inside a tiled window's frame, enlarged by 6 points on every side to include the resize edges that macOS places just outside the frame, the state becomes `Pressed` and the tracker remembers whether the press was in the title-bar region (the top band of the window, default 40 points, which covers title bars and unified toolbars). As an optional refinement, `AXUIElementCopyElementAtPosition` on the system-wide element can identify the element under the cursor. Because it is a blocking call, it runs on the app's AX queue (TA-13) and can only demote `Pressed` back to `Idle` (for example, the press was on a toolbar button) if its answer arrives before the window starts moving.
3. **Lockstep movement (rule from spike S1):** while `Pressed`, the tracker reads the window's frame from the window server list on drag events (at most 30 times per second). The window follows the cursor when its movement is within 12 points plus 35 percent of the cursor's travel, or points the same way and covers between half and one and a half times the distance; a window that moves the same way but less than half as far is lagging and gets another reading. Session C showed that windows trail the cursor by 40 to 50 percent during fast flicks. The original plan, waiting for `kAXWindowMovedNotification`, On a move, the window's new origin is compared with its origin at press time: if the press was in the title-bar region, the origin changed by about the cursor's travel (within 6 points) and the size is unchanged, it is a user drag: state `Dragging`. A resize notification means the user is resizing by an edge or corner: state `Resizing` (TA-25). is no longer needed for detection. If the mouse goes up without any move or resize, it was a click or a content drag: state `Idle`. Window server reads take milliseconds and never wait for an app.

```
                  leftMouseDown on title-bar band of a tiled window
        +-------+ ------------------------------------------------> +---------+
        | Idle  |                                                     | Pressed |
        +-------+ <-- leftMouseUp (click), resize detected, ---------  +---------+
            ^         window did not follow the cursor                     |
            |                                                              | Moved notification in lockstep with cursor
            |                                                              v
            |   leftMouseUp, drop target found                       +----------+
            +------------------------ Dropped (engine.applyDrop) <-- | Dragging |
            |   leftMouseUp, no target                               +----------+
            +------------------------ Cancelled (engine.snapBack) <--   |   ^
            |   Escape pressed (window keeps following the cursor)      |   | leftMouseDragged:
            +------------------------ marks cancelled, no overlay  <----+   | update overlay
                                                                            +--
   Pressed --Resized notification--> Resizing --leftMouseDragged--> engine.resizeLive (TA-25)
                                     Resizing --leftMouseUp-------> engine.resizeEnd, then Idle
   Also: Dragging/Pressed/Resizing -> Idle when TILE32 is paused or loses permission,
         or when the shown Space changes while the button is down (session A: the user
         carries the window to another desktop; US-29 handles the move, there is no drop).
```

During `Dragging`, the tracker finds the display under the cursor, asks the engine for that display's tree snapshot, calls `dropTarget` (TA-6), and tells the overlay (TA-15) what to draw. On `leftMouseUp` the tracker sends the engine one of `applyDrop(dragged, targetWindow, zone, targetDisplay)`, `moveToEmptyDisplay(dragged, targetDisplay)` or `snapBack(dragged)`. For a drop onto another display the engine removes the window from the source tree and inserts it into the target tree with `splitting` (or as the root for an empty display), or swaps the two windows between trees.

**Escape:** a listen-only global key monitor for `keyDown` with key code 53 (Escape) is active only in state `Dragging`. After Escape, the OS keeps moving the window with the cursor until release, so the tracker marks the drag as cancelled, hides the overlay, and treats the release as a cancel. Apple's documentation for `addGlobalMonitorForEvents` states that key events can be monitored when the app is trusted for Accessibility, so Escape is expected to work with the one permission TILE32 has. Spike S1 confirms this on macOS 27. If it turns out that Input Monitoring is needed after all, Escape is dropped (US-17.1 says so), because the spec requires only the Accessibility permission (US-2.5, N-4), and the mouse-only cancel remains (OQ-1).

**Risk:** this entry carries the highest technical risk of the project (C-2). It is validated first by spike S1.

**Serves:** US-13, US-14, US-15, US-16, US-17, US-18, US-19, US-20, N-2, N-7, C-2

### TA-15 Drop-zone overlay

**Description:** The preview for US-16 is drawn by one borderless, transparent `NSPanel` per display, created by `OverlayController`. Properties: style mask `.borderless` plus `.nonactivatingPanel` so it never takes focus; `ignoresMouseEvents = true` so it never blocks the mouse; level `.floating`, which is above ordinary app windows; collection behaviour `[.canJoinAllSpaces, .stationary, .ignoresCycle]`; no shadow; background clear. Its content is a custom view that draws a rounded rectangle in the accent colour with a translucent fill and a label ("Swap places", "Place on the left", "Place on the right", "Place above", "Place below", or "Move to this display" for an empty display, where the highlight covers the whole usable area) in the centre. During a resize (TA-25) the same panel shows only a percentage label, without a highlight.

The overlay is updated from `leftMouseDragged` events (throttled to the display refresh rate) and hidden on release, cancel, pause and permission loss. The overlay has a one-time cost at start-up and nothing in the idle state. Exact visual design is in the UX document.

**Serves:** US-16, N-2

### TA-16 Displays and Spaces

**Description:** Displays: `NSApplication.didChangeScreenParametersNotification` triggers a rebuild of the display table in `TileGeometry`. The engine compares old and new `DisplayID`s. A new display gets an empty tree. A removed display's windows are appended, in their previous order, to the tree of the display that now contains most of each window (US-9.2), using `appending`. Windows do not move back by themselves when a display returns (US-9.3). After any change, a window whose frame lies outside every display is moved into a visible area (N-5).

Spaces: every Space and display pair has its own tree (TA-3). Session A confirmed that the Accessibility API lists only the windows of the shown desktop (plus minimised ones). TILE32 therefore knows windows on hidden desktops through the window server list (number, owner, Space) and keeps the Accessibility element it read during the window's last visible moment; such an element stays valid and writable while the desktop is hidden (`specs/spikes.md`). `TileSpaces` (TA-26) tells the engine which Space each display currently shows and which Space each window is on. On `NSWorkspace.activeSpaceDidChangeNotification` the engine asks for the current Spaces again. Trees of Spaces that became hidden turn dormant, unchanged; trees of Spaces that became visible are applied. Because a returning Space's tree was never touched, its arrangement and proportions come back exactly (US-12.2). A Space shown for the first time gets a tree built with `flat` from its windows (US-12.4).

A window that macOS moved to another Space (US-29) is found when its Space id no longer matches its tree: the engine removes it from the old tree with `removing` (the old Space re-flows when it is next shown, or at once if it is shown) and adds it to the new tree with `appending`.

Native full-screen windows are detected through `AXFullScreen` and through the Space type (a full-screen Space has no tree). On entering full screen, the window leaves its tree with a return hint (TA-9); on leaving, it returns through the hint (US-30). Stage Manager is not supported in version 1.

**Fallback (US-12.7):** if `TileSpaces` reports that the undocumented functions are not available, the engine switches to a reduced mode: it treats the windows that `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` lists as visible (public, no Screen Recording needed for bounds and owner), keeps one tree per display, never writes to windows that are not on screen, and sets a status flag for the menu.

**Serves:** US-5, US-9, US-12, US-29, US-30, C-5, C-6, C-7

### TA-17 Menu-bar application layer

**Description:** The app is an agent app (`LSUIElement = YES`), so it has no Dock icon and no main window. `MenuBarController` owns an `NSStatusItem` and builds the `NSMenu` lazily in `menuNeedsUpdate`, so the "Windows" submenu always shows the current state (US-3.3). The controller only displays state it receives from the engine and sends commands: tile now, make sizes equal, pause or resume, untile, exclude or include an app, bring a window to the front, toggle start at login, quit. It makes no decisions itself. The icon has three states (active, paused, warning) that follow the engine state. "Start at login" uses `SMAppService.mainApp`, and its checkbox always shows the system's actual status. Visual details are in the UX document.

**Serves:** US-1, US-2, US-3, US-4, US-22, US-23, US-24, US-25, US-27, N-6

### TA-18 Original frames and Untile

**Description:** When the engine first registers a window, before it moves it, it stores the window's current frame in an in-memory `OriginalFrameStore` (keyed by `WindowID`). It is kept as long as the window lives. "Untile" sets the run state to paused, then writes each stored frame back to its window. Before writing, the frame is checked against the usable areas of the connected displays: if it no longer lies fully on a display, it is moved and, if needed, shrunk so that it is fully visible (US-24.3). Windows registered after the app started have their frame stored at their first sighting, so they are restored to where they opened. Windows on Spaces that are not shown are marked as pending and restored when their Space is next shown, because no write goes to a hidden Space (US-24.7). After a crash the in-memory store is lost; windows then simply stay where they are, which satisfies N-5. Persisting the store to disk is not done in version 1 (OQ-3).

**Serves:** US-24, N-5, US-12

### TA-19 Persistence

**Description:** Persistence uses `UserDefaults` only. Stored values: the list of excluded bundle identifiers, the window limit per display (TA-27), the paused flag (default `true`, so a fresh install starts paused as US-23.5 requires), and (optional, last) the serialised layouts (US-26). The start-at-login state is not stored by the app, it is read from `SMAppService`. Nothing else is written, and the app writes no other files. Layouts, if implemented, are stored as JSON per Space and display, including the weights, with window descriptors (TA-20), and are dropped on any parse error. The Space part of the key is the Space's UUID (TA-26), because the numeric Space id can change after a logout.

**Serves:** US-22.4, US-23.3, US-25, US-26, N-4

### TA-20 Window identity

**Description:** While a window exists, the engine identifies it with an internal `WindowID` mapped from the window's `CGWindowID`, the number macOS uses for the window everywhere. The `CGWindowID` is read once per window from its `AXUIElement` with the undocumented, read-only function `_AXUIElementGetWindow` (TA-26). It is also the number that the Space queries need, so one identity serves both. If that function is unavailable (fallback mode), the key is the pair (process id, `AXUIElement`), compared with `CFEqual` and hashed with `CFHash`, and on-screen entries from `CGWindowListCopyWindowInfo` are linked to AX windows by process id and frame.

Across a restart (US-26 only), a window is described by bundle identifier, window title, and index among that app's windows, in that order of trust. This is a best-effort match with known limits: apps with changing titles (browsers, editors) and several untitled windows may be matched wrongly or not at all, and a window that cannot be matched is simply treated as new (L3). This is why US-26 is optional.

**Serves:** US-26, US-3, US-8 (rejoin at old place), US-12, US-29

### TA-21 Privacy and permission surface

**Description:** The app declares no network entitlement and makes no network calls. It reads only window geometry, title, subrole, minimised and full-screen flags, app name and bundle identifier. It never reads window content, never records the screen and never logs window titles outside of debug builds. The undocumented functions of TA-26 only return Space and window numbers. The only requested permission is Accessibility. Escape cancel is kept only if it works with that permission (OQ-1); a second permission is never requested in version 1. The hardened runtime is enabled, with no entitlement exceptions.

**Serves:** N-4, C-1, US-2.5

### TA-22 Build, signing and run

**Description:** Commands, run from `dev/`:

| Task | Command |
|---|---|
| Unit tests for the core and the engine | `swift test` |
| Build the app bundle | `./build-app.sh` (debug configuration, so the debug menu and title logging are available; creates `build/TILE32.app` with `Info.plist` including `LSUIElement`, then signs it with the Apple Development certificate) |
| Build the test app | `./build-app.sh FakeWindows` |
| Release build | `./build-app.sh TILE32 release` (release configuration, Developer ID, notarization; task T-3.8) |

**Identifiers:** the app is `com.66ideas.tile32`, the test app `com.66ideas.tile32.FakeWindows`. They never change (N-12).

**Signing:** macOS ties the Accessibility permission to the app's identifier and code signature. An ad-hoc signature changes with every build, which would reset the permission every time. Development builds are therefore signed with the owner's "Apple Development: Alexander Ilg" certificate, always with the hardened runtime, at the fixed output path `dev/build/TILE32.app`.

**Notarization (N-11):** release builds are signed with the owner's "Developer ID Application: Alexander Ilg (AHBM4Y6VPX)" certificate with a secure timestamp and the hardened runtime, then submitted with `xcrun notarytool submit --wait` and stapled with `xcrun stapler staple`. Notarization checks the signature, the hardened runtime and malware, not which functions an app calls, so the undocumented functions of TA-26 do not block it. A release build has a different signature than a development build, so macOS asks for the Accessibility permission once more for each of them. The script target is `./build-app.sh TILE32 release`, and the notarization credentials are stored in the keychain with `notarytool store-credentials`, never in the repository. Notarization is set up in M3, but the hardened runtime and clean entitlements are used from the first build so nothing has to change later.

**Serves:** N-8, N-11, N-12, US-2

### TA-23 Logging and diagnostics

**Description:** Logging uses `os.Logger` with subsystem `com.66ideas.tile32` and categories `engine`, `ax`, `drag`, `resize`, `spaces`, `layout`, `ui`. Window titles are logged only in debug builds. A "Debug" submenu, visible only in debug builds, has "Dump layout trees" (prints each display's tree in text and the registry to the log) and "Copy diagnostics" (puts the trees, the registry, the display table and the current drag state on the clipboard as text). The state machine of TA-14 logs every transition at debug level. These tools are needed for the spikes.

**Serves:** all stories (diagnosability), N-3

### TA-24 Testing strategy

**Description:** Three levels:

1. **Unit tests for `TileCore`** with no OS involved. Scenarios ported from the prototype, each as a test:
   - A, B, C plus D appended, then D dropped on the bottom of A: result is a horizontal split of `[vertical[A, D], B, C]` at a third each, with A and D at half of the first column (US-15.4).
   - A, B, C at a third each, D dropped on the right of B: normalisation gives A, B, D, C at 1/3, 1/6, 1/6, 1/3 (rule L5).
   - Weights: appending to 0.5, 0.25, 0.25 gives 0.375, 0.1875, 0.1875, 0.25 (rule L3); removing the 0.5 child gives 0.5, 0.5 (rule L4); flattening multiplies weights; weights always sum to 1.
   - Resizing: the scenario of US-28.6 (a third each to 0.5, 0.25, 0.25), a resize inside a nested column, an outer edge (no change), the minimum clamp, and snapping at 0.49 and 0.51 to 0.5.
   - Swap of two leaves in different branches, with weights unchanged.
   - Normalisation: empty split, single-child split, nested same-direction splits, deeply nested splits.
   - Empty tree and one-window tree for every operation, dropping a window on itself, dropping on an unknown target.
   - `zone(at:in:)` at and around the boundaries 0.28 and 0.72, in the corners (ties), and on very wide (32:9) and very tall rectangles.
   - `frames(in:gap:)`: shares follow the weights, no overlap, no gap larger than `gap`, seamless rounding on odd sizes.
2. **Engine tests** with fake AX, geometry and Space implementations: new window, close, minimise and restore, display disconnect, switching between many Spaces (dormant trees stay unchanged and no write reaches a hidden Space), a window moved to another Space, full screen in and out, fallback mode when Space information is missing, live resize, permission loss and return, window that cannot shrink (retry then stop), coalescing of many events, feedback suppression (no second pass for self-made moves).
3. **Manual acceptance on the real machine** with a checklist per user story (in `specs/review.md`), on both displays, with real apps (Safari, Chrome, Terminal, Finder, a code editor, Slack, a video-call app).

The `FakeWindows` app is a small SwiftUI app that opens windows on command with configurable behaviour: minimum size, delayed opening, several windows at once, a dialog and a sheet, a window that resizes itself, a full-screen toggle. It makes the cases of US-10, US-11, US-12 and US-21 repeatable.

**Serves:** all stories (verification), N-1

### TA-25 Resizing by edge

**Description:** A resize starts when the drag tracker moves from `Pressed` to `Resizing` (TA-14) for a tiled window W.

1. **Which edges:** on the first resize notification, the AX layer reads W's frame on W's app queue, and the engine compares it with W's tile. Each edge that moved by more than 2 points is an active edge; a corner drag gives two. An active edge on the display border has no neighbour and is ignored; W is put back into its tile on release (US-19.2).
2. **Live update (US-28.4):** on each `leftMouseDragged`, throttled to 30 updates per second, the AX layer reads W's current frame, and the engine computes `resizing(window: W, edge:, to: edge coordinate + gap / 2, in: layout rect)` on a working copy of the tree. It writes the new frames of all other affected windows, never of W itself, because the user is holding W. The writes go through the expected-frame suppression of TA-12.
3. **Slow apps (Q-13):** the AX layer measures how long each app takes to accept a frame. If an app needs more than 50 ms on average over the last five writes, live updates for that app's windows pause until release, and the log notes it.
4. **Release:** on `leftMouseUp`, the engine reads W's final frame, applies `resizing` with `snap: true`, commits the tree, and writes all affected frames including W, so W lines up with the gap and the snapped boundary.
5. **Percentage label:** during the resize, the overlay (TA-15) shows W's share of its split, rounded to whole percent, in the centre of W's tile. When the boundary would snap on release, the label shows the snapped value.
6. **Clamping:** if the user drags past the minimum of rule L8, the tree stops at the minimum. W itself may briefly overlap its neighbour while the button is held, and is set back to its tile on release.

**Serves:** L8, US-19, US-28, N-2

### TA-26 Space information (read-only undocumented functions)

**Description:** macOS has no public interface for Spaces. `TileSpaces` provides one protocol to the engine:

```swift
public protocol SpaceService: Sendable {
    var isAvailable: Bool { get }                                   // false = fallback mode (TA-16)
    func currentSpaces() -> [DisplayID: SpaceInfo]                  // Space shown on each display
    func spaces(of windows: [CGWindowID]) -> [CGWindowID: SpaceID]
    func windowNumber(of element: AXElementBox) -> CGWindowID?      // for TA-20
}
public struct SpaceInfo: Sendable { let id: SpaceID; let uuid: String; let isFullScreen: Bool }
```

The implementation uses exactly these four undocumented functions, and no others:

| Function | Purpose |
|---|---|
| `SLSMainConnectionID` | The app's own connection to the window server, needed by the next two |
| `SLSCopyManagedDisplaySpaces` | For each display: its identifier, the Space it shows, and its list of Spaces with id, UUID and type (desktop or full screen) |
| `SLSCopySpacesForWindows` | For a list of window numbers: the Spaces each window is on |
| `_AXUIElementGetWindow` | The window number (`CGWindowID`) of an Accessibility window element |

Rules for their use:
- **Read-only.** None of them changes anything. Functions that move windows between Spaces or create Spaces are never used (constitution, technical rule 1).
- **Resolved at runtime.** Each function is looked up by name with `dlsym` when the app starts, first under its `SLS` name in the SkyLight framework, then under its older `CGS` name in CoreGraphics. A missing name sets `isAvailable` to false instead of crashing at launch, and the engine uses the fallback of TA-16 (US-12.7). The app is not linked against any private framework.
- **Isolated.** Only `TileSpaces` contains them. The rest of the code sees the protocol, and tests use a fake.
- **Display identifiers.** When "Displays have separate Spaces" is on, each display entry carries the display's UUID, which maps to `DisplayID`. When it is off, there is a single entry named "Main", and its Space is shown on all displays, so every display gets its own tree for that Space (US-12.6).
- **Cost and timing.** Calls are made on Space changes, display changes and window registration, not on every mouse event, and their results are cached until the next change.
- **Persistence.** Numeric Space ids can change after a logout; the Space UUID is used wherever an id has to survive a restart (TA-19).
- **Diagnostics.** At start the app logs the macOS version and which functions were found. "Copy diagnostics" includes this.

Notarization is not affected: it checks the signature, the hardened runtime and malware, not which functions are called (N-11). AltTab, Amethyst and Hammerspoon use the same functions in notarized releases.

**Serves:** US-12, US-29, US-30, C-5, C-9, N-11

### TA-27 Window limit and recency

**Description:** Rule L9 and US-31 need two things the engine did not have: a limit per display and an order of use.

- **Limits:** `[DisplayID: Int]` in `UserDefaults`, range 2 to 16. Default: 12 for displays at least 3840 points wide, 6 for smaller ones.
- **Recency:** the engine keeps the windows in order of last use. It starts from the window server's front-to-back order of the on-screen windows (`WindowServerList`, public), and moves a window to the front whenever it becomes focused (`kAXFocusedWindowChangedNotification` and `NSWorkspace.didActivateApplicationNotification`, from M1). No extra permission is needed.
- **Choosing tiles:** when a layout would exceed its limit, the most recent windows up to the limit are tiled, and the others are minimised through `kAXMinimizedAttribute`. The engine remembers them in `minimisedByEngine`, so it never touches windows the user minimised (US-31.8). Its own minimise and restore writes are suppressed like frame writes (TA-12).
- **Swapping in:** when a window in `minimisedByEngine` comes back, or a new window opens on a full layout, the engine replaces the least recently used leaf with the returning window (`replacing(_:with:)` in `TileCore`, which keeps the arrangement and the weights) and minimises the window it replaced.
- **Freed tiles:** when a tile is freed, the most recent window in `minimisedByEngine` for that layout returns through `appending` (US-31.6).
- **Untile:** windows in `minimisedByEngine` are restored and then get their original frames (US-24.8).

**Serves:** L9, US-31, US-3.5, US-24.8

---

## 3. Runtime flows

### 3.1 Start-up
1. `TILE32` starts, creates the status item (US-1), checks the permission (TA-8).
2. Without permission: state `.noPermission`, menu shows the explanation and the button. Polling continues.
3. With permission: `TileGeometry` builds the display table, the AX layer discovers apps and windows (TA-9), the engine classifies them (TA-10) and records original frames (TA-18). In M0 it then waits for "Tile now". From M1 on, it reads the paused flag (TA-19): on a fresh install it is paused and nothing moves until the user chooses "Resume tiling" (US-23.5); otherwise automatic tiling starts.

### 3.2 New window (M1)
1. The AX observer posts `windowCreated(pid, element)` to the engine.
2. The engine starts or extends the coalescing timer (TA-12).
3. After the quiet period, it reads and classifies the window. If it is tiled: it assigns a `WindowID`, stores the original frame, finds the display that contains most of the window, and calls `tree.appending(id)` (L3).
4. The engine computes `frames(in:gap:)` for that display, writes the new expected frames (TA-12), and sends one batch of frame writes to the AX layer (TA-11).
5. The AX layer reads back; windows that did not reach their size are reported and marked "does not fit".

### 3.3 Close (M1)
1. `kAXUIElementDestroyed` (or minimise or app hide) reaches the engine.
2. After the quiet period, the engine removes the window with `removing` (L4, L5), recomputes the frames of that display and writes them.

### 3.4 Drag-to-split (M2)
1. The user presses the title bar: `MouseDragTracker` goes to `Pressed`, then to `Dragging` once the window follows the cursor (TA-14).
2. On each `leftMouseDragged`, the tracker asks the engine for a read-only snapshot (tree and display rectangle for the display under the cursor), calls `dropTarget`, and updates the overlay (TA-15).
3. On `leftMouseUp` with a target: the tracker sends `applyDrop`. The engine updates one or two trees (`swapping`, or `removing` plus `splitting`), computes frames for all affected displays, and writes them immediately, without the coalescing wait.
4. On `leftMouseUp` without a target, or after Escape: the engine writes the old frame of the dragged window back (snap back).

### 3.5 Display change (M1)
1. `didChangeScreenParameters` fires. `TileGeometry` rebuilds the table; the engine compares display ids.
2. Added display: empty tree. Removed display: its windows move to another display's tree with `appending`.
3. The engine recomputes and writes frames for every affected display, and moves any window that lies outside all displays into view (TA-16).

### 3.6 Space switch (M1)
1. `activeSpaceDidChange` fires. The engine asks `TileSpaces` for the Space shown on each display.
2. Trees of Spaces that are no longer shown become dormant, unchanged. No write is made to their windows.
3. Trees of newly shown Spaces are checked against the windows actually on that Space: windows that left (moved by macOS, US-29) are removed, windows that arrived are appended. A Space without a tree gets one from `flat`.
4. The engine computes and writes frames only if a tree changed in step 3. Otherwise the windows are already where they belong, and nothing moves (US-12.2).

### 3.7 Resize by edge (M2)
1. The tracker goes from `Pressed` to `Resizing` on W's first resize notification (TA-14).
2. While the button is held, the engine updates the working tree and writes the neighbours' frames at up to 30 per second (TA-25).
3. On release, the boundary is snapped, the tree committed, and all affected windows, including W, are written once.

### 3.8 Permission loss (M3, US-27)
1. The timer notices that `AXIsProcessTrusted` is false.
2. The engine switches to `.noPermission`: no further writes, overlay hidden, drag tracker reset, observers released.
3. The menu shows the warning state and the settings button. When the permission returns, the engine runs start-up step 3 again.

---

## 4. Risks and spikes (riskiest first)

| Spike | Question to answer | Method | Done when | Milestone |
|---|---|---|---|---|
| **S1 Drag detection** (C-2, TA-14) | Does the combination of title-bar hit test and lockstep movement identify user drags reliably, with no false positives for resize, content drags and app-driven moves? Does global Escape detection need an extra permission? | Small menu-bar tool that only logs the state machine transitions. Test with Finder, Safari, Chrome, Terminal, a code editor, Slack, and apps with custom title bars | Every tested app classified correctly in at least 20 drags each, and OQ-1 answered | Start of M0, finished in M2 |
| **S6 Space functions** (C-5, TA-26) | Are the four functions of TA-26 present on macOS 27 under the expected names? Do they report the correct Space for every window across 16 Spaces, with "Displays have separate Spaces" on and off? Are full-screen Spaces reported with their own type? Do Space UUIDs survive a logout? Does a notarized test build still find them? | Logging tool that prints the Space table and the Space of every window on each Space switch | All answers documented; TA-26 confirmed or revised before any Space feature is built | M0 |
| **S7 Live resize** (TA-25, Q-13) | Can neighbours follow a dragged edge smoothly at 30 updates per second in Safari, Chrome, VS Code, Terminal and Slack? Which apps need update-on-release? | Resize tool on the real ultrawide, measuring write times per app | Smooth for the tested apps, or the slow ones identified and the 50 ms rule confirmed | M2 |
| **S2 Frame writing** (TA-11) | Can we set position and size reliably across both displays? Which apps have minimum sizes, slow responses, or need the enhanced-UI workaround? | Tool that sets frames for all windows, reads back, and logs differences, including moves from the ultrawide to the laptop display | Setting works for the tested apps, with a list of the known exceptions | M0 |
| **S3 Window listing and fallback** (TA-9, TA-16) | Does `kAXWindowsAttribute` list windows on all Spaces? Can frames be written to windows on hidden Spaces at all (the design avoids it, but Untile and US-29 need to know)? Does the fallback with `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` give bounds and owner without Screen Recording? How are minimised, hidden and full-screen windows reported? How long do AX reads take for 30 windows? | Logging tool, with windows spread over several Spaces | Facts documented and TA-16 confirmed or revised | M0 |
| **S4 Notifications and feedback** (TA-9, TA-12) | Is `kAXWindowCreated` reliable for apps started later and for apps with many windows? Does the suppression logic prevent loops? | `FakeWindows` with delayed and multiple windows, plus real apps | No layout loop in 10 minutes of stress, no lost windows | M1 |
| **S5 Signing and permission** (TA-22) | Does a stable signing identity keep the Accessibility permission across rebuilds? | Rebuild and relaunch several times | Permission survives rebuilds | M0 |

Order of risk: S1 (drag detection) and S6 (Space functions) are the two highest risks and both start in M0. Then S2, S3 and S5 in M0, S4 in M1, S7 in M2.

Milestone mapping: M0 runs S5, S6, S2, S3 and the logging part of S1 (it does not move windows based on drag yet). M1 runs S4 and builds the per-Space layouts on the results of S6. M2 completes S1, runs S7, and adds the overlay and resizing. M3 adds the classification and exclude features of TA-10, persistence, untile, permission-loss behaviour and notarization.

Other known risks: apps that fight window placement (some games, some Electron apps), apps with custom title bars that fail the title-bar band (mitigated by the lockstep rule), and OS updates that change window behaviour (mitigated by using only public APIs).

---

## 5. Repository layout (under `dev/`)

```
dev/
  Package.swift
  build-app.sh                  builds, bundles and signs TILE32.app (and FakeWindows.app)
  Resources/
    Info.plist                  LSUIElement = YES, bundle id, version
    TILE32.entitlements         hardened runtime, no extra entitlements
  Sources/
    TileCore/                   LayoutNode, LayoutTree, operations, frames, drop zones (pure)
    TileLog/                    os.Logger per category (TA-23)
    TileGeometry/               display table, coordinate conversion, DisplayID
    TileSpaces/                 SpaceService protocol, SkyLight implementation (runtime-resolved), fallback
    TileAX/                     AXWorker, observers, attribute reads, frame writes, classification inputs
    TileEngine/                 LayoutEngine actor, window registry, coalescing, suppression, untile
    TileInput/                  MouseDragTracker, EscapeMonitor
    TileUI/                     MenuBarController, OverlayController, PermissionGuide
    TILE32/                     main entry, wiring
    FakeWindows/                SwiftUI test app
  Tests/
    TileCoreTests/
    TileGeometryTests/
    TileEngineTests/
```

The repository root holds `README.md`, `LICENSE` (MIT), `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md` and `THIRD_PARTY_NOTICES.md` (licences and attribution for any code taken from other open-source projects). Brand assets (app icon, 66ideas logo) live in `dev/Resources/Brand/`, copied from the 66ideas brand kit by `dev/sync-brand.sh`; the help page lives in `dev/Resources/Help/`.

---

## 6. Third-party code

The layout logic is ported from the project's own prototype. If code or technique is taken from open-source window managers (for example the frame-writing and enhanced-UI workaround from Rectangle, or the observer set-up from AeroSpace), the file keeps a comment with the origin and licence, and the notice is added to `THIRD_PARTY_NOTICES.md`. Only MIT-compatible sources are used. No code from any earlier project of the owner is used.

---

## 7. Open questions

| # | Question | Suggested default |
|---|---|---|
| OQ-1 | (Answered in session C: yes.) A global `keyDown` monitor for Escape works with the Accessibility permission alone on macOS 27. Escape cancel stays. | Answered 2026-10-18 |
| OQ-2 | Project layout: SwiftPM-only with a build script (proposed), or a generated Xcode project (XcodeGen)? | SwiftPM plus `build-app.sh`, no extra tooling. |
| OQ-3 | Should original frames be persisted to survive a crash? | No. Windows stay where they are after a crash, which is safe (N-5). |
| OQ-4 | (Answered 2026-10-24.) The 40 point title band missed Finder windows with tabs, whose tab bar lies below it. The lockstep rule alone decides: a window that moves with the cursor is a layout drag wherever it was grabbed. The band is kept for the log only. | Answered |
| OQ-6 | Deployment target: macOS 27 only, or lower? | macOS 27 for version 1. |
| OQ-7 | (Answered 2026-10-19: keep US-26.) Window identity after a restart of TILE32 is exact (window number); after a restart of the computer it is best effort (app, title hash, position). On the first visit of each desktop the order is: remembered layout that matches the screen, layout read back from the window frames (`LayoutTree.inferred`), remembered layout that moves windows back, fresh arrangement. | Answered |
| OQ-9 | Are 30 live updates per second and the 50 ms slow-app threshold right for resizing (TA-25)? | Start with these values and tune them in spike S7. |

---

## 8. Decisions

| Decision | Where | Date |
|---|---|---|
| Read-only undocumented functions are allowed for Spaces and window numbers only, resolved at runtime, isolated in `TileSpaces`, with a fallback. Owner's decision, after confirming that notarization stays possible. | TA-26, constitution technical rule 1 | 2026-10-18 |
| Layouts are kept per Space and display (`LayoutKey`); hidden Spaces' trees stay dormant and are never written to. | TA-3, TA-16 | 2026-10-18 |
| Splits carry weights; the user changes them by dragging edges. | TA-3, TA-4, TA-25 | 2026-10-18 |
| Window identity is the `CGWindowID`, read with `_AXUIElementGetWindow`; `AXUIElement` equality only in fallback mode. | TA-20 | 2026-10-18 |
| App identifier `com.66ideas.tile32`; development builds signed with the Apple Development certificate (former OQ-5), releases with Developer ID and notarized. | TA-22 | 2026-10-18 |
| Escape cancel is kept only if it works with the Accessibility permission alone. | TA-14, OQ-1 | 2026-10-11 |

---

## 9. Traceability: user story to architecture entries

| Story | Entries |
|---|---|
| US-1 Menu-bar presence | TA-17 |
| US-2 Permission request and status | TA-8, TA-21, TA-22 |
| US-3 See my windows | TA-9, TA-17, TA-20 |
| US-4 Tile now | TA-4, TA-5, TA-11, TA-17 |
| US-5 One layout per display | TA-3, TA-7, TA-16 |
| US-6 New windows join | TA-4, TA-9, TA-12 |
| US-7 Closing re-flows | TA-4, TA-9, TA-12 |
| US-8 Hidden and minimised | TA-9 (return hint), TA-20 |
| US-9 Displays connect and disconnect | TA-7, TA-16 |
| US-10 Windows that cannot shrink | TA-11, TA-12 |
| US-11 Several or slow windows | TA-9, TA-12, TA-13 |
| US-12 One layout per Space | TA-3, TA-16, TA-20, TA-26 |
| US-13 Drag by the title bar | TA-14 |
| US-14 Drop to swap | TA-4, TA-6, TA-14 |
| US-15 Drop to split | TA-4, TA-6, TA-14 |
| US-16 Preview before release | TA-6, TA-15 |
| US-17 Cancel a drag | TA-14 |
| US-18 Drag to another display | TA-4, TA-14, TA-16 |
| US-19 Snap back | TA-11, TA-12, TA-14, TA-25 |
| US-20 Separate from other title-bar uses | TA-10, TA-14 |
| US-21 Dialogs and panels stay floating | TA-10 |
| US-22 Exclude apps | TA-10, TA-17, TA-19 |
| US-23 Pause and resume | TA-17, TA-19 |
| US-24 Untile | TA-18 |
| US-25 Start at login | TA-17, TA-19 |
| US-26 Remember my layout | TA-19, TA-20 |
| US-27 Permission revoked or lost | TA-8, TA-17 |
| US-28 Resize by dragging an edge | TA-3, TA-4, TA-5, TA-14, TA-15, TA-25 |
| US-29 Move a window to another Space | TA-16, TA-20, TA-26 |
| US-30 Full-screen windows | TA-9, TA-10, TA-16, TA-26 |
| US-31 Window limit per display | TA-4, TA-19, TA-27 |
