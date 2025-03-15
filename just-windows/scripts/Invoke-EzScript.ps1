function Show-SecurityBanner {
    Write-Output '
    ________             ______                       __             __     
    |        \           /      \                     |  \           |  \    
    | $$$$$$$$ ________ |  $$$$$$\  _______   ______   \$$  ______  _| $$_   
    | $$__    |        \| $$___\$$ /       \ /      \ |  \ /      \|   $$ \  
    | $$  \    \$$$$$$$$ \$$    \ |  $$$$$$$|  $$$$$$\| $$|  $$$$$$\\$$$$$$  
    | $$$$$     /    $$  _\$$$$$$\| $$      | $$   \$$| $$| $$  | $$ | $$ __ 
    | $$_____  /  $$$$_ |  \__| $$| $$_____ | $$      | $$| $$__/ $$ | $$|  \
    | $$     \|  $$    \ \$$    $$ \$$     \| $$      | $$| $$    $$  \$$  $$
     \$$$$$$$$ \$$$$$$$$  \$$$$$$   \$$$$$$$ \$$       \$$| $$$$$$$    \$$$$ 
                                                          | $$               
                                                          | $$               
                                                           \$$         
                                                                    BY: Keyboard Cowboys
'
}


function Initialize-SecurityDirectory {
    $script:logPath = "C:\Program Files\SecurityConfig"
    New-Item -ItemType Directory -Path $logPath -Force
}

# Write-SecurityLog
<#
.SYNOPSIS
    Writes a message to the security log file.

.DESCRIPTION
    Logs security-related events and messages to component-specific log files
    within the security configuration directory.

.PARAMETER Component
    The name of the component generating the log entry.

.PARAMETER Message
    The message to be logged.

.PARAMETER Level
    The severity level of the log entry. Valid values are 'Info', 'Error', and 'Warning'.
    Defaults to 'Info'.

.EXAMPLE
    Write-SecurityLog -Component "Firewall" -Message "Rule successfully added" -Level Info
#>
function Write-SecurityLog {
    [CmdletBinding()]
    param(
        [string]$Component,
        [string]$Message,
        [ValidateSet('Info', 'Error', 'Warning')]
        [string]$Level = 'Info'
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logFile = Join-Path $script:logPath "$Component.log"
    "$timestamp [$Level] - $Message" | Out-File $logFile -Append
    
    switch($Level) {
        'Error' { Write-Error $Message }
        'Warning' { Write-Warning $Message }
        default { Write-Output $Message }
    }
}

# Set-AuditPolicy
<#
.SYNOPSIS
    Configures Windows audit policies.

.DESCRIPTION
    Sets up comprehensive auditing policies for various security-related categories
    including account logon events, account management, object access, and system events.

.NOTES
    Requires administrative privileges to modify audit policies.
    Uses the auditpol.exe command-line tool.

.EXAMPLE
    Set-AuditPolicy
#>
function Set-AuditPolicy {
    Write-Verbose "Configuring audit policies..."
    try {
        $categories = @(
            "Account Logon", "Account Management", "DS Access",
            "Logon/Logoff", "Object Access", "Policy Change",
            "Privilege Use", "Detailed Tracking", "System"
        )

        foreach ($category in $categories) {
            auditpol /set /category:"$category" /success:enable /failure:enable
        }
        Write-SecurityLog -Component "AuditPolicy" -Message "Successfully configured audit policies"
    }
    catch {
        Write-SecurityLog -Component "AuditPolicy" -Message $_.Exception.Message -Level Error
    }
}

# Set-ZerologonMitigation
<#
.SYNOPSIS
    Implements mitigations for the Zerologon vulnerability.

.DESCRIPTION
    Configures registry settings and monitoring to protect against the Zerologon
    vulnerability (CVE-2020-1472) in Windows domain controllers.

.NOTES
    - Requires administrative privileges
    - Creates scheduled tasks for monitoring
    - Modifies registry settings for Netlogon parameters

.OUTPUTS
    Creates a CSV file with Zerologon-related events in the security configuration directory.

.EXAMPLE
    Set-ZerologonMitigation
#>
function Set-ZerologonMitigation {
    [CmdletBinding()]
    param()
    Write-Verbose "Configuring Zerologon mitigations..." -Verbose
    
    try {
        # Registry path for Netlogon parameters
        $registryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters"
        
        # Create registry path if it doesn't exist
        if (!(Test-Path $registryPath)) {
            New-Item -Path $registryPath -Force | Out-Null
            Write-Verbose "Created new registry path: $registryPath"
        }
        
        # Define required registry settings
        $settings = @{
            "FullSecureChannelProtection" = 1      # Enable enforcement mode
            "RequireSecureRPC" = 1                 # Force secure RPC usage
            "RequireStrongKey" = 1                 # Require strong key for secure channel
            "RequireSignOrSeal" = 1                # Require signing or sealing
            "SealSecureChannel" = 1                # Enforce channel sealing
            "SignSecureChannel" = 1                # Enforce channel signing
            "VulnerableChannelAllowList" = ""      # Clear vulnerable channel allow list
        }
        
        # Apply registry settings
        foreach ($setting in $settings.GetEnumerator()) {
            try {
                $valueType = if ($setting.Key -eq "VulnerableChannelAllowList") { "String" } else { "DWord" }
                Set-ItemProperty -Path $registryPath -Name $setting.Key -Value $setting.Value -Type $valueType -Force
                Write-Verbose "Successfully set $($setting.Key) to $($setting.Value)"
            }
            catch {
                Write-Warning "Failed to set $($setting.Key): $_"
            }
        }
        
        # Configure event log monitoring
        $eventLogName = "System"
        $eventSourceName = "Netlogon"
        
        # Define critical event IDs to monitor
        $criticalEvents = @(
            5827, # Denied machine account connections
            5828, # Denied trust account connections
            5829, # Allowed vulnerable connections (warning)
            5830, # Allowed machine account by policy
            5831  # Allowed trust account by policy
        )
        
        # Create scheduled task to monitor events
        $taskName = "ZerologonMonitoring"
        $taskDescription = "Monitors for Zerologon-related security events"
        
        $taskAction = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument @"
            Get-WinEvent -FilterHashtable @{
                LogName = '$eventLogName'
                ProviderName = '$eventSourceName'
                ID = $($criticalEvents -join ',')
            } -MaxEvents 100 | 
            Export-Csv -Path 'C:\Program Files\SecurityConfig\ZerologonEvents.csv' -NoTypeInformation -Append
"@
        
        $taskTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 1)
        
        Register-ScheduledTask -TaskName $taskName -Description $taskDescription `
            -Action $taskAction -Trigger $taskTrigger -RunLevel Highest -Force
        
        Write-Verbose "Successfully configured Zerologon mitigations and monitoring"
        
        # Additional validation checks
        $currentSettings = Get-ItemProperty -Path $registryPath
        $misconfigurations = @()
        
        foreach ($setting in $settings.GetEnumerator()) {
            if ($currentSettings.$($setting.Key) -ne $setting.Value) {
                $misconfigurations += $setting.Key
            }
        }
        
        if ($misconfigurations.Count -gt 0) {
            Write-Warning "The following settings may not have been applied correctly: $($misconfigurations -join ', ')"
        }
        else {
            Write-Output "All Zerologon mitigations have been successfully validated"
        }
    }
    catch {
        Write-Error "Failed to configure Zerologon mitigations: $_"
        throw
    }
}

# Set-KerberoastingMitigation
<#
.SYNOPSIS
    Implements mitigations against Kerberoasting attacks.

.DESCRIPTION
    Configures security settings to protect against Kerberoasting attacks by identifying
    service accounts with SPNs, configuring delegation settings, and setting appropriate
    Kerberos ticket lifetimes.

.NOTES
    Requires Domain Admin privileges in an Active Directory environment.

.OUTPUTS
    Creates a CSV file documenting user accounts with SPNs.

.EXAMPLE
    Set-KerberoastingMitigation
#>
function Set-KerberoastingMitigation {
    [CmdletBinding()]
    param()
    Write-Verbose "Configuring Kerberoasting mitigations..." -Verbose
    try {
        # Check for SPNs on user accounts
        $userSPNs = Get-ADUser -Filter * -Properties ServicePrincipalNames |
            Where-Object { $null -ne $_.ServicePrincipalNames }
        
        if ($userSPNs) {
            # Log users with SPNs
            $userSPNs | Select-Object Name, ServicePrincipalNames |
                Export-Csv -Path (Join-Path $script:logPath "UserSPNs.csv") -NoTypeInformation
            
            Write-SecurityLog -Component "Kerberoasting" -Message "Found user accounts with SPNs. Check UserSPNs.csv" -Level Warning
        }
        
        # Configure resource-based constrained delegation
        $servicePrincipals = Get-ADServiceAccount -Filter *
        foreach ($sp in $servicePrincipals) {
            Set-ADServiceAccount -Identity $sp -TrustedForDelegation $false
        }
        
        # Set maximum Kerberos ticket lifetime
        $maxTicketAge = 10 # hours
        Set-GPRegistryValue -Name "Default Domain Policy" -Key "HKLM\SYSTEM\CurrentControlSet\Services\Kdc" `
            -ValueName "MaxServiceTicketAge" -Type DWord -Value ($maxTicketAge * 3600)
        
        Write-SecurityLog -Component "Kerberoasting" -Message "Successfully configured Kerberoasting mitigations"
    }
    catch {
        Write-SecurityLog -Component "Kerberoasting" -Message $_.Exception.Message -Level Error
    }
}

# Set-GlobalAuditPolicy
<#
.SYNOPSIS
    Configures global audit policies for the system.

.DESCRIPTION
    Sets up global audit policies for file system and registry access, with different
    configurations for server and workstation environments.

.NOTES
    Requires administrative privileges to modify audit policies.
    Uses SACL to configure auditing.

.EXAMPLE
    Set-GlobalAuditPolicy
#>
function Set-GlobalAuditPolicy {
    [CmdletBinding()]
    param()
    Write-Verbose "Configuring global audit policies..." -Verbose
    
    try {
        # Replace Get-WmiObject with Get-CimInstance
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
        
        if ($osInfo.Caption -match "server") {
            auditpol /resourceSACL /set /type:File /user:"Domain Admins" /success /failure /access:FW
            auditpol /resourceSACL /set /type:Key /user:"Domain Admins" /success /failure /access:FW
        } else {
            auditpol /resourceSACL /set /type:File /user:Administrator /success /failure /access:FW
            auditpol /resourceSACL /set /type:Key /user:Administrator /success /failure /access:FW
        }
        Write-SecurityLog -Component "GlobalAudit" -Message "Successfully configured global audit policies"
    }
    catch {
        Write-SecurityLog -Component "GlobalAudit" -Message $_.Exception.Message -Level Error
    }
}

# Set-SMBConfiguration
<#
.SYNOPSIS
    Configures SMB protocol security settings.

.DESCRIPTION
    Manages SMB protocol versions and security settings, including disabling SMBv1
    and configuring secure SMB settings based on the OS version.

.NOTES
    Requires administrative privileges.
    Different configurations are applied based on OS version and type.

.EXAMPLE
    Set-SMBConfiguration
#>
function Set-SMBConfiguration {
    [CmdletBinding()]
    param()
    Write-Verbose "Configuring SMB settings..." -Verbose
    try {
        # Replace Get-WmiObject with Get-CimInstance
        If ($PSVersionTable.PSVersion -ge [version]"3.0") { 
            $OSWMI = Get-CimInstance -ClassName Win32_OperatingSystem -Property Caption,Version 
        } Else { 
            # Fallback for older PowerShell versions
            Write-Warning "PowerShell version < 3.0 detected. Some features may not work as expected."
            return
        }
        
        $OSVer = [version]$OSWMI.Version
        $OSName = $OSWMI.Caption

        if ($OSVer -ge [version]"6.2") { 
            If ((Get-SmbServerConfiguration).EnableSMB1Protocol) { 
                Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force 
            } 
        }
        elseif ($OSVer -ge [version]"6.0" -and $OSVer -lt [version]"6.2") { 
            Set-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters -Name SMB1 -Value 0 -Type DWord 
        }

        if ($OSVer -ge [version]"6.3" -and $OSName -match "\bserver\b") { 
            If ((Get-WindowsFeature FS-SMB1).Installed) { Remove-WindowsFeature FS-SMB1 } 
        }
        elseif ($OSVer -ge [version]"6.3" -and $OSName -notmatch "\bserver\b") {
            If ((Get-WindowsOptionalFeature -Online -FeatureName smb1protocol).State -eq "Enabled") { 
                Disable-WindowsOptionalFeature -Online -FeatureName smb1protocol 
            }
        }
        
        Write-SecurityLog -Component "SMBConfig" -Message "Successfully configured SMB settings"
    }
    catch {
        Write-SecurityLog -Component "SMBConfig" -Message $_.Exception.Message -Level Error
    }
}

# Enable-SecureSMB
<#
.SYNOPSIS
    Enables secure SMB protocol settings.

.DESCRIPTION
    Enables SMBv2 protocol and configures secure SMB settings based on the
    operating system version.

.NOTES
    Requires administrative privileges.
    Configures different settings based on OS version.

.EXAMPLE
    Enable-SecureSMB
#>
function Enable-SecureSMB {
    [CmdletBinding()]
    param()
    Write-Verbose "Enabling secure SMB..." -Verbose
    try {
        # Replace Get-WmiObject with Get-CimInstance
        If ($PSVersionTable.PSVersion -ge [version]"3.0") { 
            $OSWMI = Get-CimInstance -ClassName Win32_OperatingSystem -Property Caption,Version 
        } Else { 
            Write-Warning "PowerShell version < 3.0 detected. Some features may not work as expected."
            return
        }
        
        $OSVer = [version]$OSWMI.Version
        $OSName = $OSWMI.Caption

        if ($OSVer -ge [version]"6.2") { 
            Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force 
        }
        elseif ($OSVer -ge [version]"6.0" -and $OSVer -lt [version]"6.2") { 
            Set-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters SMB2 -Type DWORD -Value 1 -Force
        }

        Write-SecurityLog -Component "SecureSMB" -Message "Successfully enabled secure SMB"
    }
    catch {
        Write-SecurityLog -Component "SecureSMB" -Message $_.Exception.Message -Level Error
    }
}

function Ensure-PolicyFileEditor {
    $moduleName = "PolicyFileEditor"
    Write-Host "Checking for the $moduleName module..." -ForegroundColor Cyan

    # Check if the module is available
    if (-not (Get-Module -ListAvailable -Name $moduleName)) {
        Write-Host "$moduleName module not found. Preparing to install from PSGallery." -ForegroundColor Yellow

        # Retrieve PSGallery repository information
        $psGallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
        if ($psGallery) {
            # If PSGallery is not trusted, set it to Trusted
            if ($psGallery.InstallationPolicy -ne "Trusted") {
                Write-Host "Setting PSGallery repository as Trusted..." -ForegroundColor Yellow
                Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop
            }
        } else {
            Write-Warning "PSGallery repository is not registered. You may need to register it manually."
        }

        # Install the module from PSGallery
        try {
            Write-Host "Installing $moduleName module..." -ForegroundColor Yellow
            Install-Module -Name $moduleName -Force -Scope AllUsers -AllowClobber -ErrorAction Stop
            Write-Host "$moduleName module installed successfully." -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to install $moduleName module. Error details: $_"
            throw
        }
    }
    else {
        Write-Host "$moduleName module is already installed." -ForegroundColor Green
    }

    # Import the module into the current session
    try {
        Import-Module -Name $moduleName -Force -ErrorAction Stop
        Write-Host "$moduleName module imported successfully." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to import $moduleName module. Error details: $_"
        throw
    }
}

# Set-GroupPolicies
<#
.SYNOPSIS
    Configures security-related group policies.

.DESCRIPTION
    Sets various security-related group policies including autorun prevention,
    IIS installation prevention, and Windows Update configurations.

.NOTES
    Requires administrative privileges.
    Modifies registry-based group policy settings.

.EXAMPLE
    Set-GroupPolicies
#>
function Set-GroupPolicies() {
    Write-Host "Applying hardening Group Policy settings..." -ForegroundColor Gray
    try {
        # === USER ACCOUNT CONTROL (UAC) Settings ===
        # Enable UAC overall
        Set-PolicyFileEntry -Path "$env:systemroot\system32\GroupPolicy\Machine\registry.pol" `
            -Key "SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
            -ValueName "EnableLUA" -Type DWord -Data 1
        # Require Admin Approval Mode for the built-in Administrator account
        Set-PolicyFileEntry -Path "$env:systemroot\system32\GroupPolicy\Machine\registry.pol" `
            -Key "SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
            -ValueName "FilterAdministratorToken" -Type DWord -Data 1
        # Prompt for consent on the secure desktop for administrators
        Set-PolicyFileEntry -Path "$env:systemroot\system32\GroupPolicy\Machine\registry.pol" `
            -Key "SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
            -ValueName "ConsentPromptBehaviorAdmin" -Type DWord -Data 2
        # Automatically deny elevation requests for standard users
        Set-PolicyFileEntry -Path "$env:systemroot\system32\GroupPolicy\Machine\registry.pol" `
            -Key "SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
            -ValueName "ConsentPromptBehaviorUser" -Type DWord -Data 0
        # Switch to secure desktop when prompting for elevation
        Set-PolicyFileEntry -Path "$env:systemroot\system32\GroupPolicy\Machine\registry.pol" `
            -Key "SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
            -ValueName "PromptOnSecureDesktop" -Type DWord -Data 1
        # Only elevate UIAccess apps installed in secure locations
        Set-PolicyFileEntry -Path "$env:systemroot\system32\GroupPolicy\Machine\registry.pol" `
            -Key "SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
            -ValueName "EnableSecureUIAPaths" -Type DWord -Data 1
        # Virtualize file and registry write failures per user
        Set-PolicyFileEntry -Path "$env:systemroot\system32\GroupPolicy\Machine\registry.pol" `
            -Key "SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
            -ValueName "EnableVirtualization" -Type DWord -Data 1

        # === LDAP Signing Settings ===
        # For domain controllers and clients: require LDAP signing on the server and client
        Set-PolicyFileEntry -Path "$env:systemroot\system32\GroupPolicy\Machine\registry.pol" `
            -Key "SYSTEM\CurrentControlSet\Services\NTDS\Parameters" `
            -ValueName "LDAPServerIntegrity" -Type DWord -Data 2
        Set-PolicyFileEntry -Path "$env:systemroot\system32\GroupPolicy\Machine\registry.pol" `
            -Key "SYSTEM\CurrentControlSet\Services\NTDS\Parameters" `
            -ValueName "LDAPClientIntegrity" -Type DWord -Data 2
        # Require LDAP Channel Binding tokens (value '2' is used here as an example for "Always")
        Set-PolicyFileEntry -Path "$env:systemroot\system32\GroupPolicy\Machine\registry.pol" `
            -Key "SYSTEM\CurrentControlSet\Services\NTDS\Parameters" `
            -ValueName "LDAPChannelBinding" -Type DWord -Data 2

        # === SMB Signing Settings ===
        # Client: digitally sign communications (always)
        Set-PolicyFileEntry -Path "$env:systemroot\system32\GroupPolicy\Machine\registry.pol" `
            -Key "SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" `
            -ValueName "RequireSecuritySignature" -Type DWord -Data 1
        # Server: digitally sign communications (always)
        Set-PolicyFileEntry -Path "$env:systemroot\system32\GroupPolicy\Machine\registry.pol" `
            -Key "SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" `
            -ValueName "RequireSecuritySignature" -Type DWord -Data 1

        # === SChannel (Secure Channel) Signing Settings ===
        # Force signing or encryption on secure channel data
        Set-PolicyFileEntry -Path "$env:systemroot\system32\GroupPolicy\Machine\registry.pol" `
            -Key "SYSTEM\CurrentControlSet\Services\Netlogon\Parameters" `
            -ValueName "SignSecureChannel" -Type DWord -Data 1

        # === NTLMv2 Settings ===
        # Set LAN Manager authentication level to send NTLMv2 responses only (refuse LM & NTLM)
        Set-PolicyFileEntry -Path "$env:systemroot\system32\GroupPolicy\Machine\registry.pol" `
            -Key "SYSTEM\CurrentControlSet\Control\Lsa" `
            -ValueName "LmCompatibilityLevel" -Type DWord -Data 5

        # === Remote Desktop & Secure Channel Enhancements ===
        # Require Network Level Authentication (NLA) for Remote Desktop
        Set-PolicyFileEntry -Path "$env:systemroot\system32\GroupPolicy\Machine\registry.pol" `
            -Key "SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" `
            -ValueName "UserAuthentication" -Type DWord -Data 1

        # === Security Log Size ===
        # Set the maximum Security log size to 196608 KB (adjust this value as needed)
        Set-PolicyFileEntry -Path "$env:systemroot\system32\GroupPolicy\Machine\registry.pol" `
            -Key "SYSTEM\CurrentControlSet\Services\Eventlog\Security" `
            -ValueName "MaxSize" -Type DWord -Data 196608

        # === PowerShell Logging ===
        # Enable PowerShell Script Block Logging
        Set-PolicyFileEntry -Path "$env:systemroot\system32\GroupPolicy\Machine\registry.pol" `
            -Key "SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" `
            -ValueName "EnableScriptBlockLogging" -Type DWord -Data 1

        # === Name Resolution & Proxy Settings ===
        # Disable LLMNR (Multicast Name Resolution)
        Set-PolicyFileEntry -Path "$env:systemroot\system32\GroupPolicy\Machine\registry.pol" `
            -Key "SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" `
            -ValueName "EnableMulticast" -Type DWord -Data 0
        # Disable WPAD (Web Proxy Auto-Discovery) by deactivating the WinHttpAutoProxySvc
        Set-PolicyFileEntry -Path "$env:systemroot\system32\GroupPolicy\Machine\registry.pol" `
            -Key "SYSTEM\CurrentControlSet\Services\WinHttpAutoProxySvc" `
            -ValueName "Start" -Type DWord -Data 4

        Write-Host "Group Policy hardening settings applied successfully." -ForegroundColor Green
    }
    catch {
        Write-Output "$Error[0] $_" | Out-File "C:\Program Files\ezScript\groupPolicy.txt"
        Write-Host "Error applying Group Policy settings. Check C:\Program Files\ezScript\groupPolicy.txt" -ForegroundColor DarkYellow
    }
}


# Disable-TelnetService
<#
.SYNOPSIS
    Disables Telnet client and server services.

.DESCRIPTION
    Uses DISM to disable both Telnet client and server features without requiring
    a system restart.

.NOTES
    Requires administrative privileges.
    Changes take effect without system restart.

.EXAMPLE
    Disable-TelnetService
#>
function Disable-TelnetService {
    [CmdletBinding()]
    param()
    Write-Verbose "Disabling Telnet services..." -Verbose
    try {
        dism /online /Disable-feature /featurename:TelnetClient /NoRestart
        dism /online /Disable-feature /featurename:TelnetServer /NoRestart
        Write-SecurityLog -Component "Telnet" -Message "Successfully disabled Telnet services"
    }
    catch {
        Write-SecurityLog -Component "Telnet" -Message $_.Exception.Message -Level Error
    }
}

# Set-WindowsDefender
<#
.SYNOPSIS
    Configures Windows Defender security settings.

.DESCRIPTION
    Implements comprehensive Windows Defender configurations including real-time monitoring,
    cloud protection, PUA protection, and Attack Surface Reduction (ASR) rules.

.NOTES
    Requires administrative privileges.
    Some settings may require Windows 10 or later.

.EXAMPLE
    Set-WindowsDefender
#>
function Set-WindowsDefender {
    [CmdletBinding()]
    param()
    Write-Verbose "Configuring Windows Defender..." -Verbose
    try {
        setx /M MP_FORCE_USE_SANDBOX 1
        Set-MpPreference -EnableRealtimeMonitoring $true
        Set-MpPreference -DisableAutoExclusions $true
        Set-MpPreference -PUAProtection Enabled
        Set-MpPreference -SubmitSamplesConsent 2
        Set-MpPreference -CloudBlockLevel High
        Set-MpPreference -CloudExtendedTimeout 50

        Write-Verbose "Configuring ASR rules..."
        # Extended ASR rules
        $rules = @(
            "e6db77e5-3df2-4cf1-b95a-636979351e5b", # Block process creations from PSExec and WMI commands
            "D1E49AAC-8F56-4280-B9BA-993A6D", # Block all Office applications from creating child processes
            "C1DB55AB-C21A-4637-BB3F-A12568109D35", # Block Office applications from creating executable content
            "9E6C4E1F-7D60-472F-BA1A-A39EF669E4B2", # Block Office applications from injecting code into other processes
            "26190899-1602-49e8-8b27-eb1d0a1ce869", # Block JavaScript or VBScript from launching downloaded executable content
            "3b576869-a4ec-4529-8536-b80a7769e899", # Block execution of potentially obfuscated scripts
            "5beb7efe-fd9a-4556-801d-275e5ffc04cc", # Block Win32 API calls from Office macro
            "75668c1f-73b5-4cf0-bb93-3ecf5cb7cc84", # Block Office applications from creating child processes
            "d3e037e1-3eb8-44c8-a917-57927947596d", # Block Adobe Reader from creating child processes
            "d4f940ab-401b-4efc-aadc-ad5f3c50688a"  # Block persistence through WMI event subscription
        )

        foreach ($ruleId in $rules) {
            Write-Verbose "Adding ASR rule: $ruleId"
            Add-MpPreference -AttackSurfaceReductionRules_Ids $ruleId -AttackSurfaceReductionRules_Actions Enabled
        }

        Write-Verbose "Configuring additional Defender settings..."
        # Configure additional Defender settings
        Set-MpPreference -EnableNetworkProtection Enabled
        Set-MpPreference -EnableControlledFolderAccess Enabled
        Set-MpPreference -ScanScheduleDay Everyday
        Set-MpPreference -RemediationScheduleDay Everyday
        Set-MpPreference -DisableArchiveScanning $false
        Set-MpPreference -DisableRemovableDriveScanning $false
        Set-MpPreference -DisableScanningMappedNetworkDrivesForFullScan $false
        
        Write-SecurityLog -Component "WindowsDefender" -Message "Successfully configured Windows Defender"
    }
    catch {
        Write-SecurityLog -Component "WindowsDefender" -Message $_.Exception.Message -Level Error
    }
}

# Set-FirewallRules
<#
.SYNOPSIS
    Configures Windows Firewall rules for security hardening.

.DESCRIPTION
    Creates firewall rules to block potentially dangerous executables and
    configures both x64 and x86 paths where applicable.

.NOTES
    Requires administrative privileges.
    Creates separate rules for SysWOW64 executables when available.

.EXAMPLE
    Set-FirewallRules
#>
function Set-FirewallRules {
    [CmdletBinding()]
    param()
    Write-Verbose "Configuring Windows Firewall..." -Verbose
    try {
        $blockedApps = @(
            @{path="%systemroot%\system32\appvlp.exe"; name="appvlp.exe"},
            @{path="%systemroot%\system32\calc.exe"; name="calc.exe"},
            @{path="%systemroot%\system32\certutil.exe"; name="certutil.exe"},
            @{path="%systemroot%\system32\cmstp.exe"; name="cmstp.exe"},
            @{path="%systemroot%\system32\cscript.exe"; name="cscript.exe"},
            @{path="%systemroot%\system32\esentutl.exe"; name="esentutl.exe"},
            @{path="%systemroot%\system32\expand.exe"; name="expand.exe"},
            @{path="%systemroot%\system32\extrac32.exe"; name="extrac32.exe"},
            @{path="%systemroot%\system32\findstr.exe"; name="findstr.exe"},
            @{path="%systemroot%\system32\hh.exe"; name="hh.exe"},
            @{path="%systemroot%\system32\makecab.exe"; name="makecab.exe"},
            @{path="%systemroot%\system32\mshta.exe"; name="mshta.exe"},
            @{path="%systemroot%\system32\msiexec.exe"; name="msiexec.exe"},
            @{path="%systemroot%\system32\nltest.exe"; name="nltest.exe"},
            @{path="%systemroot%\system32\notepad.exe"; name="notepad.exe"},
            @{path="%systemroot%\system32\odbcconf.exe"; name="odbcconf.exe"},
            @{path="%systemroot%\system32\pcalua.exe"; name="pcalua.exe"},
            @{path="%systemroot%\system32\regasm.exe"; name="regasm.exe"},
            @{path="%systemroot%\system32\regsvr32.exe"; name="regsvr32.exe"},
            @{path="%systemroot%\system32\replace.exe"; name="replace.exe"},
            @{path="%systemroot%\system32\rpcping.exe"; name="rpcping.exe"},
            @{path="%systemroot%\system32\rundll32.exe"; name="rundll32.exe"},
            @{path="%systemroot%\system32\runscripthelper.exe"; name="runscripthelper.exe"},
            @{path="%systemroot%\system32\scriptrunner.exe"; name="scriptrunner.exe"},
            @{path="%systemroot%\system32\SyncAppvPublishingServer.exe"; name="SyncAppvPublishingServer.exe"},
            @{path="%systemroot%\system32\wbem\wmic.exe"; name="wmic.exe"},
            @{path="%systemroot%\system32\wscript.exe"; name="wscript.exe"}
        )

        foreach ($app in $blockedApps) {
            Write-Verbose "Creating firewall rule for $($app.name)"
            $ruleName = "Block $($app.name) netconns"
            netsh advfirewall firewall add rule name="$ruleName" `
                program="$($app.path)" protocol=tcp dir=out enable=yes action=block profile=any
            
            # Add rules for SysWOW64 versions if they exist
            if (Test-Path "${env:systemroot}\SysWOW64") {
                Write-Verbose "Creating x86 firewall rule for $($app.name)"
                $ruleName = "Block $($app.name) netconns (x86)"
                $path = $app.path -replace "system32","SysWOW64"
                netsh advfirewall firewall add rule name="$ruleName" `
                    program="$path" protocol=tcp dir=out enable=yes action=block profile=any
            }
        }
        Write-SecurityLog -Component "Firewall" -Message "Successfully configured firewall rules"
    }
    catch {
        Write-SecurityLog -Component "Firewall" -Message $_.Exception.Message -Level Error
    }
}

# Disable-RemoteManagement
<#
.SYNOPSIS
    Configures secure remote management settings.

.DESCRIPTION
    Disables PowerShell remoting, configures WinRM trusted hosts,
    and sets secure PowerShell session configurations.

.NOTES
    Requires administrative privileges.
    May impact remote management capabilities.

.EXAMPLE
    Disable-RemoteManagement
#>
function Disable-RemoteManagement {
    [CmdletBinding()]
    param()
    Write-Verbose "Configuring remote management settings..." -Verbose
    try {
        Write-Verbose "Disabling PowerShell remoting"
        Disable-PSRemoting -Force
        
        Write-Verbose "Configuring WinRM trusted hosts"
        Set-Item wsman:\localhost\client\trustedhosts * -Force
        
        Write-Verbose "Configuring PowerShell session security"
        Set-PSSessionConfiguration -Name "Microsoft.PowerShell" -SecurityDescriptorSddl "O:NSG:BAD:P(A;;GA;;;BA)(A;;GA;;;WD)(A;;GA;;;IU)S:P(AU;FA;GA;;;WD)(AU;SA;GXGW;;;WD)"
        
        Write-SecurityLog -Component "RemoteManagement" -Message "Successfully configured remote management settings"
    }
    catch {
        Write-SecurityLog -Component "RemoteManagement" -Message $_.Exception.Message -Level Error
    }
}

# Disable-AnonymousLDAP
<#
.SYNOPSIS
    Disables anonymous LDAP binds.

.DESCRIPTION
    Configures LDAP security settings to prevent anonymous binds on domain controllers,
    enhancing directory service security.

.NOTES
    Requires Domain Admin privileges.
    Only applies to server operating systems.

.EXAMPLE
    Disable-AnonymousLDAP
#>
function Disable-AnonymousLDAP {
    [CmdletBinding()]
    param()
    Write-Verbose "Configuring LDAP settings..." -Verbose
    try {
        # Replace Get-WmiObject with Get-CimInstance
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
        
        if ($osInfo.Caption -match "server") {
            Write-Verbose "Configuring LDAP settings on server OS"
            $rootDSE = Get-ADRootDSE
            $objectPath = 'CN=Directory Service,CN=Windows NT,CN=Services,{0}' -f $rootDSE.ConfigurationNamingContext
            Set-ADObject -Identity $objectPath -Add @{ 'msDS-Other-Settings' = 'DenyUnauthenticatedBind=1' }
            Write-SecurityLog -Component "LDAP" -Message "Successfully configured LDAP settings"
        } else {
            Write-Verbose "Skipping LDAP configuration on non-server OS"
            Write-SecurityLog -Component "LDAP" -Message "Skipping LDAP configuration on non-server OS" -Level Info
        }
    }
    catch {
        Write-SecurityLog -Component "LDAP" -Message $_.Exception.Message -Level Error
    }
}

# Set-SecurityRegistry
<#
.SYNOPSIS
    Configures security-related registry settings.

.DESCRIPTION
    Implements comprehensive registry-based security configurations including
    LSA protection, TCP/IP security, and system policies.

.NOTES
    Requires administrative privileges.
    Makes extensive registry modifications.

.EXAMPLE
    Set-SecurityRegistry
#>
function Set-SecurityRegistry {
    [CmdletBinding()]
    param()
    Write-Verbose "Configuring security registry settings..." -Verbose
    
    # Check if machine is a Domain Controller and disable vulnerable Netlogon connections
    try {
        # Replace Get-WmiObject with Get-CimInstance
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
        if ($osInfo.ProductType -eq 2) {  # Domain Controller
            Write-Verbose "Configuring DC-specific Netlogon settings"
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters" -Name "VulnerableChannelAllowList" -Value "" -Type String
            Write-SecurityLog -Component "Registry" -Message "Successfully disabled vulnerable Netlogon connections on DC" -Level Info
        }
    } catch {
        Write-SecurityLog -Component "Registry" -Message "Failed to configure Netlogon settings: $_" -Level Error
    }

    try {
        Write-Verbose "Beginning registry configuration..."
        $registrySettings = @{
            # Windows Update Settings
            "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" = @{
                "AutoInstallMinorUpdates" = 1
                "NoAutoUpdate" = 0
                "AUOptions" = 4
                "IncludeRecommendedUpdates" = 1
            }
            
            # UAC and System Policies
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" = @{
                "EnableLUA" = 1
                "PromptOnSecureDesktop" = 1
                "EnableInstallerDetection" = 1
                "FilterAdministratorToken" = 1
                "EnableSecureUIAPaths" = 1
                "ConsentPromptBehaviorAdmin" = 2
                "EnableVirtualization" = 1
                "ValidateAdminCodeSignatures" = 1
                "DisableAutomaticRestartSignOn" = 1
                "LocalAccountTokenFilterPolicy" = 0
                "EnableUIADesktopToggle" = 0
            }
            
            # LSA Security Settings
            "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" = @{
                "RunAsPPL" = 1
                "everyoneincludesanonymous" = 0
                "restrictanonymous" = 1
                "restrictanonymoussam" = 1
                "NoLMHash" = 1
                "LimitBlankPasswordUse" = 1
                "LmCompatibilityLevel" = 5
                "TokenLeakDetectDelaySecs" = 30
                "auditbaseobjects" = 1
                "fullprivilegeauditing" = 1
                "SCENoApplyLegacyAuditPolicy" = 1
                "DisableDomainCreds" = 1
                "SubmitControl" = 0
                "ForceGuest" = 0
                "DisableRestrictedAdmin" = 0
                "DisableRestrictedAdminOutboundCreds" = 1
                "UseMachineId" = 1
                "SecureBoot" = 1
                "ProductType" = 1
            }

            # TCP/IP Security Settings
            "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" = @{
                "EnableICMPRedirect" = 0
                "DisableIPSourceRouting" = 2
                "EnableDeadGWDetect" = 0
                "KeepAliveTime" = 300000
                "TcpMaxDataRetransmissions" = 3
                "SynAttackProtect" = 1
                "EnableMulticastForwarding" = 0
                "NoNameReleaseOnDemand" = 1
                "PerformRouterDiscovery" = 0
                "TCPMaxPortsExhausted" = 5
                "DisableRSS" = 0
                "EnablePMTUDiscovery" = 1
                "EnableConnectionRateLimiting" = 1
            }
        }

        foreach ($path in $registrySettings.Keys) {
            Write-Verbose "Processing registry path: $path"
            if (!(Test-Path $path)) {
                Write-Verbose "Creating new registry path: $path"
                New-Item -Path $path -Force | Out-Null
            }
            
            foreach ($name in $registrySettings[$path].Keys) {
                try {
                    Write-Verbose "Setting $name in $path"
                    Set-ItemProperty -Path $path -Name $name -Value $registrySettings[$path][$name] -Type DWord -Force
                }
                catch {
                    Write-Warning "Failed to set $name in $path : $_"
                    continue
                }
            }
        }
        
        Write-SecurityLog -Component "Registry" -Message "Successfully configured registry settings"
    }
    catch {
        Write-SecurityLog -Component "Registry" -Message $_.Exception.Message -Level Error
    }
}

# Set-LocalAccounts
<#
.SYNOPSIS
    Secures local user accounts.

.DESCRIPTION
    Updates passwords for local user accounts, excluding specific administrative
    accounts, and exports the new credentials securely.

.NOTES
    Requires administrative privileges.
    Excludes built-in Administrator and krbtgt accounts.

.OUTPUTS
    Creates a CSV file with updated account credentials.

.EXAMPLE
    Set-LocalAccounts
#>
function Set-LocalAccounts {
    [CmdletBinding()]
    param()
    Write-Verbose "Configuring local accounts..." -Verbose
    try {
        # Define accounts to exclude from password changes
        $excludedAccounts = @(
            "Administrator",
            "krbtgt"  # Kerberos ticket granting account
        )

        # Generate secure passwords and update all local accounts except excluded ones
        $users = Get-LocalUser
        $accountDetails = @()
        
        foreach ($user in $users) {
            # Skip excluded accounts
            if ($excludedAccounts -contains $user.Name) {
                Write-Verbose "Skipping password change for excluded account: $($user.Name)" -Level Info
                continue
            }

            Write-Verbose "Processing account: $($user.Name)"
            $newPassword = -join ((33..126) | Get-Random -Count 16 | ForEach-Object {[char]$_})
            $securePassword = ConvertTo-SecureString -String $newPassword -AsPlainText -Force
            $user | Set-LocalUser -Password $securePassword
            
            $accountDetails += [PSCustomObject]@{
                "AccountName" = $user.Name
                "NewPassword" = $newPassword
            }
        }
        
        # Export account details to secure location (excluding the excluded accounts)
        $accountDetails | Export-Csv -Path (Join-Path $script:logPath "LocalAccounts.csv") -NoTypeInformation
        Write-SecurityLog -Component "LocalAccounts" -Message "Successfully updated local account passwords (excluding Administrator and krbtgt accounts)"
    }
    catch {
        Write-SecurityLog -Component "LocalAccounts" -Message $_.Exception.Message -Level Error
    }
}

# Rename-AdminAccount
<#
.SYNOPSIS
    Renames the administrator account for security.

.DESCRIPTION
    Renames the built-in administrator account to a random name and
    records the change securely.

.NOTES
    Requires administrative privileges.
    Records the name change in a secure log.

.OUTPUTS
    Creates a CSV file documenting the administrator account rename.

.EXAMPLE
    Rename-AdminAccount
#>
function Rename-AdminAccount {
    [CmdletBinding()]
    param()
    Write-Verbose "Renaming administrator account..." -Verbose
    try {
        $currentAdminName = "Administrator"
        $newAdminName = "SecurityAdmin_$(Get-Random -Minimum 1000 -Maximum 9999)"
        
        Write-Verbose "Checking for administrator account..."
        $adminAccount = Get-LocalUser -Name $currentAdminName
        if ($adminAccount) {
            Write-Verbose "Renaming administrator account to $newAdminName"
            Rename-LocalUser -Name $currentAdminName -NewName $newAdminName
            Write-SecurityLog -Component "AdminAccount" -Message "Successfully renamed administrator account"
            
            # Record the new admin name securely
            Write-Verbose "Recording admin account name change"
            [PSCustomObject]@{
                "OriginalName" = $currentAdminName
                "NewName" = $newAdminName
                "DateChanged" = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            } | Export-Csv -Path (Join-Path $script:logPath "AdminRename.csv") -NoTypeInformation
        }
    }
    catch {
        Write-SecurityLog -Component "AdminAccount" -Message $_.Exception.Message -Level Error
    }
}

# Set-HomeGroupServices
<#
.SYNOPSIS
    Configures HomeGroup services for security.

.DESCRIPTION
    Disables HomeGroup listener and provider services to enhance
    network security.

.NOTES
    Requires administrative privileges.
    May impact home network sharing capabilities.

.EXAMPLE
    Set-HomeGroupServices
#>
function Set-HomeGroupServices {
    [CmdletBinding()]
    param()
    Write-Verbose "Configuring HomeGroup services..." -Verbose
    try {
        $services = @("HomeGroupListener", "HomeGroupProvider")
        
        foreach ($service in $services) {
            Write-Verbose "Processing service: $service"
            if (Get-Service -Name $service -ErrorAction SilentlyContinue) {
                Write-Verbose "Stopping and disabling $service"
                Stop-Service -Name $service -Force -ErrorAction Stop
                Set-Service -Name $service -StartupType Disabled
            }
        }
        Write-SecurityLog -Component "HomeGroup" -Message "Successfully disabled HomeGroup services"
    }
    catch {
        Write-SecurityLog -Component "HomeGroup" -Message $_.Exception.Message -Level Error
    }
}


# Set-TechnicalAccount
<#
.SYNOPSIS
    Creates and configures a technical support account.

.DESCRIPTION
    Creates a technical support account with administrative privileges
    and secure password, recording credentials securely.

.NOTES
    Requires administrative privileges.
    Only runs on non-server operating systems.

.OUTPUTS
    Creates a CSV file with technical account credentials.

.EXAMPLE
    Set-TechnicalAccount
#>
function Set-TechnicalAccount {
    [CmdletBinding()]
    param()
    Write-Verbose "Configuring technical support account..." -Verbose
    
    try {
        # Replace Get-WmiObject with Get-CimInstance
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
        if ($osInfo.Caption -match "server") {
            Write-Verbose "Skipping technical account creation on server OS"
            Write-SecurityLog -Component "TechAccount" -Message "Skipping technical account creation on server OS" -Level Info
            return
        }

        $techUsername = "TechSupport_$(Get-Random -Minimum 1000 -Maximum 9999)"
        Write-Verbose "Generating credentials for $techUsername"
        $password = "sec" + ([Guid]::NewGuid()).ToString().Substring(0, 12) + "!"
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force

        $existingUser = Get-LocalUser -Name $techUsername -ErrorAction SilentlyContinue
        if ($existingUser) {
            Write-Verbose "Removing existing technical account"
            Remove-LocalUser -Name $techUsername
        }

        Write-Verbose "Creating new technical account"
        New-LocalUser -Name $techUsername -Password $securePassword -Description "Technical Support Account" -PasswordNeverExpires $false
        Add-LocalGroupMember -Group "Administrators" -Member $techUsername

        Write-Verbose "Storing account details securely"
        [PSCustomObject]@{
            "Username" = $techUsername
            "Password" = $password
            "Created" = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        } | Export-Csv -Path (Join-Path $script:logPath "TechAccount.csv") -NoTypeInformation

        Write-SecurityLog -Component "TechAccount" -Message "Successfully created technical support account"
    }
    catch {
        Write-SecurityLog -Component "TechAccount" -Message $_.Exception.Message -Level Error
    }
}

# Invoke-SecurityHardening
<#
.SYNOPSIS
    Main function that executes all security hardening components.

.DESCRIPTION
    Orchestrates the execution of all security hardening functions in the proper
    order, handling errors and logging for each component.

.NOTES
    Requires administrative privileges.
    Creates comprehensive logs of all operations.

.EXAMPLE
    Invoke-SecurityHardening
#>
function Invoke-SecurityHardening {
    [CmdletBinding()]
    param()
    
    Show-SecurityBanner
    Initialize-SecurityDirectory
    
    $components = @(
        @{Name = "Set-AuditPolicy"; Description = "Configuring audit policies"},
        @{Name = "Set-GlobalAuditPolicy"; Description = "Setting up global audit policies"},
        @{Name = "Ensure-PolicyFileEditor"; Description = "Ensure required modules installed"}
        @{Name = "Set-SMBConfiguration"; Description = "Configuring SMB protocol"},
        @{Name = "Enable-SecureSMB"; Description = "Enabling secure SMB"},
        @{Name = "Set-GroupPolicies"; Description = "Setting group policies"},
        @{Name = "Disable-TelnetService"; Description = "Disabling Telnet"},
        @{Name = "Set-KerberoastingMitigation"; Description = "Configuring Kerberos security"},
        @{Name = "Set-ZerologonMitigation"; Description = "Configuring Zerologon mitigations"},
        @{Name = "Set-WindowsDefender"; Description = "Configuring Windows Defender"},
        @{Name = "Set-FirewallRules"; Description = "Setting up firewall rules"},
        @{Name = "Disable-RemoteManagement"; Description = "Configuring remote management"},
        @{Name = "Disable-AnonymousLDAP"; Description = "Securing LDAP"},
        @{Name = "Set-SecurityRegistry"; Description = "Configuring security registry"},
        @{Name = "Set-LocalAccounts"; Description = "Securing local accounts"},
        #@{Name = "Rename-AdminAccount"; Description = "Securing admin account"},
        @{Name = "Set-HomeGroupServices"; Description = "Configuring HomeGroup"},
        @{Name = "Set-TechnicalAccount"; Description = "Setting up technical account"}
    )

    foreach ($component in $components) {
        Write-Verbose "`nExecuting: $($component.Description)" -Verbose
        try {
            & $component.Name
        }
        catch {
            Write-SecurityLog -Component "MainExecution" -Message "Failed to execute $($component.Name): $_" -Level Error
        }
    }

    Write-Output "`nSecurity hardening complete. Logs available at: $script:logPath"
}

# Execute the script
Invoke-SecurityHardening
