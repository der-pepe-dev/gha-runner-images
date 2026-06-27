<#
.SYNOPSIS
  Installs the QEMU guest agent from a mounted VirtIO ISO when available.
#>

$ErrorActionPreference = 'Stop'

function Find-QemuGuestAgentMsi {
    $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Z]:\\$' }
    foreach ($drive in $drives) {
        $candidates = @(
            (Join-Path $drive.Root 'guest-agent\qemu-ga-x86_64.msi')
            (Join-Path $drive.Root 'qemu-ga\qemu-ga-x86_64.msi')
        )
        foreach ($candidate in $candidates) {
            if (Test-Path $candidate) {
                return $candidate
            }
        }
    }
    return $null
}

if (Get-Service -Name QEMU-GA -ErrorAction SilentlyContinue) {
    Write-Host 'QEMU guest agent already installed.'
    exit 0
}

$msi = Find-QemuGuestAgentMsi
if (-not $msi) {
    Write-Warning 'QEMU guest agent MSI not found on mounted media. Attach the VirtIO ISO if you want this installed during image build.'
    exit 0
}

Write-Host "Installing QEMU guest agent from $msi"
Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestart" -Wait -NoNewWindow

if (Get-Service -Name QEMU-GA -ErrorAction SilentlyContinue) {
    Set-Service -Name QEMU-GA -StartupType Automatic
    Start-Service -Name QEMU-GA -ErrorAction SilentlyContinue
    Write-Host 'QEMU guest agent installed.'
} else {
    Write-Warning 'QEMU guest agent installer finished, but service was not found.'
}
