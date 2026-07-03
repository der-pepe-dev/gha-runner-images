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

if ($env:INSTALL_BUILDTOOLS -eq 'true') {
    Write-Host 'Installing Visual Studio Build Tools (MSBuild + MSVC C++ + Windows SDK)...'
    $bt = 'C:\Windows\Temp\vs_BuildTools.exe'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest $env:VS_BUILDTOOLS_URL -OutFile $bt -UseBasicParsing
    # The bootstrapper is a real PE ~1-4 MB; a truncated/redirect download shows up as
    # "corrupted and unreadable" at Start-Process, so sanity-check before running.
    $sz = (Get-Item $bt).Length
    if ($sz -lt 1MB) { throw "vs_BuildTools.exe download looks bad ($sz bytes)" }
    Unblock-File $bt
    # VCTools + VC.Tools + Windows SDK are what .NET Native AOT and C++ builds need; the
    # MSBuild/ManagedDesktop workloads cover MSBuild + .NET Framework/desktop.
    $vsArgs = @(
        '--quiet', '--wait', '--norestart', '--nocache', '--installPath', 'C:\BuildTools',
        '--add', 'Microsoft.VisualStudio.Workload.MSBuildTools',
        '--add', 'Microsoft.VisualStudio.Workload.ManagedDesktopBuildTools',
        '--add', 'Microsoft.VisualStudio.Workload.VCTools',
        '--add', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
        '--add', 'Microsoft.VisualStudio.Component.Windows11SDK.22621',
        '--includeRecommended'
    )
    $p = Start-Process 'C:\Windows\Temp\vs_BuildTools.exe' -ArgumentList $vsArgs -Wait -PassThru
    # 0 = ok, 3010 = ok-but-reboot-required; anything else is a real failure.
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { throw "VS Build Tools install failed: exit $($p.ExitCode)" }
    Write-Host "VS Build Tools installed (exit $($p.ExitCode))."
}

# Standalone CMake + Ninja on PATH (VS Build Tools bundles CMake but not on PATH; mirrors
# the Linux image so cmake/ninja "just work").
if ($env:CMAKE_VERSION) {
    Write-Host "Installing CMake $env:CMAKE_VERSION..."
    Invoke-WebRequest "https://github.com/Kitware/CMake/releases/download/v$($env:CMAKE_VERSION)/cmake-$($env:CMAKE_VERSION)-windows-x86_64.zip" -OutFile 'C:\Windows\Temp\cmake.zip' -UseBasicParsing
    Expand-Archive 'C:\Windows\Temp\cmake.zip' -DestinationPath 'C:\Windows\Temp\cmakex' -Force
    if (Test-Path 'C:\Program Files\CMake') { Remove-Item 'C:\Program Files\CMake' -Recurse -Force }
    Move-Item (Get-ChildItem 'C:\Windows\Temp\cmakex' -Directory | Select-Object -First 1).FullName 'C:\Program Files\CMake'
}
if ($env:NINJA_VERSION) {
    Write-Host "Installing Ninja $env:NINJA_VERSION..."
    New-Item -ItemType Directory -Force 'C:\Program Files\Ninja' | Out-Null
    Invoke-WebRequest "https://github.com/ninja-build/ninja/releases/download/v$($env:NINJA_VERSION)/ninja-win.zip" -OutFile 'C:\Windows\Temp\ninja.zip' -UseBasicParsing
    Expand-Archive 'C:\Windows\Temp\ninja.zip' -DestinationPath 'C:\Program Files\Ninja' -Force
}

Write-Host 'Updating machine PATH + DOTNET_ROOT...'
$p = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$p = ($p.TrimEnd(';') + ';C:\Program Files\dotnet;C:\Program Files\Git\cmd;C:\Program Files\CMake\bin;C:\Program Files\Ninja')
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
