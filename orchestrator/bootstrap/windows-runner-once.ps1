<#
.SYNOPSIS
  One-shot ephemeral GitHub Actions runner bootstrap for Windows.

.DESCRIPTION
  Intended to run inside a disposable Windows runner VM after the local
  orchestrator injects environment variables or C:\gha-runner\runner.env.ps1.
#>

$ErrorActionPreference = 'Stop'

$EnvFile = $env:GHA_RUNNER_ENV_FILE
if (-not $EnvFile) { $EnvFile = 'C:\gha-runner\runner.env.ps1' }
if (Test-Path $EnvFile) { . $EnvFile }

foreach ($name in @('RUNNER_URL', 'RUNNER_TOKEN', 'RUNNER_NAME', 'RUNNER_LABELS')) {
    if (-not [Environment]::GetEnvironmentVariable($name, 'Process')) {
        throw "$name is required."
    }
}

$RunnerDir = if ($env:RUNNER_DIR) { $env:RUNNER_DIR } else { 'C:\actions-runner' }
$RunnerWorkDir = if ($env:RUNNER_WORK_DIR) { $env:RUNNER_WORK_DIR } else { 'C:\actions-work' }

New-Item -ItemType Directory -Force -Path $RunnerDir, $RunnerWorkDir | Out-Null
Set-Location $RunnerDir

if (-not (Test-Path '.\config.cmd')) {
    throw "config.cmd not found in $RunnerDir; bake or extract the runner package before using this script."
}

try {
    # --disableupdate: the auto-update restart deletes the one-shot --ephemeral
    # registration mid-update; disable it so the ephemeral runner stays registered.
    .\config.cmd `
        --unattended `
        --ephemeral `
        --disableupdate `
        --url "$env:RUNNER_URL" `
        --token "$env:RUNNER_TOKEN" `
        --name "$env:RUNNER_NAME" `
        --labels "$env:RUNNER_LABELS" `
        --work "$RunnerWorkDir" `
        --replace

    .\run.cmd
}
finally {
    .\config.cmd remove --unattended --token "$env:RUNNER_TOKEN" 2>$null | Out-Null
    Stop-Computer -Force
}
