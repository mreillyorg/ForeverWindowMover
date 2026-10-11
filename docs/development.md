# Development notes

## Repository layout

```
ForeverWindowMover-repo/
├── ForeverWindowMover/        <- the shippable addon folder
│   ├── ForeverWindowMover.toc
│   ├── ForeverWindowMover.lua
│   ├── Options.lua
│   ├── TitanBroker.lua
│   ├── Ornate-Golden-UI-Mover-Icon.png   <- source art, not shipped
│   ├── Ornate-Golden-UI-Mover-Icon.tga   <- generated addon-list icon
│   ├── README.txt             <- in-package notes for distribution sites
│   ├── CHANGELOG.md           <- generated from CHANGELOG.md
│   └── LICENSE                <- generated from LICENSE
├── docs/                      <- this documentation
├── tools/
│   ├── build.ps1              <- generate in-package copies, check, package
│   └── Convert-IconToTga.ps1  <- PNG source art -> client-readable TGA
├── dist/                      <- build output, git-ignored
├── README.md
├── CHANGELOG.md               <- repo-level release history
└── LICENSE
```

For testing, the `ForeverWindowMover` folder is what goes into `Interface\AddOns\`. A symlink or junction from the AddOns directory to the repo folder avoids copying on every change:

```powershell
New-Item -ItemType Junction -Path "C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\ForeverWindowMover" -Target "<repo>\ForeverWindowMover"
```

There is no package manager and no test harness — the client is the only runtime. The one build step is `tools/build.ps1`, and it is not needed to run the addon from a junction.

## Generated files

Two files in the addon folder are generated, not edited:

| Generated | From | Transform |
| --- | --- | --- |
| `ForeverWindowMover/CHANGELOG.md` | `CHANGELOG.md` | Same body. The author / source line is inserted after the intro paragraph, and the repo-only footer links to `docs/` are dropped, because `docs/` does not ship. |
| `ForeverWindowMover/LICENSE` | `LICENSE` | Verbatim copy. |

Editing either copy by hand is how the 0.3.1 changelogs drifted apart. Change `CHANGELOG.md` at the repository root and run `tools\build.ps1`.

`ForeverWindowMover/README.txt` is deliberately **not** generated. It is hand-wrapped plain text for distribution sites with different formatting from `README.md`, so the script only verifies that its version and Interface headers agree with the `.toc`.

## tools/build.ps1

```powershell
.\tools\build.ps1          # regenerate, verify, write dist\ForeverWindowMover-x.y.z.zip
.\tools\build.ps1 -Check   # verify only; non-zero exit if anything is out of sync
.\tools\build.ps1 -SkipPackage
```

What it does, in order:

1. Reads `## Version`, `## Interface` and `## IconTexture` from the `.toc`, and `addon.author` / `addon.website` from `ForeverWindowMover.lua`, so the attribution line it generates has one source.
2. Checks the version in the core Lua header comment, `addon.version`, the `README.md` title, the `README.txt` title, and that `CHANGELOG.md` has a `## <version>` section. **The `.toc` is authoritative.**
3. Checks the Interface number is quoted in `README.md`, `README.txt` and `docs/README.md`.
4. Checks the `.toc` and the addon folder agree on which `.lua` files exist, and that `## IconTexture` resolves to a file that is actually there and is not a PNG.
5. Regenerates the icon TGA if it is missing or older than the PNG.
6. Writes the generated `CHANGELOG.md` and `LICENSE` copies (UTF-8 without BOM, LF endings). Comparison ignores CRLF/LF differences so a Windows checkout is not reported as drift.
7. Zips a staging copy of the addon folder — excluding `*.png`, `*.psd`, `*.xcf` — into `dist/`, with the `ForeverWindowMover` folder itself at the root of the archive.

`-Check` makes it a usable pre-commit or CI gate: it reports what *would* change and exits 1 without writing.

## The addon-list icon

`## IconTexture` points at `Ornate-Golden-UI-Mover-Icon.tga`. The client reads **BLP and uncompressed TGA only** — a PNG referenced from the `.toc` is not an error, it simply renders as nothing, which is easy to miss. `tools/Convert-IconToTga.ps1` resizes the 1254x1254 source PNG to a 64x64 power-of-two square and writes a 32-bit uncompressed TGA (BGRA, bottom-left origin, 8 alpha bits).

The PNG stays in the repository as the source art. At ~2 MB it is far larger than the rest of the addon put together, so `build.ps1` leaves it out of the package. If you replace the art, drop in a new PNG and re-run the build; add `-Force` to the converter to rewrite the TGA regardless of timestamps.

## Design constraints

These are load-bearing. Breaking them is how the addon stops working on WoW: Forever.

**Only register `ADDON_LOADED` and `PLAYER_LOGIN`.** Registering an event the Forever client does not recognise can abort the addon outright. Discovery of lazily created frames is handled by a ~1 Hz scan instead of events like `MERCHANT_SHOW` or `BANKFRAME_OPENED`, and combat state is *polled* rather than watched with `PLAYER_REGEN_ENABLED`. If you need to know about something, poll it from a timer or from an `OnUpdate` that only runs while the relevant frame is shown.

**Bound anything that polls.** The discovery scan is a 15-tick burst re-armed by `ADDON_LOADED` and `PLAYER_LOGIN`, not a session-long `OnUpdate`. Frames only appear at login or when their owning addon loads, so there is nothing for a permanent timer to find. Keep it that way: if you add a new polling loop, give it a stop condition.

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
- [ ] Dragging a window hard into a screen edge and releasing there ends the drag — the window does not stay attached to the cursor.
- [ ] A window does not jump on release, and repeated drags do not creep toward the screen centre. Worth retesting with `MerchantFrame:SetScale(0.8)` applied by hand, since that is the case the scale conversion exists for.
- [ ] A window dragged to the top of the screen still has a clickable MOVE tab, now inside its top edge.
- [ ] Positions survive `/reload` and a full logout.
- [ ] Positions hold after changing UI scale or resolution.
- [ ] A window the client only creates on first use (guild bank, auction house) resets to Blizzard's layout, not to wherever the addon last put it.

Options panel:

- [ ] Disabling a group restores Blizzard's position, hides the tab, and keeps **Saved**.
- [ ] Re-enabling returns the window to the saved spot.
- [ ] Per-group **Reset** clears the position, greys out its own button, and flips the label to **Not set**.
- [ ] **Show MOVE handles** hides every tab without changing any checkbox or position.
- [ ] **Reset all positions** clears everything.
- [ ] Blizzard's **Defaults** resets positions, re-enables all groups, and shows handles.

Combat:

- [ ] Entering combat greys out every control on a visible panel, including the per-group enable checkboxes, and the status line explains why.
- [ ] Leaving combat with the panel still open re-enables the controls without reopening the page.
- [ ] Clicking a MOVE tab in combat does nothing and does not error.
- [ ] Right-clicking the Titan launcher in combat prints the combat message.

Packaging:

- [ ] `.\tools\build.ps1 -Check` passes on a clean checkout.
- [ ] Hand-editing `ForeverWindowMover/CHANGELOG.md` makes `-Check` fail.
- [ ] The addon shows its icon in the character-select AddOns list.
- [ ] The zip in `dist/` contains a `ForeverWindowMover` folder, no `.png`, and loads when dropped into `Interface\AddOns\`.

Titan / LDB:

- [ ] Without Titan or any LDB display installed, the addon loads with no errors and the options panel still works.
- [ ] With Titan, the launcher appears, left-click opens the options page, right-click toggles handles, and the label switches between `Window Mover` and `Mover: OFF`.
- [ ] Tooltip group lines match the actual enable/saved state.
- [ ] Enabling Titan *after* Forever Window Mover still produces the launcher.

Run with `/console scriptErrors 1`, or BugSack, so swallowed problems surface during testing.

## Release steps

1. Bump the version in all five places: `## Version` in the `.toc`, `addon.version` and the header comment in `ForeverWindowMover.lua`, the title line in `README.md`, and the title line in `ForeverWindowMover/README.txt`. Run `.\tools\build.ps1 -Check` to confirm you did not miss one — it checks every site against the `.toc`.
2. Update `## Interface` if targeting a new client build, and the Interface number quoted in `README.md`, `ForeverWindowMover/README.txt`, and `docs/README.md`. `-Check` covers these too.
3. Add the "NEW IN x.y.z" section to both `README.md` and `ForeverWindowMover/README.txt`, and note whether the saved-position format changed.
4. Add the release to `CHANGELOG.md` **at the repository root only**, as a new `## x.y.z` section at the top. Group entries under Added / Changed / Fixed / Removed / Unchanged, and say explicitly when the `ForeverWindowMoverDB` format is unchanged. The in-package copy is generated from it.
5. Update these docs if behaviour, the group list, or the schema changed.
6. Run `.\tools\build.ps1`. It regenerates the in-package copies, fails on any inconsistency, and writes `dist\ForeverWindowMover-x.y.z.zip` with the `ForeverWindowMover` folder (the folder itself, not its contents) at the archive root.
7. Work through the test checklist on a clean saved-variables file and on one carried over from the previous version.
8. Commit the regenerated files along with the release, and tag it `vx.y.z`, so the next changelog entry can be diffed against it with `git diff vx.y.z..HEAD -- ForeverWindowMover`.
