<#
.SYNOPSIS
  Best-effort cleanup before converting a Windows VM to a template.

.NOTES
  Sysprep is intentionally not run by default. Add it here only after testing
  your runner/template lifecycle and making sure cloned VMs get unique identity.

  This runs as a Packer provisioner, so it must NOT power the VM off — Packer
  needs WinRM alive to return, then performs the shutdown itself via the build's
  `shutdown_command`. Do not add Stop-Computer/shutdown here.
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
        # Exclude packer-* so we don't delete the env-vars helper Packer is still using
        # for this very provisioner session (otherwise it logs a cosmetic not-found error).
        Get-ChildItem -Path $path -Force -Exclude 'packer-*' -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
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

Write-Host 'Cleanup complete. Packer (proxmox-iso builder) will stop the VM.'

# Best-effort script: external tools above (wevtutil/powercfg) may leave a non-zero
# $LASTEXITCODE. Exit 0 so that does not fail the Packer provisioner.
exit 0
