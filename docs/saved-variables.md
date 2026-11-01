# Saved variables

The addon declares a single account-wide saved variable in `ForeverWindowMover.toc`:

```
## SavedVariables: ForeverWindowMoverDB
```

Account-wide means all characters on the account share one set of window positions. There is no `SavedVariablesPerCharacter` table.

On disk it lives at:

```
World of Warcraft\_classic_beta_\WTF\Account\<ACCOUNT>\SavedVariables\ForeverWindowMover.lua
```

## Schema

```lua
ForeverWindowMoverDB = {
    positions = {
        -- keyed by Blizzard global frame name, not by group key
        ["MerchantFrame"] = { x = -210, y = 94 },
        ["BankFrame"]     = { x = 0,    y = 120 },
    },
    enabled = {
        -- keyed by group key; only written once the user toggles a checkbox
        ["guildbank"] = false,
    },
    showHandles = true,
    handleTab = true,
    handleTitlebar = false,
    handleStyle = "dark",
    handleCustom = {
        width = 70, height = 20, text = true,
        bg = {0.1, 0.1, 0.1, 0.9}, hover = {0.45, 0.45, 0.45, 0.95},
    },
}
```

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `positions[frameName]` | `{x = number, y = number}` | absent | Offset in UIParent units from `UIParent`'s centre to the frame's centre. See the positioning math in [architecture](architecture.md#positioning-math). |
| `enabled[groupKey]` | `boolean` | absent, treated as enabled | Only `false` disables a group. Any other value, including `nil`, means enabled. |
| `showHandles` | `boolean` | absent, treated as `true` | The master switch, and the one Titan's right-click toggles. With it off neither drag mechanism is live. Only `false` hides them. |
| `handleTab` | `boolean` | absent, treated as `true` | Whether the visible MOVE tab is one of the drag mechanisms. |
| `handleTitlebar` | `boolean` | absent, treated as `false` | Whether the invisible strip across the window's title bar is live. Opt-in, because an invisible control is not discoverable. |
| `handleStyle` | `string` | absent, treated as `"dark"` | `dark`, `blizzard`, `minimal` or `custom`. An unrecognised name falls back to `dark` rather than leaving the tab unstyled. |
| `handleCustom` | `table` | absent, all defaults | The `custom` style. Every field is validated on read and falls back individually, so a hand-edited file cannot produce an invisible or zero-sized handle. `text = false` means no label, which is the point of a narrow custom handle; absent means the label is shown. |

`handleTab` and `handleTitlebar` are independent, and both can be off. That
leaves nothing draggable while the master switch is still on, which is a legal
state the options page reports rather than leaving you to work out.

## Bootstrap and resilience

At `ADDON_LOADED` for this addon the table is normalised before use:

```lua
ForeverWindowMoverDB = type(ForeverWindowMoverDB) == "table" and ForeverWindowMoverDB or {}
ForeverWindowMoverDB.positions = type(ForeverWindowMoverDB.positions) == "table" and ForeverWindowMoverDB.positions or {}
ForeverWindowMoverDB.enabled = type(ForeverWindowMoverDB.enabled) == "table" and ForeverWindowMoverDB.enabled or {}
db = ForeverWindowMoverDB
```

So a corrupt or hand-edited file of the wrong type is replaced rather than erroring. `showHandles` is not normalised because every reader treats non-`false` as `true`.

Positions are also validated at apply time: an entry whose `x` or `y` is not a number is ignored instead of being applied or cleaned up.

## Defaults-are-absent convention

Both boolean fields are written only when the user changes them, and both default to "on". That keeps a fresh install's saved file minimal and means a deleted saved-variables file yields fully default behaviour: everything draggable, handles visible, no stored positions.

## Compatibility

The 0.3.x releases did not change the saved-position format — 0.3.0 added the optional LDB launcher, 0.3.1 added author/URL display, 0.3.2 was bug fixes, and 0.3.3 and 0.3.4 were repository tooling and packaging. None of them touch the schema, and positions saved by earlier versions load unchanged.

One behavioural note for 0.3.2, with no schema change behind it: stored offsets have always been in UIParent units, but they used to be fed back into `SetPoint` without converting into the frame's own coordinate space. A window whose scale differed from `UIParent`'s was therefore re-applied slightly off. Existing entries are read exactly as written; they just land where they say now.

Two things to treat as a contract when editing the addon:

- **Group keys** (`vendor`, `trade`, `bank`, `guildbank`, `trainer`, `auction`, `professions`, `craft`) are persisted in `enabled`. Renaming one silently resets that group's preference for existing users.
- **Frame names** are the keys in `positions`. Removing a frame name from a group's `frames` list orphans its entry; the entry stays in the file but is never read or cleaned up.

## Manual cleanup

Deleting `ForeverWindowMover.lua` from `SavedVariables` while the game is closed is equivalent to **Reset all positions** plus re-enabling every group. Within the game, the options panel's **Reset all positions** button and Blizzard's **Defaults** button achieve the same result without touching the file by hand.
