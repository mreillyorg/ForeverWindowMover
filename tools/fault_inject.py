#!/usr/bin/env python3
"""Re-introduce each fixed bug and assert a harness still catches it.

    python tools/fault_inject.py
    python tools/fault_inject.py --lua /usr/bin/lua5.1

A suite that keeps passing once the code is broken is not testing anything.
This mutates a throwaway copy of the checkout -- never the working tree -- and
requires every mutation below to make at least one harness fail.

It earned its place: the first run found two cases in tests/state.lua that
asserted the right thing about the wrong code path, so the anchor-capture fix
was not actually covered. Two faults were silently survivable.

A mutation whose pattern no longer matches is reported as a failure rather than
skipped, because a mutation that cannot apply is a mutation that is no longer
guarding anything.

Note that single-site removals are often survivable by design: the addon
captures Blizzard's anchors at three points, so losing one is covered by the
others. Mutations here therefore remove a capability, not just a line.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent

# (label, file, find, replace, harness expected to notice)
MUTATIONS = [
    ('scale conversion dropped on apply (the 0.3.2 jump and drift bug)',
     'ForeverWindowMover.lua',
     'frame:SetPoint("CENTER", UIParent, "CENTER", saved.x / ratio, saved.y / ratio)',
     'frame:SetPoint("CENTER", UIParent, "CENTER", saved.x, saved.y)',
     'tests/positions.lua'),

    ('drag wired back to OnMouseUp (a release off the handle is lost)',
     'ForeverWindowMover.lua',
     'handle:SetScript("OnDragStop", FinishMove)',
     'handle:SetScript("OnMouseUp", FinishMove)',
     'tests/positions.lua'),

    ('no anchor snapshot at OnShow at all (Reset restores the addon position)',
     'ForeverWindowMover.lua',
     '''        CaptureOriginalPoints(name, frame)
        -- As with 0.1.0, defer until after Blizzard's panel manager runs.
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                CaptureOriginalPoints(name, frame)
                ApplyPosition(name, groupKey)
            end)''',
     '''        -- As with 0.1.0, defer until after Blizzard's panel manager runs.
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                ApplyPosition(name, groupKey)
            end)''',
     'tests/state.lua'),

    ('movedByAddon guard removed (the addon anchor recorded as the original)',
     'ForeverWindowMover.lua',
     'if originalPoints[name] or movedByAddon[name] then return end',
     'if originalPoints[name] then return end',
     'tests/state.lua'),

    ('handle no longer flips inside the frame near the screen top',
     'ForeverWindowMover.lua',
     'local inside = top and screenTop and (top * ScaleRatio(frame) + height) > screenTop',
     'local inside = false',
     'tests/handles.lua'),

    ('flip uses a fixed height, ignoring the selected style',
     'ForeverWindowMover.lua',
     'local height = info.styleHeight or 20',
     'local height = 20',
     'tests/styles.lua'),

    ('title-bar strip no longer inset from the close button',
     'ForeverWindowMover.lua',
     'titlebar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -TITLEBAR_RIGHT_INSET, 0)',
     'titlebar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)',
     'tests/styles.lua'),

    ('title-bar strip raised above the window, swallowing real buttons',
     'ForeverWindowMover.lua',
     'titlebar:SetFrameLevel(frame:GetFrameLevel())',
     'titlebar:SetFrameLevel(frame:GetFrameLevel() + 12)',
     'tests/styles.lua'),

    ('the title-bar toggle ignored, so the strip is always live',
     'ForeverWindowMover.lua',
     'if live and addon.TitlebarEnabled() then',
     'if live then',
     'tests/styles.lua'),

    ('an unknown style name no longer falls back to dark',
     'ForeverWindowMover.lua',
     '''    if name == "custom" or addon.handleStyles[name] then return name end
    return "dark"''',
     '''    return name or "dark"''',
     'tests/styles.lua'),

    ('custom style no longer validates what is on disk',
     'ForeverWindowMover.lua',
     "        style[key] = (type(value) == \"number\" and value > 0) and value or DEFAULT_CUSTOM[key]",
     "        style[key] = value or DEFAULT_CUSTOM[key]",
     'tests/styles.lua'),

    ('SetCustomStyle accepts any type',
     'ForeverWindowMover.lua',
     'if type(value) ~= allowed[field] then return false end',
     'if allowed[field] == nil then return false end',
     'tests/styles.lua'),

    ('per-group checkboxes no longer combat gated',
     'Options.lua',
     'row.check:SetEnabled(canChange)',
     '',
     'tests/options.lua'),

    ('the nothing-draggable warning never shown',
     'Options.lua',
     '''        warning:SetText(addon.NothingDraggable()
            and "Nothing is draggable: switch on the tab, the title bar, or both."
            or "")''',
     '        warning:SetText("")',
     'tests/handlepage.lua'),

    ('style checkboxes stop behaving as a radio group',
     'Options.lua',
     'check:SetChecked(name == selected)',
     'check:SetChecked(true)',
     'tests/handlepage.lua'),

    ('the colour picker result is discarded',
     'Options.lua',
     '''            local opened = ShowColourPicker(current, function(r, g, b, a)
                addon.SetCustomStyle(field, {r, g, b, a})
                RunRefreshers()
            end)''',
     '''            local opened = ShowColourPicker(current, function()
                RunRefreshers()
            end)''',
     'tests/handlepage.lua'),

    ('picker alpha ignored, so every custom colour is opaque',
     'Options.lua',
     'if ok and type(nr) == "number" then apply(nr, ng, nb, currentAlpha()) end',
     'if ok and type(nr) == "number" then apply(nr, ng, nb, 1) end',
     'tests/handlepage.lua'),

    ('cancelling the colour picker keeps the discarded colour',
     'Options.lua',
     '''    local function onCancel()
        apply(r, g, b, a)
    end''',
     '''    local function onCancel()
    end''',
     'tests/handlepage.lua'),

    ('size steppers no longer clamped, so a zero-width tab is reachable',
     'Options.lua',
     '''                if value < minimum then value = minimum end
                if value > maximum then value = maximum end''',
     '',
     'tests/handlepage.lua'),

    ('the Handles page never registered, so the settings are unreachable',
     'Options.lua',
     '''    if not addon.handlePanel then
        addon.handlePanel = BuildHandlePage()
    end''',
     '',
     'tests/handlepage.lua'),

    ('subcategory failure no longer falls back to a top-level entry',
     'Options.lua',
     '''    if not nested then
        local ok, standalone = pcall(Settings.RegisterCanvasLayoutCategory,
            addon.handlePanel, "Forever Window Mover: handles")
        if ok and standalone then
            pcall(Settings.RegisterAddOnCategory, standalone)
            addon.handleCategory = standalone
        end
    end''',
     '',
     'tests/handlepage.lua'),

    ('OpenOptions back to accepting only numeric category ids',
     'Options.lua',
     'if not ok or (type(id) ~= "number" and type(id) ~= "string") then return false end',
     'if not ok or type(id) ~= "number" then return false end',
     'tests/options.lua'),

    ('launcher never refreshed after saved variables load',
     'ForeverWindowMover.lua',
     'RefreshBroker() -- LDB may have registered before SavedVariables were loaded.',
     '',
     'tests/broker.lua'),

    ('a group key duplicated',
     'ForeverWindowMover.lua',
     '{ key = "trade",       label = "Player trades",       frames = {"TradeFrame"} },',
     '{ key = "vendor",      label = "Player trades",       frames = {"TradeFrame"} },',
     'tests/groups.lua'),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--lua', default=os.environ.get('LUA51'),
                        help='Interpreter passed through to tools/run_tests.py')
    args = parser.parse_args()

    runner_args = ['--quiet']
    if args.lua:
        runner_args = ['--lua', args.lua] + runner_args

    # Sanity-check first: if the suite does not pass on the real code, nothing
    # below means anything.
    print('Baseline: running the suite against unmodified sources')
    baseline = subprocess.run([sys.executable, str(ROOT / 'tools' / 'run_tests.py')] + runner_args,
                              cwd=ROOT, capture_output=True, text=True)
    if baseline.returncode != 0:
        print(baseline.stdout + baseline.stderr, file=sys.stderr)
        print('ERROR: the suite already fails without any mutation.', file=sys.stderr)
        return 2
    print('Baseline: PASS\n')

    failures = []
    with tempfile.TemporaryDirectory(prefix='fwm-mutate-') as tmp:
        for label, filename, find, replace, expected in MUTATIONS:
            work = Path(tmp) / 'work'
            if work.exists():
                shutil.rmtree(work)
            # The .git directory is large and irrelevant to the harnesses.
            shutil.copytree(ROOT, work,
                            ignore=shutil.ignore_patterns('.git', '.release', 'dist'))

            target = work / filename
            text = target.read_text(encoding='utf-8')
            if find not in text:
                print(f'[STALE] {label}')
                print(f'        pattern no longer present in {filename}; this mutation '
                      f'guards nothing and needs updating')
                failures.append((label, 'pattern not found'))
                continue
            target.write_text(text.replace(find, replace, 1), encoding='utf-8')

            result = subprocess.run(
                [sys.executable, 'tools/run_tests.py'] + runner_args,
                cwd=work, capture_output=True, text=True)

            if result.returncode == 0:
                print(f'[SURVIVED] {label}')
                print(f'           mutated {filename} and the suite still passed')
                failures.append((label, 'suite passed on broken code'))
                continue

            caught = [line.strip() for line in (result.stdout + result.stderr).splitlines()
                      if line.strip().startswith('tests/') and '(exit' in line]
            names = ' '.join(caught) or '(unnamed)'
            note = '' if expected in names else f'  [expected {expected}]'
            print(f'[CAUGHT] {label}')
            print(f'         by: {names}{note}')

    print('\n' + '=' * 70)
    if failures:
        print(f'{len(failures)} of {len(MUTATIONS)} mutation(s) not caught:')
        for label, why in failures:
            print(f'  - {label}: {why}')
        return 1
    print(f'All {len(MUTATIONS)} injected faults were caught by the harnesses.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
