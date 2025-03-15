function Invoke-ADPasswordRotation {
    [CmdletBinding()]
    param (
        [Parameter()]
        [int]$PasswordLength = 16,

        [Parameter()]
        [string[]]$ExcludedGroups = @("Domain Admins", "Enterprise Admins"),

        [Parameter()]
        [string[]]$AdditionalExcludedUsers = @(),

        [Parameter()]
        [string]$OutputFile = "$(Get-Location)\password_rotation_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv",

        [Parameter()]
        [switch]$ForceChangeAtLogon,

        [Parameter()]
        [switch]$UnlockAccounts,

        [Parameter()]
        [switch]$EncryptOutput
    )

    begin {
        # Improved password generation function with better entropy
        function New-SecureRandomPassword {
            param ([int]$Length = 16)

            # Character sets
            $upper   = [char[]](65..90)   # A-Z
            $lower   = [char[]](97..122)  # a-z
            $numbers = [char[]](48..57)   # 0-9
            $special = "!@#$%^&*()-_=+[]{}|;:,.<>?".ToCharArray()
            $all     = $upper + $lower + $numbers + $special

            # Ensure at least one from each character set
            $passwordArray = @(
                ($upper   | Get-Random -Count 1) 
                ($lower   | Get-Random -Count 2)
                ($numbers | Get-Random -Count 2)
                ($special | Get-Random -Count 2)
            )

            # Add remaining characters randomly selected from all
            $remainingLength = $Length - $passwordArray.Count
            if ($remainingLength -gt 0) {
                $passwordArray += ($all | Get-Random -Count $remainingLength)
            }

            # Shuffle the characters
            $shuffled = $passwordArray | Get-Random -Count $passwordArray.Count
            
            # Join and return
            return ($shuffled -join '')
        }

        # Initialize statistics
        $stats = @{
            TotalUsers = 0
            Succeeded = 0
            Failed = 0
            StartTime = Get-Date
        }

        # Initialize output collection
        $results = [System.Collections.ArrayList]::new()
        $GroupUserMap = @{}

        # Start transcript logging
        $logFile = "$(Split-Path $OutputFile -Parent)\password_rotation_log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
        Start-Transcript -Path $logFile
        Write-Host "Starting password rotation at $(Get-Date)" -ForegroundColor Cyan
    }

    process {
        try {
            # Import AD module
            Import-Module ActiveDirectory -ErrorAction Stop
            
            # Get excluded users from specified groups
            $excludedUsersList = @()
            foreach ($group in $ExcludedGroups) {
                try {
                    $groupMembers = Get-ADGroupMember -Identity $group -Recursive | Select-Object -ExpandProperty SamAccountName
                    $excludedUsersList += $groupMembers
                }
                catch {
                    Write-Warning "Could not get members of group $group`: $_"
                }
            }
            
            # Add built-in excluded accounts and additional excluded users
            $excludedUsersList += @("Administrator", "krbtgt", "Guest", "DefaultAccount") + $AdditionalExcludedUsers
            $excludedUsersList = $excludedUsersList | Select-Object -Unique
            
            Write-Host "Excluded users: $($excludedUsersList.Count)" -ForegroundColor Yellow
            
            # Get all users to process
            $users = Get-ADUser -Filter * -Properties Enabled, LockedOut | Where-Object {
                ($_.SamAccountName -notin $excludedUsersList) -and
                ($_.Enabled -eq $true)
            }
            
            $stats.TotalUsers = $users.Count
            Write-Host "Found $($users.Count) eligible users for password rotation" -ForegroundColor Cyan
            
            # Initialize output file
            "Username,Password" | Out-File -FilePath $OutputFile -Force
            
            # Process each user
            $currentUser = 0
            foreach ($user in $users) {
                $currentUser++
                Write-Progress -Activity "Rotating Passwords" -Status "$($user.SamAccountName)" -PercentComplete (($currentUser / $users.Count) * 100)
                
                try {
                    # Unlock account if needed and specified
                    if ($UnlockAccounts -and $user.LockedOut) {
                        Unlock-ADAccount -Identity $user.SamAccountName
                        Write-Host "Unlocked account for $($user.SamAccountName)" -ForegroundColor Yellow
                    }
                    
                    # Generate new password
                    $newPassword = New-SecureRandomPassword -Length $PasswordLength
                    $securePassword = ConvertTo-SecureString -String $newPassword -AsPlainText -Force
                    
                    # Set new password
                    Set-ADAccountPassword -Identity $user.SamAccountName -NewPassword $securePassword -Reset
                    
                    # Force password change at next logon if specified
                    if ($ForceChangeAtLogon) {
                        Set-ADUser -Identity $user.SamAccountName -ChangePasswordAtLogon $true
                    }
                    
                    # Record success
                    Write-Host "[$currentUser/$($users.Count)] Reset password for $($user.SamAccountName)" -ForegroundColor Green
                    $stats.Succeeded++
                    
                    # Add to results
                    $null = $results.Add([PSCustomObject]@{
                        Username = $user.SamAccountName
                        Password = $newPassword
                    })
                    
                    # Add to output file
                    "$($user.SamAccountName),$newPassword" | Out-File -FilePath $OutputFile -Append
                    
                    # Get group memberships
                    $userGroups = Get-ADPrincipalGroupMembership -Identity $user | Select-Object -ExpandProperty Name
                    
                    foreach ($groupName in $userGroups) {
                        if (!$GroupUserMap.ContainsKey($groupName)) {
                            $GroupUserMap[$groupName] = [System.Collections.ArrayList]::new()
                        }
                        
                        $null = $GroupUserMap[$groupName].Add([PSCustomObject]@{
                            User = $user.SamAccountName
                            Password = $newPassword
                        })
                    }
                }
                catch {
                    Write-Host "[$currentUser/$($users.Count)] Failed to set password for $($user.SamAccountName): $_" -ForegroundColor Red
                    $stats.Failed++
                }
                
                # Clear sensitive data from memory
                Remove-Variable -Name newPassword -ErrorAction SilentlyContinue
                Remove-Variable -Name securePassword -ErrorAction SilentlyContinue
            }
            
            # Add group information to output file
            Write-Host "`n=== GROUP MEMBERSHIP & PASSWORDS ===" -ForegroundColor Cyan
            foreach ($groupName in $GroupUserMap.Keys | Sort-Object) {
                if ($GroupUserMap[$groupName].Count -gt 0) {
                    "`n`nGroup: $groupName" | Out-File -FilePath $OutputFile -Append
                    Write-Host "`nGroup: $groupName ($($GroupUserMap[$groupName].Count) members)" -ForegroundColor Yellow
                    
                    foreach ($userEntry in $GroupUserMap[$groupName]) {
                        "$($userEntry.User),$($userEntry.Password)" | Out-File -FilePath $OutputFile -Append
                    }
                }
            }
        }
        catch {
            Write-Host "Critical error during password rotation: $_" -ForegroundColor Red
        }
    }

    end {
        # Calculate duration
        $duration = (Get-Date) - $stats.StartTime
        $formattedDuration = "{0:hh\:mm\:ss}" -f $duration
        
        # Display summary
        Write-Host "`n=== PASSWORD ROTATION SUMMARY ===" -ForegroundColor Cyan
        Write-Host "Total users processed: $($stats.TotalUsers)" -ForegroundColor White
        Write-Host "Successful password resets: $($stats.Succeeded)" -ForegroundColor Green
        Write-Host "Failed password resets: $($stats.Failed)" -ForegroundColor Red
        Write-Host "Duration: $formattedDuration" -ForegroundColor White
        Write-Host "Output file: $OutputFile" -ForegroundColor White
        Write-Host "Log file: $logFile" -ForegroundColor White

        # Encrypt the output file if requested
        if ($EncryptOutput -and $stats.Succeeded -gt 0) {
            $encryptedFile = "$OutputFile.secure"
            $bytes = [System.Text.Encoding]::UTF8.GetBytes((Get-Content -Path $OutputFile -Raw))
            $protectedBytes = [System.Security.Cryptography.ProtectedData]::Protect(
                $bytes, 
                $null, 
                [System.Security.Cryptography.DataProtectionScope]::CurrentUser
            )
            [System.IO.File]::WriteAllBytes($encryptedFile, $protectedBytes)
            Remove-Item -Path $OutputFile -Force
            Write-Host "Output file encrypted to: $encryptedFile" -ForegroundColor Green
        }

        # Stop transcript
        Stop-Transcript

        # Clear sensitive data from memory
        Remove-Variable -Name results -ErrorAction SilentlyContinue
        Remove-Variable -Name GroupUserMap -ErrorAction SilentlyContinue
        [System.GC]::Collect()
    }
}
