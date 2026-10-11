# Titan Panel / LibDataBroker launcher

`TitanBroker.lua` registers an optional **LibDataBroker-1.1** launcher. It is a convenience layer only: every feature it exposes is also available in **Options > AddOns > Forever Window Mover**.

Titan Panel is declared as `## OptionalDeps: Titan` in the `.toc`. No Titan files or libraries are bundled with this addon. Without an LDB provider present, the launcher silently does not register and the rest of the addon behaves exactly as it would otherwise.

## Enabling it

With Titan Panel 9.3.4 for Forever installed and enabled, look for **Window Mover** (or **ForeverWindowMover**) in Titan's list of available plugins and enable it on a bar using Titan's own plugin controls. Any other LDB-compatible display addon can show the same object.

## Data object

| Property | Value |
| --- | --- |
| Name | `ForeverWindowMover` |
| `type` | `launcher` |
| `label` | `Window Mover` |
| `text` | `Window Mover` when MOVE handles are shown, `Mover: OFF` when hidden |
| `icon` | `Interface\Icons\INV_Misc_Gear_01` |

## Interactions

| Input | Result |
| --- | --- |
| Left-click | `addon.OpenOptions()`. If Blizzard's settings API cannot be driven, prints a chat hint to open Options > AddOns manually. |
| Right-click | Toggles all MOVE handles via `addon.SetHandlesVisible`. Positions and per-group enable flags are untouched. Refused in combat with a chat message. |
| Hover | Tooltip: title, the two click hints, overall handle state, then one line per window group reading `Enabled - saved`, `Enabled - no position`, or `Disabled`, followed by author, version, and the GitHub URL. |

Game addons cannot open an external browser, so the tooltip's last line points at the selectable URL box in the options panel (click it, then Ctrl+C).

## Registration strategy

`TryBroker()` runs immediately on file load. If that attempt did not produce an object — the usual case, since LibStub and LDB may not be loaded yet — a listener is created for `ADDON_LOADED` and `PLAYER_LOGIN`, enough to catch Titan or a library loading after Forever Window Mover without registering any build-specific events.

The listener unregisters itself and drops its `OnEvent` script as soon as an object exists, so it does not wake for every addon load for the rest of the session. Keeping it alive bought nothing: once registered, the launcher's state is kept current by `addon.RefreshBroker()`, which the core calls directly and which needs no events.

Each step fails soft:

- Returns early unless `_G.LibStub` exists as a table or function.
- `LibStub("LibDataBroker-1.1", true)` uses LibStub's silent flag, under `pcall`, so a missing library neither errors nor warns.
- Returns early unless the result exposes `NewDataObject`.
- `GetDataObjectByName` is checked first and the existing object reused if some other code already registered this name.
- `NewDataObject` is `pcall`ed; the object is only stored on success.

## Tooltip ownership

`OnTooltipShow` only appends lines to the tooltip the display passes in. The addon deliberately does not call `SetOwner`, reposition, or `Show` the tooltip itself, because Titan 9.3.x documents tooltip-handling changes on modern WoW builds and the display addon is responsible for ownership. The helper `AddTooltipLine` prefers `AddDoubleLine` and falls back to a single `left: right` line on tooltips that lack it.

## Keeping the text in sync

`addon.RefreshBroker()` rewrites `object.text` and is called by the core after `SetHandlesVisible` and `SetEnabled`, and once at `ADDON_LOADED` — the last of these matters because LDB may register the object before saved variables are loaded, when `HandlesVisible()` is still answering from defaults.
