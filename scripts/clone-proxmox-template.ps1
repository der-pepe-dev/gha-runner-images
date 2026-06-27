<#
.SYNOPSIS
  Example helper showing how to clone a Proxmox template through the Proxmox API.

.NOTES
  Placeholder script. Review and adapt before real use.
  Do not hardcode real tokens in this file.
#>

$ErrorActionPreference = 'Stop'

$ProxmoxUrl = $env:PROXMOX_URL      # e.g. https://pve.example.local:8006/api2/json
$ApiTokenId = $env:PROXMOX_TOKEN_ID # e.g. packer@pve!packer
$ApiToken   = $env:PROXMOX_TOKEN    # token secret
$Node       = $env:PROXMOX_NODE     # e.g. pve
$SourceVmId = $env:SOURCE_VM_ID     # template VMID
$NewVmId    = $env:NEW_VM_ID
$NewVmName  = $env:NEW_VM_NAME

if (-not $ProxmoxUrl -or -not $ApiTokenId -or -not $ApiToken -or -not $Node -or -not $SourceVmId -or -not $NewVmId -or -not $NewVmName) {
    throw 'Set PROXMOX_URL, PROXMOX_TOKEN_ID, PROXMOX_TOKEN, PROXMOX_NODE, SOURCE_VM_ID, NEW_VM_ID, and NEW_VM_NAME.'
}

$headers = @{
    Authorization = "PVEAPIToken=$ApiTokenId=$ApiToken"
}

$body = @{
    newid = $NewVmId
    name  = $NewVmName
    full  = 1
}

$uri = "$ProxmoxUrl/nodes/$Node/qemu/$SourceVmId/clone"
Write-Host "Cloning template VMID $SourceVmId to VMID $NewVmId named $NewVmName"
# -SkipCertificateCheck: PVE default certs are self-signed (mirrors curl -k in the
# orchestrator and insecure_skip_tls_verify in the Packer builds). PowerShell 7 only.
Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body -SkipCertificateCheck
