[CmdletBinding()]
param(
    [string]$Domain = "corp.local",
    [string]$TargetOU = "OU=Workstations, OU = Computers, OU = Corp, DC = corp, DC = local"
)

Import-Module GroupPolicy -ErrorAction Stop

# ===== CONFIG =====
$GPOName = "GPO - Workstations - Baseline Security Policy"

# ===== CREATE OR GET GPO =====
$gpo = Get-GPO -Name $GPOName -ErrorAction SilentlyContinue

if (-not $gpo) {
    Write-Host "Creating GPO: $GPOName"
    $gpo = New-GPO -Name $GPOName
} else {
    Write-Host "GPO already exists: $GPOName"
}

# ===== PASSWORD POLICY =====
# NOTE: These apply at domain level in real environments,
# but included here for demonstration

Write-Host "Configuring password policy..."

Set-GPRegistryValue -Name $GPOName `
    -Key "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
    -ValueName "MinimumPasswordLength" `
    -Type DWord `
    -Value 12

Set-GPRegistryValue -Name $GPOName `
    -Key "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
    -ValueName "PasswordComplexity" `
    -Type DWord `
    -Value 1

# ===== ACCOUNT LOCKOUT =====
Write-Host "Configuring account lockout..."

Set-GPRegistryValue -Name $GPOName `
    -Key "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
    -ValueName "LockoutBadCount" `
    -Type DWord `
    -Value 5

# ===== BASIC HARDENING =====
Write-Host "Applying basic hardening..."

# Disable removable storage (example)
Set-GPRegistryValue -Name $GPOName `
    -Key "HKLM\SYSTEM\CurrentControlSet\Services\USBSTOR" `
    -ValueName "Start" `
    -Type DWord `
    -Value 4

# ===== LINK GPO =====
Write-Host "Linking GPO to $TargetOU..."

New-GPLink -Name $GPOName -Target $TargetOU -LinkEnabled Yes -Enforced Yes -ErrorAction SilentlyContinue

Write-Host "`nGPO baseline deployment complete."