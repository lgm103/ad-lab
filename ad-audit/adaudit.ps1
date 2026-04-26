[CmdletBinding()]
param(
    [int]$InactiveDays = 30,
    [string]$OutputDir = ".\reports"
)

Import-Module ActiveDirectory -ErrorAction Stop

# ===== INIT =====
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$Summary = @{
    TotalUsers = 0
    InactiveUsers = 0
    PasswordNeverExpires = 0
    DisabledUsers = 0
    PrivilegedUsers = 0
    StaleComputers = 0
}

# ===== HELPERS =====
function Get-InactiveUsers {
    param($Days)

    $cutoff = (Get-Date).AddDays(-$Days)

    Get-ADUser -Filter * -Properties LastLogonDate |
        Where-Object { $_.LastLogonDate -lt $cutoff -and $_.Enabled -eq $true }
}

# ===== 1. INACTIVE USERS =====
$inactive = Get-InactiveUsers -Days $InactiveDays
$inactive | Select Name, SamAccountName, LastLogonDate |
    Export-Csv "$OutputDir\inactive-users-$timestamp.csv" -NoTypeInformation

$Summary.InactiveUsers = $inactive.Count

# ===== 2. PASSWORD NEVER EXPIRES =====
$pwdNeverExpires = Get-ADUser -Filter { PasswordNeverExpires -eq $true } -Properties PasswordNeverExpires

$pwdNeverExpires | Select Name, SamAccountName |
    Export-Csv "$OutputDir\password-never-expires-$timestamp.csv" -NoTypeInformation

$Summary.PasswordNeverExpires = $pwdNeverExpires.Count

# ===== 3. DISABLED USERS =====
$disabled = Get-ADUser -Filter { Enabled -eq $false }

$disabled | Select Name, SamAccountName |
    Export-Csv "$OutputDir\disabled-users-$timestamp.csv" -NoTypeInformation

$Summary.DisabledUsers = $disabled.Count

# ===== 4. PRIVILEGED GROUPS =====
$privGroups = @("Domain Admins", "Enterprise Admins", "Administrators")

$privUsers = @()

foreach ($group in $privGroups) {
    try {
        $members = Get-ADGroupMember -Identity $group -Recursive |
            Where-Object { $_.objectClass -eq "user" }

        foreach ($m in $members) {
            $privUsers += [PSCustomObject]@{
                Group = $group
                Name  = $m.Name
                SamAccountName = $m.SamAccountName
            }
        }
    } catch {
        Write-Warning "Group not found: $group"
    }
}

$privUsers | Export-Csv "$OutputDir\privileged-users-$timestamp.csv" -NoTypeInformation
$Summary.PrivilegedUsers = $privUsers.Count

# ===== 5. STALE COMPUTERS =====
$staleCutoff = (Get-Date).AddDays(-$InactiveDays)

$staleComputers = Get-ADComputer -Filter * -Properties LastLogonDate |
    Where-Object { $_.LastLogonDate -lt $staleCutoff }

$staleComputers | Select Name, LastLogonDate |
    Export-Csv "$OutputDir\stale-computers-$timestamp.csv" -NoTypeInformation

$Summary.StaleComputers = $staleComputers.Count

# ===== TOTAL USERS =====
$Summary.TotalUsers = (Get-ADUser -Filter *).Count

# ===== SUMMARY OUTPUT =====
Write-Host "`n=== AD Audit Summary ==="
$Summary.GetEnumerator() | ForEach-Object {
    Write-Host "$($_.Key): $($_.Value)"
}

# Save summary
$Summary | ConvertTo-Json | Out-File "$OutputDir\summary-$timestamp.json"

Write-Host "`nReports saved to: $OutputDir"