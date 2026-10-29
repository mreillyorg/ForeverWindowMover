#!/usr/bin/env python3
"""Run strict Lua 5.1 syntax, harness, and luacheck gates.

Usage: python tools/check_lua_quality.py
       python tools/check_lua_quality.py --lua C:\\tools\\lua5.1.exe --luac C:\\tools\\luac5.1.exe --luacheck C:\\tools\\luacheck.exe

Three gates, in the order that fails cheapest first:

1. Every Lua file compiles under stock Lua 5.1 (luac -p).
2. Every offline harness in tests/ passes (tools/run_tests.py).
3. luacheck reports zero warnings against .luacheckrc.

All three tools must be installed locally; the client's embedded interpreter is
not a standalone executable and cannot run any of this. On Debian or Ubuntu:

    apt-get install lua5.1 lua-check

The interpreter is checked to be stock Lua 5.1, not LuaJIT and not 5.3/5.4.
Both are supersets of what the client provides, so passing under them would let
the addon or a harness come to depend on something the client does not have.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def resolve(explicit, candidates, label):
    """Resolve a user-selected tool, or probe common executable names."""
    names = [explicit] if explicit else candidates
    for name in names:
        candidate = shutil.which(name)
        if not candidate and Path(name).is_file():
            candidate = str(Path(name).resolve())
        if candidate:
            return candidate
    print(f'ERROR: {label} executable not found.', file=sys.stderr)
    if explicit:
        print(f'  Requested: {explicit}', file=sys.stderr)
    else:
        print('  Tried: ' + ', '.join(names), file=sys.stderr)
    print('  Install stock Lua 5.1, its matching luac compiler, and luacheck.', file=sys.stderr)
    print('  Debian/Ubuntu: apt-get install lua5.1 lua-check', file=sys.stderr)
    print('  Or pass explicit paths: python tools/check_lua_quality.py '
          '--lua "C:\\tools\\lua51\\lua.exe" --luac "C:\\tools\\lua51\\luac.exe" '
          '--luacheck "C:\\tools\\luacheck\\luacheck.exe"', file=sys.stderr)
    return None


def banner_for(exe):
    try:
        result = subprocess.run([exe, '-v'], text=True, capture_output=True, timeout=20)
    except (OSError, subprocess.SubprocessError) as exc:
        print(f'ERROR: Cannot execute {exe}: {exc}', file=sys.stderr)
        return None
    return (result.stdout or '') + (result.stderr or '')


def run(command, cwd=ROOT):
    print('+', ' '.join(map(str, command)), flush=True)
    try:
        return subprocess.run(list(map(str, command)), cwd=cwd, check=False).returncode
    except OSError as exc:
        print(f'ERROR: Failed to execute {command[0]}: {exc}', file=sys.stderr)
        return 2


def sources():
    """Shipped Lua at the repository root, plus the harnesses and the lint config.

    .luacheckrc is included deliberately: it is Lua, it is written so a plain
    interpreter can load it, and a typo there otherwise surfaces as a confusing
    luacheck failure instead of a syntax error.
    """
    found = sorted(ROOT.glob('*.lua'))
    found += sorted((ROOT / 'tests').glob('*.lua'))
    rc = ROOT / '.luacheckrc'
    if rc.is_file():
        found.append(rc)
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--lua', default=os.environ.get('LUA51'),
                        help='Path to stock Lua 5.1 interpreter')
    parser.add_argument('--luac', default=os.environ.get('LUAC51'),
                        help='Path to the matching Lua 5.1 compiler')
    parser.add_argument('--luacheck', default=os.environ.get('LUACHECK'),
                        help='Path to luacheck')
    args = parser.parse_args()

    lua = resolve(args.lua, ['lua5.1', 'lua5.1.exe', 'lua51.exe', 'lua.exe'], 'Lua 5.1')
    luac = resolve(args.luac, ['luac5.1', 'luac5.1.exe', 'luac51.exe', 'luac.exe'], 'luac 5.1')
    luacheck = resolve(args.luacheck, ['luacheck', 'luacheck.exe'], 'luacheck')
    if not all((lua, luac, luacheck)):
        return 2

    lua_banner = banner_for(lua)
    compiler_banner = banner_for(luac)
    if lua_banner is None or compiler_banner is None:
        return 2
    if 'Lua 5.1' not in lua_banner or 'LuaJIT' in lua_banner:
        print(f'ERROR: Expected stock Lua 5.1, got: {lua_banner.strip()}', file=sys.stderr)
        return 2
    if 'Lua 5.1' not in compiler_banner:
        print(f'ERROR: Expected a Lua 5.1 compiler, got: {compiler_banner.strip()}', file=sys.stderr)
        return 2

    print('Lua interpreter:', lua, flush=True)
    print('Lua compiler:   ', luac, flush=True)
    print('Luacheck:       ', luacheck, flush=True)

    files = sources()
    if not files:
        print('ERROR: No Lua sources found', file=sys.stderr)
        return 2
    print(f'\nParsing {len(files)} Lua files with Lua 5.1', flush=True)
    for source in files:
        if run([luac, '-p', source]):
            return 1

    if run([sys.executable, ROOT / 'tools' / 'run_tests.py', '--lua', lua]):
        return 1

    # --codes prints the warning id next to each finding, which is what you need
    # to decide between fixing it and justifying an exception in .luacheckrc.
    if run([luacheck, '.', '--codes']):
        return 1

    print('\nLua 5.1 syntax, harnesses, and luacheck: PASS')
    return 0


if __name__ == '__main__':
    sys.exit(main())
