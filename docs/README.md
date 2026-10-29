# Forever Window Mover — Documentation

Addon documentation for **Forever Window Mover** 0.3.4, a World of Warcraft: Forever (Interface `16001`) addon that makes several normally immovable Blizzard windows draggable and remembers where you put them.

- Author: Michael Reilly
- Source / issues: https://github.com/mreillyorg/ForeverWindowMover
- License: see [`LICENSE`](../LICENSE)

## Contents

| Document | What it covers |
| --- | --- |
| [User guide](user-guide.md) | Installing, moving windows, the options panel, resetting positions |
| [Supported windows](supported-windows.md) | Every window group and the Blizzard frames behind it |
| [Titan Panel / LDB launcher](titan-panel-integration.md) | The optional LibDataBroker launcher and its behaviour |
| [Architecture](architecture.md) | File layout, load sequence, frame discovery, positioning math |
| [Internal API](api-reference.md) | Functions exposed on the shared `addon` table |
| [Saved variables](saved-variables.md) | `ForeverWindowMoverDB` schema and migration notes |
| [Development notes](development.md) | Design constraints, the `tools/` scripts, testing checklist, release steps |

## At a glance

- Each supported window gets a small **MOVE** tab above its top-left corner. Drag the tab, release, position saved.
- Positions are stored **per Blizzard frame**, **per account** (not per character).
- Everything is configured under **Options > AddOns > Forever Window Mover**. There are no slash commands.
- Nothing is changed while you are in combat; the addon defers instead of risking a protected-frame error.
- Titan Panel and LibDataBroker support is optional. No Titan files or libraries are bundled.
