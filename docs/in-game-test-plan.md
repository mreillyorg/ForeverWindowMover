# In-game test plan: 0.4.0-beta

A manual checklist for testing **Forever Window Mover** 0.4.0-beta in the live client. The offline harnesses under `tests/` already cover the logic against a fake WoW API; this plan covers what only the real client can answer: rendering, real Blizzard frames, mouse routing, combat lockdown, the Settings UI and Titan Panel.

The release is a beta because of the new title-bar drag option (see the [CHANGELOG](../CHANGELOG.md#040-beta)). [New in 0.4.0](#new-in-040-and-regression) and [Drag by title bar](#drag-by-title-bar) are the sections that matter most.

Each item is an action followed by the expected result. Tick it when it passes; when it fails, leave it unticked and add a row to [Issues found](#issues-found). Items marked **(verify: ...)** test behaviour the code or docs do not settle, so record what you actually see.

## Test run

| Field | Value |
| --- | --- |
| Version under test | 0.4.0-beta |
| Interface | `16001` (WoW: Forever 1.60.1) |
| Game folder | `World of Warcraft\_forever_` |
| Tester | |
| Date | |
| Client build (`/run print(GetBuildInfo())`) | |
| UI scale / resolution | |
| Other addons enabled | |

## Installing for testing

1. From the repository root, run `.\tools\Sync-ToAddOns.ps1`. It runs `build.ps1 -Check` first, then mirrors only the shipped files into `Interface\AddOns\ForeverWindowMover`.
2. If the game is running, type `/reload` for Lua changes. A `.toc` change (version, Interface, icon) needs a full client restart.
3. Before testing, turn on Lua error reporting with `/console scriptErrors 1`, or install BugSack. The addon wraps frame calls in `pcall`, so some failures stay silent unless errors are visible.

See [Development notes](development.md#installing-it-for-testing) for `-WhatIf`, `-Watch` and `-Remove`.

## Preconditions and setup

Run the plan at least once in each of these configurations. Back up `WTF\Account\<ACCOUNT>\SavedVariables\ForeverWindowMover.lua` before you switch between them.

- [ ] **Fresh install.** Close the game, delete `ForeverWindowMover.lua` from `SavedVariables`, start the game. Expected: every group enabled, MOVE tabs visible in the Dark style, title-bar dragging off, no saved positions.
- [ ] **Upgrade from 0.3.4.** Install `dist\ForeverWindowMover-0.3.4.zip`, save positions for a few windows and disable one group, log out, then sync 0.4.0-beta over it. Expected: covered by [Saved variables and upgrade](#saved-variables-and-upgrade).
- [ ] **Without Titan Panel or any other LDB display addon.**
- [ ] **With Titan Panel 9.3.4 for Forever** (or another LDB display).
- [ ] **UI scale.** Test at the default UI scale and at least one other UI scale setting.
- [ ] Record whether this client has the click-passthrough API that protects the title-bar strip: `/run print(type(CreateFrame("Frame").SetPropagateMouseClicks))`. `function` means the passthrough is in use; `nil` means only the 40px right inset and the frame-level fallback protect the close button.
- [ ] To find out which frame a two-frame group uses on this build, open the window and run, for example, `/run print(ClassTrainerFrame and ClassTrainerFrame:IsShown(), TrainerFrame and TrainerFrame:IsShown())`. Record the result in the window table below.

## Loading and errors

- [ ] At character select, the AddOns list shows **Forever Window Mover** with its icon (the golden mover TGA) and is not flagged out of date.
- [ ] Log in with `scriptErrors` on. Expected: no Lua errors and no chat output from the addon.
- [ ] `/reload`. Expected: no Lua errors.
- [ ] **Options > AddOns** lists **Forever Window Mover**, with a **Handles** entry nested under it. If the client cannot nest it, the fallback is a separate top-level entry named **Forever Window Mover: handles**. Record which one appears.
- [ ] The chat message "Options page could not be registered" does not appear. If it does, record the full error text.
- [ ] With handles and positions in their default state, playing normally for a few minutes produces no errors and no noticeable frame-rate cost. The frame scan runs for about 15 seconds after login or after an addon loads, then stops.

## Slash commands

The addon has had no slash commands since 0.2.0. Everything is in the options panel.

- [ ] `/fwm` and `/windowmover`. Expected: the client's normal unknown-command response, and no Lua error.

## Supported windows

There are eight groups backed by eleven Blizzard frame names (see [Supported windows](supported-windows.md)). Run the same steps for every frame you can open on this build. Mark frames that do not exist on this client as N/A.

| Group (key) | Label in options | Frames | How to open | Frame seen on this build |
| --- | --- | --- | --- | --- |
| `vendor` | Vendors / merchants | `MerchantFrame` | Talk to any vendor | |
| `trade` | Player trades | `TradeFrame` | Trade with a second character | |
| `bank` | Personal bank | `BankFrame` | Talk to a banker | |
| `guildbank` | Guild bank | `GuildBankFrame` | Use a guild vault (needs a guild) | |
| `trainer` | Trainers | `ClassTrainerFrame`, `TrainerFrame` | Talk to a class trainer and a profession trainer | |
| `auction` | Auction house | `AuctionHouseFrame`, `AuctionFrame` | Talk to an auctioneer | |
| `professions` | Professions | `ProfessionsFrame`, `TradeSkillFrame` | Open a profession from the spellbook | |
| `craft` | Crafting / enchanting | `CraftFrame` | Open Enchanting, or a hunter's Beast Training (verify: which crafts use `CraftFrame` on this build) | |

For each frame:

- [ ] Open the window. Expected: a MOVE tab sits just above the window's top-left corner, about 18px in from the left edge.
- [ ] Hover the tab. Expected: the tab lightens and the tooltip reads "Drag to move: *label*" with the group's label from the table.
- [ ] Drag the tab and release. Expected: the window follows the cursor and stays exactly where you dropped it, with no jump on release.
- [ ] Close and reopen the window. Expected: it opens at the dropped position.
- [ ] Open the main options page. Expected: that group reads **Saved** and its **Reset** button is enabled.
- [ ] `/reload`, then reopen. Expected: same position.
- [ ] Log out fully, log back in, reopen. Expected: same position.
- [ ] Log in on a different character on the same account and open the same window. Expected: same position, because positions are account-wide.
- [ ] Drag the same window three or four more times to different spots. Expected: each drop lands where released, with no creeping toward the screen centre.
- [ ] Click the tab without moving the mouse. Expected: nothing happens and nothing is saved. On a group showing **Not set**, it stays **Not set**.
- [ ] Start a drag and press Escape (or otherwise close the window) before releasing. Expected: the drag ends and the window does not stay stuck to the cursor. On reopen it sits where it was when it closed.
- [ ] Drag the window hard into a screen edge and release with the cursor off the tab. Expected: the drag ends; the window is clamped on-screen and does not follow the mouse afterwards.

Group-specific:

- [ ] For two-frame groups (`trainer`, `auction`, `professions`), when both frames exist, move each one to a different spot. Expected: each frame keeps its own position (verify: whether this build uses one frame or both).
- [ ] Open a supported window together with another Blizzard panel (for example a vendor next to the bags, or a trainer with the character pane). Expected: the moved window stays at its saved spot after Blizzard rearranges its panels.
- [ ] Guild bank and auction house are created on first use. On a fresh login, open one, move it, then **Reset** it. Expected: it returns to Blizzard's default layout, not to the moved spot.

## MOVE tab and the screen-top flip

- [ ] Drag a window until its top edge touches the top of the screen. Expected: on release the tab moves to just inside the window's top edge and stays clickable.
- [ ] Drag it back down by the inside tab. Expected: on release, with room above, the tab returns to sitting outside the window.
- [ ] Repeat the flip check with each style: Minimal (16px tall), Dark (20px), Blizzard (22px), and Custom at a tall height such as 60px. Expected: a shorter tab flips later, closer to the top, than a taller one.
- [ ] `/reload` with a window saved against the screen top, then open it. Expected: the tab is already inside the top edge.
- [ ] With the tab flipped inside, check it does not block a control at the top-left of the window. Expected: the tab works, and anything it overlaps is still reachable around it (verify: which windows have a control under the flipped tab).

## UI scale

Positions are stored in UIParent units, so they should hold across UI-scale and resolution changes.

- [ ] Save a position for a window, change the UI scale in the game options, reopen the window. Expected: it is in the same place relative to the screen, and dragging it again lands where released.
- [ ] Repeat after changing resolution or window size. Expected: same.
- [ ] At a non-default UI scale, push a window against the screen top. Expected: the tab flips inside as it does at the default scale.
- [ ] Change UI scale while a window with a flipped tab is open (verify: the tab placement is only recalculated on apply, drag release or a style change, so record whether it is correct straight away or only after the next reopen).
- [ ] Optional, the case the scale conversion exists for: `/run MerchantFrame:SetScale(0.8)` with a vendor open, then drag and reopen several times. Expected: no drift. `/reload` undoes the scale.

## Handle styles and colours

Open **Options > AddOns > Forever Window Mover > Handles** with a supported window open beside it so changes are visible.

- [ ] Under **Tab appearance**, exactly one style is checked, and it is **Dark** on a fresh install.
- [ ] Select **Dark**. Expected: flat dark tab, 70×20, label "MOVE". Status: "Dark tab style selected."
- [ ] Select **Blizzard**. Expected: 70×22 tab with a visible tooltip-style border. Only one style stays checked.
- [ ] Select **Minimal**. Expected: small 22×16 tab, no label, three legible grip dots, not an empty box.
- [ ] Select **Custom**. Expected: the tab uses the custom settings below; by default 70×20 with "MOVE".
- [ ] Hover each style. Expected: the hover colour shows and reverts on leave, including the bordered Blizzard style.
- [ ] Style changes apply to an already-open window straight away, without reopening it.
- [ ] Click **Background**. Expected: the colour picker opens on the current background colour. Change colour and opacity. Expected: the swatch chip and a Custom tab update live.
- [ ] Click **Hover**, pick a colour, then hover the tab. Expected: the new hover colour.
- [ ] Open a picker, change the colour, then press **Cancel**. Expected: the colour returns to what it was before the picker opened.
- [ ] Untick **Show the MOVE label (off gives a grip instead)**. Expected: a Custom tab shows grip dots and no text. Tick it again: "MOVE" returns.
- [ ] Width **-** and **+**: steps of 5, clamped to 20–200. Height **-** and **+**: steps of 2, clamped to 12–60. Expected: the number between the buttons updates, the tab resizes, and the value never passes its limits.
- [ ] Change the custom settings while **Dark** is selected. Expected: the controls still work and the visible tab does not change until you select **Custom**.
- [ ] `/reload`. Expected: the chosen style and every custom value survive.
- [ ] If no colour picker opens, the status line reads "This build has no colour picker; edit handleCustom in the saved variables instead." Record it as a finding.

## Drag by title bar

This is the reason 0.4.0 is a beta. The strip is an invisible 24px band across the top of each window, stopping 40px short of the right edge, and it passes clicks through to whatever is underneath.

- [ ] Tick **Drag by the window's title bar**. Status: "Drag by the window's title bar enabled."
- [ ] Hover the title bar of each supported window. Expected: tooltip "Drag to move: *label*".
- [ ] Drag each window by its title bar. Expected: it moves and saves exactly as with the tab, including after `/reload`.
- [ ] **Close button.** With the strip on, click the close (X) button of every one of the eleven frames you can open. Expected: every window closes. Record any that do not.
- [ ] Click every control in the top ~24px of each window: tabs, search boxes, dropdowns, portraits, filter buttons (for example the auction house search bar, guild bank tabs, profession filters). Expected: each responds as it does with the strip off.
- [ ] Click inside each window's body (vendor items, bank slots, recipe list, trainer list). Expected: normal behaviour, and no drag starts.
- [ ] Single-click the title bar without dragging. Expected: no position is saved; a **Not set** group stays **Not set**.
- [ ] Hover controls just under the strip that have their own tooltips. Expected: those tooltips still appear when the cursor is on them and not on the strip (verify: the strip blocks mouse motion on purpose, so controls inside the strip's 24px will not get hover tooltips).
- [ ] Untick **Show the MOVE tab** while leaving the title bar on. Expected: no tab anywhere, and windows still drag by their title bars.
- [ ] Turn on both the tab and the title bar. Expected: both work. With a window against the screen top, the flipped-inside tab is still clickable over the strip.
- [ ] Untick both. Expected: red warning "Nothing is draggable: switch on the tab, the title bar, or both." and no window can be dragged.
- [ ] Turn the title bar off again. Expected: the title bars stop showing the tooltip and no longer drag.

## Settings panel: main page

Open **Options > AddOns > Forever Window Mover**.

- [ ] Header: title, intro line, byline "By Michael Reilly  |  v0.4.0-beta", a **GitHub:** label and the URL box.
- [ ] Click the URL box. Expected: the URL is highlighted; Ctrl+C copies it. Type into it and click away. Expected: the real URL comes back.
- [ ] Eight rows, one per group, in the order of the table above, each with a checkbox, a **Reset** button and **Saved** or **Not set**.
- [ ] The whole page fits the settings canvas: the **Show MOVE handles** checkbox, **Reset all positions** and the status line are visible without scrolling, at the default UI scale and at the smallest UI scale you use.
- [ ] Untick a group with its window open. Expected: the window snaps back to Blizzard's layout, its tab hides, the row still reads **Saved**. Status: "*label* disabled; saved position retained."
- [ ] Tick it again. Expected: on the next open (or straight away if open) the window returns to its saved spot. Status: "*label* enabled."
- [ ] With a group disabled, try to drag its window by title bar (with that option on). Expected: no drag.
- [ ] **Reset** on a saved group. Expected: Blizzard position restored, the row reads **Not set**, its **Reset** greys out. Status: "*label* position reset. Reopen the window if needed."
- [ ] **Reset** is greyed out on every **Not set** row.
- [ ] Untick **Show MOVE handles (also toggled by Titan right-click)**. Expected: every tab and every title-bar strip goes inactive; group checkboxes and **Saved** labels do not change. Status: "MOVE handles hidden; positions retained." Saved positions still apply when windows open.
- [ ] With **Show MOVE handles** off, the Handles page does not show the nothing-draggable warning.
- [ ] Tick it again. Status: "MOVE handles shown."
- [ ] **Reset all positions**. Expected: every row reads **Not set** and open windows return to Blizzard's layout. Status: "All window positions reset. Reopen any currently open windows."
- [ ] Leave the panel open and move a window. Expected: its row switches to **Saved** without reopening the panel.

## Defaults buttons

- [ ] Main page, Blizzard's **Defaults**. Expected: all positions reset, every group re-enabled, MOVE handles shown. Status: "All settings restored to defaults." Handles page settings are not changed by this (verify: whether the client asks "These settings" or "All settings", and what each choice does to the Handles page).
- [ ] Handles page, **Defaults**. Expected: **Show the MOVE tab** on, **Drag by the window's title bar** off, style **Dark**. Status: "Handle settings restored to defaults." Saved positions are untouched. Custom colours, label and size are kept, because this button does not reset them (verify: whether that is the intended behaviour).
- [ ] After either Defaults, the other page reflects the change when you switch to it.

## Reset and reset-all

- [ ] Reset a group whose window is created only on first use (guild bank, auction house). Expected: Blizzard's layout, not the addon's previous position.
- [ ] Reset, then `/reload`. Expected: the window opens at Blizzard's default position and the row still reads **Not set**.
- [ ] Reset a two-frame group. Expected: both frames' positions are cleared.
- [ ] Disable a group, then reset it, then enable it. Expected: the window stays at Blizzard's layout (reset deleted the coordinates).
- [ ] Reset all, `/reload`, log out and in. Expected: nothing saved anywhere.

## Combat lockdown

Get into combat (for example by attacking a training dummy or a low-level mob) and try every action that changes something. None should produce a Lua error.

- [ ] With the main page open, enter combat. Expected: every control greys out, including the per-group checkboxes and **Reset** buttons, and the status line reads "In combat: window controls are locked until combat ends."
- [ ] Leave combat with the page still open. Expected: within about a quarter of a second the controls re-enable and the combat notice clears.
- [ ] With the Handles page open, enter combat. Expected: the mechanism checkboxes, style checkboxes, colour buttons and label checkbox grey out. Record whether the **-**/**+** size steppers stay clickable (verify: the code does not disable them; a click in combat should only print "Cannot resize the tab during combat.").
- [ ] Leave combat with the Handles page open (verify: that page has no combat poll of its own, so record whether its controls re-enable without switching pages).
- [ ] Click **Defaults** on each page in combat. Expected: "Cannot restore defaults during combat." and nothing changes.
- [ ] Drag a MOVE tab in combat. Expected: nothing moves, no error.
- [ ] Drag a title bar in combat (with that option on). Expected: nothing moves, no error.
- [ ] Open a window with a saved position during combat (a vendor you were already talking to, or a profession). Expected: no error; the saved position may not apply until the window is reopened out of combat (verify: record where it opens).
- [ ] Start dragging a window, then get pulled into combat before releasing (verify: record where the window ends up and whether the position is saved).
- [ ] Titan right-click in combat. Expected: chat message "Cannot toggle MOVE handles during combat." and the label does not change.
- [ ] Titan left-click in combat (verify: record whether the settings page opens or the client blocks it).
- [ ] `/reload`, enter combat within the first 15 seconds, then open a window after combat ends. Expected: its tab is present, because the frame scan keeps running while installation is blocked by combat.

## Titan Panel and LibDataBroker

Without Titan or any LDB display:

- [ ] The addon loads with no errors and no chat output, and the options pages work.

With Titan Panel:

- [ ] **Window Mover** appears in Titan's plugin list and can be added to a bar, showing the gear icon and the text "Window Mover".
- [ ] Hover it. Expected tooltip: "Forever Window Mover", "Left-click: AddOns settings", "Right-click: Show / hide all MOVE handles", the **MOVE handles** state, one line per group reading `Enabled - saved`, `Enabled - no position` or `Disabled`, then the byline, the GitHub URL and "Copy the URL from Options > AddOns".
- [ ] Tooltip group lines match the options page after you move, disable and reset a few groups.
- [ ] Left-click. Expected: **Options > AddOns > Forever Window Mover** opens. If it cannot, chat reads "Open Options > AddOns > Forever Window Mover."
- [ ] Right-click. Expected: all handles hide and the text becomes "Mover: OFF"; the **Show MOVE handles** checkbox matches. Right-click again: "Window Mover" and handles return.
- [ ] Toggle **Show MOVE handles** in the options page. Expected: the Titan text follows.
- [ ] `/reload` with handles off. Expected: Titan shows "Mover: OFF" straight after loading.
- [ ] With Titan disabled at login, enable it later (or load it on demand if your setup allows) (verify: Titan normally needs a reload to enable; record whether the launcher appears afterwards).
- [ ] If you use another LDB display addon, repeat the hover, left-click and right-click checks there.

## Saved variables and upgrade

- [ ] Fresh install: after logging out without changing anything, `ForeverWindowMover.lua` in `SavedVariables` contains only empty `positions` and `enabled` tables.
- [ ] Upgrade from 0.3.4: every position saved under 0.3.4 applies unchanged, the disabled group is still disabled, handles are shown, and the tab is the Dark style. Nothing changes that you did not ask for.
- [ ] Upgrade from an older version (optional, using `dist\ForeverWindowMover-0.3.2.zip` or `-0.3.3.zip`). Expected: same as above.
- [ ] After changing Handles settings and logging out, the file contains `handleTab`, `handleTitlebar`, `handleStyle` and `handleCustom` with the values you set.
- [ ] Downgrade check (optional): reinstall 0.3.4 over the 0.4.0 saved file. Expected: 0.3.4 loads without errors and ignores the new fields (verify).
- [ ] Hand-edit the file with the game closed, for example set `handleStyle = "nope"` or `handleCustom = { width = 0 }`. Expected: no error; Dark style, or a default-sized custom tab.

## Other addons that move frames

The docs do not describe how the addon behaves next to other frame movers, so record what happens.

- [ ] With another frame-moving addon enabled (for example BlizzMove or MoveAnything, if available for Forever), open each supported window (verify: which addon wins, whether the window jumps between positions, and whether either addon errors).
- [ ] With a bag or bank replacement addon enabled, open the bank and guild bank (verify: whether `BankFrame` and `GuildBankFrame` are still the visible windows and still get a tab).
- [ ] With an auction house or profession replacement addon, open those windows (verify: as above).
- [ ] With Titan Panel bars at the top of the screen, push a window to the top. Expected: the flipped tab is not hidden behind the Titan bar (verify).

## New in 0.4.0 and regression

From the [0.4.0-beta changelog entry](../CHANGELOG.md#040-beta). Most of these are covered above; this section is the short pass for a quick beta sign-off.

- [ ] **Defaults match 0.3.4.** With no Handles settings changed, tabs look and behave exactly like 0.3.4: Dark style, MOVE label, title-bar strip off.
- [ ] **Handles page.** It exists under **Options > AddOns > Forever Window Mover > Handles** (or the fallback top-level entry), and every control works.
- [ ] **Four tab styles.** Dark, Blizzard (border), Minimal (grip, no label) and Custom (colours, label, width, height) render correctly.
- [ ] **Title-bar drag.** Works on every supported window, off by default, and the close button and top-edge controls still respond.
- [ ] **Independence.** Tab only, title bar only, both, neither: each behaves as described, and "neither" shows the warning.
- [ ] **Master switch.** **Show MOVE handles** and Titan right-click disable both the tab and the title-bar strip.
- [ ] **Style-aware flip.** A shorter style flips later near the screen top than a taller one.
- [ ] **Saved format unchanged.** Positions and group enable flags from 0.3.4 load as-is.

Regression checks for fixes from earlier releases:

- [ ] Positions do not drift over repeated drags (0.3.2).
- [ ] A drag released at a screen edge ends cleanly (0.3.2).
- [ ] Click without drag saves nothing (0.3.2).
- [ ] Reset restores Blizzard's layout for first-use windows (0.3.2).
- [ ] The tab stays clickable at the screen top (0.3.2).
- [ ] Per-group checkboxes grey out in combat (0.3.2).
- [ ] Only `ADDON_LOADED` and `PLAYER_LOGIN` are registered, so the addon initialises on Forever without errors (0.2.1).

## Issues found

Severity: **Blocker** (Lua error, lost positions, a window that cannot be closed or used), **Major** (a feature does not work), **Minor** (cosmetic or a workaround exists).

| # | Item | Steps | Expected | Actual | Severity |
| --- | --- | --- | --- | --- | --- |
| 1 | | | | | |
| 2 | | | | | |
| 3 | | | | | |

For a title-bar issue, include the window, the frame name, and the `SetPropagateMouseClicks` result from [Preconditions and setup](#preconditions-and-setup). Report issues at https://github.com/mreillyorg/ForeverWindowMover/issues.
