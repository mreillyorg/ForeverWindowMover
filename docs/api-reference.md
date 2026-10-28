# Internal API reference

These functions live on the private addon table shared by the three Lua files (`local addonName, addon = ...`). They are **not** exposed in `_G` and are not a public API for other addons; this page documents them for maintainers.

## Metadata and data

| Field | Type | Notes |
| --- | --- | --- |
| `addon.version` | `string` | `"0.3.3"`. Display only. The `.toc` `## Version` is the source of truth; `tools/build.ps1` fails if the two disagree. |
| `addon.author` | `string` | `"Michael Reilly"`. |
| `addon.website` | `string` | GitHub URL shown in the options panel edit box and the Titan tooltip. |
| `addon.groups` | `array` | Ordered list of `{key, label, frames}`. Drives options rows, tooltip lines, discovery, and reset. See [supported windows](supported-windows.md). |

## Queries (defined in `ForeverWindowMover.lua`)

### `addon.IsEnabled(key) -> boolean`
Whether dragging is enabled for a group. Defaults to `true` when `db` or `db.enabled` is missing, or when the stored value is anything other than `false`. Groups are opt-out, not opt-in.

### `addon.HasPosition(key) -> boolean`
`true` if any frame in the group has a stored position. Returns `false` for unknown keys or before saved variables load.

### `addon.HandlesVisible() -> boolean`
Global MOVE-tab visibility. Defaults to `true`. Deliberately independent of the per-group enable flags — hiding handles never erases positions or changes `db.enabled`.

### `addon.CanChangeFrames() -> boolean`
Alias of the internal `CanMove()`. `false` during combat lockdown. Used by the options panel to grey out controls.

## Mutators

All of these return `false` and change nothing when `db` is unset or the player is in combat. On success each refreshes the handles/options/broker as appropriate and returns `true`.

### `addon.SetEnabled(key, enabled) -> boolean`
Sets `db.enabled[key]`. Enabling re-applies saved positions for the group's frames; disabling restores Blizzard's captured anchors and calls `UpdateUIPanelPositions`. Saved positions are retained either way. Refreshes handles, options, and the broker.

### `addon.SetHandlesVisible(visible) -> boolean`
Sets `db.showHandles`, shows or hides every installed handle, refreshes options and the broker. Does not touch `db.enabled` or `db.positions`.

### `addon.ResetGroup(key) -> boolean`
For each frame in the group: deletes the stored position, aborts any in-progress drag, restores original anchors, clears `SetUserPlaced`, and re-evaluates the handle anchor. Then recalculates the native panel layout and refreshes options. A frame whose original anchors were never captured keeps its current ones — see [restore paths](architecture.md#restore-paths).

### `addon.ResetAll() -> boolean`
`ResetGroup` across every group, with a single layout recalculation and options refresh at the end.

## Options integration (defined in `Options.lua`)

### `addon.CreateOptions()`
Builds the canvas panel and registers it via `Settings.RegisterCanvasLayoutCategory` + `Settings.RegisterAddOnCategory`. Returns early if already created, or if the `Settings` API is not loaded yet — the core retries once per second. Sets `addon.optionsPanel`, `addon.optionsCategory`, `addon.optionsCreated`, and installs `addon.RefreshOptions`.

The panel supplies the hooks Blizzard's canvas registration expects: `OnRefresh`, `OnCommit` (no-op), and `OnDefault` (reset all, re-enable every group, show handles).

### `addon.OpenOptions() -> boolean`
Lazily creates the panel if needed, then `Settings.OpenToCategory(category:GetID())`. Accepts a `number` or `string` category ID, since not every build returns a number. Returns `false` if the settings API, the category, or its ID is unavailable, which is how the Titan launcher knows to fall back to a chat hint. Every step is `pcall`-guarded.

### `addon.RefreshOptions()`
Installed by `CreateOptions`. Re-syncs checkboxes, Saved/Not set labels, and enabled states — but only while the panel is shown. Called by the core after any state change. The core always calls it defensively (`if addon.RefreshOptions then ... end`) because it does not exist until the panel is built.

Note that the panel also refreshes itself: its `OnUpdate` polls `addon.CanChangeFrames()` and re-runs the internal `Refresh` when combat state flips, so controls grey out and come back without the core having to push anything. Every control, including the per-group enable checkboxes, is disabled during lockdown.

## Broker integration (defined in `TitanBroker.lua`)

### `addon.RefreshBroker()`
Updates the launcher's `text` to `"Window Mover"` or `"Mover: OFF"`. No-op until an LDB data object exists. Also called from `ADDON_LOADED` because LDB may have registered the object before saved variables were available.

## Call-direction rules

- Core → Options/Broker: only through `addon.RefreshOptions` and `addon.RefreshBroker`, always existence-checked.
- Options/Broker → Core: free use of the query and mutator functions above.
- Options and Broker never call each other, and never touch `installed`, `moving`, `originalPoints`, or `db` directly.
