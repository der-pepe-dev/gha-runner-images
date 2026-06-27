<#
.SYNOPSIS
  Installs the virtio drivers + QEMU guest agent from a mounted virtio-win ISO.

.NOTES
  The guest agent talks to the host over a virtio-serial channel, which needs the
  vioser driver. Installing the agent MSI alone leaves the service unable to reach
  the host ("agent not running" in Proxmox), so the Packer builder never gets the
  VM IP. This installs the virtio drivers first, then the agent.
#>

$ErrorActionPreference = 'Stop'

function Find-VirtioMedia {
    # Return the drive root of the mounted virtio-win media, or $null.
    foreach ($drive in (Get-PSDrive -PSProvider FileSystem)) {
        $root = $drive.Root
        if ((Test-Path (Join-Path $root 'guest-agent\qemu-ga-x86_64.msi')) -or
            (Test-Path (Join-Path $root 'vioserial'))) {
            return $root
        }
    }
    return $null
}

$media = Find-VirtioMedia
if (-not $media) {
    Write-Warning 'virtio-win media not found on any drive. Attach the virtio-win ISO.'
    exit 0
}

# 1a. Pre-trust the virtio driver publisher (Red Hat) so the driver install does NOT
#     pop an interactive "Would you like to install this device software?" dialog,
#     which would hang the unattended build. Import the signer cert from a signed
#     virtio driver into the machine TrustedPublisher (and Root) stores.
try {
    $sig = Get-ChildItem -Path $media -Recurse -Filter *.sys -ErrorAction SilentlyContinue |
           ForEach-Object { Get-AuthenticodeSignature $_.FullName -ErrorAction SilentlyContinue } |
           Where-Object { $_.SignerCertificate } |
           Select-Object -First 1
    if ($sig -and $sig.SignerCertificate) {
        foreach ($storeName in 'TrustedPublisher', 'Root') {
            $store = New-Object System.Security.Cryptography.X509Certificates.X509Store($storeName, 'LocalMachine')
            $store.Open('ReadWrite')
            $store.Add($sig.SignerCertificate)
            $store.Close()
        }
        Write-Host "Trusted virtio driver publisher: $($sig.SignerCertificate.Subject)"
    } else {
        Write-Warning 'No signed virtio driver found to pre-trust; install may prompt.'
    }
} catch {
    Write-Warning "Could not pre-trust virtio publisher: $($_.Exception.Message)"
}

# 1b. Install the virtio drivers. vioser is required so the guest agent can reach the
#     host; pnputil installs only the ones matching present devices.
Write-Host "Installing virtio drivers from $media"
& pnputil /add-driver (Join-Path $media '*.inf') /subdirs /install
Write-Host "pnputil exit code: $LASTEXITCODE"

# 2. Install the QEMU guest agent.
$msi = Join-Path $media 'guest-agent\qemu-ga-x86_64.msi'
if (Test-Path $msi) {
    Write-Host "Installing QEMU guest agent from $msi"
    Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestart" -Wait -NoNewWindow
} else {
    Write-Warning "Guest agent MSI not found at $msi"
}

# 3. Ensure the service is set to run.
if (Get-Service -Name QEMU-GA -ErrorAction SilentlyContinue) {
    Set-Service -Name QEMU-GA -StartupType Automatic
    Start-Service -Name QEMU-GA -ErrorAction SilentlyContinue
    Write-Host 'QEMU guest agent installed and started.'
} else {
    Write-Warning 'QEMU-GA service not found after install.'
}
