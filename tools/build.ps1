<#
.SYNOPSIS
    Generates the in-package copies, checks version consistency, and zips the
    addon folder for distribution.

.DESCRIPTION
    The repository keeps two copies of some files: one for people reading the
    repo and one shipped inside the addon folder. Maintaining both by hand is
    how the 0.3.1 changelogs drifted apart, so the shipped copies are generated
    here from the repo originals instead:

        CHANGELOG.md -> ForeverWindowMover/CHANGELOG.md
            Same body, with the author/source line added (the repo copy links
            to docs/ instead, which does not ship) and the footer links dropped.
        LICENSE      -> ForeverWindowMover/LICENSE
            Verbatim copy.

    ForeverWindowMover/README.txt is NOT generated. It is hand-wrapped plain
    text with deliberately different formatting from README.md, so the script
    only verifies that its version and Interface headers agree with the .toc.

    The script is also the version gate: the .toc's ## Version is authoritative
    and every other place the version appears must match it.

.PARAMETER Check
    Verify only. Reports what would change and exits non-zero if anything is
    inconsistent or out of date. Nothing is written. Suitable for CI or a
    pre-commit hook.

.PARAMETER SkipPackage
    Generate and verify, but do not build the zip.

.PARAMETER OutputDirectory
    Where the zip is written. Defaults to dist/ at the repository root.

.EXAMPLE
    .\tools\build.ps1
    Regenerate the in-package copies and write dist/ForeverWindowMover-x.y.z.zip.

.EXAMPLE
    .\tools\build.ps1 -Check
    Fail if the shipped copies or any version string are out of sync.
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
$addonDirectory = Join-Path $repoRoot $addonName
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repoRoot 'dist' }

$problems = [System.Collections.Generic.List[string]]::new()
$changes = [System.Collections.Generic.List[string]]::new()

function Add-Problem([string] $message) { $problems.Add($message) }
function Add-Change([string] $message) { $changes.Add($message) }

function Get-TextOrNull([string] $path) {
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    return Get-Content -LiteralPath $path -Raw
}

# Writes $content to $path unless -Check, and records whether it differed.
function Set-GeneratedFile([string] $path, [string] $content) {
    $relative = $path.Substring($repoRoot.Length).TrimStart('\', '/')
    $existing = Get-TextOrNull $path
    # Compare on normalised newlines so a CRLF/LF checkout difference is not
    # reported as drift.
    $normalise = { param($text) if ($null -eq $text) { $null } else { $text -replace "`r`n", "`n" } }
    if ((& $normalise $existing) -eq (& $normalise $content)) { return }

    if ($Check) {
        if ($null -eq $existing) {
            Add-Problem "$relative is missing; run tools\build.ps1 to generate it."
        }
        else {
            Add-Problem "$relative is out of sync with its source; run tools\build.ps1 to regenerate it."
        }
        return
    }

    $directory = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    # UTF-8 without a BOM, LF endings: what the repository already uses.
    [System.IO.File]::WriteAllText($path, ($content -replace "`r`n", "`n"), (New-Object System.Text.UTF8Encoding $false))
    Add-Change "wrote $relative"
}

# --- metadata -----------------------------------------------------------------

foreach ($required in @((Join-Path $repoRoot 'CHANGELOG.md'), (Join-Path $repoRoot 'LICENSE'))) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Required file not found: $required" }
}

$meta = Get-FwmMetadata -RepoRoot $repoRoot
$tocPath = $meta.TocPath
$tocLines = $meta.TocLines
$coreLuaPath = $meta.CoreLuaPath
$version = $meta.Version
$interface = $meta.Interface
$iconTexture = $meta.IconTexture
$author = $meta.Author
$website = $meta.Website
if (-not $author) { Add-Problem "Could not read addon.author from $addonName.lua" }
if (-not $website) { Add-Problem "Could not read addon.website from $addonName.lua" }

Write-Host "$addonName $version (Interface $interface)"

# --- consistency checks -------------------------------------------------------

# Every place the version is written out, per the release steps in
# docs/development.md. The .toc is the single source of truth.
$versionSites = @(
    @{ Path = $coreLuaPath;                              Pattern = "^--\s*Forever Window Mover\s+$([regex]::Escape($version))\s*$"; What = 'header comment' }
    @{ Path = $coreLuaPath;                              Pattern = "addon\.version\s*=\s*""$([regex]::Escape($version))"""      ; What = 'addon.version' }
    @{ Path = (Join-Path $repoRoot 'README.md');         Pattern = "^#\s*$addonName\s+$([regex]::Escape($version))\s*$"        ; What = 'title' }
    @{ Path = (Join-Path $addonDirectory 'README.txt');  Pattern = "(?i)^FOREVER WINDOW MOVER\s+$([regex]::Escape($version))\s*$"; What = 'title' }
    @{ Path = (Join-Path $repoRoot 'CHANGELOG.md');      Pattern = "^##\s*$([regex]::Escape($version))\s*$"                    ; What = 'release section' }
)
foreach ($site in $versionSites) {
    $text = Get-TextOrNull $site.Path
    $relative = $site.Path.Substring($repoRoot.Length).TrimStart('\', '/')
    if ($null -eq $text) {
        Add-Problem "$relative is missing."
        continue
    }
    if ($text -notmatch "(?m)$($site.Pattern)") {
        Add-Problem "$relative $($site.What) does not state version $version."
    }
}

# The Interface number is quoted in the user-facing text as well.
$interfaceSites = @(
    (Join-Path $repoRoot 'README.md'),
    (Join-Path $addonDirectory 'README.txt'),
    (Join-Path $repoRoot 'docs\README.md')
)
foreach ($path in $interfaceSites) {
    $text = Get-TextOrNull $path
    $relative = $path.Substring($repoRoot.Length).TrimStart('\', '/')
    if ($null -eq $text) {
        Add-Problem "$relative is missing."
        continue
    }
    if ($text -notmatch [regex]::Escape($interface)) {
        Add-Problem "$relative does not mention Interface $interface."
    }
}

# Every Lua file the .toc loads must exist, and vice versa.
$tocLuaFiles = $tocLines | Where-Object { $_ -match '\.lua\s*$' -and $_ -notmatch '^\s*#' } | ForEach-Object { $_.Trim() }
foreach ($file in $tocLuaFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $addonDirectory $file))) {
        Add-Problem "$addonName.toc loads $file, which does not exist."
    }
}
Get-ChildItem -LiteralPath $addonDirectory -Filter '*.lua' -File | ForEach-Object {
    if ($tocLuaFiles -notcontains $_.Name) {
        Add-Problem "$($_.Name) is in the addon folder but not listed in $addonName.toc."
    }
}

# --- icon ---------------------------------------------------------------------

# The client reads BLP and uncompressed TGA only, so a PNG IconTexture renders
# as nothing. Keep the generated TGA current with the source art.
$iconScript = Join-Path $PSScriptRoot 'Convert-IconToTga.ps1'
$iconSource = Join-Path $addonDirectory 'Ornate-Golden-UI-Mover-Icon.png'
$iconTarget = Join-Path $addonDirectory 'Ornate-Golden-UI-Mover-Icon.tga'

if ($iconTexture -and $iconTexture -match '\.png\s*$') {
    Add-Problem "## IconTexture points at a .png; the client cannot load PNG textures. Use the generated .tga (or a .blp)."
}
if (Test-Path -LiteralPath $iconSource) {
    $iconStale = (-not (Test-Path -LiteralPath $iconTarget)) -or
        ((Get-Item -LiteralPath $iconTarget).LastWriteTimeUtc -lt (Get-Item -LiteralPath $iconSource).LastWriteTimeUtc)
    if ($iconStale) {
        if ($Check) {
            Add-Problem 'Ornate-Golden-UI-Mover-Icon.tga is missing or older than the source PNG; run tools\build.ps1.'
        }
        else {
            & $iconScript | Out-Null
            Add-Change 'converted Ornate-Golden-UI-Mover-Icon.png -> .tga'
        }
    }
}

if ($iconTexture) {
    # Resolve the TOC path (Interface\AddOns\<addon>\<file>) back to disk.
    $iconLeaf = Split-Path -Leaf ($iconTexture -replace '\\', '/')
    $iconCandidates = if ([System.IO.Path]::GetExtension($iconLeaf)) {
        @($iconLeaf)
    }
    else {
        # An extensionless TOC path lets the client pick either format.
        @("$iconLeaf.tga", "$iconLeaf.blp")
    }
    $found = $iconCandidates | Where-Object { Test-Path -LiteralPath (Join-Path $addonDirectory $_) }
    if (-not $found -and -not $Check) {
        Add-Problem "## IconTexture references $iconLeaf, which is not in the addon folder."
    }
}

# --- generated in-package copies ----------------------------------------------

# CHANGELOG: identical body, different header/footer. The repo copy links to
# docs/, which is not shipped, so the package copy spells out the URL instead.
$rootChangelog = (Get-Content -LiteralPath (Join-Path $repoRoot 'CHANGELOG.md') -Raw) -replace "`r`n", "`n"
$changelogLines = [System.Collections.Generic.List[string]]($rootChangelog -split "`n")

# Drop the repo-only footer links and any trailing blank lines.
while ($changelogLines.Count -gt 0 -and
      ($changelogLines[$changelogLines.Count - 1].Trim() -eq '' -or
       $changelogLines[$changelogLines.Count - 1] -match '^\[Source and issues\]')) {
    $changelogLines.RemoveAt($changelogLines.Count - 1)
}

# Insert the attribution line after the intro paragraph.
$introIndex = -1
for ($i = 0; $i -lt $changelogLines.Count; $i++) {
    if ($changelogLines[$i] -match '^All notable changes') { $introIndex = $i; break }
}
if ($introIndex -lt 0) {
    Add-Problem 'CHANGELOG.md has no "All notable changes" intro line; cannot generate the in-package copy.'
}
else {
    $middot = [char]0x00B7
    $changelogLines.Insert($introIndex + 1, '')
    $changelogLines.Insert($introIndex + 2, "Author: $author $middot Source / issues: $website")
    Set-GeneratedFile (Join-Path $addonDirectory 'CHANGELOG.md') (($changelogLines -join "`n") + "`n")
}

# LICENSE: verbatim.
Set-GeneratedFile (Join-Path $addonDirectory 'LICENSE') (Get-Content -LiteralPath (Join-Path $repoRoot 'LICENSE') -Raw)

# --- report -------------------------------------------------------------------

foreach ($change in $changes) { Write-Host "  $change" }

if ($problems.Count -gt 0) {
    Write-Host ''
    Write-Host 'Problems:' -ForegroundColor Red
    foreach ($problem in $problems) { Write-Host "  - $problem" -ForegroundColor Red }
    exit 1
}

if ($Check) {
    Write-Host '  in-package copies and version strings are in sync'
    exit 0
}

# --- package ------------------------------------------------------------------

if ($SkipPackage) { exit 0 }

Add-Type -AssemblyName System.IO.Compression.FileSystem

$staging = Join-Path ([System.IO.Path]::GetTempPath()) ("fwm-build-" + [guid]::NewGuid().ToString('N'))
$stagedAddon = Join-Path $staging $addonName
try {
    New-Item -ItemType Directory -Path $stagedAddon -Force | Out-Null
    Get-FwmShippableFile -AddonDirectory $addonDirectory | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $stagedAddon $_.Name)
    }

    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    }
    $zipPath = Join-Path $OutputDirectory "$addonName-$version.zip"
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }

    # includeBaseDirectory: the zip must contain the ForeverWindowMover folder
    # itself so it drops straight into Interface\AddOns\.
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $stagedAddon, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $true)

    $shipped = Get-ChildItem -LiteralPath $stagedAddon -File | Sort-Object Name
    Write-Host "  packaged $($shipped.Count) files -> $($zipPath.Substring($repoRoot.Length).TrimStart('\'))"
    foreach ($file in $shipped) { Write-Host "      $($file.Name)" }
}
finally {
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
}
