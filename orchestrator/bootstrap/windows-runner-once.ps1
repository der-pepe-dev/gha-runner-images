<#
.SYNOPSIS
  One-shot JIT GitHub Actions runner bootstrap for Windows.

.DESCRIPTION
  Runs inside a disposable Windows runner VM after the orchestrator injects
  C:\gha-runner\runner.env.ps1 with $env:RUNNER_JITCONFIG (base64 JIT config).
  JIT: no config.cmd, no registration token, no on-disk credentials. run.cmd
  consumes the one-shot config, runs a single job, exits; GitHub auto-removes the
  runner. Then this shuts the VM down for the orchestrator to roll back.
#>

$ErrorActionPreference = 'Stop'

$EnvFile = $env:GHA_RUNNER_ENV_FILE
if (-not $EnvFile) { $EnvFile = 'C:\gha-runner\runner.env.ps1' }
if (Test-Path $EnvFile) { . $EnvFile }

if (-not [Environment]::GetEnvironmentVariable('RUNNER_JITCONFIG', 'Process')) {
    throw 'RUNNER_JITCONFIG is required.'
}

$RunnerDir = if ($env:RUNNER_DIR) { $env:RUNNER_DIR } else { 'C:\actions-runner' }
Set-Location $RunnerDir

if (-not (Test-Path '.\run.cmd')) {
    throw "run.cmd not found in $RunnerDir; bake the runner package before using this script."
}

# The injected config is single-use; remove the env file once read.
Remove-Item $EnvFile -Force -ErrorAction SilentlyContinue

# A vmstate (RAM) snapshot restore freezes the guest clock at snapshot time; a stale clock
# breaks JIT/token auth (GitHub rejects the runner). Step it from an HTTPS Date header
# (fast, small skew doesn't break TLS), then hand off to w32time. Harmless on cold boot.
try {
    $d = (Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 -Uri 'https://github.com').Headers['Date']
    if ($d) { Set-Date -Date ([DateTime]::Parse($d)) | Out-Null }
} catch { }
try { Start-Service w32time -ErrorAction SilentlyContinue; & w32tm /resync /force | Out-Null } catch { }

try {
    .\run.cmd --jitconfig "$env:RUNNER_JITCONFIG"
}
finally {
    Stop-Computer -Force
}
