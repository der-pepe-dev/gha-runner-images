<#
.SYNOPSIS
  Requests a GitHub Actions repo-level self-hosted runner registration token.

.REQUIRED ENVIRONMENT VARIABLES
  GITHUB_TOKEN
  GITHUB_OWNER
  GITHUB_REPO
#>

$ErrorActionPreference = 'Stop'

$Token = $env:GITHUB_TOKEN
$Owner = $env:GITHUB_OWNER
$Repo  = $env:GITHUB_REPO

if (-not $Token -or -not $Owner -or -not $Repo) {
    throw 'Set GITHUB_TOKEN, GITHUB_OWNER, and GITHUB_REPO.'
}

$headers = @{
    Authorization          = "Bearer $Token"
    Accept                 = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
}

$response = Invoke-RestMethod `
    -Method Post `
    -Uri "https://api.github.com/repos/$Owner/$Repo/actions/runners/registration-token" `
    -Headers $headers

$response.token
