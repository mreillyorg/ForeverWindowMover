<#
.SYNOPSIS
    Shared helpers for the scripts in tools/. Dot-source it; it defines
    functions and variables only and does no work on its own.

.DESCRIPTION
    build.ps1 and Sync-ToAddOns.ps1 both need to know the addon name, which
    files ship, the .toc fields and the metadata in the core Lua file. Keeping
    those in one place is the same reasoning as reading the ignore list from
    .pkgmeta: two hand-maintained copies drift.

    The addon's files live at the repository root, which is where the BigWigs
    packager looks for <package-as>.toc, so "what ships" is defined by
    subtraction -- every root file except those .pkgmeta ignores.
#>

Set-StrictMode -Version Latest

$FwmAddonName = 'ForeverWindowMover'

function Get-FwmRepoRoot {
    <#
    .SYNOPSIS
        Repository root, resolved from the tools directory.
    #>
    param([Parameter(Mandatory)][string] $ToolsDirectory)
    return (Resolve-Path -LiteralPath (Join-Path $ToolsDirectory '..')).Path
}

function Get-FwmPackageIgnore {
    <#
    .SYNOPSIS
        The ignore list from .pkgmeta.

    .DESCRIPTION
        .pkgmeta is the single source of truth for what does not ship, so the
        local zip and a CurseForge upload cannot disagree. This reads just the
        flat "ignore:" sequence rather than pulling in a YAML parser -- that is
        the only key the local tooling needs, and the file is ours.

        Throws if the key is missing, because silently shipping docs/ and
        tools/ would be worse than failing.
    #>
    param([Parameter(Mandatory)][string] $RepoRoot)

    $pkgmetaPath = Join-Path $RepoRoot '.pkgmeta'
    if (-not (Test-Path -LiteralPath $pkgmetaPath)) {
        throw "No .pkgmeta at $pkgmetaPath. It defines what ships; the tooling will not guess."
    }

    $ignore = [System.Collections.Generic.List[string]]::new()
    $inIgnore = $false
    foreach ($line in (Get-Content -LiteralPath $pkgmetaPath)) {
        # Comments and blank lines never end a block.
        if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }

        if ($line -match '^ignore\s*:') { $inIgnore = $true; continue }
        # Any other top-level key ends the ignore block.
        if ($line -match '^\S') { $inIgnore = $false; continue }

        if ($inIgnore -and $line -match '^\s*-\s*(.+?)\s*$') {
            # Strip the quotes YAML needs around a leading '*'.
            $ignore.Add($Matches[1].Trim('"', "'"))
        }
    }

    if ($ignore.Count -eq 0) {
        throw "No 'ignore:' entries found in $pkgmetaPath."
    }
    return $ignore.ToArray()
}

function Get-FwmShippableFile {
    <#
    .SYNOPSIS
        The files that make up a release.

    .DESCRIPTION
        Root files only. The addon is flat, so no subdirectory ships, and
        anything matching a .pkgmeta ignore entry or beginning with a period is
        excluded -- the packager always ignores dot files, so we match that.
    #>
    param([Parameter(Mandatory)][string] $RepoRoot)

    $ignore = Get-FwmPackageIgnore -RepoRoot $RepoRoot

    return Get-ChildItem -LiteralPath $RepoRoot -File | Where-Object {
        $name = $_.Name
        if ($name.StartsWith('.')) { return $false }
        -not ($ignore | Where-Object { $name -like $_ })
    } | Sort-Object Name
}

function Get-FwmTocField {
    <#
    .SYNOPSIS
        Reads a '## Field: value' line from .toc content.
    #>
    param(
        # .toc files contain blank separator lines, so empty elements and an
        # empty collection both have to be allowed through.
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]] $TocLines,

        [Parameter(Mandatory)][string] $Field
    )
    foreach ($line in $TocLines) {
        if ($line -match "^##\s*$Field\s*:\s*(.+?)\s*$") { return $Matches[1] }
    }
    return $null
}

function Get-FwmMetadata {
    <#
    .SYNOPSIS
        Collects paths and version metadata for the addon in $RepoRoot.

    .DESCRIPTION
        The .toc is the single source of truth for the version and Interface
        number. Author and website come from the core Lua file, which is where
        the addon itself reads them from.
    #>
    param([Parameter(Mandatory)][string] $RepoRoot)

    $tocPath = Join-Path $RepoRoot "$FwmAddonName.toc"
    $coreLuaPath = Join-Path $RepoRoot "$FwmAddonName.lua"

    foreach ($required in @($tocPath, $coreLuaPath)) {
        if (-not (Test-Path -LiteralPath $required)) { throw "Required path not found: $required" }
    }

    $tocLines = @(Get-Content -LiteralPath $tocPath)
    $coreLua = Get-Content -LiteralPath $coreLuaPath -Raw

    $version = Get-FwmTocField -TocLines $tocLines -Field 'Version'
    $interface = Get-FwmTocField -TocLines $tocLines -Field 'Interface'
    if (-not $version) { throw "No '## Version:' line in $tocPath" }
    if (-not $interface) { throw "No '## Interface:' line in $tocPath" }

    return [pscustomobject]@{
        RepoRoot       = $RepoRoot
        AddonName      = $FwmAddonName
        TocPath        = $tocPath
        TocLines       = $tocLines
        CoreLuaPath    = $coreLuaPath
        Version        = $version
        Interface      = $interface
        IconTexture    = Get-FwmTocField -TocLines $tocLines -Field 'IconTexture'
        CurseProjectId = Get-FwmTocField -TocLines $tocLines -Field 'X-Curse-Project-ID'
        WowiId         = Get-FwmTocField -TocLines $tocLines -Field 'X-WoWI-ID'
        WagoId         = Get-FwmTocField -TocLines $tocLines -Field 'X-Wago-ID'
        Author         = if ($coreLua -match 'addon\.author\s*=\s*"([^"]+)"') { $Matches[1] } else { $null }
        Website        = if ($coreLua -match 'addon\.website\s*=\s*"([^"]+)"') { $Matches[1] } else { $null }
    }
}

function Get-FwmPkgmetaField {
    <#
    .SYNOPSIS
        Reads a single top-level scalar key from .pkgmeta, e.g. package-as.
    #>
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)][string] $Field
    )
    $pkgmetaPath = Join-Path $RepoRoot '.pkgmeta'
    if (-not (Test-Path -LiteralPath $pkgmetaPath)) { return $null }
    foreach ($line in (Get-Content -LiteralPath $pkgmetaPath)) {
        if ($line -match "^$([regex]::Escape($Field))\s*:\s*(.+?)\s*$") { return $Matches[1].Trim('"', "'") }
    }
    return $null
}

function Find-FwmAddOnsDirectory {
    <#
    .SYNOPSIS
        Locates candidate Interface\AddOns directories.

    .DESCRIPTION
        Checked in order, stopping at the first source that yields anything:

          1. $env:WOW_ADDONS_PATH
          2. Walking up from the repository, which covers a checkout living
             anywhere inside the WoW tree.
          3. The default install locations, for a checkout outside it.

        Returns every match rather than guessing, so a caller that finds more
        than one can ask for -AddOnsPath instead of picking the wrong flavour.
    #>
    param([Parameter(Mandatory)][string] $RepoRoot)

    $candidates = [System.Collections.Generic.List[string]]::new()
    $addCandidate = {
        param([string] $Path)
        if (-not $Path) { return }
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
        $full = (Resolve-Path -LiteralPath $Path).Path
        if (-not ($candidates | Where-Object { $_ -ieq $full })) { $candidates.Add($full) }
    }

    & $addCandidate $env:WOW_ADDONS_PATH

    if ($candidates.Count -eq 0) {
        $directory = Get-Item -LiteralPath $RepoRoot
        while ($directory) {
            & $addCandidate (Join-Path $directory.FullName 'AddOns')
            & $addCandidate (Join-Path $directory.FullName 'Interface\AddOns')
            $directory = $directory.Parent
        }
    }

    if ($candidates.Count -eq 0) {
        $roots = @("${env:ProgramFiles(x86)}\World of Warcraft", "$env:ProgramFiles\World of Warcraft")
        $flavours = @('_classic_beta_', '_classic_era_', '_classic_', '_retail_', '_ptr_', '_xptr_', '_beta_')
        foreach ($root in $roots) {
            foreach ($flavour in $flavours) {
                & $addCandidate (Join-Path $root "$flavour\Interface\AddOns")
            }
        }
    }

    return $candidates.ToArray()
}

function Assert-FwmSafeTargetPath {
    <#
    .SYNOPSIS
        Refuses to operate on anything but <something>\AddOns\<AddonName>.

    .DESCRIPTION
        The sync tool deletes stale files inside its target, and that target
        lives in a game install. This is the guard that keeps a bad -AddOnsPath
        from pointing the delete at, say, the AddOns directory itself.
    #>
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $AddonName
    )

    $leaf = Split-Path -Leaf $Path
    $parentLeaf = Split-Path -Leaf (Split-Path -Parent $Path)
    if ($leaf -ine $AddonName) {
        throw "Refusing to operate on '$Path': the folder must be named '$AddonName'."
    }
    if ($parentLeaf -ine 'AddOns') {
        throw "Refusing to operate on '$Path': its parent must be an 'AddOns' directory."
    }
}

function Test-FwmClientRunning {
    <#
    .SYNOPSIS
        True when a WoW client process is running.
    #>
    $names = @('Wow', 'WowClassic', 'WowT', 'WowB', 'WowFullScreen')
    return [bool](Get-Process -Name $names -ErrorAction SilentlyContinue)
}
