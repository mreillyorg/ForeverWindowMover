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
│   ├── Common.ps1             <- shared helpers, dot-sourced by the others
│   ├── build.ps1              <- generate in-package copies, check, package
│   ├── Sync-ToAddOns.ps1      <- install into Interface\AddOns for testing
│   └── Convert-IconToTga.ps1  <- PNG source art -> client-readable TGA
├── dist/                      <- build output, git-ignored
├── README.md
├── CHANGELOG.md               <- repo-level release history
└── LICENSE
```

There is no package manager and no test harness — the client is the only runtime. The two scripts worth knowing are `tools/Sync-ToAddOns.ps1` for getting the addon in front of the client, and `tools/build.ps1` for releasing it.

## Installing it for testing

```powershell
.\tools\Sync-ToAddOns.ps1            # regenerate, then mirror into Interface\AddOns
.\tools\Sync-ToAddOns.ps1 -WhatIf    # dry run: what would be copied or deleted
.\tools\Sync-ToAddOns.ps1 -Watch     # re-sync on every save, until Ctrl+C
.\tools\Sync-ToAddOns.ps1 -Remove    # uninstall
```

It mirrors **only the files that ship** — `Get-FwmShippableFile` is the same helper the zip uses — so what you load in the client is what goes in the release, source PNG and all other exclusions left behind. Files from an older install that are no longer part of the addon are deleted, which is how a stale copy gets cleaned up rather than quietly shadowing the new one.

Unless you pass `-SkipBuild`, it runs `build.ps1 -SkipPackage` first, so the generated `CHANGELOG.md`, `LICENSE` and icon TGA are current before the copy. If `build.ps1` reports a problem, nothing is synced.

The AddOns directory is found automatically, in this order: `$env:WOW_ADDONS_PATH`, then by walking up from the repository — which is what resolves it when the checkout lives inside the WoW tree, as it does here — then the default install locations. If more than one candidate turns up, the script stops and lists them rather than guessing a flavour. Use `-AddOnsPath` to be explicit.

### Copy vs junction

| | `-Mode Copy` (default) | `-Mode Junction` |
| --- | --- | --- |
| What the client loads | A mirror of the shipping files | The repository folder itself |
| After an edit | Re-run the sync (or leave `-Watch` running) | Nothing, edits are already live |
| Non-shipping files visible to the client | No | Yes, including the ~2 MB source PNG |
| Matches what users get | Yes | No |

`Copy` is the default because it is the one that catches "works from the repo, broken in the zip" — a missing `.toc` entry, or a file the exclusion list removes. Reach for `Junction` when you are iterating on Lua and tired of re-syncing. Replacing an existing real folder with a junction needs `-Force`, and the two modes refuse to stomp each other: `Copy` will not write through a junction, and `Junction` will not silently delete a real folder.

Either way, the client has to be told to re-read the files. **Lua changes need `/reload`; `.toc` and metadata changes need a full client restart.** The script warns when it detects a running client.

### Safety

The scripts write into a game install, and the sync deletes stale files, so the target path is validated before anything is touched: it must be named `ForeverWindowMover` and its parent must be an `AddOns` directory (`Assert-FwmSafeTargetPath`). A bad `-AddOnsPath` fails instead of pointing a recursive delete somewhere unfortunate. `-Remove` on a junction deletes the link only, never the repository behind it. Both scripts support `-WhatIf`.

## tools/Common.ps1

Dot-sourced by the other scripts. It holds the addon name, the package exclusion list, `.toc` field parsing, the version/author metadata reads, the shippable-file selection, AddOns discovery and the target-path guard. Same reasoning as generating the in-package changelog: `build.ps1` and `Sync-ToAddOns.ps1` both need the exclusion list, and two hand-maintained copies would drift.

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

1. Reads `## Version`, `## Interface` and `## IconTexture` from the `.toc`, and `addon.author` / `addon.website` from `ForeverWindowMover.lua` (via `Get-FwmMetadata`), so the attribution line it generates has one source.
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

Packaging and tooling:

- [ ] `.\tools\build.ps1 -Check` passes on a clean checkout.
- [ ] Hand-editing `ForeverWindowMover/CHANGELOG.md` makes `-Check` fail.
- [ ] The addon shows its icon in the character-select AddOns list.
- [ ] The zip in `dist/` contains a `ForeverWindowMover` folder, no `.png`, and loads when dropped into `Interface\AddOns\`.
- [ ] `.\tools\Sync-ToAddOns.ps1` reports `0 added, 0 updated, 0 removed` on a second consecutive run.
- [ ] A junk file dropped into the installed folder is removed by the next sync.
- [ ] `-Remove` after `-Mode Junction` leaves the repository folder intact.

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
