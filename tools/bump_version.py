#!/usr/bin/env python3
"""Bump the Forever Window Mover version everywhere it is written.

    python tools/bump_version.py --patch --channel beta    # 0.3.4 -> 0.3.5-beta
    python tools/bump_version.py --minor                   # 0.3.4 -> 0.4.0
    python tools/bump_version.py --channel release         # 0.3.5-beta -> 0.3.5
    python tools/bump_version.py --patch --dry-run

The channel decides what CurseForge publishes the file as, because the packager
reads it from the TAG, not from the TOC:

    tag contains "alpha"  ->  Alpha file
    tag contains "beta"   ->  Beta file
    anything else         ->  Release file
    no tag at all         ->  Alpha file

Verified against release.sh by tagging a scratch copy three ways; see
docs/development.md. Keeping the suffix in the version itself, not only in the
tag, means the version shown in game matches the file people downloaded.

Why this exists. The version is written in seven places. `tools/build.ps1
-Check` gates four of them, so missing one fails the build rather than shipping
quietly -- but finding out from a failed release is a slow way to learn, and the
docs sites it does not gate could go stale indefinitely.

Three behaviours matter as much as the rewriting:

1. It only rewrites known, individually specified sites. It never
   blanket-replaces a version string, because historical changelog headings and
   prose about earlier releases must keep the numbers they describe.
2. It reports any *other* mention of the superseded version it did not rewrite,
   so a site this tool does not know about surfaces as a visible list instead of
   as silent staleness.
3. It refuses to produce a version whose tag already exists, locally or on
   origin. A published version cannot be reused.

It does not commit, tag, or push. It prints the commands.
"""
import argparse
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
ADDON = 'ForeverWindowMover'
TITLE = 'Forever Window Mover'
CHANNEL_SUFFIX = {'alpha': 'alpha', 'beta': 'beta', 'release': None}

# A version as it appears in text. Deliberately narrow -- three numeric
# components and an optional alphabetic channel -- so it cannot swallow an
# Interface number like 16001 or a date.
VERSION = r'\d+\.\d+\.\d+(?:-[A-Za-z][A-Za-z0-9]*)?'

_KEEP = object()  # "--channel not given": keep whatever channel is in place


class BumpError(Exception):
    """A problem that must stop the bump before anything is written."""


class Version:
    def __init__(self, major, minor, patch, channel):
        self.major, self.minor, self.patch, self.channel = major, minor, patch, channel

    @classmethod
    def parse(cls, text, label):
        match = re.fullmatch(r'(\d+)\.(\d+)\.(\d+)(?:-([A-Za-z][A-Za-z0-9]*))?', text)
        if not match:
            raise BumpError(f'{label}: cannot parse version {text!r}')
        return cls(int(match.group(1)), int(match.group(2)), int(match.group(3)),
                   match.group(4))

    def bumped(self, part, channel):
        """A major bump resets minor and patch; a minor bump resets patch."""
        major, minor, patch = self.major, self.minor, self.patch
        if part == 'major':
            major, minor, patch = major + 1, 0, 0
        elif part == 'minor':
            minor, patch = minor + 1, 0
        elif part == 'patch':
            patch += 1
        return Version(major, minor, patch,
                       self.channel if channel is _KEEP else channel)

    @property
    def numeric(self):
        return f'{self.major}.{self.minor}.{self.patch}'

    def __str__(self):
        return f'{self.numeric}-{self.channel}' if self.channel else self.numeric


def read_text(path):
    """Read without newline translation, reporting whether a BOM was present, so
    a file is written back byte-identical apart from the version. The repository
    uses LF and a TOC may carry a BOM; both have to survive a bump."""
    raw = path.read_bytes()
    bom = raw.startswith(b'\xef\xbb\xbf')
    return (raw[3:] if bom else raw).decode('utf-8'), bom


def write_text(path, text, bom):
    path.write_bytes((b'\xef\xbb\xbf' if bom else b'') + text.encode('utf-8'))


def version_sites():
    """Every place the version is stated as the CURRENT version.

    Each pattern captures it in a group named `ver`; nothing else in the match is
    touched. The first four are what tools/build.ps1 -Check gates on.
    """
    # Trailing anchors allow an optional \r. The working tree may be CRLF --
    # git's autocrlf converts on checkout -- and read_text deliberately does no
    # newline translation, so a bare `$` would never match the end of a line.
    # Getting this wrong silently skipped the .toc and the Lua header, which is
    # exactly the kind of half-bump this tool exists to prevent.
    return [
        (f'{ADDON}.toc', rf'(?m)^## Version:[ \t]*(?P<ver>{VERSION})[ \t]*\r?$'),
        # Line 1 of the core file, spelled with spaces.
        (f'{ADDON}.lua', rf'(?m)^--[ \t]*{TITLE}[ \t]+(?P<ver>{VERSION})[ \t]*\r?$'),
        (f'{ADDON}.lua', rf'addon\.version\s*=\s*"(?P<ver>{VERSION})"'),
        # The title line only, anchored to the start of the file, so the
        # "NEW IN x" headings further down keep the versions they describe.
        ('README.md', rf'\A\#[^\n]*?(?P<ver>{VERSION})'),
        ('docs/README.md', rf'\*\*{TITLE}\*\*[ \t]+(?P<ver>{VERSION})'),
        ('docs/api-reference.md',
         rf'\|[ \t]*`addon\.version`[^|]*\|[^|]*\|[ \t]*`"(?P<ver>{VERSION})"`'),
        # Worked examples in the release guide. A reader may copy-paste these,
        # and left alone they are reported as leftovers on every single bump,
        # which trains you to ignore the one report that matters. The `vx.y.z`
        # placeholders elsewhere in that file are not numeric and never match.
        ('docs/development.md', rf'(?m)^\s*git tag -a v(?P<ver>{VERSION})'),
        ('docs/development.md', rf'(?m)^\s*git push origin (?:main )?v(?P<ver>{VERSION})'),
        ('docs/development.md', rf'-m "{TITLE} (?P<ver>{VERSION})"'),
    ]


def release_note_headings(current):
    """Headings that label one release, matched against the version being replaced.

    Rewritten ONLY on a re-channel -- same numbers, new label -- because then it
    is the same release changing its name. On a numeric bump they describe the
    previous release and must be left alone; a new heading is the author's job,
    and build.ps1 -Check will insist on the changelog one.

    `current` is baked into the pattern deliberately. Matching any `## <version>`
    heading instead rewrote all eight historical changelog headings to the new
    version on the first test run, destroying the release history in one go.
    These patterns must be able to match exactly one heading and no other.
    """
    old = re.escape(str(current))
    return [
        ('CHANGELOG.md', rf'(?m)^##[ \t]+(?P<ver>{old})[ \t]*\r?$'),
        ('README.md', rf'(?m)^##[ \t]+NEW IN[ \t]+(?P<ver>{old})\b'),
    ]


# Files scanned for mentions of a superseded version that were not rewritten.
SCANNED = ('README.md', 'CHANGELOG.md', f'{ADDON}.toc', f'{ADDON}.lua',
           'Options.lua', 'TitanBroker.lua', '.pkgmeta',
           'docs/README.md', 'docs/api-reference.md', 'docs/architecture.md',
           'docs/development.md', 'docs/saved-variables.md',
           'docs/supported-windows.md', 'docs/titan-panel-integration.md',
           'docs/user-guide.md')


def git(*arguments, timeout=30):
    try:
        result = subprocess.run(('git',) + arguments, cwd=ROOT, capture_output=True,
                                text=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError):
        return None
    return result.stdout.strip() if result.returncode == 0 else None


def current_version():
    text, _ = read_text(ROOT / f'{ADDON}.toc')
    match = re.search(rf'(?m)^## Version:[ \t]*(?P<ver>{VERSION})', text)
    if not match:
        raise BumpError(f'{ADDON}.toc has no parsable ## Version line')
    return Version.parse(match.group('ver'), f'{ADDON}.toc')


def existing_tags():
    """Local tags plus whatever origin advertises.

    An unreachable remote is not fatal -- offline is a normal state -- but it is
    reported, because the collision check is weaker then.
    """
    tags = set()
    local = git('tag', '--list')
    if local:
        tags.update(line.strip() for line in local.splitlines() if line.strip())
    remote = git('ls-remote', '--tags', 'origin')
    if remote is None:
        return tags, False
    for line in remote.splitlines():
        _, _, ref = line.partition('refs/tags/')
        ref = ref.strip()
        if ref and not ref.endswith('^{}'):
            tags.add(ref)
    return tags, True


def report_repository():
    """Print repository state before anything is rewritten.

    Cheap, and it puts the two things that have gone wrong in this repository in
    front of you: a tag that already existed, and a bump prepared against a
    commit that was not the one being released.
    """
    print('Repository:')
    print(f'  HEAD     {git("log", "-1", "--format=%h %s") or "(no commits)"}')
    print(f'  branch   {git("rev-parse", "--abbrev-ref", "HEAD") or "(unknown)"}')

    ahead = 0
    counts = git('rev-list', '--left-right', '--count', '@{u}...HEAD')
    if counts:
        behind, ahead = (int(part) for part in counts.split())
        state = 'in sync with upstream'
        if ahead or behind:
            state = f'{ahead} ahead, {behind} behind upstream'
        print(f'  upstream {state}')
    else:
        print('  upstream (none configured)')

    status = (git('status', '--porcelain') or '').splitlines()
    staged = {line[3:] for line in status if line[:1] not in (' ', '?', '')}
    unstaged = {line[3:] for line in status if line[1:2] == 'M'}
    print(f'  pending  {len(staged)} staged, {len(unstaged)} unstaged')
    tags = git('tag', '--list')
    print(f'  tags     {", ".join(tags.splitlines()) if tags else "(none)"}')
    return {'pending': staged | unstaged, 'ahead': ahead}


def warn_about_pending(pending, targets):
    """A bump landing on top of an in-flight edit to the same file leaves two
    unrelated changesets tangled together. Worth naming, not blocking."""
    overlap = sorted(p for p in pending if p.replace('\\', '/') in targets)
    if overlap:
        print('\nWARNING: these files already have uncommitted changes and the bump '
              'will rewrite them:')
        for path in overlap:
            print(f'  {path}')
        print('  Consider committing or stashing first, so the bump is a reviewable '
              'change on its own.')


def apply_edits(replacements, dry_run):
    """replacements: {relative path: [(pattern, replacement for the `ver` group)]}"""
    changed, touched = [], 0
    for relative, rules in sorted(replacements.items()):
        path = ROOT / relative
        if not path.is_file():
            print(f'NOTE: {relative} not found, skipped')
            continue
        text, bom = read_text(path)
        original = text
        for pattern, new in rules:
            def swap(match, new=new):
                start, end = match.span('ver')
                whole = match.group(0)
                offset = match.start()
                return whole[:start - offset] + new + whole[end - offset:]
            text, count = re.subn(pattern, swap, text)
            if count > 1:
                # Every site in this repository is a single, specific line. A
                # pattern that matches more than once is too loose, and the
                # damage is silent: a heading pattern that matched any version
                # rather than the one being replaced rewrote eight years of
                # changelog headings to the new number before this guard existed.
                raise BumpError(
                    f'{relative}: pattern matched {count} places, expected 1.\n'
                    f'  pattern: {pattern}\n'
                    f'  Refusing to rewrite: a pattern this loose will damage '
                    f'history. Tighten it, or split it into one pattern per site.')
            if count:
                changed.append(f'  {relative}: {new}')
        if text != original:
            touched += 1
            if not dry_run:
                write_text(path, text, bom)
    return changed, touched


def leftovers(superseded):
    """Remaining mentions of the version this run replaced, excluding headings,
    which legitimately keep the number of the release they describe."""
    found = []
    for relative in SCANNED:
        path = ROOT / relative
        if not path.is_file():
            continue
        text, _ = read_text(path)
        for number, line in enumerate(text.splitlines(), 1):
            if superseded in line and not re.match(r'\s*#{1,6}\s', line):
                found.append(f'  {relative}:{number}: {line.strip()[:92]}')
    return found


def changelog_stub(version):
    """Insert an empty section so build.ps1 -Check passes, for the author to fill."""
    path = ROOT / 'CHANGELOG.md'
    text, bom = read_text(path)
    anchor = re.search(r'(?m)^##[ \t]+\d', text)
    if not anchor:
        raise BumpError('CHANGELOG.md has no existing "## x.y.z" section to insert before')
    stub = (f'## {version}\n\n'
            'TODO: describe this release. Group entries under Added / Changed / Fixed / '
            'Removed / Unchanged, and say explicitly when the `ForeverWindowMoverDB` '
            'format is unchanged.\n\n')
    write_text(path, text[:anchor.start()] + stub + text[anchor.start():], bom)
    print(f'  CHANGELOG.md: inserted an empty "## {version}" section to fill in')


def main():
    parser = argparse.ArgumentParser(
        description='Bump the Forever Window Mover version everywhere it is written.',
        formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    part = parser.add_mutually_exclusive_group()
    part.add_argument('--major', action='store_const', const='major', dest='part',
                      help='bump major, resetting minor and patch to 0')
    part.add_argument('--minor', action='store_const', const='minor', dest='part',
                      help='bump minor, resetting patch to 0')
    part.add_argument('--patch', action='store_const', const='patch', dest='part',
                      help='bump patch')
    parser.add_argument('--channel', choices=sorted(CHANNEL_SUFFIX),
                        help='alpha, beta, or release for no suffix. Decides what '
                             'CurseForge publishes the file as. Omit to keep the '
                             'current channel')
    parser.add_argument('--changelog-stub', action='store_true',
                        help='insert an empty CHANGELOG.md section for the new version, '
                             'so tools/build.ps1 -Check passes before you write it')
    parser.add_argument('--dry-run', action='store_true',
                        help='report what would change without writing')
    parser.add_argument('--allow-existing-tag', action='store_true',
                        help='proceed even if the resulting tag already exists')
    args = parser.parse_args()

    if not args.part and not args.channel:
        parser.error('nothing to do: pass --major, --minor or --patch, and/or --channel')

    state = report_repository()

    channel = _KEEP if args.channel is None else CHANNEL_SUFFIX[args.channel]
    current = current_version()
    target = current.bumped(args.part, channel)
    print(f'\nVersion: {current}  ->  {target}')

    if str(current) == str(target):
        print('Nothing would change.')
        return 0

    file_type = ('alpha' if target.channel == 'alpha'
                 else 'beta' if target.channel == 'beta' else 'release')
    tag = f'v{target}'
    print(f'Tag:     {tag}')
    print(f'Publishes to CurseForge as: {file_type.upper()}')
    if file_type == 'release':
        print('  A Release file is the default download for everyone. Use --channel beta '
              'first if you want it opt-in.')

    tags, reached_remote = existing_tags()
    if not reached_remote:
        print('\nNOTE: could not reach origin; tag collision checked against local '
              'tags only.')
    if tag in tags:
        where = 'locally or on origin' if reached_remote else 'locally'
        message = (f'tag {tag} already exists {where}. A published version cannot be '
                   f'reused; bump further')
        if not args.allow_existing_tag:
            raise BumpError(message)
        print(f'\nWARNING: {message} (continuing, --allow-existing-tag given)')
    else:
        print(f'Tag {tag} is free.')

    replacements = {}
    for relative, pattern in version_sites():
        replacements.setdefault(relative, []).append((pattern, str(target)))

    # Re-channel only: the same release changing its label, so its headings move
    # with it. On a numeric bump they describe the previous release.
    rechannel = current.numeric == target.numeric
    if rechannel:
        for relative, pattern in release_note_headings(current):
            replacements.setdefault(relative, []).append((pattern, str(target)))
        print('\nSame numbers, new channel: the CHANGELOG and "NEW IN" headings will be '
              'relabelled too.')

    warn_about_pending(state['pending'], set(replacements))

    changed, touched = apply_edits(replacements, args.dry_run)
    print(f'\n{"Would rewrite" if args.dry_run else "Rewrote"} '
          f'{len(changed)} site(s) across {touched} file(s):')
    print('\n'.join(changed) if changed else '  (none -- check the patterns)')
    if not changed:
        raise BumpError('no site matched; refusing to report success')

    if args.changelog_stub and not rechannel:
        if args.dry_run:
            print(f'  CHANGELOG.md: would insert an empty "## {target}" section')
        else:
            changelog_stub(target)

    if not args.dry_run:
        remaining = leftovers(str(current))
        if remaining:
            print(f'\nStill mentioning {current}. Prose about an earlier release belongs '
                  'here; anything else is a site this tool does not know about:')
            print('\n'.join(remaining))

    print('\nNot committed, not tagged.')
    if not rechannel and not args.changelog_stub:
        print(f'\nNEXT, AND REQUIRED: add a "## {target}" section to CHANGELOG.md and a '
              f'"## NEW IN {target}" section to README.md.')
        print('  tools/build.ps1 -Check fails until the changelog section exists, so '
              'this is not optional.')
    print('\nThen:')
    print('  python tools/check_lua_quality.py')
    print('  ./tools/build.ps1 -Check')
    if state['ahead']:
        print(f'\nWARNING: HEAD is {state["ahead"]} commit(s) ahead of upstream. A tag on '
              'an unpushed commit will not build in GitHub Actions; push first.')
    print(f'  git tag -a {tag} -m "{TITLE} {target}"')
    print(f'  git push origin HEAD {tag}')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except BumpError as error:
        print(f'ERROR: {error}', file=sys.stderr)
        sys.exit(1)
