<#
.SYNOPSIS
  Symlinks a mod folder from this repo into the Remnant 2 Win64\Mods folder,
  and registers it in mods.txt if it isn't already listed.

.PARAMETER ModName
  Name of the mod folder in this repo (e.g. LoadoutSlotCount). Must already
  exist under the repo root with a Scripts\main.lua inside it.

.PARAMETER GameWin64Path
  Path to the folder that CONTAINS the Mods folder. Since the UE4SS
  experimental-latest upgrade (new install layout), that's the game's
  Win64\ue4ss folder, not Win64 itself. Defaults to the standard Steam
  install location; override if your install is elsewhere.

.PARAMETER Force
  If the target in Win64\Mods already exists as a real folder (not a
  symlink), remove it and replace with a symlink. Without -Force, an
  existing real folder is left alone and the script errors out.

.EXAMPLE
  .\scripts\New-ModSymlink.ps1 -ModName LoadoutSlotCount
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$ModName,

    [string]$GameWin64Path = "C:\Program Files (x86)\Steam\steamapps\common\Remnant2\Remnant2\Binaries\Win64\ue4ss",

    [switch]$Force
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$RepoModPath = Join-Path $RepoRoot $ModName
$GameModsPath = Join-Path $GameWin64Path "Mods"
$TargetLinkPath = Join-Path $GameModsPath $ModName
$ModsTxtPath = Join-Path $GameModsPath "mods.txt"

if (-not (Test-Path $RepoModPath)) {
    throw "Repo mod folder not found: $RepoModPath. Create the mod folder (with Scripts\main.lua) before symlinking it."
}

if (-not (Test-Path $GameModsPath)) {
    throw "Game Mods folder not found: $GameModsPath. Check -GameWin64Path or your game install location."
}

# Handle an existing item at the target path
$existing = Get-Item -Path $TargetLinkPath -ErrorAction SilentlyContinue
if ($existing) {
    $isSymlink = [bool]($existing.LinkType)
    if ($isSymlink) {
        $currentTarget = $existing.Target
        if ($currentTarget -eq $RepoModPath) {
            Write-Host "Symlink already correct: $TargetLinkPath -> $RepoModPath"
        } else {
            Write-Host "Existing symlink points elsewhere ($currentTarget). Replacing."
            Remove-Item -Path $TargetLinkPath -Force
            New-Item -ItemType SymbolicLink -Path $TargetLinkPath -Target $RepoModPath | Out-Null
            Write-Host "Re-linked: $TargetLinkPath -> $RepoModPath"
        }
    } else {
        if (-not $Force) {
            throw "$TargetLinkPath already exists as a real folder (not a symlink). Re-run with -Force to remove it and replace with a symlink, after checking there's nothing worth keeping in it."
        }
        Write-Host "Removing existing real folder at $TargetLinkPath (-Force specified)."
        Remove-Item -Path $TargetLinkPath -Recurse -Force
        New-Item -ItemType SymbolicLink -Path $TargetLinkPath -Target $RepoModPath | Out-Null
        Write-Host "Created symlink: $TargetLinkPath -> $RepoModPath"
    }
} else {
    try {
        New-Item -ItemType SymbolicLink -Path $TargetLinkPath -Target $RepoModPath | Out-Null
        Write-Host "Created symlink: $TargetLinkPath -> $RepoModPath"
    } catch {
        throw "Failed to create symlink. Run this script from an elevated (admin) terminal, or enable Developer Mode in Windows Settings. Original error: $_"
    }
}

# Register in mods.txt if not already present
if (Test-Path $ModsTxtPath) {
    $lines = Get-Content -Path $ModsTxtPath
    $alreadyListed = $lines | Where-Object { $_ -match "^\s*$([regex]::Escape($ModName))\s*:" }
    if ($alreadyListed) {
        Write-Host "$ModName already present in mods.txt: $alreadyListed"
    } else {
        # Insert before the trailing "Built-in keybinds" comment block if present,
        # otherwise just append.
        $commentIndex = ($lines | Select-String -Pattern "^\s*;" | Select-Object -First 1).LineNumber
        $newLine = "$ModName : 1"
        if ($commentIndex) {
            $insertAt = $commentIndex - 1
            $newLines = @()
            $newLines += $lines[0..($insertAt - 1)]
            $newLines += $newLine
            $newLines += $lines[$insertAt..($lines.Length - 1)]
            Set-Content -Path $ModsTxtPath -Value $newLines
        } else {
            Add-Content -Path $ModsTxtPath -Value $newLine
        }
        Write-Host "Added '$newLine' to mods.txt"
    }
} else {
    Write-Warning "mods.txt not found at $ModsTxtPath -- add '$ModName : 1' manually."
}

Write-Host "Done. $ModName is symlinked and registered."
