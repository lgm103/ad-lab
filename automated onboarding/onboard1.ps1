$users = Import-Csv "new_users.csv"
$logFile = "onboarding.log"

# Using a List for better performance
$results = New-Object System.Collections.Generic.List[PSCustomObject]

$ouMap = @{
    "IT"          = "OU=IT,OU=Users,OU=Corp,DC=corp,DC=local"
    "HR"          = "OU=HR,OU=Users,OU=Corp,DC=corp,DC=local"
    "Finance"     = "OU=Finance,OU=Users,OU=Corp,DC=corp,DC=local"
    "Accounting"  = "OU=Accounting,OU=Users,OU=Corp,DC=corp,DC=local"
    "Sales"       = "OU=Sales,OU=Users,OU=Corp,DC=corp,DC=local"
    "Marketing"   = "OU=Marketing,OU=Users,OU=Corp,DC=corp,DC=local"
    "Engineering" = "OU=Engineering, OU=Users,OU=Corp,DC=corp,DC=local"
}

function Get-UniqueUsername {
    param($baseUsername)
    $username = $baseUsername
    $i = 1
    # Fixed Filter syntax
    while (Get-ADUser -Filter "SamAccountName -eq '$username'" -ErrorAction SilentlyContinue) {
        $username = "$baseUsername$i"
        $i++
    }
    return $username
}

foreach ($user in $users) {
    # Validate CSV data
    if ([string]::IsNullOrWhiteSpace($user.FirstName) -or [string]::IsNullOrWhiteSpace($user.LastName) -or [string]::IsNullOrWhiteSpace($user.Department)) {
        $results.Add([PSCustomObject]@{
            Name     = "$($user.FirstName) $($user.LastName)"
            Username = "N/A"
            Status   = "Failed"
            Message  = "Missing required fields"
        })
        continue
    }

    if (-not $ouMap.ContainsKey($user.Department)) {
        $results.Add([PSCustomObject]@{
            Name     = "$($user.FirstName) $($user.LastName)"
            Username = "N/A"
            Status   = "Failed"
            Message  = "Invalid department: $($user.Department)"
        })
        continue
    }

    $baseUsername = ($user.FirstName.Substring(0,1) + $user.LastName).ToLower().Replace(" ", "")
    $username = Get-UniqueUsername $baseUsername

    try {
        $userParams = @{
            Name                  = "$($user.FirstName) $($user.LastName)"
            GivenName             = $user.FirstName
            Surname               = $user.LastName
            SamAccountName        = $username
            UserPrincipalName     = "$username@corp.local"
            AccountPassword       = (ConvertTo-SecureString "TempP@ss123!" -AsPlainText -Force)
            Enabled               = $true
            Path                  = $ouMap[$user.Department]
            ChangePasswordAtLogon = $true # Better Security
        }

        New-ADUser @userParams
        
        # Identity can be the name from the groupMap
        Add-ADGroupMember -Identity $user.Department -Members $username

        $status = "Created"
        $message = "Success"
    } catch {
        $status = "Failed"
        $message = $_.Exception.Message
    }

    # Logging & Reporting
    $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $username | $status | $message"
    Add-Content $logFile $logEntry

    $results.Add([PSCustomObject]@{
        Name     = "$($user.FirstName) $($user.LastName)"
        Username = $username
        Status   = $status
        Message  = $message
    })
}

# Display results to console
$results | Out-GridView -Title "Onboarding Results"