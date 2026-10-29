#!/usr/bin/env python3
"""Run every offline Lua harness for Forever Window Mover.

From the repository root:  python tools/run_tests.py
Pick an interpreter:       python tools/run_tests.py --lua C:\\path\\to\\lua5.1.exe

Harnesses are discovered from tests/ rather than from a hand-maintained list, so
a new one is picked up automatically. Each runs with the repository root as its
working directory, because the addon's Lua files and the TOC live there and the
harnesses open them by relative path.

Exit status is 0 only if every harness exits 0.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
TESTS = ROOT / 'tests'

# The WoW client embeds Lua 5.1, so that is the only fully supported dialect.
# LuaJIT is a 5.1 superset and is accepted with a warning. Names are tried in
# order; plain 'lua' is last because on many systems it is 5.3/5.4, which
# diverges from the client in ways a harness could come to depend on.
CANDIDATES = ('lua5.1', 'lua5.1.exe', 'lua51.exe', 'luajit', 'luajit.exe', 'lua', 'lua.exe')

# Checked only if nothing suitable is on PATH.
FALLBACKS = (
    Path('/usr/bin/lua5.1'),
    Path(os.path.expanduser('~')) / 'tools' / 'lua-5.1.5' / 'lua5.1.exe',
)

# wow.lua is the shared client stub, loaded by the harnesses. It is not a
# harness itself and exits 0 doing nothing, which would look like a silent pass.
NOT_A_HARNESS = {'wow.lua'}


def probe(candidate):
    """Return (resolved_path, banner) if candidate is a usable Lua, else (None, reason)."""
    resolved = shutil.which(candidate) or (candidate if Path(candidate).is_file() else None)
    if not resolved:
        return None, 'not found'
    try:
        result = subprocess.run([resolved, '-v'], capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError) as exc:
        return None, f'could not execute ({exc})'
    lines = ((result.stdout or '') + (result.stderr or '')).strip().splitlines()
    banner = lines[0] if lines else ''
    if 'Lua 5.1' in banner or 'LuaJIT' in banner:
        return resolved, banner
    return None, f'reports "{banner or "no version banner"}", not Lua 5.1'


def find_lua(explicit=None):
    """Return (path, banner). Raises RuntimeError if nothing usable is found.

    An explicitly requested interpreter is never silently replaced: if --lua or
    $LUA51 names something unusable that is an error, because quietly testing
    against a different dialect than the one asked for is a wrong answer.
    """
    if explicit:
        resolved, info = probe(explicit)
        if resolved:
            return resolved, info
        raise RuntimeError(
            f'Requested interpreter is not usable: {explicit} -- {info}.\n'
            'The WoW client embeds Lua 5.1; 5.2 and later diverge from it.')

    tried = []
    for candidate in list(CANDIDATES) + [str(p) for p in FALLBACKS]:
        resolved, info = probe(candidate)
        if resolved:
            return resolved, info
        tried.append(f'{candidate} ({info})')
    raise RuntimeError(
        'No Lua 5.1 interpreter found. Tried:\n  ' + '\n  '.join(tried) +
        '\nSet LUA51, pass --lua, or put lua5.1 on PATH. On Debian or Ubuntu: '
        'apt-get install lua5.1')


def harnesses():
    """Every tests/*.lua, syntax.lua first so a parse error fails fast."""
    if not TESTS.is_dir():
        return []
    files = [p for p in TESTS.glob('*.lua') if p.name not in NOT_A_HARNESS]
    return sorted(files, key=lambda p: (p.name != 'syntax.lua', p.name))


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--lua', default=os.environ.get('LUA51'),
                        help='Interpreter to use. Defaults to $LUA51, then PATH, then known installs.')
    parser.add_argument('--quiet', action='store_true', help='Only print failures and the summary.')
    args = parser.parse_args()

    try:
        lua, banner = find_lua(args.lua)
    except RuntimeError as exc:
        print(exc, file=sys.stderr)
        return 2

    print(f'Interpreter: {lua}')
    print(f'Reported:    {banner}')
    if 'LuaJIT' in banner:
        print('WARNING: LuaJIT is a 5.1 superset. Harnesses must not rely on ffi, bit, jit or goto.')

    found = harnesses()
    if not found:
        print(f'No harnesses found in {TESTS}.', file=sys.stderr)
        return 2
    print(f'Harnesses:   {len(found)}\n')

    failures = []
    for path in found:
        rel = path.relative_to(ROOT).as_posix()
        result = subprocess.run([lua, rel], cwd=ROOT, capture_output=True, text=True)
        output = ((result.stdout or '') + (result.stderr or '')).strip()
        ok = result.returncode == 0
        if not ok:
            failures.append((rel, result.returncode))
        if not args.quiet or not ok:
            print(f'[{"PASS" if ok else "FAIL"}] {rel}')
            for line in output.splitlines():
                print('        ' + line)

    print('\n' + '=' * 60)
    print(f'PASSED: {len(found) - len(failures)}   FAILED: {len(failures)}   TOTAL: {len(found)}')
    if failures:
        print('\nFailed harnesses:')
        for rel, code in failures:
            print(f'  {rel} (exit {code})')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
