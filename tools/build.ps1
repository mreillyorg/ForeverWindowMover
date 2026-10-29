<#
.SYNOPSIS
    Validates the release and builds a local zip matching what CurseForge gets.

.DESCRIPTION
    Release packaging and publishing are done by the BigWigs packager from
    .github/workflows/release.yml when an annotated tag is pushed. This script
    is the validation gate that runs before it, and a local zip builder for
    testing the package by hand.

    It checks what the packager does not:

      - Every place the version is written agrees with the .toc ## Version,
        which is authoritative.
      - The Interface number is quoted consistently in the user-facing text.
      - The .toc and the working tree agree on which .lua files exist.
      - ## IconTexture resolves to a file that is present and is not a PNG,
        which the client cannot read.
      - .pkgmeta exists, its package-as matches the .toc name, and it does not
        ignore a file the addon needs.

    The set of files that ship comes from the .pkgmeta ignore list via
    Get-FwmShippableFile, so this zip and a CurseForge upload cannot disagree
    about their contents.

.PARAMETER Check
    Verify only, write nothing, exit non-zero on any problem. This is what CI
    runs before handing over to the packager, and it works as a pre-commit
    hook.

.PARAMETER SkipPackage
    Validate but do not build the zip.

.PARAMETER OutputDirectory
    Where the zip is written. Defaults to dist/ at the repository root.

.EXAMPLE
    .\tools\build.ps1
    Validate and write dist/ForeverWindowMover-x.y.z.zip.

.EXAMPLE
    .\tools\build.ps1 -Check
    Fail if any version string, the icon, or .pkgmeta is out of sync.
#>
[CmdletBinding()]
param(
    [switch] $Check,
    [switch] $SkipPackage,
    [string] $OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Common.ps1')

$repoRoot = Get-FwmRepoRoot -ToolsDirectory $PSScriptRoot
$addonName = $FwmAddonName
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repoRoot 'dist' }

$problems = [System.Collections.Generic.List[string]]::new()
$changes = [System.Collections.Generic.List[string]]::new()

function Add-Problem([string] $message) { $problems.Add($message) }
function Add-Change([string] $message) { $changes.Add($message) }

function Get-TextOrNull([string] $path) {
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    return Get-Content -LiteralPath $path -Raw
}

function Get-Relative([string] $path) {
    return $path.Substring($repoRoot.Length).TrimStart('\', '/')
}

# --- metadata -----------------------------------------------------------------

$meta = Get-FwmMetadata -RepoRoot $repoRoot
$version = $meta.Version
$interface = $meta.Interface

if (-not $meta.Author) { Add-Problem "Could not read addon.author from $addonName.lua" }
if (-not $meta.Website) { Add-Problem "Could not read addon.website from $addonName.lua" }

$curseId = $meta.CurseProjectId
Write-Host "$addonName $version (Interface $interface)"
if ($curseId) {
    Write-Host "  CurseForge project $curseId"
}
else {
    Write-Host '  no ## X-Curse-Project-ID in the .toc; CurseForge upload will be skipped'
}

# --- version and interface consistency ----------------------------------------

# Every place the version is written out, per the release steps in
# docs/development.md. The .toc is the single source of truth.
$versionSites = @(
    @{ Path = $meta.CoreLuaPath;                 Pattern = "^--\s*Forever Window Mover\s+$([regex]::Escape($version))\s*$"; What = 'header comment' }
    @{ Path = $meta.CoreLuaPath;                 Pattern = "addon\.version\s*=\s*""$([regex]::Escape($version))"""         ; What = 'addon.version' }
    @{ Path = (Join-Path $repoRoot 'README.md'); Pattern = "^#\s*$addonName\s+$([regex]::Escape($version))\s*$"            ; What = 'title' }
    @{ Path = (Join-Path $repoRoot 'CHANGELOG.md'); Pattern = "^##\s*$([regex]::Escape($version))\s*$"                     ; What = 'release section' }
)
foreach ($site in $versionSites) {
    $text = Get-TextOrNull $site.Path
    if ($null -eq $text) {
        Add-Problem "$(Get-Relative $site.Path) is missing."
        continue
    }
    if ($text -notmatch "(?m)$($site.Pattern)") {
        Add-Problem "$(Get-Relative $site.Path) $($site.What) does not state version $version."
    }
}

# The Interface number is quoted in the user-facing text as well.
foreach ($path in @((Join-Path $repoRoot 'README.md'), (Join-Path $repoRoot 'docs\README.md'))) {
    $text = Get-TextOrNull $path
    if ($null -eq $text) {
        Add-Problem "$(Get-Relative $path) is missing."
        continue
    }
    if ($text -notmatch [regex]::Escape($interface)) {
        Add-Problem "$(Get-Relative $path) does not mention Interface $interface."
    }
}

# --- .toc and .lua agreement --------------------------------------------------

$tocLuaFiles = @($meta.TocLines | Where-Object { $_ -match '\.lua\s*$' -and $_ -notmatch '^\s*#' } | ForEach-Object { $_.Trim() })
foreach ($file in $tocLuaFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $file))) {
        Add-Problem "$addonName.toc loads $file, which does not exist."
    }
}
Get-ChildItem -LiteralPath $repoRoot -Filter '*.lua' -File | ForEach-Object {
    if ($tocLuaFiles -notcontains $_.Name) {
        Add-Problem "$($_.Name) is at the repository root but not listed in $addonName.toc."
    }
}

# --- packaging metadata -------------------------------------------------------

# package-as decides the folder name inside the zip, which has to match the
# addon folder name the .toc and IconTexture path assume.
$packageAs = Get-FwmPkgmetaField -RepoRoot $repoRoot -Field 'package-as'
if (-not $packageAs) {
    Add-Problem '.pkgmeta has no package-as; the packager would guess the name from the .toc file name.'
}
elseif ($packageAs -ne $addonName) {
    Add-Problem ".pkgmeta package-as is '$packageAs' but the addon is '$addonName'; the zip folder would not match the IconTexture path."
}

# Catch an ignore rule that would strip something the addon needs to run.
$shippable = @(Get-FwmShippableFile -RepoRoot $repoRoot)
$shippableNames = $shippable | ForEach-Object { $_.Name }
foreach ($required in @("$addonName.toc") + $tocLuaFiles) {
    if ($shippableNames -notcontains $required) {
        Add-Problem "$required would not be packaged; check the ignore list in .pkgmeta."
    }
}

# --- icon ---------------------------------------------------------------------

# The client reads BLP and uncompressed TGA only, so a PNG IconTexture renders
# as nothing. Keep the generated TGA current with the source art.
$iconSource = Join-Path $repoRoot 'Ornate-Golden-UI-Mover-Icon.png'
$iconTarget = Join-Path $repoRoot 'Ornate-Golden-UI-Mover-Icon.tga'

if ($meta.IconTexture -and $meta.IconTexture -match '\.png\s*$') {
    Add-Problem '## IconTexture points at a .png; the client cannot load PNG textures. Use the generated .tga (or a .blp).'
}
if (Test-Path -LiteralPath $iconSource) {
    $iconStale = (-not (Test-Path -LiteralPath $iconTarget)) -or
        ((Get-Item -LiteralPath $iconTarget).LastWriteTimeUtc -lt (Get-Item -LiteralPath $iconSource).LastWriteTimeUtc)
    if ($iconStale) {
        if ($Check) {
            Add-Problem 'Ornate-Golden-UI-Mover-Icon.tga is missing or older than the source PNG; run tools\build.ps1.'
        }
        else {
            & (Join-Path $PSScriptRoot 'Convert-IconToTga.ps1') | Out-Null
            Add-Change 'converted Ornate-Golden-UI-Mover-Icon.png -> .tga'
        }
    }
}

if ($meta.IconTexture) {
    # Resolve the TOC path (Interface\AddOns\<addon>\<file>) back to disk.
    $iconLeaf = Split-Path -Leaf ($meta.IconTexture -replace '\\', '/')
    $iconCandidates = if ([System.IO.Path]::GetExtension($iconLeaf)) {
        @($iconLeaf)
    }
    else {
        # An extensionless TOC path lets the client pick either format.
        @("$iconLeaf.tga", "$iconLeaf.blp")
    }
    # @() matters: a single match would otherwise be a bare string, and
    # indexing a string gives you its first character.
    $found = @($iconCandidates | Where-Object { Test-Path -LiteralPath (Join-Path $repoRoot $_) })
    if ($found.Count -eq 0 -and -not $Check) {
        Add-Problem "## IconTexture references $iconLeaf, which is not in the repository root."
    }
    # An icon that exists but is excluded from the package is worse than no
    # icon: it works locally and silently breaks for everyone else.
    if ($found.Count -gt 0 -and ($shippableNames -notcontains $found[0])) {
        Add-Problem "$($found[0]) would not be packaged; check the ignore list in .pkgmeta."
    }
}

# --- report -------------------------------------------------------------------

foreach ($change in $changes) { Write-Host "  $change" }

if ($problems.Count -gt 0) {
    Write-Host ''
    Write-Host 'Problems:' -ForegroundColor Red
    foreach ($problem in $problems) { Write-Host "  - $problem" -ForegroundColor Red }
    exit 1
}

Write-Host "  validated; $($shippable.Count) files would be packaged"

if ($Check) { exit 0 }

# --- package ------------------------------------------------------------------

if ($SkipPackage) { exit 0 }

Add-Type -AssemblyName System.IO.Compression.FileSystem

$staging = Join-Path ([System.IO.Path]::GetTempPath()) ("fwm-build-" + [guid]::NewGuid().ToString('N'))
$stagedAddon = Join-Path $staging $addonName
try {
    New-Item -ItemType Directory -Path $stagedAddon -Force | Out-Null
    $shippable | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $stagedAddon $_.Name)
    }

    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    }
    $zipPath = Join-Path $OutputDirectory "$addonName-$version.zip"
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }

    # includeBaseDirectory: the zip must contain the ForeverWindowMover folder
    # itself so it drops straight into Interface\AddOns\, which is also what
    # the packager produces from package-as.
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $stagedAddon, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $true)

    Write-Host "  packaged $($shippable.Count) files -> $(Get-Relative $zipPath)"
    foreach ($file in $shippable) { Write-Host "      $($file.Name)" }
}
finally {
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
}

# Explicit, because every other path exits explicitly. Falling off the end
# would leave $LASTEXITCODE holding whatever the caller's previous command set,
# so a successful package could look like a failure.
exit 0
