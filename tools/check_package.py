#!/usr/bin/env python3
"""Validate the built archive before it is published.

Run after BigWigsMods/packager or tools/build.ps1:

    python tools/check_package.py [output-dir]      default: .release

tools/build.ps1 -Check validates the *sources*: version strings, the TOC and
Lua agreeing, .pkgmeta's package-as, the icon. This script validates the
*artefact*, which nothing else looks at:

1. Structure -- exactly one top-level folder, named for the addon, no unsafe
   members, and no non-runtime content that an ignore rule should have removed.
2. Completeness -- every file the client needs actually shipped, derived from
   the TOC rather than from a list that could drift.
3. Fidelity -- the shipped TOC is the one in the repository, same version. A
   build that quietly repackaged an older TOC would otherwise look fine.

Addon behaviour is not checked here; the workflow runs the Lua quality gate
first.
"""
from pathlib import Path
import re
import sys
import zipfile

ROOT = Path(__file__).resolve().parent.parent
ADDON = 'ForeverWindowMover'

# Content that must never reach a user. Shipping tests/ would be the worst of
# these: the harnesses replace CreateFrame and friends with stubs.
FORBIDDEN_PARTS = ('tests', 'tools', 'docs', '.github', 'dist', '.release')
FORBIDDEN_SUFFIXES = ('.png', '.psd', '.xcf', '.py', '.ps1', '.cmd', '.yml', '.yaml')
FORBIDDEN_NAMES = ('.luacheckrc', '.pkgmeta', '.gitignore', '.gitattributes')


class PackageError(Exception):
    """A release-blocking problem with the archive."""


def fail(message):
    raise PackageError(message)


def check(condition, message):
    """Explicit raise rather than assert, so python -O cannot skip a release gate."""
    if not condition:
        raise PackageError(message)


def toc_version(text, label):
    match = re.search(r'^##\s*Version:\s*(\S+)', text, re.M)
    if not match:
        fail(f'{label} has no ## Version line')
    return match.group(1)


def expected_runtime():
    """Files the client must receive, derived from the TOC plus ## IconTexture."""
    text = (ROOT / f'{ADDON}.toc').read_text(encoding='utf-8-sig')
    required = {f'{ADDON}/{ADDON}.toc'}
    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith('## IconTexture:'):
            # Interface\AddOns\<addon>\<file> -> the leaf, which is what ships.
            leaf = line.split(':', 1)[1].strip().replace('\\', '/').rsplit('/', 1)[-1]
            if leaf:
                required.add(f'{ADDON}/{leaf}')
            continue
        if not line or line.startswith('#'):
            continue
        required.add(f'{ADDON}/{line}')
    return required


def check_archive(path, version):
    with zipfile.ZipFile(path) as arc:
        corrupt = arc.testzip()
        if corrupt:
            fail(f'corrupt {path.name}: first bad member {corrupt}')
        names = set(arc.namelist())
        files = {n for n in names if n and not n.endswith('/')}
        check(bool(files), f'{path.name} contains no files')

        # 1. Structure.
        top = {n.split('/', 1)[0] for n in files}
        if top != {ADDON}:
            fail(f'{path.name}: expected only "{ADDON}" at the top level, got {sorted(top)}. '
                 f'The zip must drop straight into Interface\\AddOns.')

        for member in files:
            if member.startswith('/') or '..' in Path(member).parts:
                fail(f'{path.name}: unsafe archive member {member}')
            parts = Path(member).parts
            for part in parts[1:]:
                if part in FORBIDDEN_PARTS:
                    fail(f'{path.name}: non-runtime content {member} '
                         f'(check the ignore list in .pkgmeta)')
            leaf = parts[-1]
            if leaf in FORBIDDEN_NAMES or leaf.endswith(FORBIDDEN_SUFFIXES):
                fail(f'{path.name}: {member} should not ship '
                     f'(check the ignore list in .pkgmeta)')

        # Flat addon: no subdirectories at all.
        nested = sorted(n for n in files if n.count('/') > 1)
        if nested:
            fail(f'{path.name}: unexpected subdirectories: {nested[:8]}')

        # 2. Completeness.
        missing = sorted(expected_runtime() - names)
        if missing:
            fail(f'{path.name} is missing runtime files: {", ".join(missing)}')

        # .pkgmeta declares a manual changelog, so it has to be in there.
        check(f'{ADDON}/CHANGELOG.md' in names,
              f'{path.name}: CHANGELOG.md missing, but .pkgmeta sets manual-changelog')

        # 3. Fidelity.
        shipped = toc_version(arc.read(f'{ADDON}/{ADDON}.toc').decode('utf-8-sig'),
                              f'{ADDON}.toc inside {path.name}')
        if shipped != version:
            fail(f'{path.name} ships version {shipped}, the repository says {version}')

    print(f'PASS: {path.name} -- {len(files)} files, version {version}, '
          f'{ADDON}/ at the archive root')


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / '.release'
    if not out.is_absolute():
        out = ROOT / out

    version = toc_version((ROOT / f'{ADDON}.toc').read_text(encoding='utf-8-sig'),
                          f'{ADDON}.toc')
    print(f'Repository version: {version}')
    print(f'Looking for archives in: {out}')

    if not out.is_dir():
        fail(f'{out} does not exist. Build first with BigWigsMods/packager or '
             f'tools/build.ps1.')
    archives = sorted(out.glob('*.zip'))
    if not archives:
        fail(f'no *.zip found in {out}. Build first.')

    for path in archives:
        check_archive(path, version)
    print(f'\nChecked {len(archives)} archive(s): PASS')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, PackageError, zipfile.BadZipFile) as exc:
        print(f'ERROR: {exc}', file=sys.stderr)
        sys.exit(1)
