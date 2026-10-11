# User guide

## Installation

1. Close the game client.
2. Copy the `ForeverWindowMover` folder into `World of Warcraft\_classic_beta_\Interface\AddOns\`.
   The folder name must stay `ForeverWindowMover` so it matches `ForeverWindowMover.toc`.
3. Start the game, and at the character select screen make sure **Forever Window Mover** is checked in the AddOns list.

The `.toc` targets Interface `16001` (WoW: Forever 1.60.1). On other client builds the addon may be flagged out of date; enable "Load out of date AddOns" at your own risk.

## Moving a window

1. Open one of the [supported windows](supported-windows.md), for example a vendor.
2. A dark **MOVE** tab appears just above the window's top-left corner.
3. Hold the left mouse button on the tab and drag. Hovering the tab shows a tooltip naming the window group.
4. Release. The position is saved immediately and reapplied every time that window opens.

Notes:

- Windows are clamped to the screen, so you cannot drag one fully off-display.
- If you drag a window right to the top of the screen, the **MOVE** tab moves to just inside the window's top edge so it stays clickable.
- Each Blizzard frame remembers its own position. Moving the vendor window does not move the bank.
- Dragging is blocked during combat. Leave combat and try again.
- Clicking the tab without moving the mouse does nothing. You need to actually drag.
- If a window is closed mid-drag, the move is finalised and the current position is saved.

## Options panel

Open **Game Menu > Options > AddOns > Forever Window Mover**, or left-click the Titan Panel launcher if you use it.

| Control | Effect |
| --- | --- |
| Per-group checkbox | Enables or disables dragging for that window group. Disabling restores Blizzard's original anchors but **keeps** the saved position. |
| Per-group **Reset** | Clears the saved position for that group and restores Blizzard's anchors. Greyed out when nothing is saved. |
| **Saved** / **Not set** | Whether any frame in that group currently has a stored position. |
| **Show MOVE handles** | Shows or hides every MOVE tab at once. Independent of the per-group checkboxes and of saved positions. |
| **Reset all positions** | Clears every saved position in one go. |
| Status line (bottom) | Confirms the last action, or explains why it was refused (usually combat). |

Blizzard's **Defaults** button on the settings page resets all positions, re-enables every group, and turns MOVE handles back on.

All controls are disabled while you are in combat lockdown, and the status line says so. If you are looking at the page when combat ends, the controls come back on their own within a fraction of a second.

## Resetting vs disabling

These are deliberately different:

- **Disable** a group — the window snaps back to Blizzard's layout and the MOVE tab hides, but your coordinates are still on disk. Re-enable and the window returns to where you had it.
- **Reset** a group — the stored coordinates are deleted, `SetUserPlaced` is cleared, and Blizzard's panel layout is recalculated. Re-enabling will not bring the old position back.

Hiding all MOVE handles does neither; it only hides the drag tabs.

## Troubleshooting

**No MOVE tab on a window.**
Confirm the group is enabled and **Show MOVE handles** is on. A few frames are only created the first time you use the feature; the addon rescans about once a second for a short while after login and after any addon loads, so open the window and give it a moment. Frames the client refuses to make movable are skipped silently.

**A window will not move.**
You are probably in combat. Some frames are protected on certain beta builds; the addon catches those failures rather than erroring, so a single stubborn frame does not break the rest.

**A window keeps jumping back.**
Blizzard's UI panel manager repositions managed frames. Forever Window Mover re-applies your saved position after `UpdateUIPanelPositions` runs, which normally wins. If a frame still fights back, reset that group and move it again.

**The options page is missing.**
The page registers at login and the addon retries for a few seconds if Blizzard's settings UI was not ready. If registration fails outright, the addon prints the error to chat once.

**Reset put a window somewhere odd.**
Fixed in 0.3.2 for windows that the client creates on first use. Before that, the addon could record its own position as the window's "original" one and restore to that. If a window is still in the wrong place, reset it, close and reopen it, then drag it again.
