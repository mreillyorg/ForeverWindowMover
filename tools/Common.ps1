<#
.SYNOPSIS
    Shared helpers for the scripts in tools/. Dot-source it; it defines
    functions and variables only and does no work on its own.

.DESCRIPTION
    build.ps1 and Sync-ToAddOns.ps1 both need the addon name, the list of files
    that ship, the .toc fields and the metadata in the core Lua file. Keeping
    those in one place is the same reasoning as generating the in-package
    CHANGELOG: two hand-maintained copies drift.
#>

Set-StrictMode -Version Latest

# Files kept in the repository but never shipped: source art the client cannot
# read, and anything a packaging host would strip anyway. Both the zip and the
# AddOns sync use this list, so what you test is what you ship.
$FwmAddonName = 'ForeverWindowMover'
$FwmPackageExclusions = @('*.png', '*.psd', '*.xcf')

function Get-FwmRepoRoot {
    <#
    .SYNOPSIS
        Repository root, resolved from the tools directory.
    #>
    param([Parameter(Mandatory)][string] $ToolsDirectory)
    return (Resolve-Path -LiteralPath (Join-Path $ToolsDirectory '..')).Path
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

    $addonDirectory = Join-Path $RepoRoot $FwmAddonName
    $tocPath = Join-Path $addonDirectory "$FwmAddonName.toc"
    $coreLuaPath = Join-Path $addonDirectory "$FwmAddonName.lua"

    foreach ($required in @($addonDirectory, $tocPath, $coreLuaPath)) {
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
        AddonDirectory = (Resolve-Path -LiteralPath $addonDirectory).Path
        TocPath        = $tocPath
        TocLines       = $tocLines
        CoreLuaPath    = $coreLuaPath
        Version        = $version
        Interface      = $interface
        IconTexture    = Get-FwmTocField -TocLines $tocLines -Field 'IconTexture'
        Author         = if ($coreLua -match 'addon\.author\s*=\s*"([^"]+)"') { $Matches[1] } else { $null }
        Website        = if ($coreLua -match 'addon\.website\s*=\s*"([^"]+)"') { $Matches[1] } else { $null }
        Exclusions     = $FwmPackageExclusions
    }
}

function Get-FwmShippableFile {
    <#
    .SYNOPSIS
        The files that make up a release: everything in the addon folder except
        the package exclusions.
    #>
    param([Parameter(Mandatory)][string] $AddonDirectory)

    return Get-ChildItem -LiteralPath $AddonDirectory -File | Where-Object {
        $name = $_.Name
        -not ($FwmPackageExclusions | Where-Object { $name -like $_ })
    } | Sort-Object Name
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
