# Supported windows

Window groups are declared in `addon.groups` in `ForeverWindowMover.lua`. Each group has a stable `key` (used in saved variables), a display `label`, and one or more global Blizzard frame names.

| Key | Label | Blizzard frames |
| --- | --- | --- |
| `vendor` | Vendors / merchants | `MerchantFrame` |
| `trade` | Player trades | `TradeFrame` |
| `bank` | Personal bank | `BankFrame` |
| `guildbank` | Guild bank | `GuildBankFrame` |
| `trainer` | Trainers | `ClassTrainerFrame`, `TrainerFrame` |
| `auction` | Auction house | `AuctionHouseFrame`, `AuctionFrame` |
| `professions` | Professions | `ProfessionsFrame`, `TradeSkillFrame` |
| `craft` | Crafting / enchanting | `CraftFrame` |

## How groups and frames relate

- The **enable** flag and the **Reset** button operate on a whole group.
- **Saved positions are stored per frame name**, not per group. `trainer`, `auction`, and `professions` list two frame names each because different client builds (and load-on-demand addons) expose different frames for the same activity. Whichever exists gets its own entry.
- A group shows **Saved** in the options panel if *any* of its frames has a stored position.

## Adding a group

Append an entry to `addon.groups`:

```lua
{ key = "mail", label = "Mailbox", frames = {"MailFrame"} },
```

Nothing else needs changing. The options rows, the Titan tooltip lines, discovery, saving, and reset all iterate `addon.groups`. Two things to keep in mind:

- **Panel height.** Since 0.3.2 the options panel places rows with a layout cursor and sizes itself to its content, so no offsets need editing — but the height still grows by `LAYOUT.rowHeight` (34px) per row. Eight groups come to 552px, which is about as tall as Blizzard's settings canvas will show; a canvas category does not scroll. Past roughly eight groups, reduce `LAYOUT.rowHeight` or split the list into sections rather than letting the bottom controls fall off the page. See [architecture](architecture.md#options-panel-layout).
- **Key stability.** Once a `key` has shipped, changing it orphans users' `enabled` flags for that group. Keys are effectively part of the saved-variable contract.
