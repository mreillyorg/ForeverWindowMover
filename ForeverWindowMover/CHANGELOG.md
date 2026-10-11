# Changelog

All notable changes to **Forever Window Mover**. Every release so far targets WoW: Forever 1.60.1 (Interface `16001`).

Author: Michael Reilly · Source / issues: https://github.com/mreillyorg/ForeverWindowMover

Release dates are not recorded in the repository history, so versions are listed newest-first without dates.

## 0.3.1

Added

- `addon.version`, `addon.author`, and `addon.website` metadata on the shared addon table (display only, no effect on movement or saving).
- Author and version byline in **Options > AddOns > Forever Window Mover**, plus a GitHub URL box. Clicking it highlights the URL for Ctrl+C; focus loss restores the real URL if it was edited. Addons cannot launch an external browser, so copy-paste is the mechanism.
- Author, version, and repository lines on the Titan Panel / LDB launcher tooltip.
- `## Author` and `## X-Website` in the `.toc`.
- `LICENSE` shipped inside the addon folder.
- Full documentation set in the repository `docs/` folder: user guide, supported windows, Titan/LDB integration, architecture, internal API, saved variables, development notes.

Unchanged

- Window movement behaviour, the group list, and the `ForeverWindowMoverDB` format. Positions from 0.1.0, 0.2.x, and 0.3.0 load as-is.

## 0.3.0

Added

- Optional **LibDataBroker 1.1 launcher** (`TitanBroker.lua`), surfaced as *Window Mover* in Titan Panel 9.3.4 for Forever or any other LDB display addon. No Titan files or libraries are bundled; without Titan the addon behaves exactly as before.
  - Left-click: open **Options > AddOns > Forever Window Mover**.
  - Right-click: toggle all MOVE tabs.
  - Tooltip: per-group enabled / saved-position status.
  - Label switches between `Window Mover` and `Mover: OFF`.
- Global **Show MOVE handles** switch (`ForeverWindowMoverDB.showHandles`), with a checkbox in the options panel and the Titan right-click binding. Hiding handles does not erase positions or change any per-group enable flag.
- `addon.HandlesVisible()`, `addon.SetHandlesVisible()`, and `addon.OpenOptions()` on the shared addon table.
- `## OptionalDeps: Titan` in the `.toc`.

Changed

- Handle visibility is now computed in one place from both the per-group enable flag and `showHandles`, instead of being shown/hidden ad hoc inside `SetEnabled`.
- The launcher is refreshed after saved variables load, so an LDB display that registered first still gets correct state.
- Blizzard's **Defaults** button now also re-enables MOVE handles.

## 0.2.1

Fixed

- Removed the speculative event registrations added in 0.2.0 (`BANKFRAME_OPENED`, `GUILDBANKFRAME_OPENED`, `TRAINER_SHOW`, `AUCTION_HOUSE_SHOW`, `TRADE_SKILL_SHOW`, `CRAFT_SHOW`, `PLAYER_REGEN_ENABLED`). Registering an event the Forever client does not recognise can abort initialization outright, which is what broke 0.2.0.

Changed

- Only `ADDON_LOADED` and `PLAYER_LOGIN` are registered. Lazily created Blizzard frames are now discovered by a ~1 Hz `OnUpdate` scan instead.
- Merchant and trade handling was rebased on the known-working 0.1.0 code path.
- Frame mutations wrapped in `pcall` so a protected frame on one beta build cannot take the other groups down with it.
- Saved-variable bootstrap hardened with `type()` checks, so a corrupt or hand-edited table is replaced instead of erroring.

Unchanged

- Still reads `ForeverWindowMoverDB.positions.MerchantFrame` and `.TradeFrame` from 0.1.0. No migration needed.

## 0.2.0

Added

- Six more window groups beyond vendor and trade: personal bank (`BankFrame`), guild bank (`GuildBankFrame`), trainers (`ClassTrainerFrame`, `TrainerFrame`), auction house (`AuctionHouseFrame`, `AuctionFrame`), professions (`ProfessionsFrame`, `TradeSkillFrame`), and legacy crafting / enchanting (`CraftFrame`). Where Blizzard may use either of two frame names, both are supported and remembered independently.
- Options panel under **Options > AddOns > Forever Window Mover** (`Options.lua`): per-group enable toggle, per-group reset, reset-all, and a saved / not-set indicator per group.
- `ForeverWindowMoverDB.enabled`, keyed by group key.
- Original-position capture and restore, so disabling a group puts the window back where Blizzard had it.

Changed

- Positions are keyed per Blizzard frame name rather than per window type.
- Disabling a group keeps its saved position until explicitly reset.

Removed

- The `/fwm` and `/windowmover` slash commands. Everything moved into the options panel; the addon has no chat commands from this release onward.

## 0.1.0

Initial prototype.

- MOVE tab above the merchant / vendor window (`MerchantFrame`) and the player-to-player trade window (`TradeFrame`).
- Drag to reposition; each window remembers its own position between logins via `ForeverWindowMoverDB`.
- Saved positions re-applied after Blizzard recalculates panel layout (`UpdateUIPanelPositions` hook).
- Slash commands: `/fwm`, `/windowmover`, with `reset`, `reset vendor`, and `reset trade`.
