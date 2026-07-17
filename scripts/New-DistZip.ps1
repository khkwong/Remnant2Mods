<#
.SYNOPSIS
  Packages a mod folder (Scripts\, mod.json, README.md) into a distributable
  zip under dist\vX.Y.Z\, auto-incrementing the version folder based on the
  highest vX.Y.Z folder already under dist\.

.PARAMETER ModName
  Name of the mod folder in this repo (e.g. MoreLoadoutSlots). Must contain
  Scripts\, mod.json, and README.md.

.PARAMETER Bump
  Which part of the version to increment when auto-detecting: major, minor,
  or patch (default). Ignored if -Version is given. If dist\ has no existing
  vX.Y.Z folders yet, the first version is always 1.0.0.

.PARAMETER Version
  Use this exact version instead of picking one via -Bump. Still must be
  exactly one step (major/minor/patch) past the highest existing dist\
  version — arbitrary jumps (e.g. 1.0.0 -> 1.0.2 or 1.0.0 -> 1.2.0) are
  rejected.

.PARAMETER Force
  Overwrite the output zip if it already exists for the target version.

.EXAMPLE
  .\scripts\New-DistZip.ps1 -ModName LoadoutNamer
  # dist\v1.0.0 already exists -> creates dist\v1.0.1\LoadoutNamer-v1.0.1.zip

.EXAMPLE
  .\scripts\New-DistZip.ps1 -ModName LoadoutNamer -Bump minor

.EXAMPLE
  .\scripts\New-DistZip.ps1 -ModName LoadoutNamer -Version 2.0.0 -Force
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$ModName,

    [ValidateSet("major", "minor", "patch")]
    [string]$Bump = "patch",

    [string]$Version,

    [switch]$Force
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ModPath = Join-Path $RepoRoot $ModName
$DistRoot = Join-Path $RepoRoot "dist"

if (-not (Test-Path $ModPath)) {
    throw "Mod folder not found: $ModPath"
}
foreach ($required in @("Scripts", "mod.json", "README.md")) {
    if (-not (Test-Path (Join-Path $ModPath $required))) {
        throw "$ModPath is missing required item: $required"
    }
}

# Determine the highest existing dist\ version, then the only three valid
# next versions from it (exactly one step up: major, minor, or patch).
$existingVersions = @()
if (Test-Path $DistRoot) {
    Get-ChildItem $DistRoot -Directory |
        Where-Object { $_.Name -match '^v(\d+)\.(\d+)\.(\d+)$' } |
        ForEach-Object { $existingVersions += [version]$_.Name.TrimStart('v') }
}

if ($existingVersions.Count -eq 0) {
    $validNext = @{ patch = "1.0.0"; minor = "1.0.0"; major = "1.0.0" }
} else {
    $latest = $existingVersions | Sort-Object -Descending | Select-Object -First 1
    $validNext = @{
        patch = "{0}.{1}.{2}" -f $latest.Major, $latest.Minor, ($latest.Build + 1)
        minor = "{0}.{1}.0" -f $latest.Major, ($latest.Minor + 1)
        major = "{0}.0.0" -f ($latest.Major + 1)
    }
}

if ($Version) {
    if ($validNext.Values -notcontains $Version) {
        throw "'$Version' is not a single-step increment from the latest dist version ($(if ($latest) { $latest } else { '(none yet)' })). Valid next versions right now: $($validNext.patch) (patch), $($validNext.minor) (minor), $($validNext.major) (major)."
    }
    $targetVersion = $Version
} else {
    $targetVersion = $validNext[$Bump]
}

$modJson = Get-Content (Join-Path $ModPath "mod.json") -Raw | ConvertFrom-Json
if ($modJson.ModVersion -ne $targetVersion) {
    throw "$ModName\mod.json has ModVersion '$($modJson.ModVersion)', but the target distribution version is '$targetVersion'. Update ModVersion in mod.json to '$targetVersion' before re-running."
}

$versionFolder = Join-Path $DistRoot "v$targetVersion"
$zipPath = Join-Path $versionFolder "$ModName-v$targetVersion.zip"

if ((Test-Path $zipPath) -and -not $Force) {
    throw "$zipPath already exists. Re-run with -Force to overwrite, or pick a different -Version/-Bump."
}

New-Item -ItemType Directory -Force -Path $versionFolder | Out-Null

# Stage a clean copy so stray local files (e.g. LoadoutNamer's saved loadout_names.txt) never end up in the zip
$stage = Join-Path $versionFolder "_stage_$ModName"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
$stageModPath = Join-Path $stage $ModName
New-Item -ItemType Directory -Force -Path $stageModPath | Out-Null

Copy-Item (Join-Path $ModPath "Scripts") (Join-Path $stageModPath "Scripts") -Recurse -Force
Copy-Item (Join-Path $ModPath "mod.json") (Join-Path $stageModPath "mod.json") -Force
Copy-Item (Join-Path $ModPath "README.md") (Join-Path $stageModPath "README.md") -Force

if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path $stageModPath -DestinationPath $zipPath

Remove-Item $stage -Recurse -Force

Write-Host "Created $zipPath"
