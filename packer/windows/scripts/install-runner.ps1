<#
.SYNOPSIS
  Bake the CI toolchain + GitHub Actions runner (unregistered) + boot waiter into the
  Windows golden template, for ephemeral JIT runners.

.NOTES
  Reads RUNNER_VERSION / DOTNET_CHANNEL / GIT_URL from the environment (Packer
  environment_vars). Expects windows-runner-once.ps1 + gha-runner-waiter.ps1 already
  uploaded to C:\Windows\Temp.
#>
$ErrorActionPreference = 'Stop'
$rv     = $env:RUNNER_VERSION
$ch     = $env:DOTNET_CHANNEL
$giturl = $env:GIT_URL

New-Item -Force -ItemType Directory 'C:\gha-runner', 'C:\actions-runner', 'C:\actions-work' | Out-Null
Copy-Item 'C:\Windows\Temp\windows-runner-once.ps1' 'C:\gha-runner\windows-runner-once.ps1' -Force
Copy-Item 'C:\Windows\Temp\gha-runner-waiter.ps1'   'C:\gha-runner\gha-runner-waiter.ps1'   -Force

Write-Host 'Installing Git for Windows...'
Invoke-WebRequest $giturl -OutFile 'C:\Windows\Temp\git.exe' -UseBasicParsing
Start-Process 'C:\Windows\Temp\git.exe' -ArgumentList '/VERYSILENT', '/NORESTART' -Wait

Write-Host "Installing .NET SDK $ch..."
Invoke-WebRequest 'https://dot.net/v1/dotnet-install.ps1' -OutFile 'C:\Windows\Temp\dotnet-install.ps1' -UseBasicParsing
& 'C:\Windows\Temp\dotnet-install.ps1' -Channel $ch -InstallDir 'C:\Program Files\dotnet'

if ($env:PWSH_MSI_URL) {
    Write-Host 'Installing PowerShell 7 (pwsh)...'
    Invoke-WebRequest $env:PWSH_MSI_URL -OutFile 'C:\Windows\Temp\pwsh.msi' -UseBasicParsing
    Start-Process msiexec -ArgumentList '/i', 'C:\Windows\Temp\pwsh.msi', '/quiet', '/norestart', 'ADD_PATH=1' -Wait
}

Write-Host 'Updating machine PATH + DOTNET_ROOT...'
$p = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$p = ($p.TrimEnd(';') + ';C:\Program Files\dotnet;C:\Program Files\Git\cmd')
[Environment]::SetEnvironmentVariable('Path', $p, 'Machine')
[Environment]::SetEnvironmentVariable('DOTNET_ROOT', 'C:\Program Files\dotnet', 'Machine')

Write-Host "Extracting GitHub Actions runner $rv (unregistered)..."
$zip = 'C:\actions-runner\runner.zip'
Invoke-WebRequest "https://github.com/actions/runner/releases/download/v$rv/actions-runner-win-x64-$rv.zip" -OutFile $zip -UseBasicParsing
Expand-Archive $zip -DestinationPath 'C:\actions-runner' -Force
Remove-Item $zip -Force

Write-Host 'Registering the boot waiter scheduled task (SYSTEM, at startup)...'
$action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-ExecutionPolicy Bypass -NonInteractive -File C:\gha-runner\gha-runner-waiter.ps1'
$trigger   = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName 'gha-runner-waiter' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

Write-Host 'Windows runner bake complete.'
