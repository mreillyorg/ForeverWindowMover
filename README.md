# ForeverWindowMover 0.4.0-beta
Helps move some of the immovable Blizzard windows

WoW: Forever 1.60.1 (Interface **16001**)

Author: Michael Reilly

Source / issues: [https://github.com/mreillyorg/ForeverWindowMover](https://github.com/mreillyorg/ForeverWindowMover)

Full documentation (absolute links, because this file ships inside the addon where `docs/` does not): [docs](https://github.com/mreillyorg/ForeverWindowMover/blob/main/docs/README.md) — [user guide](https://github.com/mreillyorg/ForeverWindowMover/blob/main/docs/user-guide.md), [architecture](https://github.com/mreillyorg/ForeverWindowMover/blob/main/docs/architecture.md), [internal API](https://github.com/mreillyorg/ForeverWindowMover/blob/main/docs/api-reference.md), [saved variables](https://github.com/mreillyorg/ForeverWindowMover/blob/main/docs/saved-variables.md), [Titan integration](https://github.com/mreillyorg/ForeverWindowMover/blob/main/docs/titan-panel-integration.md), [development notes](https://github.com/mreillyorg/ForeverWindowMover/blob/main/docs/development.md)

## NEW IN 0.4.0-beta: HANDLE STYLES, OR NO HANDLE AT ALL

A new **Options > AddOns > Forever Window Mover > Handles** page.

Pick how the **MOVE** tab looks: **Dark** (the existing look, and still the default), **Blizzard** (a bordered, native-looking tab), **Minimal** (a small grip with no text), or **Custom** — your own background and hover colours, the label on or off, and your own width and height.

Or do away with the tab: switch on **Drag by the window's title bar** and move each window by its own title bar, like any other window. It is off by default and invisible by design, so hover a title bar to confirm it is active. The tab and the title bar are independent, so you can use either, both, or neither.

**Show MOVE handles** still turns everything off at once, including from the Titan right-click.

Defaults reproduce 0.3.4 exactly, and saved positions are untouched. This is a **beta** because the title-bar option changes how mouse clicks reach Blizzard's windows. Clicks are passed through to whatever is underneath, so buttons in a title bar should keep working — but if a window's close button stops responding, turn that option off and report which window it was.

## NEW IN 0.3.4: NOW ON CURSEFORGE

The first release you can install from CurseForge instead of unzipping by hand. The addon's code is **unchanged** from 0.3.2, so there is nothing to relearn and nothing to reconfigure. If you are coming from 0.3.1, the fixes you want are in the 0.3.2 notes below.

0.3.3 was tagged but never published, so 0.3.2 is the last version anyone installed manually.

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