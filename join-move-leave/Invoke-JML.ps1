[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$CsvPath,

    [string]$ConfigPath = ".\config.json",
    [string]$Domain = "corp.local",
    [string]$LogDir = ".\logs",
    [switch]$DryRun
)
$script:Results = @()

Write-Host "ConfigPath = $ConfigPath"
Import-Module ActiveDirectory -ErrorAction Stop

if (-not (Test-Path $ConfigPath)) {
    throw "Config file not found: $ConfigPath"
}


function Test-Config {
    param($config)

    $requiredDepts = $config.OUMap.PSObject.Properties.Name

    foreach ($dept in $requiredDepts) {
        if (-not $config.GroupMap.$dept) {
            throw "Missing group mapping for department: $dept"
        }
    }
}

$config = Get-Content $ConfigPath | ConvertFrom-Json
Test-Config $config


# Validate required fields
if (-not $config.Domain -or -not $config.OUMap -or -not $config.GroupMap) {
    throw "Invalid config file structure"
}

$Domain    = $config.Domain
$OUMap     = $config.OUMap
$GroupMap  = $config.GroupMap
$DefaultPw = $config.DefaultPassword


$OUMap = @{}
foreach ($key in $config.OUMap.PSObject.Properties.Name) {
    $OUMap[$key.ToUpper()] = $config.OUMap.$key
}

$GroupMap = @{}
foreach ($key in $config.GroupMap.PSObject.Properties.Name) {
    $GroupMap[$key.ToUpper()] = $config.GroupMap.$key
}

# ===== INIT =====
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$LogFile   = Join-Path $LogDir "jml-$timestamp.log"
$JsonLog   = Join-Path $LogDir "jml-$timestamp.json"

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

$Results = @()


function Write-Log {
    param($Level, $Message, $User)

    $entry = [PSCustomObject]@{
        Time = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Level   = $Level
        User    = $User
        Message = $Message
    }

    $script:Results += $entry

    "$($entry.Time) [$Level] [$User] $Message" | Out-File -Append $LogFile
}

function Get-Username {
    param($FirstName, $LastName)
    return ($FirstName.Substring(0,1) + $LastName).ToLower()
}

function Get-ADUserSafe {
    param($Username)
    try {
        return Get-ADUser -Identity $Username -Properties MemberOf -ErrorAction Stop
    } catch {
        return $null
    }
}

# ===== VALIDATION =====
if (-not (Test-Path $CsvPath)) {
    throw "CSV file not found: $CsvPath"
}

$users = Import-Csv $CsvPath

if (-not $users) {
    throw "CSV is empty or invalid"
}

# ===== JOINER =====
function Process-Joiner {
    param($User)

    $username = Get-Username $User.FirstName $User.LastName
        
    $deptRaw = $User.Department

    if (-not $deptRaw) {
        Write-Log "ERROR" "Missing Department field" $username
        return
    }

    $dept = $deptRaw.Trim().ToUpper()

    $ou = $OUMap[$dept]

    if (-not $ou) {
        Write-Log "ERROR" "No OU mapping for department: '$deptRaw' (normalized: '$dept')" $username
        return
    }


    if (Get-ADUserSafe $username) {
        Write-Log "INFO" "User exists, skipping creation" $username
        return
    }

    try {
        if ($DryRun) {
            Write-Log "DRYRUN" "Would create user in $ou" $username
        } else {
            New-ADUser `
                -Name "$($User.FirstName) $($User.LastName)" `
                -GivenName $User.FirstName `
                -Surname $User.LastName `
                -SamAccountName $username `
                -UserPrincipalName "$username@$Domain" `
                -Path $ou `
                -AccountPassword (ConvertTo-SecureString $DefaultPw -AsPlainText -Force) `
                -Enabled $true `
                -ChangePasswordAtLogon $true

            Write-Log "SUCCESS" "User created" $username
        }

        Set-UserGroups -Username $username -Department $User.Department

    } catch {
        Write-Log "ERROR" $_.Exception.Message $username
    }
}

# ===== MOVER =====
function Process-Mover {
    param($User)

    $username = Get-Username $User.FirstName $User.LastName
    $adUser = Get-ADUserSafe $username

    if (-not $adUser) {
        Write-Log "ERROR" "User not found for move" $username
        return
    }

    $deptRaw = $User.Department

    if (-not $deptRaw) {
        Write-Log "ERROR" "Missing Department field" $username
        return
    }

    $dept = $deptRaw.Trim().ToUpper()

    $ou = $OUMap[$dept]

    if (-not $ou) {
        Write-Log "ERROR" "No OU mapping for department: '$deptRaw' (normalized: '$dept')" $username
        return
    }
    try {
        if ($DryRun) {
            Write-Log "DRYRUN" "Would move to $ou" $username
        } else {
            Move-ADObject -Identity $adUser.DistinguishedName -TargetPath $ou
            Write-Log "SUCCESS" "User moved to $ou" $username
        }

        Set-UserGroups -Username $username -Department $User.Department

    } catch {
        Write-Log "ERROR" $_.Exception.Message $username
    }
}

# ===== LEAVER =====
function Process-Leaver {
    param($User)

    $username = Get-Username $User.FirstName $User.LastName

    try {
        if ($DryRun) {
            Write-Log "DRYRUN" "Would disable account" $username
        } else {
            Disable-ADAccount -Identity $username
            Write-Log "SUCCESS" "Account disabled" $username
        }
    } catch {
        Write-Log "ERROR" $_.Exception.Message $username
    }
}

# ===== GROUP MANAGEMENT =====
function Set-UserGroups {
    param($Username, $Department)

    $desiredGroups = $GroupMap[$Department]
    if (-not $desiredGroups) { return }

    $user = Get-ADUserSafe $Username
    $currentGroups = $user.MemberOf | ForEach-Object {
        (Get-ADGroup $_).Name
    }

    foreach ($group in $desiredGroups) {
        if ($currentGroups -notcontains $group) {
            if ($DryRun) {
                Write-Log "DRYRUN" "Would add to $group" $Username
            } else {
                Add-ADGroupMember -Identity $group -Members $Username
                Write-Log "SUCCESS" "Added to $group" $Username
            }
        }
    }

    foreach ($group in $currentGroups) {
        if ($GroupMap.Values -contains $group -and $desiredGroups -notcontains $group) {
            if ($DryRun) {
                Write-Log "DRYRUN" "Would remove from $group" $Username
            } else {
                Remove-ADGroupMember -Identity $group -Members $Username -Confirm:$false
                Write-Log "SUCCESS" "Removed from $group" $Username
            }
        }
    }
}

# ===== MAIN =====
foreach ($user in $users) {
    switch ($user.Status) {
        "Joiner" { Process-Joiner $user }
        "Mover"  { Process-Mover $user }
        "Leaver" { Process-Leaver $user }
        default  { Write-Log "WARN" "Unknown status: $($user.Status)" $user.FirstName }
    }
}

# ===== EXPORT REPORT =====
$Results | ConvertTo-Json -Depth 3 | Out-File $JsonLog

Write-Host "Execution complete"
Write-Host "Log: $LogFile"
Write-Host "JSON Report: $JsonLog"