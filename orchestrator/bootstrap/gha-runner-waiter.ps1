<#
.SYNOPSIS
  Boot waiter for the Windows ephemeral runner.

.DESCRIPTION
  Registered as a Scheduled Task (at startup, SYSTEM) in the golden template. On each
  boot it waits for the orchestrator to inject C:\gha-runner\runner.env.ps1 (via the
  guest agent), then runs the one-shot JIT bootstrap. Mirrors the Linux
  gha-runner-waiter.service.
#>

$ErrorActionPreference = 'Continue'
$envFile   = 'C:\gha-runner\runner.env.ps1'
$bootstrap = 'C:\gha-runner\windows-runner-once.ps1'

# Wait up to ~5 min for the orchestrator to write the env (rollback -> start -> agent up
# -> file-write).
for ($i = 0; $i -lt 150; $i++) {
    if (Test-Path $envFile) { break }
    Start-Sleep -Seconds 2
}

if (Test-Path $envFile) {
    & powershell.exe -ExecutionPolicy Bypass -File $bootstrap
} else {
    Write-Warning 'no C:\gha-runner\runner.env.ps1 injected'
}
