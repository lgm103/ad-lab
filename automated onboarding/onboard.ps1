$users = Import-Csv "new_users.csv"
$results = @()
$logFile = "onboarding.log"

$ouMap = @{
    "IT" = "OU=IT, OU=Users, OU= Corp, DC=corp, DC=local"
    "HR" = "OU=HR, OU=Users, OU= Corp, DC=corp, DC=local"
    "Finance" = "OU=Finance, OU=Users, OU= Corp, DC=corp, DC=local"
}

$groupMap = @{
    "IT" = "IT"
    "HR" = "HR"
    "Finance" = "Finance"
}

function Get-UniqueUsername {
    param($baseUsername)

    $username = $baseUsername
    $i = 1

    while (Get-ADUser -Filter { SamAccountName -eq $username } -ErrorAction SilentlyContinue) {
        $username = "$baseUsername$i"
        $i++
    }

    return $username
}

foreach ($user in $users) {


    if (-not $user.FirstName -or -not $user.LastName -or -not $user.Department) {
        $results += [PSCustomObject]@{
            Name     = "$($user.FirstName) $($user.LastName)"
            Username = "N/A"
            Status   = "Failed"
            Message  = "Missing required fields"
        }
        continue
    }

    if (-not $ouMap.ContainsKey($user.Department)) {
        $results += [PSCustomObject]@{
            Name     = "$($user.FirstName) $($user.LastName)"
            Username = "N/A"
            Status   = "Failed"
            Message  = "Invalid department"
        }
        continue
    }

    $baseUsername = ($user.FirstName.Substring(0,1) + $user.LastName).ToLower()
    $username = Get-UniqueUsername $baseUsername
    $existingUser = Get-ADUser -Filter { SamAccountName -eq $username } -ErrorAction SilentlyContinue

    if ($existingUser) {
        $results += [PSCustomObject]@{
            Name     = "$($user.FirstName) $($user.LastName)"
            Username = $username
            Status   = "Skipped"
            Message  = "User already exists"
        }
        continue
    }

    try {
        New-ADUser `
            -Name "$($user.FirstName) $($user.LastName)" `
            -GivenName $user.FirstName `
            -Surname $user.LastName `
            -SamAccountName $username `
            -UserPrincipalName "$username@corp.local" `
            -AccountPassword (ConvertTo-SecureString "TempP@ss123!" -AsPlainText -Force) `
            -Enabled $true `
            -Path $ouMap[$user.Department]

        Add-ADGroupMember `
            -Identity $groupMap[$user.Department] `
            -Members $username

        $status = "Created"
        $message = "Success"

    } catch {
        $status = "Failed"
        $message = $_.Exception.Message
    }

    # Logging
    $logEntry = "$(Get-Date) | $username | $status | $message"
    Add-Content $logFile $logEntry

    # Reporting object
    $results += [PSCustomObject]@{
        Name     = "$($user.FirstName) $($user.LastName)"
        Username = $username
        Status   = $status
        Message  = $message
    }
}

# Export report
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$results | Export-Csv "onboarding_report_$timestamp.csv" -NoTypeInformation