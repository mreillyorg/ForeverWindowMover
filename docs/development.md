# Development notes

## Repository layout

```
ForeverWindowMover-repo/
├── ForeverWindowMover/        <- the shippable addon folder
│   ├── ForeverWindowMover.toc
│   ├── ForeverWindowMover.lua
│   ├── Options.lua
│   ├── TitanBroker.lua
│   ├── README.txt             <- in-package notes for distribution sites
│   ├── CHANGELOG.md           <- in-package release history
│   └── LICENSE
├── docs/                      <- this documentation
├── README.md
├── CHANGELOG.md               <- repo-level release history
└── LICENSE
```

For testing, the `ForeverWindowMover` folder is what goes into `Interface\AddOns\`. A symlink or junction from the AddOns directory to the repo folder avoids copying on every change:

```powershell
New-Item -ItemType Junction -Path "C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\ForeverWindowMover" -Target "<repo>\ForeverWindowMover"
```

There is no build step, no package manager, and no test harness — the client is the only runtime.

## Design constraints

These are load-bearing. Breaking them is how the addon stops working on WoW: Forever.

**Only register `ADDON_LOADED` and `PLAYER_LOGIN`.** Registering an event the Forever client does not recognise can abort the addon outright. Discovery of lazily created frames is handled by a ~1 Hz `OnUpdate` scan instead of events like `MERCHANT_SHOW` or `BANKFRAME_OPENED`.

**Wrap every frame mutation in `pcall`.** Some bank and professions frames are protected on some beta builds. A failure must be contained to that one frame so the other groups keep working.

**Never act during combat lockdown.** `CanMove()` gates installation, applying, restoring, dragging, and all four mutators. Mutators return `false` so callers can explain the refusal instead of failing silently.

**Defer position application past Blizzard's panel manager.** `OnShow` re-applies through `C_Timer.After(0, ...)`, and `UpdateUIPanelPositions` is hooked with `hooksecurefunc` so managed panels get corrected after the layout pass. Applying synchronously on `OnShow` loses the race.

**Keep the three files decoupled.** The core owns frames and state; `Options.lua` and `TitanBroker.lua` only call core functions, and the core only reaches back through existence-checked `addon.RefreshOptions` / `addon.RefreshBroker`.

**Treat group keys and frame names as a saved-variable contract.** See [saved variables](saved-variables.md#compatibility).

## Manual test checklist

Frame behaviour:

- [ ] Each supported window shows a MOVE tab, drags, and reopens in the new spot.
- [ ] Two frames in the same group (e.g. `ClassTrainerFrame` and `TrainerFrame`) keep separate positions.
- [ ] A window closed mid-drag saves its position rather than sticking in a moving state.
- [ ] Positions survive `/reload` and a full logout.
- [ ] Positions hold after changing UI scale or resolution.

Options panel:

- [ ] Disabling a group restores Blizzard's position, hides the tab, and keeps **Saved**.
- [ ] Re-enabling returns the window to the saved spot.
- [ ] Per-group **Reset** clears the position, greys out its own button, and flips the label to **Not set**.
- [ ] **Show MOVE handles** hides every tab without changing any checkbox or position.
- [ ] **Reset all positions** clears everything.
- [ ] Blizzard's **Defaults** resets positions, re-enables all groups, and shows handles.

Combat:

- [ ] Entering combat greys out every control on a visible panel.
- [ ] Clicking a MOVE tab in combat does nothing and does not error.
- [ ] Right-clicking the Titan launcher in combat prints the combat message.

Titan / LDB:

- [ ] Without Titan or any LDB display installed, the addon loads with no errors and the options panel still works.
- [ ] With Titan, the launcher appears, left-click opens the options page, right-click toggles handles, and the label switches between `Window Mover` and `Mover: OFF`.
- [ ] Tooltip group lines match the actual enable/saved state.
- [ ] Enabling Titan *after* Forever Window Mover still produces the launcher.

Run with `/console scriptErrors 1`, or BugSack, so swallowed problems surface during testing.

## Release steps

1. Bump the version in all four places: `## Version` in the `.toc`, `addon.version` in `ForeverWindowMover.lua`, the header comment in `ForeverWindowMover.lua`, and the title line in `ForeverWindowMover/README.txt`.
2. Update `## Interface` if targeting a new client build, and the Interface number quoted in `README.md`, `ForeverWindowMover/README.txt`, and `docs/README.md`.
3. Add the "NEW IN x.y.z" section to both `README.md` and `ForeverWindowMover/README.txt`, and note whether the saved-position format changed.
4. Add the release to **both** changelogs — `CHANGELOG.md` and `ForeverWindowMover/CHANGELOG.md` — as a new `## x.y.z` section at the top. The two files are maintained in parallel and their version sections should stay identical; only the headers differ, since the repo copy links to `docs/` while the in-package copy spells out the GitHub URL instead. Group entries under Added / Changed / Fixed / Removed / Unchanged, and say explicitly when the `ForeverWindowMoverDB` format is unchanged.
5. Update these docs if behaviour, the group list, or the schema changed.
6. Work through the test checklist on a clean saved-variables file and on one carried over from the previous version.
7. Zip the `ForeverWindowMover` folder (the folder itself, not its contents) for distribution.
8. Commit and tag the release as `vx.y.z`, so the next changelog entry can be diffed against it with `git diff vx.y.z..HEAD -- ForeverWindowMover`.
