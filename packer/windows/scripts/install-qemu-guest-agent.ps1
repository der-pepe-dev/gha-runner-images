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
#     which would hang the unattended build. virtio drivers are CATALOG-signed, so the
#     signer cert lives in the .cat files (the .sys have no embedded signature). Import
#     every unique catalog signer cert into the machine TrustedPublisher (and Root).
try {
    $certs = @{}
    Get-ChildItem -Path $media -Recurse -Filter *.cat -ErrorAction SilentlyContinue |
        ForEach-Object {
            $s = Get-AuthenticodeSignature $_.FullName -ErrorAction SilentlyContinue
            if ($s -and $s.SignerCertificate) {
                $certs[$s.SignerCertificate.Thumbprint] = $s.SignerCertificate
            }
        }
    if ($certs.Count -gt 0) {
        foreach ($storeName in 'TrustedPublisher', 'Root') {
            $store = New-Object System.Security.Cryptography.X509Certificates.X509Store($storeName, 'LocalMachine')
            $store.Open('ReadWrite')
            foreach ($c in $certs.Values) { $store.Add($c) }
            $store.Close()
        }
        Write-Host "Pre-trusted $($certs.Count) virtio publisher cert(s)."
    } else {
        Write-Warning 'No virtio catalog signer cert found; driver install may prompt.'
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

# pnputil returns non-zero when some bundled drivers match no device (normal when
# installing the whole virtio set). That is not a failure here, so exit explicitly so
# a stray $LASTEXITCODE does not fail the build.
exit 0
