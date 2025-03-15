#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Script to analyze Windows system logs for suspicious activity.

.DESCRIPTION
    Analyzes Windows Event Logs to detect potential security issues, 
    errors, and suspicious activity in the specified time period.

.PARAMETER Hours
    Number of hours of logs to analyze. Default is 1 hour.

.PARAMETER OutputFile
    Optional file path to save results. If not specified, results are displayed to console only.

.EXAMPLE
    .\Analyze-Logs.ps1
    Analyzes logs for the past 1 hour.

.EXAMPLE
    .\Analyze-Logs.ps1 -Hours 24
    Analyzes logs for the past 24 hours.

.EXAMPLE
    .\Analyze-Logs.ps1 -Hours 12 -OutputFile "C:\Logs\log_analysis.txt"
    Analyzes logs for the past 12 hours and saves results to the specified file.
#>

param (
    [Parameter(Position=0)]
    [int]$Hours = 1,
    
    [Parameter(Position=1)]
    [string]$OutputFile = ""
)

function Write-LogOutput {
    param (
        [Parameter(ValueFromPipeline=$true)]
        [string]$Message,
        
        [System.ConsoleColor]$ForegroundColor = [System.ConsoleColor]::White
    )
    
    # Write to console
    Write-Host $Message -ForegroundColor $ForegroundColor
    
    # Write to file if specified
    if ($OutputFile -ne "") {
        $Message | Out-File -FilePath $OutputFile -Append
    }
}

# Start transcript if output file is specified
if ($OutputFile -ne "") {
    if (Test-Path $OutputFile) {
        Remove-Item $OutputFile -Force
    }
}

# Calculate start time for filtering
$StartTime = (Get-Date).AddHours(-$Hours)
$CurrentTime = Get-Date

Write-LogOutput "=== Log Analysis - Last $Hours Hour(s) ===" -ForegroundColor Cyan
Write-LogOutput "Started at $(Get-Date)" -ForegroundColor Cyan
Write-LogOutput "Analyzing events from: $StartTime to $CurrentTime" -ForegroundColor Yellow
Write-LogOutput ""

# Define event log categories to check
$SecurityLogName = "Security"
$SystemLogName = "System"
$ApplicationLogName = "Application"
$PowerShellLogName = "Windows PowerShell"
$MaxEvents = 100  # Limit number of events for performance

# Analysis: Authentication logs (Security log)
Write-LogOutput "=== Authentication Logs Analysis ===" -ForegroundColor Green

# Failed login attempts (Event ID 4625)
Write-LogOutput "Failed login attempts:" -ForegroundColor Yellow
try {
    $failedLogins = Get-WinEvent -FilterHashtable @{
        LogName = $SecurityLogName
        Id = 4625
        StartTime = $StartTime
    } -ErrorAction SilentlyContinue -MaxEvents $MaxEvents
    
    if ($failedLogins) {
        $groupedFailures = $failedLogins | Group-Object -Property {
            $_.Properties[5].Value
        } | Sort-Object -Property Count -Descending
        
        foreach ($group in $groupedFailures) {
            Write-LogOutput "  $($group.Count) failed attempts for account: $($group.Name)"
            
            # Show source IPs for these attempts
            $sourceIPs = $group.Group | Group-Object -Property {
                try { $_.Properties[19].Value } catch { "Unknown" }
            } | Sort-Object -Property Count -Descending
            
            foreach ($ip in $sourceIPs) {
                Write-LogOutput "    - $($ip.Count) attempts from: $($ip.Name)"
            }
        }
    } else {
        Write-LogOutput "  No failed login attempts found in the specified time period."
    }
} catch {
    Write-LogOutput "  Error retrieving failed login attempts: $_" -ForegroundColor Red
}

# Successful logins (Event ID 4624)
Write-LogOutput "Successful logins:" -ForegroundColor Yellow
try {
    $successfulLogins = Get-WinEvent -FilterHashtable @{
        LogName = $SecurityLogName
        Id = 4624
        StartTime = $StartTime
    } -ErrorAction SilentlyContinue -MaxEvents $MaxEvents | Where-Object {
        $_.Properties[8].Value -eq 2 -or  # Interactive login
        $_.Properties[8].Value -eq 10      # Remote interactive login
    }
    
    if ($successfulLogins) {
        $groupedSuccess = $successfulLogins | Group-Object -Property {
            $_.Properties[5].Value
        } | Sort-Object -Property Count -Descending
        
        foreach ($group in $groupedSuccess) {
            Write-LogOutput "  $($group.Count) successful logins for account: $($group.Name)"
            
            # Show source IPs for these logins
            $sourceIPs = $group.Group | Group-Object -Property {
                try { $_.Properties[18].Value } catch { "Local" }
            } | Sort-Object -Property Count -Descending
            
            foreach ($ip in $sourceIPs) {
                if ($ip.Name -ne "::1" -and $ip.Name -ne "127.0.0.1" -and $ip.Name -ne "Local") {
                    Write-LogOutput "    - $($ip.Count) logins from: $($ip.Name)"
                }
            }
        }
    } else {
        Write-LogOutput "  No successful logins found in the specified time period."
    }
} catch {
    Write-LogOutput "  Error retrieving successful login attempts: $_" -ForegroundColor Red
}

# Admin account usage (Event ID 4672)
Write-LogOutput "Admin privilege usage:" -ForegroundColor Yellow
try {
    $adminPrivileges = Get-WinEvent -FilterHashtable @{
        LogName = $SecurityLogName
        Id = 4672
        StartTime = $StartTime
    } -ErrorAction SilentlyContinue -MaxEvents $MaxEvents
    
    if ($adminPrivileges) {
        $groupedAdmin = $adminPrivileges | Group-Object -Property {
            $_.Properties[1].Value
        } | Sort-Object -Property Count -Descending
        
        foreach ($group in $groupedAdmin) {
            Write-LogOutput "  $($group.Count) admin privilege assignments for account: $($group.Name)"
        }
    } else {
        Write-LogOutput "  No admin privilege usage found in the specified time period."
    }
} catch {
    Write-LogOutput "  Error retrieving admin privilege usage: $_" -ForegroundColor Red
}

Write-LogOutput ""

# Analysis: System logs
Write-LogOutput "=== System Logs Analysis ===" -ForegroundColor Green

# Critical and Error events
Write-LogOutput "Critical system errors:" -ForegroundColor Yellow
try {
    $systemErrors = Get-WinEvent -FilterHashtable @{
        LogName = $SystemLogName
        Level = 1,2  # Critical (1) and Error (2)
        StartTime = $StartTime
    } -ErrorAction SilentlyContinue -MaxEvents $MaxEvents
    
    if ($systemErrors) {
        $groupedErrors = $systemErrors | Group-Object -Property {
            $_.ProviderName + ": " + $_.Id
        } | Sort-Object -Property Count -Descending
        
        foreach ($group in $groupedErrors) {
            Write-LogOutput "  $($group.Count) occurrences of $($group.Name)"
            # Show most recent message of this type
            $latestMessage = ($group.Group | Sort-Object TimeCreated -Descending | Select-Object -First 1).Message
            $truncatedMessage = if ($latestMessage.Length -gt 100) { $latestMessage.Substring(0, 100) + "..." } else { $latestMessage }
            Write-LogOutput "    - Recent message: $truncatedMessage"
        }
    } else {
        Write-LogOutput "  No critical system errors found in the specified time period."
    }
} catch {
    Write-LogOutput "  Error retrieving system errors: $_" -ForegroundColor Red
}

# Service start/stop events
Write-LogOutput "Service activity:" -ForegroundColor Yellow
try {
    $serviceEvents = Get-WinEvent -FilterHashtable @{
        LogName = $SystemLogName
        Id = 7035, 7036, 7045  # Service control events
        StartTime = $StartTime
    } -ErrorAction SilentlyContinue -MaxEvents $MaxEvents
    
    if ($serviceEvents) {
        $groupedServices = $serviceEvents | Group-Object -Property {
            $_.Message -replace "^.*service\s*'([^']+)'.*$", '$1'
        } | Sort-Object -Property Count -Descending
        
        foreach ($group in $groupedServices) {
            Write-LogOutput "  $($group.Count) service events for: $($group.Name)"
        }
    } else {
        Write-LogOutput "  No service activity found in the specified time period."
    }
} catch {
    Write-LogOutput "  Error retrieving service events: $_" -ForegroundColor Red
}

Write-LogOutput ""

# Analysis: Application logs
Write-LogOutput "=== Application Logs Analysis ===" -ForegroundColor Green

# Application errors and warnings
Write-LogOutput "Application errors:" -ForegroundColor Yellow
try {
    $appErrors = Get-WinEvent -FilterHashtable @{
        LogName = $ApplicationLogName
        Level = 1,2,3  # Critical (1), Error (2), Warning (3)
        StartTime = $StartTime
    } -ErrorAction SilentlyContinue -MaxEvents $MaxEvents
    
    if ($appErrors) {
        $groupedAppErrors = $appErrors | Group-Object -Property {
            $_.ProviderName + ": " + $_.Id
        } | Sort-Object -Property Count -Descending
        
        foreach ($group in $groupedAppErrors) {
            Write-LogOutput "  $($group.Count) occurrences of $($group.Name)"
        }
    } else {
        Write-LogOutput "  No application errors found in the specified time period."
    }
} catch {
    Write-LogOutput "  Error retrieving application errors: $_" -ForegroundColor Red
}

Write-LogOutput ""

# Analysis: PowerShell activity
Write-LogOutput "=== PowerShell Activity Analysis ===" -ForegroundColor Green

# PowerShell script execution
Write-LogOutput "PowerShell script executions:" -ForegroundColor Yellow
try {
    $psScriptEvents = Get-WinEvent -FilterHashtable @{
        LogName = $PowerShellLogName
        Id = 400,800  # PowerShell script execution
        StartTime = $StartTime
    } -ErrorAction SilentlyContinue -MaxEvents $MaxEvents
    
    if ($psScriptEvents) {
        $groupedPSEvents = $psScriptEvents | Group-Object -Property {
            $_.Message -replace "^.*CommandLine=([^\r\n]+).*$", '$1' -replace ".{50}$", "..."
        } | Sort-Object -Property Count -Descending
        
        foreach ($group in $groupedPSEvents) {
            Write-LogOutput "  $($group.Count) executions: $($group.Name)"
        }
    } else {
        Write-LogOutput "  No PowerShell script executions found in the specified time period."
    }
} catch {
    Write-LogOutput "  Error retrieving PowerShell execution events: $_" -ForegroundColor Red
}

Write-LogOutput ""

# Analysis: Software installation
Write-LogOutput "=== Software Installation Analysis ===" -ForegroundColor Green

# Software installation events
Write-LogOutput "Software installations:" -ForegroundColor Yellow
try {
    $msiInstallEvents = Get-WinEvent -FilterHashtable @{
        LogName = $ApplicationLogName
        ProviderName = "MsiInstaller"
        StartTime = $StartTime
    } -ErrorAction SilentlyContinue -MaxEvents $MaxEvents | Where-Object { $_.Id -eq 1033 -or $_.Id -eq 1034 }
    
    if ($msiInstallEvents) {
        foreach ($event in $msiInstallEvents) {
            $product = $event.Message -replace "^.*product: ([^,]+).*$", '$1'
            $action = if ($event.Id -eq 1033) { "installed" } else { "removed" }
            Write-LogOutput "  $product was $action at $($event.TimeCreated)"
        }
    } else {
        Write-LogOutput "  No software installation events found in the specified time period."
    }
} catch {
    Write-LogOutput "  Error retrieving software installation events: $_" -ForegroundColor Red
}

Write-LogOutput ""

# Analysis: Windows Defender activity
Write-LogOutput "=== Windows Defender Analysis ===" -ForegroundColor Green

# Windows Defender events
Write-LogOutput "Windows Defender detections:" -ForegroundColor Yellow
try {
    $defenderEvents = Get-WinEvent -FilterHashtable @{
        LogName = "Microsoft-Windows-Windows Defender/Operational"
        Id = 1006, 1007, 1008, 1009, 1116, 1117  # Malware detected and actions
        StartTime = $StartTime
    } -ErrorAction SilentlyContinue -MaxEvents $MaxEvents
    
    if ($defenderEvents) {
        foreach ($event in $defenderEvents) {
            $threat = $event.Message -replace "^.*Threat Name: ([^\r\n]+).*$", '$1'
            $action = if ($event.Id -eq 1007) { "blocked" } else { "detected" }
            Write-LogOutput "  Threat '$threat' was $action at $($event.TimeCreated)"
        }
    } else {
        Write-LogOutput "  No Windows Defender detections found in the specified time period."
    }
} catch {
    Write-LogOutput "  Error retrieving Windows Defender events or Windows Defender logs not available: $_" -ForegroundColor Red
}

Write-LogOutput ""

# Analysis: Firewall activity
Write-LogOutput "=== Firewall Activity Analysis ===" -ForegroundColor Green

# Firewall rule changes
Write-LogOutput "Firewall rule changes:" -ForegroundColor Yellow
try {
    $firewallEvents = Get-WinEvent -FilterHashtable @{
        LogName = "Microsoft-Windows-Windows Firewall With Advanced Security/Firewall"
        StartTime = $StartTime
    } -ErrorAction SilentlyContinue -MaxEvents $MaxEvents
    
    if ($firewallEvents) {
        foreach ($event in $firewallEvents) {
            Write-LogOutput "  $($event.TimeCreated) - ID $($event.Id): $($event.Message -replace '\r\n.*', '...')"
        }
    } else {
        Write-LogOutput "  No firewall rule changes found in the specified time period."
    }
} catch {
    Write-LogOutput "  Error retrieving firewall events or firewall logs not available: $_" -ForegroundColor Red
}

Write-LogOutput ""

# Analysis: User account changes
Write-LogOutput "=== User Account Changes ===" -ForegroundColor Green

# User account events (creation, modification, enabling, disabling)
Write-LogOutput "User account changes:" -ForegroundColor Yellow
try {
    $accountEvents = Get-WinEvent -FilterHashtable @{
        LogName = $SecurityLogName
        Id = 4720, 4722, 4723, 4724, 4725, 4726, 4738  # Account creation, modification, etc.
        StartTime = $StartTime
    } -ErrorAction SilentlyContinue -MaxEvents $MaxEvents
    
    if ($accountEvents) {
        foreach ($event in $accountEvents) {
            $action = switch ($event.Id) {
                4720 { "created" }
                4722 { "enabled" }
                4723 { "password changed" }
                4724 { "password reset" }
                4725 { "disabled" }
                4726 { "deleted" }
                4738 { "modified" }
                default { "unknown action" }
            }
            
            $targetAccount = try { $event.Properties[0].Value } catch { "Unknown" }
            $actingAccount = try { $event.Properties[4].Value } catch { "Unknown" }
            
            Write-LogOutput "  Account '$targetAccount' was $action by '$actingAccount' at $($event.TimeCreated)"
        }
    } else {
        Write-LogOutput "  No user account changes found in the specified time period."
    }
} catch {
    Write-LogOutput "  Error retrieving user account change events: $_" -ForegroundColor Red
}

Write-LogOutput ""

# Analysis: Remote Desktop activity
Write-LogOutput "=== Remote Desktop Activity ===" -ForegroundColor Green

# RDP connection events
Write-LogOutput "RDP connections:" -ForegroundColor Yellow
try {
    $rdpEvents = Get-WinEvent -FilterHashtable @{
        LogName = "Microsoft-Windows-TerminalServices-LocalSessionManager/Operational"
        Id = 21, 22, 23, 24, 25  # RDP session events
        StartTime = $StartTime
    } -ErrorAction SilentlyContinue -MaxEvents $MaxEvents
    
    if ($rdpEvents) {
        foreach ($event in $rdpEvents) {
            $action = switch ($event.Id) {
                21 { "initiated" }
                22 { "shell start" }
                23 { "logged on" }
                24 { "disconnected" }
                25 { "reconnected" }
                default { "unknown action" }
            }
            
            $sourceInfo = "from " + ($event.Message -replace "^.*Source Network Address: ([^\r\n]+).*$", '$1')
            $userName = $event.Message -replace "^.*User: ([^\r\n]+).*$", '$1'
            
            if ($userName -and $sourceInfo) {
                Write-LogOutput "  $action - User: $userName $sourceInfo at $($event.TimeCreated)"
            }
        }
    } else {
        Write-LogOutput "  No RDP connection events found in the specified time period."
    }
} catch {
    Write-LogOutput "  Error retrieving RDP events or RDP logs not available: $_" -ForegroundColor Red
}

Write-LogOutput ""

# Analysis: Task Scheduler activity
Write-LogOutput "=== Task Scheduler Activity ===" -ForegroundColor Green

# Scheduled Task registration/modification
Write-LogOutput "Scheduled Task changes:" -ForegroundColor Yellow
try {
    $taskEvents = Get-WinEvent -FilterHashtable @{
        LogName = "Microsoft-Windows-TaskScheduler/Operational"
        Id = 106, 140, 141, 200, 201  # Task registration, deletion, modification, execution
        StartTime = $StartTime
    } -ErrorAction SilentlyContinue -MaxEvents $MaxEvents
    
    if ($taskEvents) {
        $groupedTaskEvents = $taskEvents | Group-Object -Property {
            $_.Message -replace "^.*Task Name: ([^\r\n]+).*$", '\1' -replace "\\\\", "\"
        } | Sort-Object -Property Count -Descending
        
        foreach ($group in $groupedTaskEvents) {
            $actions = $group.Group | ForEach-Object {
                switch ($_.Id) {
                    106 { "registered" }
                    140 { "updated" }
                    141 { "deleted" }
                    200 { "executed" }
                    201 { "completed" }
                    default { "unknown action" }
                }
            } | Sort-Object | Get-Unique -AsString
            
            $actionSummary = $actions -join ", "
            Write-LogOutput "  Task '$($group.Name)' - Actions: $actionSummary ($($group.Count) events)"
        }
    } else {
        Write-LogOutput "  No Task Scheduler events found in the specified time period."
    }
} catch {
    Write-LogOutput "  Error retrieving Task Scheduler events or Task Scheduler logs not available: $_" -ForegroundColor Red
}

Write-LogOutput ""

# Generate log summary
Write-LogOutput "=== Log Analysis Summary ===" -ForegroundColor Cyan
Write-LogOutput "Period analyzed: Last $Hours hour(s)" -ForegroundColor Cyan
Write-LogOutput "Start Time: $StartTime" -ForegroundColor Cyan
Write-LogOutput "End Time: $CurrentTime" -ForegroundColor Cyan
Write-LogOutput ""

# Count authentication failures
$authFailureCount = 0
try {
    $authFailureCount = (Get-WinEvent -FilterHashtable @{
        LogName = $SecurityLogName
        Id = 4625
        StartTime = $StartTime
    } -ErrorAction SilentlyContinue).Count
} catch {}
Write-LogOutput "Authentication failures: $authFailureCount" -ForegroundColor Yellow

# Count successful logins
$successLoginCount = 0
try {
    $successLoginCount = (Get-WinEvent -FilterHashtable @{
        LogName = $SecurityLogName
        Id = 4624
        StartTime = $StartTime
    } -ErrorAction SilentlyContinue | Where-Object {
        $_.Properties[8].Value -eq 2 -or  # Interactive login
        $_.Properties[8].Value -eq 10      # Remote interactive login
    }).Count
} catch {}
Write-LogOutput "Successful (interactive) logins: $successLoginCount" -ForegroundColor Yellow

# Count system errors
$systemErrorCount = 0
try {
    $systemErrorCount = (Get-WinEvent -FilterHashtable @{
        LogName = $SystemLogName
        Level = 1,2  # Critical (1) and Error (2)
        StartTime = $StartTime
    } -ErrorAction SilentlyContinue).Count
} catch {}
Write-LogOutput "System errors: $systemErrorCount" -ForegroundColor Yellow

# Check for suspicious activity indicators
$suspicious = 0
$suspicious += $authFailureCount
try {
    # Account lockouts
    $suspicious += (Get-WinEvent -FilterHashtable @{
        LogName = $SecurityLogName
        Id = 4740  # Account lockout
        StartTime = $StartTime
    } -ErrorAction SilentlyContinue).Count
} catch {}

Write-LogOutput ""

# Conclusion based on findings
if ($suspicious -gt 10) {
    Write-LogOutput "ALERT: High number of suspicious events detected ($suspicious)" -ForegroundColor Red
} elseif ($suspicious -gt 5) {
    Write-LogOutput "WARNING: Moderate number of suspicious events detected ($suspicious)" -ForegroundColor Yellow
} else {
    Write-LogOutput "NOTICE: Low number of suspicious events detected ($suspicious)" -ForegroundColor Green
}

Write-LogOutput ""
Write-LogOutput "=== Log Analysis Complete ===" -ForegroundColor Cyan
Write-LogOutput "Completed at $(Get-Date)" -ForegroundColor Cyan

if ($OutputFile -ne "") {
    Write-Host "Analysis results saved to: $OutputFile" -ForegroundColor Green
}
