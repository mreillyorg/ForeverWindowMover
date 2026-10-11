# ForeverWindowMover 0.3.1
Helps move some of the immovable Blizzard windows

WoW: Forever 1.60.1 (Interface **16001**)

Author: Michael Reilly

Source / issues: [https://github.com/mreillyorg/ForeverWindowMover](https://github.com/mreillyorg/ForeverWindowMover)

Full documentation: [`docs/`](docs/README.md) — [user guide](docs/user-guide.md), [architecture](docs/architecture.md), [internal API](docs/api-reference.md), [saved variables](docs/saved-variables.md), [Titan integration](docs/titan-panel-integration.md), [development notes](docs/development.md)

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