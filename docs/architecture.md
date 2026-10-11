# Architecture

## Files

Load order is set by `ForeverWindowMover.toc`:

| File | Role |
| --- | --- |
| `ForeverWindowMover.lua` | Core: group table, saved-variable bootstrap, frame discovery, MOVE handles, position save/apply/reset, event loop. Owns all public functions on `addon`. |
| `Options.lua` | Blizzard **Options > AddOns** canvas panel. Defines `addon.CreateOptions`, `addon.OpenOptions`, and `addon.RefreshOptions`. Reads and calls core functions only. |
| `TitanBroker.lua` | Optional LibDataBroker 1.1 launcher. Defines `addon.RefreshBroker`. Degrades to a no-op when no LDB is present. |

Non-Lua files in the addon folder: `ForeverWindowMover.toc`, `README.txt`, `CHANGELOG.md`, `LICENSE`, and `Ornate-Golden-UI-Mover-Icon.tga` — the addon-list icon named by `## IconTexture`. The `.tga` is generated from `Ornate-Golden-UI-Mover-Icon.png` by `tools/Convert-IconToTga.ps1`; the client reads BLP and uncompressed TGA only, so a PNG referenced from the `.toc` would render as nothing. The PNG is the source art and is not shipped.

`Options.lua` and `TitanBroker.lua` are intentionally decoupled from dragging: they call into the core, never manipulate frames directly, and the core only calls back into them through soft checks (`if addon.RefreshOptions then ... end`).

The three files share state through the private addon table from `local addonName, addon = ...`. Nothing is published to `_G` except the saved-variable `ForeverWindowMoverDB`.

## Core state

All module-local in `ForeverWindowMover.lua`:

| Variable | Purpose |
| --- | --- |
| `db` | Reference to `ForeverWindowMoverDB`, set at `ADDON_LOADED`. `nil` until then, and most functions treat `nil` as "defaults, do nothing destructive". |
| `groupsByKey` | `key` → group lookup built once from `addon.groups`. |
| `installed` | Frame name → `{frame, handle}` for frames already hooked. Doubles as the "already installed" guard. |
| `moving` | Frame name → `true` while a drag is in progress. |
| `originalPoints` | Frame name → captured array of Blizzard's original anchor points, used by disable and reset. |
| `movedByAddon` | Frame name → `true` once the live anchors came from this addon (an applied position, or a drag) rather than from Blizzard's layout. Gates `CaptureOriginalPoints`. |
| `applying` | Re-entrancy guard so an `ApplyPosition` that triggers layout updates cannot recurse. |

## Load and discovery sequence

```
ADDON_LOADED (self)   -> normalise ForeverWindowMoverDB, set db, RefreshBroker(), TryOptions()
ADDON_LOADED (any)    -> InstallFrames(), StartScan()   -- LoD addons create new native frames
PLAYER_LOGIN          -> InstallFrames(), TryOptions(),
                         hooksecurefunc("UpdateUIPanelPositions", ApplyAllVisible),
                         StartScan(), unregister PLAYER_LOGIN
Scan (~1 Hz, bounded) -> if db then InstallFrames(); TryOptions() end
```

Three deliberate design choices here:

- **No build-specific events.** On WoW: Forever, registering an event the client does not know can abort the addon. Only `ADDON_LOADED` and `PLAYER_LOGIN` are registered. Lazily created frames are found by the polling scan instead.
- **Idempotent retries.** `InstallFrame` returns immediately if the frame is already in `installed`, and `TryOptions` returns immediately once `addon.optionsCreated` is set, so each pass is cheap (a bounded loop over the ~11 declared frame names).
- **The scan is a burst, not a session-long timer.** `StartScan` arms `SCAN_BURST_TICKS` (15) ticks at `SCAN_INTERVAL` (1s) and is re-armed by every `ADDON_LOADED` and by `PLAYER_LOGIN`. `Scan` stops itself once the burst is spent, or early once the options page is registered and every declared frame is installed.

`StopScan` cancels the `C_Timer.NewTicker` where one is available; on a build without tickers, `StartScan` falls back to a throttled `OnUpdate` on the event frame that `StopScan` removes the same way. Two details make stopping safe:

- Native frames only come into existence at login or when the addon that owns them loads, and both of those re-arm the burst, so a stopped scan has nothing left to find.
- `Scan` does not decrement the burst while `CanMove()` is false. Installation is refused in combat, so a lockdown cannot silently consume the burst before the frames become installable.

The early-exit condition cannot be "every declared frame is installed" on its own, because groups list alternative frame names (`ClassTrainerFrame` *or* `TrainerFrame`) and only one of each pair exists on a given build. That is why the burst is bounded by a tick count as well.

`TryOptions` wraps `addon.CreateOptions` in `pcall` and reports a failure to chat exactly once, guarded by `settingsFailureReported`.

## Installing a frame

`InstallFrame(name, groupKey, label)`:

1. Bails out if already installed or if in combat.
2. Bails out if `_G[name]` is missing or has no `SetMovable` method.
3. In a `pcall`: captures the original anchor points, then `SetMovable(true)` and `SetClampedToScreen(true)`. If the client refuses, the frame is skipped silently and will not be retried that pass.
4. Creates the MOVE handle: a `HANDLE_WIDTH` x `HANDLE_HEIGHT` (70x20) `Button` child of the target frame, at frame level +12, with a dark `SetColorTexture` background, a `GameFontNormalSmall` "MOVE" label, and hover highlight plus `GameTooltip` text.
5. Wires drag scripts (below).
6. Positions the handle with `UpdateHandleAnchor` and hides it if the group is disabled or handles are globally hidden.
7. `HookScript("OnShow", ...)` — snapshots Blizzard's anchors (see [restore paths](#restore-paths)) and re-applies the saved position, deferred via `C_Timer.After(0, ...)` so it runs *after* Blizzard's panel manager, with a direct-call fallback if `C_Timer` is unavailable.
8. Applies the saved position once right away in case the frame is already open.

### Handle placement

`UpdateHandleAnchor(name)` anchors the handle `BOTTOMLEFT` to the frame's `TOPLEFT` at `(HANDLE_INSET_X, 0)` — just above the window — except when the window's top is within `HANDLE_HEIGHT` of `UIParent`'s top, in which case it flips to `TOPLEFT`/`TOPLEFT` at `(HANDLE_INSET_X, -2)` and sits just inside the window instead.

The flip exists because `SetClampedToScreen(true)` clamps the *window*, not its child handle. Without it, a window dragged to the top of the display pushes its own MOVE tab off-screen, where it cannot be clicked, and the only way back is the options panel. The comparison converts the frame's `GetTop()` into UIParent units with `ScaleRatio` first. It is re-evaluated on apply, on drag end, on reset, and from `UpdateHandles`.

### Drag lifecycle

- `RegisterForDrag("LeftButton")` plus `OnDragStart` / `OnDragStop`, **not** `OnMouseDown` / `OnMouseUp`. The window is clamped to the screen while the cursor is not, so the button can be released well away from the handle. `OnMouseUp` is delivered by cursor position and would be missed in exactly that case, leaving the window attached to the mouse until it was closed. `OnDragStop` is always delivered to whoever started the drag. The trade-off is that a click with no movement no longer starts and ends a zero-distance move.
- `OnDragStart` → `StartMove` — refuses when already moving, in combat, or when the group is disabled; captures original points, hides the tooltip, `pcall`s `StartMoving()`, and on success marks both `moving[name]` and `movedByAddon[name]`. The latter is set at drag *start* because Blizzard's anchors are gone from that moment on, however the drag ends.
- `OnDragStop` → `FinishMove`.
- `OnHide` → `FinishMove`, so closing a window mid-drag still saves cleanly.
- `FinishMove` — no-op unless `moving[name]`; `pcall`s `StopMovingOrSizing()`, clears the flag, then `SavePosition` and `UpdateHandleAnchor`.

## Positioning math

Saved coordinates are `UIParent`-centre-relative offsets in UIParent units, which keeps them valid across resolution and UI-scale changes.

Both directions go through one helper, `ScaleRatio(frame)`, which returns `frame:GetEffectiveScale() / UIParent:GetEffectiveScale()` and falls back to `1` for a missing, non-numeric or non-positive scale so it can never divide by zero. For every frame at Blizzard's default scale the ratio is exactly `1`.

Save (`SavePosition`):

```lua
local x, y = frame:GetCenter()
local parentX, parentY = UIParent:GetCenter()
local ratio = ScaleRatio(frame)
db.positions[name] = {
    x = math.floor(x * ratio - parentX + 0.5),
    y = math.floor(y * ratio - parentY + 0.5),
}
```

`GetCenter` reports in the frame's own coordinate space, so `* ratio` converts it into UIParent's before the centre offset is taken. `math.floor(v + 0.5)` rounds to the nearest whole unit.

Apply (`ApplyPosition`):

```lua
local ratio = ScaleRatio(frame)
frame:ClearAllPoints()
frame:SetPoint("CENTER", UIParent, "CENTER", saved.x / ratio, saved.y / ratio)
```

The division is not optional. `SetPoint` offsets are measured in the **anchored frame's** coordinate space, not the relative frame's, so feeding a UIParent-unit offset straight back in would re-apply the scale and land the window at `offset * ratio`. Because `SavePosition` calls `ApplyPosition` immediately after storing, that error showed up as a visible jump on mouse release and compounded toward the screen centre with every further drag. It was invisible at `ratio == 1`, which is every frame Blizzard ships unless another addon rescales one.

`ApplyPosition` refuses to run when: `applying` is already true, the frame is mid-drag, `db` is unset, the player is in combat, the group is disabled, there is no saved entry, the frame does not exist, `x`/`y` are not numbers, or the frame is currently hidden. The `SetPoint` call itself is wrapped in `pcall` — a protected bank or professions frame on a beta build fails alone rather than breaking the loop over other frames. Only on success does it set `movedByAddon[name]` and refresh the handle anchor.

Note the side effect of collapsing all anchors to a single `CENTER` point: frames that Blizzard anchored with multiple points lose those extra anchors until reset or disable restores them. That restore is only trustworthy because of the capture rules below.

## Restore paths

- `CaptureOriginalPoints` snapshots every `GetPoint(i)` tuple, stores it only if at least one point exists, and refuses outright once `movedByAddon[name]` is set. That refusal is the whole point of the flag: a frame created with no anchors has nothing to snapshot at install time, and without the guard the *next* capture would record the addon's own `CENTER` anchor as "Blizzard's original", so Disable and Reset would restore the addon's position instead of the client's layout.
- Capture is attempted at install, at `OnShow` (synchronously, and again inside the deferred callback), and at drag start. `OnShow` is the one that matters for lazily created frames: Blizzard's layout has put real anchors on the frame by then, and it runs before the deferred `ApplyPosition` that would otherwise replace them.
- `RestoreOriginalPoints` clears anchors and replays the snapshot inside a `pcall`. On success it drops both the snapshot and `movedByAddon[name]`, so the frame is back to being Blizzard-owned and the next capture is allowed again. On failure it keeps both, so the restore can be retried and no wrong snapshot can be taken in the meantime.
- If no snapshot was ever taken, Disable and Reset leave the anchors alone rather than clearing a frame to no points at all, and rely on `UpdateNativeLayout` to put managed panels back.
- `UpdateNativeLayout` calls `UpdateUIPanelPositions` (if present, under `pcall`) after a disable or reset so Blizzard's layout manager recomputes managed panel slots.

## Combat safety

`CanMove()` returns `false` whenever `InCombatLockdown()` exists and is true, and is exposed to the options panel as `addon.CanChangeFrames`. It gates frame installation, position application and restoration, drag start, `SetEnabled`, `SetHandlesVisible`, `ResetGroup`, and `ResetAll`. Those mutators return `false` when refused, which the options panel and the Titan launcher turn into a user-facing "cannot ... during combat" message. Nothing is queued for after combat; the next scan or the next `OnShow` picks things up.

Two places watch combat state rather than just reacting to a refusal, and both do it without registering a combat event — `PLAYER_REGEN_ENABLED` and `PLAYER_REGEN_DISABLED` were removed in 0.2.1 for aborting the addon on Forever:

- `Scan` holds the discovery burst open while `CanMove()` is false, so lockdown cannot consume it.
- The options panel polls `addon.CanChangeFrames()` from its own `OnUpdate` every 0.25s and re-runs `Refresh` when the answer changes, which greys the controls out on entering combat and restores them on leaving it. `OnUpdate` does not run on a hidden frame, so this costs nothing while the page is closed.

## Options panel layout

`Options.lua` builds its canvas from a single `LAYOUT` table of widths, gaps and column fractions, plus a small top-down cursor (`NewCursor`). `cursor:Place(height, gap)` reserves a band and returns the `y` to anchor it at; `cursor:Skip(gap)` opens a section gap; `cursor:Middle(y, height)` gives the vertical centre of a band for anchoring differently sized widgets along one row; `cursor:Height()` reports the total needed, which is what the panel is finally sized to.

Horizontal positions come either from `LAYOUT.padding` / `LAYOUT.checkInset` or from a derived column — `ActionColumnX()` for the per-row **Reset** button, `SavedColumnX()` for the Saved / Not set text — and widgets that belong to the same row anchor to each other (`LEFT` of the previous widget's `RIGHT`) rather than to absolute offsets. Adding, removing or reordering a row therefore needs no other edits, and the panel height follows automatically instead of being a fixed 550.
