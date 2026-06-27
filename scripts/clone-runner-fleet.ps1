<#
.SYNOPSIS
  Example helper for cloning the default non-HA runner fleet.

.DESCRIPTION
  Clones one Linux runner and one Windows runner per Proxmox node:
    gha-linux01 / gha-win01 on pve01
    gha-linux02 / gha-win02 on pve02
    gha-linux03 / gha-win03 on pve03

  The recommended orchestration model is one tiny local orchestrator per node:
    gha-orch01 on pve01 manages gha-linux01 and gha-win01
    gha-orch02 on pve02 manages gha-linux02 and gha-win02
    gha-orch03 on pve03 manages gha-linux03 and gha-win03

  This script is intentionally a scaffold. It uses environment variables for the
  Proxmox API token and a simple YAML file for runner definitions.

.NOTES
  Requires PowerShell 7. For YAML parsing, install powershell-yaml or replace
  the ConvertFrom-Yaml call with your preferred parser.
#>

param(
    [string]$FleetFile = "$PSScriptRoot/fleet.local.yml",
    [switch]$IncludeOrchestrators
)

$ErrorActionPreference = 'Stop'

$ApiTokenId = $env:PROXMOX_TOKEN_ID
$ApiToken   = $env:PROXMOX_TOKEN

if (-not $ApiTokenId -or -not $ApiToken) {
    throw 'Set PROXMOX_TOKEN_ID and PROXMOX_TOKEN.'
}

if (-not (Test-Path $FleetFile)) {
    throw "Fleet file not found: $FleetFile. Copy fleet.example.yml to fleet.local.yml first."
}

if (-not (Get-Command ConvertFrom-Yaml -ErrorAction SilentlyContinue)) {
    throw 'ConvertFrom-Yaml not found. Install the powershell-yaml module or adapt this script.'
}

$fleet = Get-Content $FleetFile -Raw | ConvertFrom-Yaml

$headers = @{
    Authorization = "PVEAPIToken=$ApiTokenId=$ApiToken"
}

function New-ProxmoxVmClone {
    param(
        [Parameter(Mandatory)]$Item,
        [Parameter(Mandatory)][int]$TemplateVmid
    )

    $full = if ($fleet.full_clone) { 1 } else { 0 }

    $body = @{
        newid  = $Item.vmid
        name   = $Item.name
        full   = $full
        target = $Item.node
    }

    if ($fleet.storage) {
        $body.storage = $fleet.storage
    }

    $uri = "$($fleet.proxmox_url)/nodes/$($Item.node)/qemu/$TemplateVmid/clone"
    Write-Host "Cloning template $TemplateVmid to $($Item.name) on $($Item.node) as VMID $($Item.vmid)"
    # -SkipCertificateCheck: PVE default certs are self-signed (mirrors curl -k in the
    # orchestrator and insecure_skip_tls_verify in the Packer builds). PowerShell 7 only.
    Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body -SkipCertificateCheck
}

if ($IncludeOrchestrators -and $fleet.orchestrators) {
    foreach ($orch in $fleet.orchestrators) {
        New-ProxmoxVmClone -Item $orch -TemplateVmid ([int]$fleet.orchestrator_template_vmid)
    }
}

foreach ($runner in $fleet.runners) {
    $templateVmid = if ($runner.template -eq 'windows') { [int]$fleet.windows_template_vmid } else { [int]$fleet.linux_template_vmid }
    New-ProxmoxVmClone -Item $runner -TemplateVmid $templateVmid
}
