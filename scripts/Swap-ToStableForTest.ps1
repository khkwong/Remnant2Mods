<#
.SYNOPSIS
  Temporarily swaps the live game install from UE4SS experimental-latest to the
  backed-up stable v3.0.1 build, with AllowModsMod enabled, to test whether the
  three mods still work under stable + AllowModsMod. Fully reversible: the
  experimental install is renamed aside, not deleted, and the stable backup is
  only ever read from, never modified.

.NOTES
  Run from an elevated (Administrator) PowerShell. Requires the game to be
  closed first.
#>
$ErrorActionPreference = "Stop"

$base = "C:\Program Files (x86)\Steam\steamapps\common\Remnant2\Remnant2\Binaries\Win64"
$backup = "$base\_ue4ss-3.0.1-backup"

Write-Host "1. Moving the experimental install aside (reversible)..."
Rename-Item -Path "$base\ue4ss" -NewName "ue4ss-experimental"
Rename-Item -Path "$base\dwmapi.dll" -NewName "dwmapi.dll.experimental-disabled"

Write-Host "2. Copying the stable backup's runtime files into Win64 root (backup untouched)..."
Copy-Item -Path "$backup\UE4SS.dll" -Destination "$base\UE4SS.dll"
Copy-Item -Path "$backup\dwmapi.dll" -Destination "$base\dwmapi.dll"
Copy-Item -Path "$backup\UE4SS-settings.ini" -Destination "$base\UE4SS-settings.ini"
Copy-Item -Path "$backup\imgui.ini" -Destination "$base\imgui.ini" -ErrorAction SilentlyContinue
foreach ($dir in @("CustomGameConfigs","MemberVarLayoutTemplates","UE4SS-config","UE4SS_Signatures","VTableLayoutTemplates","watches","Mods")) {
    Copy-Item -Path "$backup\$dir" -Destination "$base\$dir" -Recurse
}

Write-Host "3. Re-symlinking the three mods against the restored old layout (Mods directly under Win64)..."
& powershell -ExecutionPolicy Bypass -File "c:\Users\chubb\Projects\Remnant2Mods\scripts\New-ModSymlink.ps1" -ModName MoreLoadoutSlots -GameWin64Path $base -Force
& powershell -ExecutionPolicy Bypass -File "c:\Users\chubb\Projects\Remnant2Mods\scripts\New-ModSymlink.ps1" -ModName LoadoutNamer -GameWin64Path $base
& powershell -ExecutionPolicy Bypass -File "c:\Users\chubb\Projects\Remnant2Mods\scripts\New-ModSymlink.ps1" -ModName EquipmentSearch -GameWin64Path $base

Write-Host "4. Current mods.txt:"
Get-Content "$base\Mods\mods.txt"

Write-Host "`nDone. Launch the game fresh (no hot-reload) and open Character -> Loadouts."
Write-Host "Log will be at: $base\UE4SS.log"
Write-Host "`nTo revert later: run scripts\Revert-ToExperimental.ps1 (ask Claude to generate it when you're ready)."
