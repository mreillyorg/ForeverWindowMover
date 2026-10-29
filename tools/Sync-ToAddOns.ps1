<#
.SYNOPSIS
    Installs the addon into Interface\AddOns for local testing.

.DESCRIPTION
    Copies the files that ship -- the ignore list in .pkgmeta decides which --
    into <AddOns>\ForeverWindowMover. Because the shipping list comes from the
    same place the BigWigs packager reads, what you load in the client is what
    CurseForge will serve. Files left behind by an older install are deleted
    rather than allowed to shadow the new ones.

    Unless you pass -SkipBuild it runs tools/build.ps1 -Check first, so a
    version mismatch or a stale icon stops the sync instead of being tested.

    The AddOns directory is found automatically: $env:WOW_ADDONS_PATH, then by
    walking up from the repository (which covers a checkout inside the WoW
    tree), then the default install locations. Pass -AddOnsPath to override. If
    more than one candidate turns up, the script stops and lists them rather
    than guessing a flavour.

    Only <AddOns>\ForeverWindowMover is ever touched, and the path is checked
    against that shape before anything is written or deleted.

    There is deliberately no junction mode. The addon's files now live at the
    repository root, so linking the repo into Interface\AddOns would put .git,
    docs/ and tools/ inside the game install. Use -Watch instead; it copies on
    every save.

.PARAMETER Watch
    Re-sync whenever a file at the repository root changes. Runs until Ctrl+C,
    so start it in your own terminal rather than from an agent or a build step.

.PARAMETER Remove
    Delete the installed folder and exit.

.PARAMETER SkipBuild
    Do not validate first. Faster, but a stale icon or version will be synced.

.EXAMPLE
    .\tools\Sync-ToAddOns.ps1
    Validate, then mirror the shipping files into Interface\AddOns.

.EXAMPLE
    .\tools\Sync-ToAddOns.ps1 -WhatIf
    Show what would be copied or deleted without touching anything.

.EXAMPLE
    .\tools\Sync-ToAddOns.ps1 -Watch -SkipBuild
    Copy on every save while you iterate. /reload in the client to pick changes up.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $AddOnsPath,
    [switch] $Watch,
    [switch] $Remove,
    [switch] $SkipBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Common.ps1')

$repoRoot = Get-FwmRepoRoot -ToolsDirectory $PSScriptRoot
$meta = Get-FwmMetadata -RepoRoot $repoRoot

# --- resolve the target -------------------------------------------------------

if ($AddOnsPath) {
    if (-not (Test-Path -LiteralPath $AddOnsPath -PathType Container)) {
        throw "-AddOnsPath does not exist or is not a directory: $AddOnsPath"
    }
    $addOnsDirectory = (Resolve-Path -LiteralPath $AddOnsPath).Path
}
else {
    $found = @(Find-FwmAddOnsDirectory -RepoRoot $repoRoot)
    if ($found.Count -eq 0) {
        throw "Could not find an Interface\AddOns directory. Pass -AddOnsPath, or set `$env:WOW_ADDONS_PATH."
    }
    if ($found.Count -gt 1) {
        $list = ($found | ForEach-Object { "  $_" }) -join "`n"
        throw "Found more than one AddOns directory; pass -AddOnsPath to choose one:`n$list"
    }
    $addOnsDirectory = $found[0]
}

$target = Join-Path $addOnsDirectory $meta.AddonName
# Everything below writes to or deletes from $target, so validate its shape.
Assert-FwmSafeTargetPath -Path $target -AddonName $meta.AddonName

function Test-TargetIsJunction {
    if (-not (Test-Path -LiteralPath $target)) { return $false }
    return [bool]((Get-Item -LiteralPath $target -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint)
}

Write-Host "$($meta.AddonName) $($meta.Version) (Interface $($meta.Interface))"
Write-Host "  source  $repoRoot"
Write-Host "  target  $target"

# --- remove -------------------------------------------------------------------

if ($Remove) {
    if (-not (Test-Path -LiteralPath $target)) {
        Write-Host '  nothing installed'
        exit 0
    }
    $isJunction = Test-TargetIsJunction
    $what = if ($isJunction) { 'junction' } else { 'folder' }
    if ($PSCmdlet.ShouldProcess($target, "Remove the installed $what")) {
        if ($isJunction) {
            # Deletes the link only. Be explicit so a future refactor cannot
            # quietly start recursing into whatever it points at.
            [System.IO.Directory]::Delete($target)
        }
        else {
            Remove-Item -LiteralPath $target -Recurse -Force
        }
        Write-Host "  removed the installed $what"
    }
    exit 0
}

# --- validate -----------------------------------------------------------------

if (-not $SkipBuild) {
    Write-Host '  --- build.ps1 -Check ---'
    $global:LASTEXITCODE = 0
    & (Join-Path $PSScriptRoot 'build.ps1') -Check
    if ($LASTEXITCODE -ne 0) {
        throw 'build.ps1 -Check reported problems; nothing was synced. Fix them, or re-run with -SkipBuild.'
    }
    Write-Host '  -----------------------'
}

if (Test-FwmClientRunning) {
    Write-Warning 'A WoW client is running. Lua changes need /reload; .toc and metadata changes need a full client restart.'
}

# A junction left over from an older version of this script would make the copy
# write into the repository itself.
if (Test-TargetIsJunction) {
    throw "$target is a junction, probably from an earlier version of this script. Run with -Remove first; junction mode is no longer supported now that the addon lives at the repository root."
}

# --- sync ---------------------------------------------------------------------

# Mirrors the shipping files and deletes anything else in the target. Returns a
# summary so -Watch can print one line per pass.
function Sync-Once {
    $added = 0; $updated = 0; $removed = 0; $same = 0

    if (-not (Test-Path -LiteralPath $target)) {
        if ($PSCmdlet.ShouldProcess($target, 'Create the addon folder')) {
            New-Item -ItemType Directory -Path $target -Force | Out-Null
        }
    }

    $sourceFiles = @(Get-FwmShippableFile -RepoRoot $repoRoot)
    if ($sourceFiles.Count -eq 0) { throw "No files to sync from $repoRoot" }

    foreach ($file in $sourceFiles) {
        $destination = Join-Path $target $file.Name
        $existing = if (Test-Path -LiteralPath $destination) { Get-Item -LiteralPath $destination } else { $null }

        if ($null -eq $existing) {
            if ($PSCmdlet.ShouldProcess($destination, 'Copy new file')) {
                Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
            }
            Write-Host "    + $($file.Name)"
            $added++
            continue
        }

        # Length plus write time is enough here: these are small text files
        # edited in place, not content-addressed artefacts.
        if ($existing.Length -ne $file.Length -or $existing.LastWriteTimeUtc -ne $file.LastWriteTimeUtc) {
            if ($PSCmdlet.ShouldProcess($destination, 'Overwrite changed file')) {
                Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
            }
            Write-Host "    ~ $($file.Name)"
            $updated++
        }
        else {
            $same++
        }
    }

    if (-not (Test-Path -LiteralPath $target)) {
        # Only reachable under -WhatIf, where the folder was never created.
        return [pscustomobject]@{ Added = $added; Updated = $updated; Removed = $removed; Unchanged = $same }
    }

    # Stale cleanup: files a previous version installed, and anything .pkgmeta
    # now ignores. Subdirectories are removed too -- the addon is flat, so one
    # being there means it is left over.
    $expected = $sourceFiles | ForEach-Object { $_.Name }
    foreach ($entry in Get-ChildItem -LiteralPath $target -Force) {
        if ($entry.PSIsContainer -or $expected -notcontains $entry.Name) {
            if ($PSCmdlet.ShouldProcess($entry.FullName, 'Remove stale entry')) {
                Remove-Item -LiteralPath $entry.FullName -Recurse -Force
            }
            Write-Host "    - $($entry.Name)"
            $removed++
        }
    }

    return [pscustomobject]@{ Added = $added; Updated = $updated; Removed = $removed; Unchanged = $same }
}

$result = Sync-Once
Write-Host ("  {0} added, {1} updated, {2} removed, {3} unchanged" -f
    $result.Added, $result.Updated, $result.Removed, $result.Unchanged)

if (-not $Watch) { exit 0 }

# --- watch mode ---------------------------------------------------------------

Write-Host ''
Write-Host "Watching $repoRoot -- Ctrl+C to stop."
Write-Host 'Remember to /reload in the client after each sync.'

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $repoRoot
# Root level only: that is where the addon's files are, and it keeps writes to
# dist/, docs/ and tools/ from triggering a sync.
$watcher.IncludeSubdirectories = $false
$watcher.NotifyFilter = [System.IO.NotifyFilters]::LastWrite -bor
    [System.IO.NotifyFilters]::FileName -bor
    [System.IO.NotifyFilters]::Size
try {
    $watcher.EnableRaisingEvents = $true
    while ($true) {
        # Editors write a file in several operations, so wait for the burst to
        # settle rather than syncing a half-written file.
        $change = $watcher.WaitForChanged([System.IO.WatcherChangeTypes]::All, 1000)
        if ($change.TimedOut) { continue }
        do {
            $followUp = $watcher.WaitForChanged([System.IO.WatcherChangeTypes]::All, 400)
        } while (-not $followUp.TimedOut)

        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $($change.Name) changed"
        try {
            $pass = Sync-Once
            Write-Host ("  {0} added, {1} updated, {2} removed, {3} unchanged" -f
                $pass.Added, $pass.Updated, $pass.Removed, $pass.Unchanged)
        }
        catch {
            Write-Warning "Sync failed: $($_.Exception.Message)"
        }
    }
}
finally {
    $watcher.EnableRaisingEvents = $false
    $watcher.Dispose()
}
