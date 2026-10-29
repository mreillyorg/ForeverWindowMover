<#
.SYNOPSIS
    Converts the source icon PNG into the uncompressed 32-bit TGA that the WoW
    client can actually load.

.DESCRIPTION
    The client reads BLP and uncompressed TGA textures only -- a PNG referenced
    from ## IconTexture silently renders as nothing. This script resizes the
    high-resolution source art down to a power-of-two square and writes a
    32-bit uncompressed TGA (bottom-left origin, 8 alpha bits) next to it.

    The PNG stays in the repository as the source of truth for the art and is
    excluded from the shipped package by the "*.png" ignore rule in .pkgmeta.

.PARAMETER Size
    Edge length of the generated square texture. Must be a power of two; 64 is
    the usual size for an addon-list icon.

.PARAMETER Force
    Rewrite the TGA even when it is already newer than the PNG.

.EXAMPLE
    .\tools\Convert-IconToTga.ps1
#>
[CmdletBinding()]
param(
    [string] $SourcePath = (Join-Path (Join-Path $PSScriptRoot '..') 'Ornate-Golden-UI-Mover-Icon.png'),
    [string] $DestinationPath = (Join-Path (Join-Path $PSScriptRoot '..') 'Ornate-Golden-UI-Mover-Icon.tga'),
    [int] $Size = 64,
    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Size -le 0 -or ($Size -band ($Size - 1)) -ne 0) {
    throw "Size must be a power of two, got $Size."
}

$source = (Resolve-Path -LiteralPath $SourcePath).Path
$destinationDirectory = Split-Path -Parent $DestinationPath
if (-not (Test-Path -LiteralPath $destinationDirectory)) {
    throw "Destination directory does not exist: $destinationDirectory"
}
$destination = Join-Path (Resolve-Path -LiteralPath $destinationDirectory).Path (Split-Path -Leaf $DestinationPath)

if (-not $Force -and (Test-Path -LiteralPath $destination)) {
    $sourceStamp = (Get-Item -LiteralPath $source).LastWriteTimeUtc
    $destinationStamp = (Get-Item -LiteralPath $destination).LastWriteTimeUtc
    if ($destinationStamp -ge $sourceStamp) {
        Write-Verbose "Icon is already up to date: $destination"
        return $destination
    }
}

Add-Type -AssemblyName System.Drawing

$image = [System.Drawing.Image]::FromFile($source)
try {
    $bitmap = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $graphics.DrawImage($image, (New-Object System.Drawing.Rectangle 0, 0, $Size, $Size))
        }
        finally { $graphics.Dispose() }

        # 18-byte TGA header: uncompressed true-colour, 32 bits per pixel,
        # 8 alpha bits, bottom-left origin (the format default).
        $header = [byte[]]::new(18)
        $header[2] = 2
        $header[12] = [byte]($Size -band 0xFF)
        $header[13] = [byte](($Size -shr 8) -band 0xFF)
        $header[14] = [byte]($Size -band 0xFF)
        $header[15] = [byte](($Size -shr 8) -band 0xFF)
        $header[16] = 32
        $header[17] = 8

        # Pixels are BGRA, and rows run bottom-to-top for a bottom-left origin.
        $pixels = [byte[]]::new($Size * $Size * 4)
        $offset = 0
        for ($y = $Size - 1; $y -ge 0; $y--) {
            for ($x = 0; $x -lt $Size; $x++) {
                $colour = $bitmap.GetPixel($x, $y)
                $pixels[$offset] = $colour.B
                $pixels[$offset + 1] = $colour.G
                $pixels[$offset + 2] = $colour.R
                $pixels[$offset + 3] = $colour.A
                $offset += 4
            }
        }

        $stream = [System.IO.File]::Create($destination)
        try {
            $stream.Write($header, 0, $header.Length)
            $stream.Write($pixels, 0, $pixels.Length)
        }
        finally { $stream.Dispose() }
    }
    finally { $bitmap.Dispose() }
}
finally { $image.Dispose() }

Write-Verbose ("Wrote {0} ({1}x{1}, {2} bytes)" -f $destination, $Size, (Get-Item -LiteralPath $destination).Length)
return $destination
