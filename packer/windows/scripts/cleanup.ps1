<#
.SYNOPSIS
  Best-effort cleanup before converting a Windows VM to a template.

.NOTES
  Sysprep is intentionally not run by default. Add it here only after testing
  your runner/template lifecycle and making sure cloned VMs get unique identity.
#>

$ErrorActionPreference = 'Continue'

Write-Host 'Disabling hibernation...'
powercfg /hibernate off

Write-Host 'Enabling long paths...'
New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Value 1 -PropertyType DWord -Force | Out-Null

Write-Host 'Clearing temporary folders...'
$paths = @($env:TEMP, 'C:\Windows\Temp')
foreach ($path in $paths) {
    if (Test-Path $path) {
        Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host 'Clearing event logs best-effort...'
try {
    wevtutil el | ForEach-Object { wevtutil cl $_ 2>$null }
} catch {
    Write-Warning "Event log cleanup failed: $($_.Exception.Message)"
}

# Optional Sysprep location:
# & "$env:SystemRoot\System32\Sysprep\Sysprep.exe" /generalize /oobe /shutdown /quiet

Write-Host 'Cleanup complete. Shutting down.'
Stop-Computer -Force
