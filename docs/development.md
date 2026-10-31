# Development notes

## Repository layout

The addon's files live at the **repository root**. That is not a stylistic choice: the BigWigs packager looks for `<package-as>.toc` in the top directory, and its `-t` switch cannot be aimed at a subdirectory because the checkout's `.git` has to be in the same place. See [CurseForge publishing](#curseforge-publishing).

```
ForeverWindowMover-repo/
├── ForeverWindowMover.toc      <- the addon itself, at the root
├── ForeverWindowMover.lua
├── Options.lua
├── TitanBroker.lua
├── Ornate-Golden-UI-Mover-Icon.tga   <- generated addon-list icon, ships
├── Ornate-Golden-UI-Mover-Icon.png   <- source art, does NOT ship
├── README.md                   <- ships
├── CHANGELOG.md                <- ships, and is the packager's release notes
├── LICENSE                     <- ships
├── .pkgmeta                    <- defines what ships; read by tools/ too
├── .github/workflows/
│   └── release.yml             <- tag -> validate -> package -> CurseForge
├── .gitattributes              <- pins LF; CRLF for *.cmd; binaries protected
├── .luacheckrc                 <- lint config; declares every WoW global used
├── run-tests.cmd               <- launcher for tools/run_tests.py
├── tests/                      <- offline Lua harnesses, do NOT ship
│   ├── wow.lua                 <- stand-in for the client, loaded first
│   ├── syntax.lua              <- compiles every TOC-listed file
│   ├── groups.lua              <- the group table as a saved-variable contract
│   ├── positions.lua           <- save/apply unit conversion and drift
│   ├── state.lua               <- bootstrap, mutators, anchor capture
│   ├── handles.lua             <- MOVE tab placement and visibility
│   ├── options.lua             <- panel layout and combat gating
│   └── broker.lua              <- the optional LibDataBroker launcher
├── docs/                       <- this documentation, does not ship
├── tools/                      <- does not ship
│   ├── Common.ps1              <- shared helpers, dot-sourced by the others
│   ├── build.ps1               <- validate sources, and build a local zip
│   ├── Sync-ToAddOns.ps1       <- install into Interface\AddOns for testing
│   ├── Convert-IconToTga.ps1   <- PNG source art -> client-readable TGA
│   ├── run_tests.py            <- discover and run the harnesses
│   ├── check_lua_quality.py    <- compile + harnesses + zero-warning lint
│   ├── check_package.py        <- validate the built zip
│   ├── bump_version.py         <- roll the version and pick the channel
│   └── fault_inject.py         <- prove the harnesses catch each bug; not in CI
├── dist/                       <- local build output, git-ignored
└── .release/                   <- packager working directory, git-ignored
```

Everything at the root either ships or is listed in `.pkgmeta`'s `ignore`. There is no third category, and `build.ps1` will tell you if a new file falls between the two.

There is no package manager and no test harness — the client is the only runtime. The two scripts worth knowing are `tools/Sync-ToAddOns.ps1` for getting the addon in front of the client, and `tools/build.ps1` for releasing it.

## Installing it for testing

```powershell
.\tools\Sync-ToAddOns.ps1            # regenerate, then mirror into Interface\AddOns
.\tools\Sync-ToAddOns.ps1 -WhatIf    # dry run: what would be copied or deleted
.\tools\Sync-ToAddOns.ps1 -Watch     # re-sync on every save, until Ctrl+C
.\tools\Sync-ToAddOns.ps1 -Remove    # uninstall
```

It mirrors **only the files that ship** — `Get-FwmShippableFile` is the same helper the zip uses — so what you load in the client is what goes in the release, source PNG and all other exclusions left behind. Files from an older install that are no longer part of the addon are deleted, which is how a stale copy gets cleaned up rather than quietly shadowing the new one.

Unless you pass `-SkipBuild`, it runs `build.ps1 -Check` first, so a version mismatch or a stale icon stops the sync rather than being tested. If `-Check` reports a problem, nothing is synced.

The AddOns directory is found automatically, in this order: `$env:WOW_ADDONS_PATH`, then by walking up from the repository — which is what resolves it when the checkout lives inside the WoW tree, as it does here — then the default install locations. If more than one candidate turns up, the script stops and lists them rather than guessing a flavour. Use `-AddOnsPath` to be explicit.

### No junction mode

Before 0.3.3 the script could link the addon subfolder into `Interface\AddOns` instead of copying. That option is gone: with the addon at the repository root, a junction would put `.git`, `docs/` and `tools/` inside the game install. `-Watch` covers the same "edit and go" case by copying on every save, and a junction left over from the old script is detected and refused rather than written through — run `-Remove` first.

Copying is also the mode that catches "works from my tree, broken in the zip", since it installs exactly the files `.pkgmeta` says will ship.

The client still has to be told to re-read the files. **Lua changes need `/reload`; `.toc` and metadata changes need a full client restart.** The script warns when it detects a running client.

### Safety

The scripts write into a game install, and the sync deletes stale files, so the target path is validated before anything is touched: it must be named `ForeverWindowMover` and its parent must be an `AddOns` directory (`Assert-FwmSafeTargetPath`). A bad `-AddOnsPath` fails instead of pointing a recursive delete somewhere unfortunate. `-Remove` on a junction deletes the link only, never the repository behind it. Both scripts support `-WhatIf`.

## tools/Common.ps1

Dot-sourced by the other scripts. It holds the addon name, `.toc` and `.pkgmeta` field parsing, the version/author metadata reads, the shippable-file selection, AddOns discovery and the target-path guard.

`Get-FwmPackageIgnore` reads only the flat `ignore:` sequence out of `.pkgmeta` rather than pulling in a YAML parser — that is the one key the local tooling needs and the file is ours. It throws if the key is missing, because silently shipping `docs/` and `tools/` would be worse than failing.

## What ships, and who decides

`.pkgmeta`'s `ignore` list is the **single source of truth**. The BigWigs packager reads it when building the CurseForge upload, and `Get-FwmShippableFile` in `tools/Common.ps1` parses the same list so `build.ps1` and `Sync-ToAddOns.ps1` agree with it. Add a repo-only file to `ignore` and all three stop shipping it; no PowerShell changes.

Currently ignored: `docs`, `tools`, `dist`, and `*.png`. Files beginning with a period are always ignored by the packager, so `.pkgmeta`, `.gitignore` and `.github` need no entry — and `Get-FwmShippableFile` skips dot files for the same reason.

Two guards exist because getting this wrong is quiet rather than loud:

- `build.ps1` fails if an `ignore` rule would strip the `.toc`, any `.lua` file listed in it, or the icon. An addon that works from your working tree and is broken in the zip is the worst failure mode here.
- `build.ps1` fails if `.pkgmeta`'s `package-as` does not match the addon name, because that name becomes the folder inside the zip and the `## IconTexture` path depends on it.

Before 0.3.3 the addon lived in a subfolder and `CHANGELOG.md` and `LICENSE` were **generated** into it from the root copies, with `build.ps1` checking for drift. The flat layout made that unnecessary: there is one of each now, and they ship directly. `README.txt` went the same way — it duplicated `README.md` as plain text, and `README.md` ships.

## Testing and the quality gate

The client's embedded interpreter is not a standalone executable, so none of
this can run in game. Install stock Lua 5.1 and luacheck:

```bash
apt-get install lua5.1 lua-check      # Debian/Ubuntu, and what CI uses
```

On Windows, put `lua5.1.exe`, `luac5.1.exe` and `luacheck.exe` on PATH, set
`LUA51` / `LUAC51` / `LUACHECK`, or pass explicit paths to the scripts.

```powershell
.\run-tests.cmd                       # just the harnesses
python tools\run_tests.py             # same thing, no pause
python tools\check_lua_quality.py     # the full gate, as CI runs it
python tools\fault_inject.py          # prove the harnesses still have teeth
```

`check_lua_quality.py` is three gates in the order that fails cheapest first:

1. `luac5.1 -p` on every Lua file, including the harnesses and `.luacheckrc`.
2. Every harness in `tests/`, via `run_tests.py`.
3. `luacheck . --codes`, which must report **zero** warnings.

It refuses an interpreter that is not stock Lua 5.1. LuaJIT and 5.3/5.4 are
supersets of what the client provides, so a harness that passed under them
could still be relying on something that does not exist in game.

### The harnesses

`tests/wow.lua` is a deliberately small stand-in for the client: one generic
region type with the full method set, an event registry, and geometry that does
real arithmetic. UIParent is 800x600 at effective scale 1, and `SetPoint`
genuinely moves a frame, so a save/apply cycle can be repeated to check for
drift rather than only inspecting one call.

Harnesses load it first, then the addon's files against their own namespace
table:

```lua
local wow = assert(loadfile("tests/wow.lua"))()
local addon = {}
assert(loadfile("ForeverWindowMover.lua"))("ForeverWindowMover", addon)
wow.fire("ADDON_LOADED", "ForeverWindowMover")
```

Nothing is tested through a back door: the addon exposes `SavePosition` and
friends as file locals, so the harnesses drive the real entry points -- events,
the handle's drag scripts, the panel's `OnClick` and `OnUpdate` -- and assert on
`ForeverWindowMoverDB` and on where frames ended up. That also catches wiring
mistakes, not just arithmetic.

`syntax.lua` runs first because a parse error should fail in a second rather
than after everything else. It reads the module list from the TOC, so a file
added there is compile-checked automatically and a `.lua` at the root that the
TOC does not load is reported.

### Fault injection

`tools/fault_inject.py` re-introduces each fixed bug into a throwaway copy of
the checkout and requires a harness to notice. A suite that keeps passing on
broken code is not testing anything.

This is not theoretical. On its first run two mutations survived: both cases
covering the anchor-capture fix were asserting the right thing about the wrong
code path, so that fix had no real coverage. `tests/state.lua` cases 10 to 12
exist because of that run.

It also showed that single-line removals are often survivable *by design* --
Blizzard's anchors are captured at three separate points, so losing one is
covered by the others. Mutations therefore remove a capability rather than a
line, and a mutation whose pattern no longer matches is reported as a failure,
not skipped, because it has stopped guarding anything.

**This is deliberately not part of CI.** It runs the whole suite once per
mutation, so it costs roughly an order of magnitude more than the quality gate
for a result that only changes when the harnesses or the fixed bugs change --
which is not on every push. Run it when you touch `tests/`, when you change
any of the behaviour a mutation targets, and before a release. If you add it to
the workflow later, put it on `workflow_dispatch` or a schedule rather than on
every push.

## Bumping the version

```powershell
python tools\bump_version.py --patch --channel beta --dry-run
python tools\bump_version.py --patch --channel beta --changelog-stub
python tools\bump_version.py --channel release        # promote, same numbers
python tools\bump_version.py --minor                  # keep the current channel
```

The version is written in nine places. `build.ps1 -Check` gates four of them,
so missing one fails the build rather than shipping quietly — but finding out
from a failed release is a slow way to learn, and the documentation sites it
does not gate could go stale indefinitely.

`--major`, `--minor` and `--patch` roll the number; `--channel` sets the
suffix, where `release` means no suffix. Either can be used alone, so promoting
a beta to a release is `--channel release` with no roll. Omitting `--channel`
keeps whatever channel is in place.

### The channel decides what CurseForge publishes

The packager reads the file type from the **tag**, not from the TOC:

| Tag | CurseForge file type |
| --- | --- |
| contains `alpha` | Alpha |
| contains `beta` | Beta |
| anything else | Release |
| no tag at all | Alpha |

The match is a case-insensitive substring anywhere in the tag, and `alpha` is
checked first, so a tag containing both is an alpha. Verified against
`release.sh` by tagging a scratch copy three ways.

This tool keeps the suffix in the version itself as well as in the tag, so the
version shown in game matches the file people downloaded. `0.3.5-beta` in the
TOC, tagged `v0.3.5-beta`, published as a Beta file.

### What it will not do

- **It never blanket-replaces a version string.** Every site is an individually
  specified pattern. Release-note headings are matched against the version being
  *replaced*, and only on a re-channel, because on a numeric bump they describe
  the previous release.
- **It refuses a pattern that matches more than once.** Every site here is a
  single specific line, so a second match means the pattern is too loose. This
  guard exists because an earlier draft matched any `## <version>` heading and
  rewrote all eight historical changelog headings to the new number in one go.
- **It refuses a version whose tag already exists**, locally or on origin, since
  a published version cannot be reused. `--allow-existing-tag` overrides it.
- **It reports any remaining mention of the superseded version** that it did not
  rewrite, so a site it does not know about surfaces as a list rather than as
  silent staleness. Prose about an earlier release is expected in that list.
- **It does not commit, tag or push.** It prints the commands.

A numeric bump leaves the changelog alone, so `build.ps1 -Check` will fail until
you add a `## <version>` section. That is deliberate: the check is what stops a
release going out with no notes. `--changelog-stub` inserts an empty section if
you would rather fill it in afterwards.

The tool reads bytes without newline translation and preserves any BOM, so a
bump is byte-identical apart from the version. Its line-anchored patterns still
allow an optional `\r` even though [`.gitattributes`](#line-endings) now pins the
working tree to LF: that tolerance is what was missing when it silently skipped
the `.toc` and the Lua header, and keeping it costs nothing if someone checks
out with their own `core.autocrlf`.

## Line endings

`.gitattributes` pins the working tree, rather than leaving it to each
contributor's `core.autocrlf`. Text is LF, `*.cmd` and `*.bat` are CRLF because
`cmd.exe` is unreliable with LF-only scripts inside parenthesised blocks, and
`*.png`, `*.tga`, `*.blp` and `*.zip` are marked `binary` explicitly so no
newline conversion can ever be applied to the icon the client loads.

The index has always stored LF, so adding this changed no committed content —
`git add --renormalize .` staged nothing. It only made the checkout match. Two
concrete problems came from the mismatch:

- `tools/bump_version.py` used patterns ending in a bare `$`, which cannot match
  the end of a CRLF line, so it rewrote four of six version sites and skipped
  the `.toc` and the Lua header without saying so.
- `tools/build.ps1` copies the working tree into the local zip while CI builds
  from a Linux checkout. The two archives differed in line endings for the same
  commit. They are now byte-identical.

If you have a checkout from before this was added, renormalise it with:

```powershell
git rm --cached -r .
git reset --hard
```

That empties the index so every file is re-written through the new attributes.
`git checkout-index -a -f` is not enough; it leaves the existing files alone.

## CurseForge publishing

Releases are built and published by the [BigWigs packager](https://github.com/BigWigsMods/packager) from `.github/workflows/release.yml`. The whole flow is driven by pushing a tag:

```powershell
git tag -a v0.3.4 -m "Forever Window Mover 0.3.4"
git push origin v0.3.4
```

The workflow runs, in order: the Lua 5.1 install, the quality gate, `tools/build.ps1 -Check`, a packager build with `-d` so nothing uploads, `tools/check_package.py` against that build, the artifact upload, and finally -- **only on a tag** -- a second packager run with uploading enabled, which creates the GitHub release with `CHANGELOG.md` as the notes and publishes to CurseForge project **1737408** (from `## X-Curse-Project-ID` in the `.toc`).

Two deliberate choices in that order:

- **It builds on pushes to `main` and `develop` as well as on tags.** A tag-only workflow never runs its own release steps until a release is in flight, which is the worst moment to discover one of them is broken. Branch pushes do everything except publish.
- **Nothing is published that has not been checked.** The verification build uses `-d`, so the structure check runs against a real archive before any upload exists. A CurseForge file cannot be quietly withdrawn, which makes the extra few seconds of rebuilding worth it.

Publishing is gated by a plain `if: startsWith(github.ref, 'refs/tags/')` on that last step rather than by computing a flag into the packager's arguments. An empty string is falsy in GitHub expressions, so the obvious `${{ cond && '' || '-d' }}` is silently *always* `-d`: publishing would be disabled while the workflow looked correct.

Things that will bite you:

- **Tags must be annotated.** `git tag -a`, not `git tag`. The packager uses the tag to determine the version and will not find a lightweight one. `v0.3.1` is lightweight, which is why it predates this workflow.
- **`CF_API_TOKEN` must be set** as a repository secret, from [CurseForge's API tokens page](https://authors.curseforge.com/#/settings/api-tokens). `GH_API_TOKEN` is wired to the automatic `GITHUB_TOKEN` and needs nothing. `WOWI_API_TOKEN` and `WAGO_API_TOKEN` are optional; unset means that upload is skipped. Note the packager's own wiki still shows the deprecated `CF_API_KEY` and `GITHUB_OAUTH` names.
- **Keep the version literal in the `.toc`.** The packager can substitute `@project-version@` from the tag, but `build.ps1 -Check` gates on the `.toc` version matching the other sites, so the keyword would fail validation. Bump by hand and let `-Check` police it.
- Zip naming differs between the two paths: the packager uses the tag, so `v0.3.4` gives `ForeverWindowMover-v0.3.4.zip`, while `build.ps1` produces `ForeverWindowMover-0.3.4.zip` from the `.toc`. Harmless, but don't be surprised.
- Interface `16001` is the Forever (`camelot`) game type. The packager supports it natively — it appears in the packager's own interface examples and in `release.sh`'s TOC suffix list — so no `-g` override is needed.

`workflow_dispatch` is enabled so you can package a test build from the Actions tab without tagging. Untagged builds are marked alpha and are not uploaded to CurseForge.

## tools/build.ps1

```powershell
.\tools\build.ps1          # validate, write dist\ForeverWindowMover-x.y.z.zip
.\tools\build.ps1 -Check   # validate only; non-zero exit on any problem
.\tools\build.ps1 -SkipPackage
```

It is the validation gate CI runs before the packager, and a local zip builder for checking a package by hand. It checks what the packager does not:

1. Reads `## Version`, `## Interface`, `## IconTexture` and `## X-Curse-Project-ID` from the `.toc`, plus `addon.author` / `addon.website` from `ForeverWindowMover.lua`, via `Get-FwmMetadata`.
2. Checks the version in the core Lua header comment, `addon.version`, the `README.md` title, and that `CHANGELOG.md` has a `## <version>` section. **The `.toc` is authoritative.**
3. Checks the Interface number is quoted in `README.md` and `docs/README.md`.
4. Checks the `.toc` and the root agree on which `.lua` files exist.
5. Checks `.pkgmeta`'s `package-as` matches the addon name, and that nothing the addon needs is caught by an `ignore` rule.
6. Checks `## IconTexture` resolves to a file that exists, is not a PNG, and is actually in the package.
7. Regenerates the icon TGA if it is missing or older than the PNG.
8. Zips a staging copy into `dist/`, with the `ForeverWindowMover` folder at the root of the archive — the same shape the packager produces from `package-as`.

`-Check` makes it a usable pre-commit hook as well as the CI gate: it reports problems and exits 1 without writing.

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

Most of the behaviour above is now covered by `tests/`, so run
`python tools\check_lua_quality.py` first and use this list for what a harness
cannot reach: actual rendering, real client frames, and Titan Panel itself.

Packaging and tooling:

- [ ] `python tools\check_lua_quality.py` passes, including zero luacheck warnings.
- [ ] `python tools\fault_inject.py` reports every mutation caught.
- [ ] `.\tools\build.ps1 -Check` passes on a clean checkout.
- [ ] Bumping `## Version` in the `.toc` alone makes `-Check` fail, naming each site that disagrees.
- [ ] Adding a `.lua` file or the `.tga` to `.pkgmeta`'s `ignore` makes `-Check` fail.
- [ ] The addon shows its icon in the character-select AddOns list.
- [ ] The zip in `dist/` contains a `ForeverWindowMover` folder, no `.png`, no `docs/` or `tools/`, and loads when dropped into `Interface\AddOns\`.
- [ ] `.\tools\Sync-ToAddOns.ps1` reports `0 added, 0 updated, 0 removed` on a second consecutive run.
- [ ] A junk file dropped into the installed folder is removed by the next sync.

Release pipeline (first time, and after any workflow change):

- [ ] `CF_API_TOKEN` is set as a repository secret.
- [ ] Workflow permissions allow `contents: write`.
- [ ] A `workflow_dispatch` run from the Actions tab packages without errors.
- [ ] An annotated tag push produces a GitHub release with `CHANGELOG.md` as the notes and a zip attached.
- [ ] The file appears on CurseForge project 1737408, flagged for the right game version.

Titan / LDB:

- [ ] Without Titan or any LDB display installed, the addon loads with no errors and the options panel still works.
- [ ] With Titan, the launcher appears, left-click opens the options page, right-click toggles handles, and the label switches between `Window Mover` and `Mover: OFF`.
- [ ] Tooltip group lines match the actual enable/saved state.
- [ ] Enabling Titan *after* Forever Window Mover still produces the launcher.

Run with `/console scriptErrors 1`, or BugSack, so swallowed problems surface during testing.

## Release steps

1. Bump the version with `python tools\bump_version.py`, which rewrites all nine places it is written and picks the release channel. See [bumping the version](#bumping-the-version). Run it with `--dry-run` first.
2. Update `## Interface` if targeting a new client build, and the Interface number quoted in `README.md` and `docs/README.md`. `.\tools\build.ps1 -Check` covers these.
3. Add a "NEW IN x.y.z" section to `README.md`, and note whether the saved-position format changed. If nothing user-visible changed, say that rather than inventing something.
4. Add the release to `CHANGELOG.md` as a new `## x.y.z` section at the top. Group entries under Added / Changed / Fixed / Removed / Unchanged, and say explicitly when the `ForeverWindowMoverDB` format is unchanged. This file is published verbatim as the GitHub release notes and the CurseForge changelog, so write it for users.
5. Update these docs if behaviour, the group list, or the schema changed.
6. Run `python tools\check_lua_quality.py` and `.\tools\build.ps1 -Check`, then work through the manual checklist on a clean saved-variables file and on one carried over from the previous version. `.\tools\Sync-ToAddOns.ps1` installs the build for you.
7. Commit, then tag **annotated** and push the tag:

   ```powershell
   git tag -a vx.y.z -m "Forever Window Mover x.y.z"
   git push origin main vx.y.z
   ```

   The tag push triggers `.github/workflows/release.yml`, which validates, packages and publishes. A lightweight tag (`git tag` with no `-a`) will not work.
8. Check the Actions run, then confirm the file appeared on CurseForge and the GitHub release has the right notes attached.

The annotated tag also means the next release can be diffed against this one with `git diff vx.y.z..HEAD`.
