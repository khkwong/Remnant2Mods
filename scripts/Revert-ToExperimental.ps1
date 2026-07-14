<#
.SYNOPSIS
  Reverts the live game install from the temporary stable-UE4SS test back to
  experimental-latest (undoes Swap-ToStableForTest.ps1). Deletes the
  stable-runtime files that were copied into Win64 root; the backup itself
  was never modified and is untouched by this script either.

.NOTES
  Run from an elevated (Administrator) PowerShell. Requires the game to be
  closed first.
#>
$ErrorActionPreference = "Stop"

$base = "C:\Program Files (x86)\Steam\steamapps\common\Remnant2\Remnant2\Binaries\Win64"

Write-Host "1. Removing the stable runtime files copied into Win64 root..."
Remove-Item -Path "$base\UE4SS.dll" -Force
Remove-Item -Path "$base\dwmapi.dll" -Force
Remove-Item -Path "$base\UE4SS-settings.ini" -Force
Remove-Item -Path "$base\imgui.ini" -Force -ErrorAction SilentlyContinue
foreach ($dir in @("CustomGameConfigs","MemberVarLayoutTemplates","UE4SS-config","UE4SS_Signatures","VTableLayoutTemplates","watches","Mods")) {
    Remove-Item -Path "$base\$dir" -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "2. Restoring the experimental install..."
Rename-Item -Path "$base\dwmapi.dll.experimental-disabled" -NewName "dwmapi.dll"
Rename-Item -Path "$base\ue4ss-experimental" -NewName "ue4ss"

Write-Host "`nDone. Back on experimental-latest. mods.txt (unchanged from before the swap):"
Get-Content "$base\ue4ss\Mods\mods.txt"
