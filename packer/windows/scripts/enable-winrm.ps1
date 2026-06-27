<#
.SYNOPSIS
  Enables WinRM for Packer build-time provisioning.

.WARNING
  This script enables Basic auth and unencrypted WinRM as a build-time example
  for isolated template-build networks. Tighten this for production networks.
  Do not expose build VMs with this configuration to untrusted networks.
#>

$ErrorActionPreference = 'Stop'

Write-Host 'Setting network profile to Private where possible...'
try {
    Get-NetConnectionProfile | Where-Object { $_.NetworkCategory -ne 'Private' } | Set-NetConnectionProfile -NetworkCategory Private
} catch {
    Write-Warning "Could not set network profile: $($_.Exception.Message)"
}

Write-Host 'Enabling PowerShell remoting...'
Enable-PSRemoting -Force -SkipNetworkProfileCheck

Write-Host 'Configuring WinRM service...'
winrm quickconfig -quiet
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/client/auth '@{Basic="true"}'

Write-Host 'Opening WinRM firewall rules...'
try {
    Enable-NetFirewallRule -DisplayGroup 'Windows Remote Management'
} catch {
    Write-Warning "Could not enable WinRM firewall display group: $($_.Exception.Message)"
}

try {
    New-NetFirewallRule -Name 'Packer-WinRM-HTTP' -DisplayName 'Packer WinRM HTTP' -Enabled True -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow -ErrorAction SilentlyContinue | Out-Null
} catch {
    Write-Warning "Could not create WinRM firewall rule: $($_.Exception.Message)"
}

Write-Host 'Restarting WinRM...'
Restart-Service WinRM

Write-Host 'WinRM build-time setup complete.'
