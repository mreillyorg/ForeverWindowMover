<#
.SYNOPSIS
    Syncs the ForeverWindowMover folder into Interface\AddOns for local testing.

.DESCRIPTION
    Mirrors exactly the files that ship -- the package exclusions in
    tools/Common.ps1 apply here too -- so what you test in the client is what
    goes in the zip. Stale files left over from an older install are removed.

    By default it runs tools/build.ps1 -SkipPackage first, so the generated
    in-package CHANGELOG, LICENSE and icon TGA are current before the copy.

    The AddOns directory is found automatically: $env:WOW_ADDONS_PATH, then by
    walking up from the repository (which covers a checkout inside the WoW
    tree), then the default install locations. Pass -AddOnsPath to override. If
    more than one candidate turns up, the script stops and lists them instead
    of guessing a flavour.

    Only <AddOns>\ForeverWindowMover is ever touched, and the path is checked
    against that shape before anything is written or deleted.

.PARAMETER Mode
    Copy (default)  Mirror the shipping files into the AddOns folder.
    Junction        Point the AddOns folder at the repository instead, so edits
                    need no re-sync. The client then also sees the files that
                    do not ship, including the multi-megabyte source PNG.
                    Replacing an existing real folder needs -Force.

.PARAMETER Watch
    Re-sync whenever a file in the addon folder changes. Runs until Ctrl+C, so
    start it in your own terminal rather than from an agent or a build step.

.PARAMETER Remove
    Delete the synced folder or junction and exit.

.PARAMETER SkipBuild
    Do not run build.ps1 first. Faster, but the generated files may be stale.

.PARAMETER Force
    Allow replacing a real directory with a junction.

.EXAMPLE
    .\tools\Sync-ToAddOns.ps1
    Regenerate, then mirror into the detected AddOns directory.

.EXAMPLE
    .\tools\Sync-ToAddOns.ps1 -WhatIf
    Show what would be copied or deleted without touching anything.

.EXAMPLE
    .\tools\Sync-ToAddOns.ps1 -Watch -SkipBuild
    Copy on every save while you iterate. /reload in the client to pick changes up.

.EXAMPLE
    .\tools\Sync-ToAddOns.ps1 -Mode Junction -Force
    Replace the installed folder with a junction to the repository.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $AddOnsPath,
    [ValidateSet('Copy', 'Junction')]
    [string] $Mode = 'Copy',
    [switch] $Watch,
    [switch] $Remove,
    [switch] $SkipBuild,
    [switch] $Force
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
Write-Host "  source  $($meta.AddonDirectory)"
Write-Host "  target  $target"

# --- remove -------------------------------------------------------------------

if ($Remove) {
    if (-not (Test-Path -LiteralPath $target)) {
        Write-Host '  nothing installed'
        exit 0
    }
    $what = if (Test-TargetIsJunction) { 'junction' } else { 'folder' }
    if ($PSCmdlet.ShouldProcess($target, "Remove the installed $what")) {
        # Remove-Item on a junction deletes the link, not the contents, but be
        # explicit about it so a future refactor cannot quietly recurse into
        # the repository.
        if ($what -eq 'junction') {
            [System.IO.Directory]::Delete($target)
        }
        else {
            Remove-Item -LiteralPath $target -Recurse -Force
        }
        Write-Host "  removed the installed $what"
    }
    exit 0
}

# --- regenerate ---------------------------------------------------------------

if (-not $SkipBuild) {
    Write-Host '  --- build.ps1 -SkipPackage ---'
    $global:LASTEXITCODE = 0
    & (Join-Path $PSScriptRoot 'build.ps1') -SkipPackage
    if ($LASTEXITCODE -ne 0) {
        throw 'build.ps1 reported problems; nothing was synced. Fix them, or re-run with -SkipBuild.'
    }
    Write-Host '  ------------------------------'
}

if (Test-FwmClientRunning) {
    Write-Warning 'A WoW client is running. Lua changes need /reload; .toc and metadata changes need a full client restart.'
}

# --- junction mode ------------------------------------------------------------

if ($Mode -eq 'Junction') {
    if (Test-TargetIsJunction) {
        $existing = (Get-Item -LiteralPath $target -Force).LinkTarget
        if ($existing -ieq $meta.AddonDirectory) {
            Write-Host '  junction already points at the repository; nothing to do'
            exit 0
        }
        if ($PSCmdlet.ShouldProcess($target, "Repoint the junction at $($meta.AddonDirectory)")) {
            [System.IO.Directory]::Delete($target)
        }
    }
    elseif (Test-Path -LiteralPath $target) {
        if (-not $Force) {
            throw "$target is a real directory. Re-run with -Force to replace it with a junction, or use -Mode Copy."
        }
        if ($PSCmdlet.ShouldProcess($target, 'Delete the installed folder and replace it with a junction')) {
            Remove-Item -LiteralPath $target -Recurse -Force
        }
    }

    if ($PSCmdlet.ShouldProcess($target, "Create a junction to $($meta.AddonDirectory)")) {
        New-Item -ItemType Junction -Path $target -Target $meta.AddonDirectory | Out-Null
        Write-Host "  junction -> $($meta.AddonDirectory)"
        Write-Host '  note: the client now also sees files that do not ship, including the source PNG'
    }
    exit 0
}

# --- copy mode ----------------------------------------------------------------

if (Test-TargetIsJunction) {
    throw "$target is a junction. Edits are already live; use -Mode Junction, or -Remove first to switch to Copy."
}

# Mirrors the shipping files and deletes anything else in the target. Returns a
# summary so -Watch can print one line per pass.
function Sync-Once {
    $added = 0; $updated = 0; $removed = 0; $same = 0

    if (-not (Test-Path -LiteralPath $target)) {
        if ($PSCmdlet.ShouldProcess($target, 'Create the addon folder')) {
            New-Item -ItemType Directory -Path $target -Force | Out-Null
        }
    }

    $sourceFiles = @(Get-FwmShippableFile -AddonDirectory $meta.AddonDirectory)
    if ($sourceFiles.Count -eq 0) { throw "No files to sync from $($meta.AddonDirectory)" }

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

    # Stale cleanup: files a previous version installed, and anything the
    # exclusion list now keeps out. Subdirectories are removed too -- the addon
    # is flat, so one being there means it is left over.
    if (-not (Test-Path -LiteralPath $target)) {
        # Only reachable under -WhatIf, where the folder was never created.
        return [pscustomobject]@{ Added = $added; Updated = $updated; Removed = $removed; Unchanged = $same }
    }
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
Write-Host "Watching $($meta.AddonDirectory) -- Ctrl+C to stop."
Write-Host 'Remember to /reload in the client after each sync.'

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $meta.AddonDirectory
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
