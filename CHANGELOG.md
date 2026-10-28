# Changelog

All notable changes to **Forever Window Mover**. Every release so far targets WoW: Forever 1.60.1 (Interface `16001`).

Release dates are not recorded in the repository history, so versions are listed newest-first without dates.

## 0.3.3

A repository and tooling release. **No Lua in the addon changed**, so in-game behaviour, the group list and the `ForeverWindowMoverDB` format are identical to 0.3.2.

Added

- `tools/Sync-ToAddOns.ps1`: installs the addon into `Interface\AddOns` for local testing. Mirrors only the files that ship, so the client loads what the zip would contain, and deletes files left behind by an older install instead of letting them shadow the new ones. Finds the AddOns directory automatically — `$env:WOW_ADDONS_PATH`, then by walking up from the repository, then the default install locations — and stops rather than guessing if more than one candidate turns up. Regenerates first unless `-SkipBuild`. Supports `-Watch` to re-sync on save, `-Mode Junction` to link the repository folder instead of copying, `-Remove` to uninstall, and `-WhatIf` for a dry run.
- `tools/Common.ps1`: the addon name, package exclusion list, `.toc` parsing, version/author metadata reads, shippable-file selection, AddOns discovery and target-path guard, shared by `build.ps1` and `Sync-ToAddOns.ps1`. The exclusion list now has one definition rather than one per script, which is the same reasoning behind generating the in-package changelog.

Changed

- `tools/build.ps1` reads its metadata through `Common.ps1` instead of parsing the `.toc` itself. Behaviour and output are unchanged.
- The sync and packaging scripts validate their target before writing or deleting: the folder must be named `ForeverWindowMover` and its parent must be an `AddOns` directory. These scripts write into a game install, so a mistyped `-AddOnsPath` fails instead of pointing a recursive delete somewhere unfortunate.

Fixed

- `docs/supported-windows.md` still told you that adding a group meant shifting hardcoded offsets inside a fixed 640x550 panel. That stopped being true in 0.3.2, when the options panel moved to a layout cursor. It now documents the real remaining constraint: the derived height grows 34px per row and a settings canvas does not scroll.
- `docs/development.md` recommended creating the AddOns junction by hand; it now points at `Sync-ToAddOns.ps1` and explains when a junction is the wrong choice.

## 0.3.2

Fixed

- Saved positions are re-applied through the same scale conversion used to store them. `SetPoint` offsets are measured in the anchored frame's own coordinate space while positions are stored in UIParent units, so a frame whose scale differed from `UIParent`'s landed short of where it was dropped and drifted further on every subsequent drag. Every frame at Blizzard's default scale was unaffected, which is why this went unnoticed.
- Dragging uses `OnDragStart` / `OnDragStop` instead of `OnMouseDown` / `OnMouseUp`. The window is clamped to the screen but the cursor is not, so releasing the button at a screen edge could happen away from the MOVE tab. `OnMouseUp` is delivered by cursor position and was missed in that case, leaving the window stuck to the mouse until it was closed. A side effect: clicking a MOVE tab without dragging no longer saves a zero-distance move.
- Blizzard's original anchors are no longer overwritten by the addon's own. A frame created with no anchors had nothing to snapshot at install time, and the later snapshot recorded the addon's own `CENTER` anchor as the "original", so Disable and Reset restored the addon's position instead of Blizzard's layout. Anchors are now captured at `OnShow`, before the deferred apply, and a per-frame flag refuses any snapshot taken after the addon has moved the frame.
- The MOVE tab flips inside the window's top edge when there is no room above it. Clamping applies to the window, not to its child handle, so a window dragged to the top of the display left its tab off-screen and unclickable, recoverable only from the options panel.
- `addon.OpenOptions()` accepts a string category ID as well as a number, instead of falling back to the chat hint on builds where `category:GetID()` does not return a number.
- The per-group enable checkboxes are disabled during combat lockdown, like every other control on the panel. They previously stayed clickable and only printed a refusal after the fact.

Changed

- Frame discovery no longer runs a permanent `OnUpdate`. It is a bounded ~1 Hz burst, restarted by `ADDON_LOADED` and `PLAYER_LOGIN`, extended while in combat (when installation is refused anyway), and cancelled once there is nothing left to find. Native frames only appear at login or when the addon owning them loads, and both restart the burst. `C_Timer.NewTicker` is used where available, with the previous throttled `OnUpdate` as a self-removing fallback.
- The options panel derives its geometry from a layout table and a vertical cursor, and sizes itself to its content rather than a fixed 640x550. Combat state is polled from the panel's own `OnUpdate` while it is shown, so controls re-enable as soon as combat ends — without registering `PLAYER_REGEN_ENABLED`, which 0.2.1 removed for aborting the addon on Forever.
- The Titan / LibDataBroker listener unregisters itself once the launcher exists, instead of waking for every addon load for the rest of the session.

Added

- `## IconTexture` in the `.toc`. The client reads BLP and uncompressed TGA textures only, so `tools/Convert-IconToTga.ps1` converts `Ornate-Golden-UI-Mover-Icon.png` to a 64x64 32-bit TGA and the `.toc` points at that. The PNG stays in the repository as the source art and is left out of the package.
- `tools/build.ps1`: generates the in-package `CHANGELOG.md` and `LICENSE` from the repository originals, verifies that every copy of the version and Interface number agrees with the `.toc`, refreshes the icon, and zips the addon folder into `dist/`. `-Check` verifies without writing anything.

Unchanged

- The `ForeverWindowMoverDB` format, the group list, and the group keys. Positions from 0.1.0, 0.2.x, and 0.3.0/0.3.1 load as-is.

## 0.3.1

Added

- `addon.version`, `addon.author`, and `addon.website` metadata on the shared addon table (display only, no effect on movement or saving).
- Author and version byline in **Options > AddOns > Forever Window Mover**, plus a read-only-by-convention GitHub URL box. Clicking it highlights the URL for Ctrl+C; focus loss restores the real URL if it was edited. Addons cannot launch an external browser, so copy-paste is the mechanism.
- Author, version, and repository lines on the Titan Panel / LDB launcher tooltip.
- `## Author` and `## X-Website` in the `.toc`.
- `LICENSE` shipped inside the addon folder.
- `docs/` documentation set: user guide, supported windows, Titan/LDB integration, architecture, internal API, saved variables, development notes.

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

[Source and issues](https://github.com/mreillyorg/ForeverWindowMover) · [documentation](docs/README.md)
