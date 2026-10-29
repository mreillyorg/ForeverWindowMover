# ForeverWindowMover 0.3.3
Helps move some of the immovable Blizzard windows

WoW: Forever 1.60.1 (Interface **16001**)

Author: Michael Reilly

Source / issues: [https://github.com/mreillyorg/ForeverWindowMover](https://github.com/mreillyorg/ForeverWindowMover)

Full documentation (absolute links, because this file ships inside the addon where `docs/` does not): [docs](https://github.com/mreillyorg/ForeverWindowMover/blob/main/docs/README.md) — [user guide](https://github.com/mreillyorg/ForeverWindowMover/blob/main/docs/user-guide.md), [architecture](https://github.com/mreillyorg/ForeverWindowMover/blob/main/docs/architecture.md), [internal API](https://github.com/mreillyorg/ForeverWindowMover/blob/main/docs/api-reference.md), [saved variables](https://github.com/mreillyorg/ForeverWindowMover/blob/main/docs/saved-variables.md), [Titan integration](https://github.com/mreillyorg/ForeverWindowMover/blob/main/docs/titan-panel-integration.md), [development notes](https://github.com/mreillyorg/ForeverWindowMover/blob/main/docs/development.md)

## NEW IN 0.3.3: NOTHING, IF YOU ONLY PLAY THE GAME

A repository and tooling release. The addon's code is **unchanged** from 0.3.2, so there is nothing to relearn and nothing to reconfigure. If you are upgrading from 0.3.1, the fixes you want are in the 0.3.2 notes below. The new material is packaging and local-testing scripts, which only matter if you work on the addon.

## NEW IN 0.3.2: DRAG AND RESET FIXES, ADDON LIST ICON

A maintenance release. Dragging now ends reliably when you release the mouse at a screen edge, instead of leaving the window stuck to the cursor. **Reset** and the per-window checkbox put a window back where Blizzard had it, which some windows previously got wrong. A window dragged to the very top of the screen keeps its **MOVE** tab reachable. The addon list now shows an icon. Saved positions and the saved-position format are unchanged.

## NEW IN 0.3.1: AUTHOR AND GITHUB DETAILS

The Options > AddOns panel now shows the author and a selectable GitHub **URL**. Click inside the **URL** box and press Ctrl+C to copy the link. The Titan Panel launcher tooltip also lists the author, version and repository. Game addons cannot open external browser windows directly. All window-movement behaviour and saved-position formats are unchanged.

## NEW IN 0.3.0: OPTIONAL TITAN PANEL / LIBDATABROKER LAUNCHER

With Titan Panel 9.3.4 for Forever installed and enabled, look for *Window Mover* (or *ForeverWindowMover*) in Titan's available plugins. Enable it on the bar using Titan's own plugin controls.

- Left-click: Open Options > AddOns > Forever Window Mover.
- Right-click: Show or hide **ALL** **MOVE** tabs, without losing positions.
- Hover: Show which window categories are enabled and have saved locations.

This is a LibDataBroker 1.1 **LAUNCHER**. It can also be shown by other **LDB** compatible display addons. Titan Panel is **OPTIONAL**. When it isn't installed, Forever Window Mover loads and works just like before, including its AddOns settings. No Titan Panel files or libraries are bundled in this download.

## WINDOWS

- Merchant / vendor        - MerchantFrame
- Player-to-player trade  - TradeFrame
- Personal bank           - BankFrame
- Guild bank              - GuildBankFrame
- Trainers                - ClassTrainerFrame, TrainerFrame
- Auction house           - AuctionHouseFrame, AuctionFrame
- Professions             - ProfessionsFrame, TradeSkillFrame
- Crafting / enchanting   - CraftFrame

Each Blizzard frame keeps its own saved position (per account). The *Show **MOVE** handles* setting affects visibility of every tab, but does **NOT** override or delete the enable setting for any individual window group. Per-window enable / reset controls and reset-all are still under Options > AddOns > Forever Window Mover. No addon chat commands needed.