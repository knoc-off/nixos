# VM Post-Install Setup Script
# Runs at first login via autounattend.xml FirstLogonCommands.
# ASCII-only to avoid Windows PowerShell encoding issues.
# Log: C:\ProgramData\vm-setup.log

$ErrorActionPreference = 'Continue'
$logFile = "$env:ProgramData\vm-setup.log"

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] $msg" | Out-File -Append $logFile -Encoding UTF8
}

Write-Log "=== VM post-install setup starting ==="

# --- 1. Execution policy ---

Write-Log "Setting execution policy to Unrestricted..."
Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope LocalMachine -Force
Write-Log "Execution policy set"

# --- 2. OpenSSH Server (for sshfs access from host) ---

Write-Log "Installing OpenSSH Server..."
$sshCap = Get-WindowsCapability -Online | Where-Object { $_.Name -like 'OpenSSH.Server*' }
if ($sshCap -and $sshCap.State -ne 'Installed') {
    Add-WindowsCapability -Online -Name $sshCap.Name
    Write-Log "OpenSSH Server capability added"
} else {
    Write-Log "OpenSSH Server already installed or not available"
}

Start-Service sshd -ErrorAction SilentlyContinue
Set-Service -Name sshd -StartupType Automatic -ErrorAction SilentlyContinue
Write-Log "sshd service configured for auto-start"

# Deploy SSH public key for passwordless host access.
# The key file is placed on the deploy ISO by Nix at build time.
# Admin users on Windows need the key in ProgramData, not user profile.
$sshDir = "C:\ProgramData\ssh"
$authKeys = "$sshDir\administrators_authorized_keys"
$keyFile = $null

# Find the key file on the same drive as this script, or scan drives
if ($PSCommandPath) {
    $scriptDrive = Split-Path -Qualifier $PSCommandPath
    $candidate = "$scriptDrive\authorized_keys"
    if (Test-Path $candidate) { $keyFile = $candidate }
}
if (-not $keyFile) {
    foreach ($d in 'C','D','E','F','G','H','I','J','K') {
        $candidate = "$d`:\authorized_keys"
        if (Test-Path $candidate) { $keyFile = $candidate; break }
    }
}

if ($keyFile) {
    Write-Log "Found SSH key file: $keyFile"
    if (-not (Test-Path $sshDir)) { mkdir $sshDir -Force | Out-Null }
    Copy-Item $keyFile $authKeys -Force
    # Fix permissions: only SYSTEM and Administrators should read this
    icacls $authKeys /inheritance:r /grant "SYSTEM:(F)" /grant "Administrators:(F)" | Out-Null
    Write-Log "SSH authorized_keys deployed to $authKeys"
} else {
    Write-Log "WARNING: No authorized_keys file found on any drive"
}

# --- 3. VirtIO FS service ---

Write-Log "Configuring VirtioFsSvc..."
sc.exe config VirtioFsSvc start=auto 2>&1 | Out-Null
sc.exe start VirtioFsSvc 2>&1 | Out-Null
Write-Log "VirtioFsSvc configured"

Write-Log "=== VM post-install setup complete ==="
