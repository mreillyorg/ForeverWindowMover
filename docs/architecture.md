# Architecture

## Files

Load order is set by `ForeverWindowMover.toc`:

| File | Role |
| --- | --- |
| `ForeverWindowMover.lua` | Core: group table, saved-variable bootstrap, frame discovery, MOVE handles, position save/apply/reset, event loop. Owns all public functions on `addon`. |
| `Options.lua` | Blizzard **Options > AddOns** canvas panel. Defines `addon.CreateOptions`, `addon.OpenOptions`, and `addon.RefreshOptions`. Reads and calls core functions only. |
| `TitanBroker.lua` | Optional LibDataBroker 1.1 launcher. Defines `addon.RefreshBroker`. Degrades to a no-op when no LDB is present. |

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
| `applying` | Re-entrancy guard so an `ApplyPosition` that triggers layout updates cannot recurse. |

## Load and discovery sequence

```
ADDON_LOADED (self)   -> normalise ForeverWindowMoverDB, set db, RefreshBroker(), TryOptions()
ADDON_LOADED (any)    -> InstallFrames()        -- LoD addons create new native frames
PLAYER_LOGIN          -> InstallFrames(), TryOptions(),
                         hooksecurefunc("UpdateUIPanelPositions", ApplyAllVisible),
                         unregister PLAYER_LOGIN
OnUpdate (~1 Hz)      -> if db then InstallFrames(); TryOptions() end
```

Two deliberate design choices here:

- **No build-specific events.** On WoW: Forever, registering an event the client does not know can abort the addon. Only `ADDON_LOADED` and `PLAYER_LOGIN` are registered. Lazily created frames are found by the one-second polling scan instead.
- **Idempotent retries.** `InstallFrame` returns immediately if the frame is already in `installed`, and `TryOptions` returns immediately once `addon.optionsCreated` is set, so the repeating scan is cheap (a bounded loop over the ~11 declared frame names).

`TryOptions` wraps `addon.CreateOptions` in `pcall` and reports a failure to chat exactly once, guarded by `settingsFailureReported`.

## Installing a frame

`InstallFrame(name, groupKey, label)`:

1. Bails out if already installed or if in combat.
2. Bails out if `_G[name]` is missing or has no `SetMovable` method.
3. In a `pcall`: captures the original anchor points, then `SetMovable(true)` and `SetClampedToScreen(true)`. If the client refuses, the frame is skipped silently and will not be retried that pass.
4. Creates the MOVE handle: a 70x20 `Button` child of the target frame, anchored `BOTTOMLEFT` to the frame's `TOPLEFT` at `(18, 0)`, at frame level +12, with a dark `SetColorTexture` background, a `GameFontNormalSmall` "MOVE" label, and hover highlight plus `GameTooltip` text.
5. Wires drag scripts (below).
6. Hides the handle immediately if the group is disabled or handles are globally hidden.
7. `HookScript("OnShow", ...)` — re-applies the saved position, deferred via `C_Timer.After(0, ...)` so it runs *after* Blizzard's panel manager, with a direct-call fallback if `C_Timer` is unavailable.
8. Applies the saved position once right away in case the frame is already open.

### Drag lifecycle

- `OnMouseDown` (left button only) — refuses in combat or when the group is disabled; re-captures original points, hides the tooltip, `pcall`s `StartMoving()`, and marks `moving[name]` only if that succeeded.
- `OnMouseUp` (left button) — `FinishMove()`.
- `OnHide` — `FinishMove()`, so closing a window mid-drag still saves cleanly.
- `FinishMove` — no-op unless `moving[name]`; `pcall`s `StopMovingOrSizing()`, clears the flag, then `SavePosition`.

## Positioning math

Saved coordinates are `UIParent`-centre-relative offsets in UIParent units, which keeps them valid across resolution and UI-scale changes.

Save (`SavePosition`):

```lua
local x, y = frame:GetCenter()
local parentX, parentY = UIParent:GetCenter()
local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
db.positions[name] = {
    x = math.floor(x * ratio - parentX + 0.5),
    y = math.floor(y * ratio - parentY + 0.5),
}
```

The `ratio` term converts the frame's own coordinate space into UIParent's, so frames with a non-default scale are stored correctly. `math.floor(v + 0.5)` rounds to the nearest whole unit.

Apply (`ApplyPosition`):

```lua
frame:ClearAllPoints()
frame:SetPoint("CENTER", UIParent, "CENTER", saved.x, saved.y)
```

`ApplyPosition` refuses to run when: `applying` is already true, the frame is mid-drag, `db` is unset, the player is in combat, the group is disabled, there is no saved entry, the frame does not exist, `x`/`y` are not numbers, or the frame is currently hidden. The `SetPoint` call itself is wrapped in `pcall` — a protected bank or professions frame on a beta build fails alone rather than breaking the loop over other frames.

Note the side effect of collapsing all anchors to a single `CENTER` point: frames that Blizzard anchored with multiple points lose those extra anchors until reset or disable restores them.

## Restore paths

- `CaptureOriginalPoints` snapshots every `GetPoint(i)` tuple the first time a frame is touched (and again at drag start), and only stores it if at least one point exists.
- `RestoreOriginalPoints` clears anchors and replays the snapshot inside a `pcall`, dropping the snapshot only on success so a failed restore can be retried.
- `UpdateNativeLayout` calls `UpdateUIPanelPositions` (if present, under `pcall`) after a disable or reset so Blizzard's layout manager recomputes managed panel slots.

## Combat safety

`CanMove()` returns `false` whenever `InCombatLockdown()` exists and is true, and is exposed to the options panel as `addon.CanChangeFrames`. It gates frame installation, position application and restoration, drag start, `SetEnabled`, `SetHandlesVisible`, `ResetGroup`, and `ResetAll`. Those mutators return `false` when refused, which the options panel and the Titan launcher turn into a user-facing "cannot ... during combat" message. Nothing is queued for after combat; the next scan or the next `OnShow` picks things up.
