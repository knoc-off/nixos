# VM Post-Install Setup Script
# Runs at first login via autounattend.xml FirstLogonCommands.
# Installs VirtIO guest tools, WinFSP, and starts the VirtIO FS service.
# Log: C:\ProgramData\vm-setup.log

$ErrorActionPreference = 'Continue'
$logFile = "$env:ProgramData\vm-setup.log"

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $msg" | Out-File -Append $logFile -Encoding UTF8
}

Write-Log "=== VM post-install setup starting ==="

# --- 1. VirtIO Guest Tools (all drivers + SPICE agent + VirtIO FS driver) ---

Write-Log "Searching for virtio-win-guest-tools.exe..."
$installed = $false

# The deploy ISO bundles the exe alongside this script, so check our own
# drive first.  Fall back to scanning all letters just in case.
$searchOrder = @()
if ($PSCommandPath) {
    $scriptDrive = Split-Path -Qualifier $PSCommandPath
    $searchOrder += $scriptDrive.TrimEnd(':')
    Write-Log "Script is running from $scriptDrive"
}
foreach ($d in 'C','D','E','F','G','H','I','J','K') {
    if ($d -notin $searchOrder) { $searchOrder += $d }
}

foreach ($d in $searchOrder) {
    $exe = "$d`:\virtio-win-guest-tools.exe"
    if (Test-Path $exe) {
        Write-Log "Found: $exe — installing..."
        $proc = Start-Process -FilePath $exe -ArgumentList '/S' -Wait -NoNewWindow -PassThru
        Write-Log "VirtIO guest tools exited with code $($proc.ExitCode)"
        $installed = $true
        break
    }
}
if (-not $installed) { Write-Log "WARNING: virtio-win-guest-tools.exe not found on any drive" }

# --- 2. Wait for network ---

# Guest tools just installed network drivers — give the adapter time to
# get a DHCP lease before we start testing connectivity.
Write-Log "Waiting for network (10s grace period for DHCP)..."
Start-Sleep -Seconds 10

$online = $false
for ($i = 0; $i -lt 30; $i++) {
    try {
        $null = Invoke-WebRequest -Uri "https://github.com" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        $online = $true; break
    } catch { Start-Sleep -Seconds 2 }
}
if ($online) { Write-Log "Network is up" }
else         { Write-Log "WARNING: No network after 70s, skipping WinFSP download" }

# --- 3. WinFSP (virtiofs shared folder support) ---

if ($online) {
    Write-Log "Fetching latest WinFSP release..."
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $release = Invoke-RestMethod "https://api.github.com/repos/winfsp/winfsp/releases/latest"
        $msiUrl = ($release.assets | Where-Object { $_.name -like "winfsp-*.msi" } |
                   Select-Object -First 1).browser_download_url
        if ($msiUrl) {
            $msiPath = "$env:TEMP\winfsp.msi"
            Write-Log "Downloading $msiUrl"
            Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -UseBasicParsing
            $proc = Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /quiet /norestart" -Wait -NoNewWindow -PassThru
            Write-Log "WinFSP exited with code $($proc.ExitCode)"
            Remove-Item $msiPath -ErrorAction SilentlyContinue
        } else { Write-Log "WARNING: No WinFSP MSI found in release assets" }
    } catch { Write-Log "WARNING: WinFSP install failed: $_" }
}

# --- 4. VirtIO FS service ---

Write-Log "Configuring VirtioFsSvc..."
Start-Sleep -Seconds 5
sc.exe config VirtioFsSvc start=auto 2>&1 | Out-Null
sc.exe start VirtioFsSvc 2>&1 | Out-Null
Write-Log "VirtioFsSvc configured"

Write-Log "=== VM post-install setup complete ==="
