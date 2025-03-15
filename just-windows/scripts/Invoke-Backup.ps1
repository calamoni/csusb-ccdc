#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Optimized System Backup Solution using OOP principles for Windows systems.
    
.DESCRIPTION
    Object-oriented PowerShell script for backing up various system configurations on Windows.
    
.PARAMETER Help
    Show the help message.
    
.PARAMETER ConfigFile
    Specify a custom configuration file path.
    
.PARAMETER LogFile
    Specify a custom log file path.
    
.PARAMETER VerboseOutput
    Enable verbose output during backup operations.
    
.PARAMETER DryRun
    Perform a trial run with no actual changes made.
    
.PARAMETER ExcludePattern
    Specify patterns to exclude from backup.
    
.PARAMETER SystemName
    The system component to back up (network, firewall, services, etc.)
    
.PARAMETER BaseDir
    Specify a base directory where system-specific backup folders will be created.
    
.EXAMPLE
    .\backup.ps1 all C:\Backups
    This will backup all system configurations to C:\Backups\all
    
.EXAMPLE
    .\backup.ps1 -VerboseOutput network C:\Backups
    This will backup network configurations to C:\Backups\network with verbose output
#>

[CmdletBinding()]
param (
    [switch]$Help,
    [string]$ConfigFile,
    [string]$LogFile,
    [switch]$VerboseOutput,
    [switch]$DryRun,
    [string[]]$ExcludePattern,
    [Parameter(Position=0)]
    [string]$SystemName,
    [Parameter(Position=1)]
    [string]$BaseDir
)

# Base class for backup operations
class BackupSystem {
    # Properties with default values
    [string]$ConfigFile
    [string]$LogFile
    [bool]$Verbose
    [bool]$DryRun
    [string[]]$ExcludePatterns
    [string]$BaseDir
    [string]$SystemName
    [string]$BackupDir
    [string]$Timestamp
    [string]$BackupPath
    [string[]]$SourceDirs
    
    # Constructor
    BackupSystem([string]$systemName, [string]$baseDir, [hashtable]$options) {
        $this.SystemName = $systemName
        $this.BaseDir = $baseDir
        $this.BackupDir = Join-Path $baseDir $systemName
        $this.Timestamp = Get-Date -Format "yyyyMMdd"
        $this.BackupPath = Join-Path $this.BackupDir $this.Timestamp
        
        # Set options from parameters
        $this.ConfigFile = $options.ConfigFile
        $this.LogFile = $options.LogFile
        $this.Verbose = $options.Verbose
        $this.DryRun = $options.DryRun
        $this.ExcludePatterns = $options.ExcludePatterns
        
        # Ensure log directory exists
        $logDir = Split-Path -Parent $this.LogFile
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        
        $this.WriteLog("INFO", "Initialized $systemName backup system")
    }
    
    # Method to write logs
    [void] WriteLog([string]$level, [string]$message) {
        $logTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "[$logTimestamp] [$level] $message" | Out-File -FilePath $this.LogFile -Append
        
        if ($this.Verbose -or $level -eq "ERROR") {
            if ($level -eq "ERROR") {
                Write-Host "[$level] $message" -ForegroundColor Red
            } elseif ($level -eq "WARNING") {
                Write-Host "[$level] $message" -ForegroundColor Yellow
            } else {
                Write-Host "[$level] $message"
            }
        }
    }
    
    # Method to check if a command exists
    [bool] CommandExists([string]$command) {
        return $null -ne (Get-Command $command -ErrorAction SilentlyContinue)
    }
    
    # Method to check dependencies
    [void] CheckDependencies() {
        if (-not $this.CommandExists("robocopy")) {
            $this.WriteLog("ERROR", "robocopy is required but not available. It should be included with Windows.")
            exit 1
        }
        
        $this.WriteLog("INFO", "Using robocopy for file operations")
    }
    
    # Method to create destination directory if it doesn't exist
    [void] EnsureDirectory([string]$path) {
        if (-not (Test-Path $path)) {
            $this.WriteLog("INFO", "Creating directory: $path")
            New-Item -Path $path -ItemType Directory -Force | Out-Null
        }
    }
    
    # Method to copy a file safely
    [bool] SafeCopyFile([string]$source, [string]$destination) {
        # Create parent directory if it doesn't exist
        $destDir = Split-Path -Parent $destination
        $this.EnsureDirectory($destDir)
        
        try {
            # Try to copy the file
            Copy-Item -Path $source -Destination $destination -Force
            $this.WriteLog("INFO", "Copied file: $source to $destination")
            return $true
        } catch {
            $this.WriteLog("WARNING", "Failed to copy file: $source`: $($_.Exception.Message)")
            return $false
        }
    }
    
    # Method to safely copy a directory
    [void] SafeCopyDirectory([string]$source, [string]$destination) {
        if (-not (Test-Path $source)) {
            $this.WriteLog("INFO", "Source does not exist, skipping: $source")
            return
        }
        
        # Create destination directory
        $this.EnsureDirectory($destination)
        
        # Try PowerShell copy first
        try {
            $files = Get-ChildItem -Path $source -File -Recurse -Force -ErrorAction Continue
            $this.WriteLog("INFO", "Found $($files.Count) files in $source")
            
            foreach ($file in $files) {
                $relativePath = $file.FullName.Substring($source.Length)
                $destPath = Join-Path $destination $relativePath
                $destDir = Split-Path -Parent $destPath
                $this.EnsureDirectory($destDir)
                
                $this.SafeCopyFile($file.FullName, $destPath)
            }
            
            # If no files were found, try robocopy as a fallback
            if ($files.Count -eq 0) {
                throw "No files found, trying robocopy instead"
            }
        } catch {
            $this.WriteLog("INFO", "PowerShell copy failed or found no files. Trying robocopy: $($_.Exception.Message)")
            
            # Fallback to robocopy
            $robocopyArgs = @(
                "`"$source`"",
                "`"$destination`"",
                "/E",        # Copy subdirectories, including empty ones
                "/ZB",       # Use restartable mode; if access denied use backup mode
                "/COPY:DAT", # Copy Data, Attributes, and Timestamps
                "/R:3",      # Number of retries on failed copies
                "/W:1",      # Wait time between retries
                "/NP",       # No progress
                "/MT:8"      # Multithreaded - 8 threads
            )
            
            # Add exclude patterns
            foreach ($pattern in $this.ExcludePatterns) {
                $robocopyArgs += "/XF"
                $robocopyArgs += $pattern
            }
            
            try {
                $this.WriteLog("INFO", "Running robocopy with arguments: $($robocopyArgs -join ' ')")
                & robocopy $robocopyArgs
                $this.WriteLog("INFO", "Robocopy completed for $source")
            } catch {
                $this.WriteLog("WARNING", "robocopy encountered issues with $source`: $($_.Exception.Message)")
            }
        }
    }
    
    # Virtual method to get source directories (to be overridden in child classes)
    [string[]] GetSourceDirs() {
        return @()
    }
    
    # Method to perform system dump
    [void] PerformSystemDump() {
        $dumpDir = Join-Path $this.BackupPath "system_info"
        $this.EnsureDirectory($dumpDir)
        
        $this.WriteLog("INFO", "Creating system information snapshot in $dumpDir")
        
        # Common system information to gather
        Get-CimInstance Win32_OperatingSystem | Out-File -FilePath "$dumpDir\os_info.txt"
        Get-Volume | Out-File -FilePath "$dumpDir\disk_usage.txt"
        Get-PSDrive | Out-File -FilePath "$dumpDir\psdrive_info.txt"
        Get-NetAdapter | Out-File -FilePath "$dumpDir\network_adapters.txt"
        Get-NetIPAddress | Out-File -FilePath "$dumpDir\ip_addresses.txt"
        Get-Process | Out-File -FilePath "$dumpDir\processes.txt"
        Get-LocalUser | Out-File -FilePath "$dumpDir\local_users.txt"
        Get-Service | Out-File -FilePath "$dumpDir\service_status.txt"
        
        # Installed software
        Get-WmiObject -Class Win32_Product | Select-Object Name, Version, Vendor | 
            Out-File -FilePath "$dumpDir\installed_software.txt"
            
        # Create a system snapshot timestamp
        Get-Date | Out-File -FilePath "$dumpDir\snapshot_time.txt"
        $this.WriteLog("INFO", "System information snapshot completed")
    }
    
    # Method to create a manifest file
    [void] CreateManifest() {
        $manifestContent = @"
Backup System: Optimized System Backup Solution (PowerShell) v3.0
Date: $(Get-Date)
System: $($this.SystemName)
Computer Name: $($env:COMPUTERNAME)
Windows Version: $(Get-CimInstance Win32_OperatingSystem).Version
Source Directories:
$(($this.SourceDirs | ForEach-Object { "  - $_" }) -join "`r`n")
"@
        
        $manifestContent | Out-File -FilePath "$($this.BackupPath)\manifest.txt"
        
        # Create a "latest" marker file
        "Latest backup: $($this.Timestamp)" | Out-File -FilePath "$($this.BackupDir)\latest.txt"
        
        # Create directory junction if possible
        $latestLink = Join-Path $this.BackupDir "latest"
        if (Test-Path $latestLink) {
            $this.WriteLog("INFO", "Removing previous 'latest' junction point")
            Remove-Item -Path $latestLink -Force -Recurse -ErrorAction SilentlyContinue
        }
        
        # Ensure the parent directory of the junction exists
        $latestParent = Split-Path -Parent $latestLink
        $this.EnsureDirectory($latestParent)
        
        try {
            # Create symbolic link to the latest backup
            New-Item -ItemType Junction -Path $latestLink -Target $this.BackupPath | Out-Null
        } catch {
            $this.WriteLog("WARNING", "Could not create symbolic link to latest backup`: $($_.Exception.Message)")
        }
    }
    
    # Main backup method
    [void] Backup() {
        $this.CheckDependencies()
        $this.WriteLog("INFO", "Starting backup of $($this.SystemName) to $($this.BackupPath)")
        
        if ($this.DryRun) {
            $this.WriteLog("INFO", "DRY RUN Mode: No changes will be made")
            return
        }
        
        # Prepare directories
        $this.EnsureDirectory($this.BackupDir)
        $this.EnsureDirectory($this.BackupPath)
        
        # Get source directories for this system
        $this.SourceDirs = $this.GetSourceDirs()
        
        if ($this.SourceDirs.Count -eq 0) {
            $this.WriteLog("WARNING", "No source directories identified for system: $($this.SystemName)")
            $this.WriteLog("INFO", "Will continue with system info dump only")
        } else {
            # Process each source directory
            foreach ($src in $this.SourceDirs) {
                if (-not (Test-Path $src)) {
                    $this.WriteLog("INFO", "Source does not exist, skipping: $src")
                    continue
                }
                
                # Get the base name for the destination
                $baseName = Split-Path -Leaf $src
                $destDir = Join-Path $this.BackupPath $baseName
                
                if (Test-Path -Path $src -PathType Container) {
                    # Directory backup
                    $this.SafeCopyDirectory($src, $destDir)
                } else {
                    # Single file backup
                    $destParent = Split-Path -Parent $destDir
                    $this.EnsureDirectory($destParent)
                    $this.SafeCopyFile($src, $destParent)
                }
            }
        }
        
        # Perform system dump and create manifest
        $this.PerformSystemDump()
        $this.CreateManifest()
        $this.WriteLog("INFO", "Backup completed successfully: $($this.SystemName) to $($this.BackupPath)")
    }
}

# Network backup class
class NetworkBackup : BackupSystem {
    NetworkBackup([string]$baseDir, [hashtable]$options) : base("network", $baseDir, $options) {}
    
    # Override GetSourceDirs for network-specific paths
    [string[]] GetSourceDirs() {
        $sources = @()
        
        if (Test-Path "C:\Windows\System32\drivers\etc") { 
            $this.WriteLog("INFO", "Adding etc directory to backup")
            $sources += "C:\Windows\System32\drivers\etc" 
        }
        
        if (Test-Path "C:\Windows\System32\NetworkList") { 
            $this.WriteLog("INFO", "Adding NetworkList directory to backup")
            $sources += "C:\Windows\System32\NetworkList" 
        }
        
        # Additional network files and directories
        $networkFiles = @(
            "C:\Windows\System32\drivers\etc\hosts",
            "C:\Windows\System32\drivers\etc\networks",
            "C:\Windows\System32\drivers\etc\protocol",
            "C:\Windows\System32\drivers\etc\services"
        )
        
        foreach ($file in $networkFiles) {
            if (Test-Path $file) {
                $this.WriteLog("INFO", "Adding network file to backup: $file")
                $sources += $file
            }
        }
        
        return $sources
    }
    
    # Override system dump with network-specific info
    [void] PerformSystemDump() {
        # Call the parent method first
        ([BackupSystem]$this).PerformSystemDump()
        
        $dumpDir = Join-Path $this.BackupPath "system_info"
        
        # Additional network-specific information
        $this.WriteLog("INFO", "Capturing additional network information")
        Get-NetIPConfiguration | Out-File -FilePath "$dumpDir\net_ip_config.txt"
        Get-DnsClientServerAddress | Out-File -FilePath "$dumpDir\dns_servers.txt"
        Get-NetConnectionProfile | Out-File -FilePath "$dumpDir\connection_profiles.txt"
        Get-NetNeighbor | Out-File -FilePath "$dumpDir\arp_cache.txt"
        Get-NetAdapterStatistics | Out-File -FilePath "$dumpDir\interface_statistics.txt"
    }
}

# Firewall backup class
class FirewallBackup : BackupSystem {
    FirewallBackup([string]$baseDir, [hashtable]$options) : base("firewall", $baseDir, $options) {}
    
    # Override GetSourceDirs for firewall-specific paths
    [string[]] GetSourceDirs() {
        $sources = @()
        
        if (Test-Path "C:\Windows\System32\WDI\LogFiles\FirewallAPI.dll") { 
            $sources += "C:\Windows\System32\WDI\LogFiles\FirewallAPI.dll" 
        }
        if (Test-Path "C:\Windows\System32\LogFiles\Firewall") { 
            $sources += "C:\Windows\System32\LogFiles\Firewall" 
        }
        
        return $sources
    }
    
    # Override system dump with firewall-specific info
    [void] PerformSystemDump() {
        # Call the parent method first
        ([BackupSystem]$this).PerformSystemDump()
        
        $dumpDir = Join-Path $this.BackupPath "system_info"
        
        # Add firewall-specific information
        $this.WriteLog("INFO", "Capturing detailed firewall information")
        Get-NetFirewallProfile | Out-File -FilePath "$dumpDir\firewall_profiles.txt"
        Get-NetFirewallRule | Out-File -FilePath "$dumpDir\firewall_rules.txt"
        
        # Export firewall rules to a format that can be reimported
        $firewallExportPath = "$dumpDir\firewall_export.wfw"
        netsh advfirewall export "$firewallExportPath" | Out-Null
        
        # Get current firewall configuration
        netsh advfirewall show allprofiles | Out-File -FilePath "$dumpDir\firewall_config.txt"
    }
}

# All systems backup class
class AllSystemsBackup : BackupSystem {
    AllSystemsBackup([string]$baseDir, [hashtable]$options) : base("all", $baseDir, $options) {}
    
    # Override GetSourceDirs for all critical system paths
    [string[]] GetSourceDirs() {
        return @(
            "C:\Windows\System32\config",
            "C:\Windows\System32\drivers\etc",
            "C:\Users\*\AppData\Roaming",
            "C:\ProgramData"
        )
    }
    
    # Backup important system files directly
    [void] BackupSystemFiles() {
        $this.WriteLog("INFO", "Backing up critical system files")
        
        # Important Windows directories to back up
        $dirsToCopy = @(
            @{Source = "C:\Windows\System32\config"; Destination = Join-Path $this.BackupPath "config"},
            @{Source = "C:\Windows\System32\drivers\etc"; Destination = Join-Path $this.BackupPath "etc"},
            @{Source = "C:\ProgramData"; Destination = Join-Path $this.BackupPath "ProgramData"}
        )
        
        foreach ($dir in $dirsToCopy) {
            if (Test-Path $dir.Source) {
                $this.SafeCopyDirectory($dir.Source, $dir.Destination)
            }
        }
        
        # Back up user AppData\Roaming directories
        $roamingBackupDir = Join-Path $this.BackupPath "Roaming"
        $this.EnsureDirectory($roamingBackupDir)
        
        # Get list of users
        $userProfiles = Get-ChildItem -Path "C:\Users" -Directory
        foreach ($userProfile in $userProfiles) {
            $roamingPath = Join-Path $userProfile.FullName "AppData\Roaming"
            if (Test-Path $roamingPath) {
                $userRoamingBackup = Join-Path $roamingBackupDir $userProfile.Name
                $this.EnsureDirectory($userRoamingBackup)
                
                # Copy important configuration files only
                $configDirs = @("Microsoft\Windows", "Microsoft\Office")
                foreach ($configDir in $configDirs) {
                    $sourcePath = Join-Path $roamingPath $configDir
                    $destPath = Join-Path $userRoamingBackup $configDir
                    
                    if (Test-Path $sourcePath) {
                        $this.SafeCopyDirectory($sourcePath, $destPath)
                    }
                }
            }
        }
    }
    
    # Override the backup method to include direct file backup
    [void] Backup() {
        # Call the parent backup method
        ([BackupSystem]$this).Backup()
        
        # Add the direct file backup step
        if (-not $this.DryRun) {
            $this.BackupSystemFiles()
        }
    }
}

# Factory method to create the appropriate backup system
function New-BackupSystem {
    param (
        [string]$SystemName,
        [string]$BaseDir,
        [hashtable]$Options
    )
    
    switch ($SystemName) {
        "network" { return [NetworkBackup]::new($BaseDir, $Options) }
        "firewall" { return [FirewallBackup]::new($BaseDir, $Options) }
        "all" { return [AllSystemsBackup]::new($BaseDir, $Options) }
        default { return [BackupSystem]::new($SystemName, $BaseDir, $Options) }
    }
}

# Function to display help
function Show-Help {
    Write-Host @"
Optimized System Backup Solution using OOP principles

Usage: .\$(Split-Path -Leaf $PSCommandPath) [OPTIONS] <system_name> <base_directory>

Systems:
  all           Backup all system configurations
  network       Backup network configurations
  firewall      Backup firewall rules
  services      Backup service configurations
  database      Backup database (SQL Server)
  web           Backup web server configurations (IIS)
  custom        Custom backup defined in configuration file

Options:
  -Help                        Show this help message
  -ConfigFile FILE             Use specified config file
  -LogFile FILE                Log file location
  -VerboseOutput               Enable verbose output
  -DryRun                      Perform a trial run with no changes made
  -ExcludePattern PATTERN      Exclude files/directories matching pattern

Examples:
  .\$(Split-Path -Leaf $PSCommandPath) all C:\Backups
  .\$(Split-Path -Leaf $PSCommandPath) -VerboseOutput network C:\Backups
  .\$(Split-Path -Leaf $PSCommandPath) -DryRun firewall C:\Backups

"@
    exit 0
}

# Main script execution

# Check for help flag
if ($Help) {
    Show-Help
}

# Set default configuration values
$ConfigFile = if ($ConfigFile) { $ConfigFile } elseif ($env:KK_CONFIG_DIR) { "$($env:KK_CONFIG_DIR)\backup-config.ps1" } else { "C:\ProgramData\backup-config.ps1" }
$LogFile = if ($LogFile) { $LogFile } elseif ($env:KK_LOG_DIR) { "$($env:KK_LOG_DIR)\system-backup.log" } else { "C:\ProgramData\Logs\system-backup.log" }
$VERBOSE = if ($VerboseOutput) { $true } else { $false }
$DRY_RUN = if ($DryRun) { $true } else { $false }
$EXCLUDE_PATTERNS = if ($ExcludePattern) { $ExcludePattern } else { @("C:\Windows\Temp\*", "C:\Temp\*", "C:\ProgramData\Temp\*") }
$BASE_DIR = if ($env:KK_BASE_DIR) { $env:KK_BASE_DIR } else { "C:\Program Files\KeyboardKowboys" }

# Check for required arguments
if (-not $SystemName -or -not $BaseDir) {
    Write-Host "ERROR: Missing required arguments" -ForegroundColor Red
    Show-Help
}

# Create backup options hashtable
$backupOptions = @{
    ConfigFile = $ConfigFile
    LogFile = $LogFile
    Verbose = $VERBOSE
    DryRun = $DRY_RUN
    ExcludePatterns = $EXCLUDE_PATTERNS
}

# Create and run the appropriate backup system
$backupSystem = New-BackupSystem -SystemName $SystemName -BaseDir $BaseDir -Options $backupOptions
$backupSystem.Backup()

exit 0
