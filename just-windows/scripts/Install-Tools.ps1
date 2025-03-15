<#
.SYNOPSIS
    Installs Windows security and system tools to a specified directory and adds it to PATH.
.DESCRIPTION
    This script installs the following tools from the CSUSB-CCDC repository:
    - Autoruns.exe
    - Chainsaw
    - Hardening Kitty
    - Process Explorer (procexp.exe)
    - TCPView
    The script will download or copy these tools, extract ZIP files, and add the installation
    directory to the system PATH.
.PARAMETER InstallDir
    The directory where the tools will be installed. Defaults to "C:\SecurityTools".
.PARAMETER SourceDir
    Optional. The source directory containing the tool files. If not specified, the script assumes
    the files need to be downloaded.
.EXAMPLE
    .\Install-Tools.ps1
    Installs tools to the default directory (C:\SecurityTools)
.EXAMPLE
    .\Install-Tools.ps1 -InstallDir "D:\Tools" -SourceDir ".\tools"
    Installs tools from the .\tools directory to D:\Tools
#>

param (
    [string]$InstallDir = "C:\SecurityTools",
    [string]$SourceDir = $null
)

# Ensure we're running as administrator
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "You need to run this script as an Administrator!"
    exit 1
}

# Create installation directory if it doesn't exist
if (-not (Test-Path -Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir | Out-Null
    Write-Host "Created installation directory: $InstallDir" -ForegroundColor Green
} else {
    Write-Host "Using existing installation directory: $InstallDir" -ForegroundColor Yellow
}

# Set the GitHub repository URL for downloading files if no source directory is provided
$repoUrl = "https://github.com/CSUSB-CISO/csusb-ccdc/raw/main/bin/windows"

# Function to download a file if it doesn't exist in the source directory
function Get-ToolFile {
    param (
        [string]$FileName,
        [string]$DestinationPath
    )
    
    if ($SourceDir -and (Test-Path -Path "$SourceDir\$FileName")) {
        Write-Host "Copying $FileName from source directory..." -ForegroundColor Cyan
        Copy-Item -Path "$SourceDir\$FileName" -Destination $DestinationPath
    } else {
        Write-Host "Downloading $FileName..." -ForegroundColor Cyan
        $downloadUrl = "$repoUrl/$FileName"
        
        try {
            Invoke-WebRequest -Uri $downloadUrl -OutFile $DestinationPath
        } catch {
            Write-Error "Failed to download $FileName. Error: $_"
            return $false
        }
    }
    return $true
}

# Tool installation functions
function Install-Autoruns {
    $toolName = "Autoruns.exe"
    $destinationPath = Join-Path -Path $InstallDir -ChildPath $toolName
    
    if (Get-ToolFile -FileName $toolName -DestinationPath $destinationPath) {
        Write-Host "Autoruns installed successfully." -ForegroundColor Green
    }
}

function Install-Chainsaw {
    $zipName = "chainsaw_x86_64-pc-windows-msvc.zip"
    $zipPath = Join-Path -Path $InstallDir -ChildPath $zipName
    $chainsawDir = Join-Path -Path $InstallDir -ChildPath "Chainsaw"
    
    if (Get-ToolFile -FileName $zipName -DestinationPath $zipPath) {
        if (-not (Test-Path -Path $chainsawDir)) {
            New-Item -ItemType Directory -Path $chainsawDir | Out-Null
        }
        
        Write-Host "Extracting Chainsaw..." -ForegroundColor Cyan
        Expand-Archive -Path $zipPath -DestinationPath $chainsawDir -Force
        Remove-Item -Path $zipPath -Force  # Clean up the zip file
        
        # Add the actual executable path to PATH rather than just the top directory
        $chainsawExePath = Join-Path -Path $chainsawDir -ChildPath "chainsaw"
        if (Test-Path -Path $chainsawExePath) {
            Add-DirectoryToPath -Directory $chainsawExePath
        }
        
        Write-Host "Chainsaw installed successfully." -ForegroundColor Green
    }
}

function Install-HardeningKitty {
    $zipName = "hardening_kitty.zip"
    $zipPath = Join-Path -Path $InstallDir -ChildPath $zipName
    $kittyDir = Join-Path -Path $InstallDir -ChildPath "HardeningKitty"
    
    if (Get-ToolFile -FileName $zipName -DestinationPath $zipPath) {
        if (-not (Test-Path -Path $kittyDir)) {
            New-Item -ItemType Directory -Path $kittyDir | Out-Null
        }
        
        Write-Host "Extracting Hardening Kitty..." -ForegroundColor Cyan
        Expand-Archive -Path $zipPath -DestinationPath $kittyDir -Force
        Remove-Item -Path $zipPath -Force  # Clean up the zip file
        
        # Find the module directory
        $sourcePath = Get-ChildItem -Path $kittyDir -Recurse -Filter "HardeningKitty.psm1" | Select-Object -First 1
        if ($sourcePath) {
            $sourceDir = Split-Path -Path $sourcePath.FullName -Parent
            
            # Create a module directory in PowerShell modules path
            $psModulePath = [Environment]::GetEnvironmentVariable("PSModulePath", "Machine").Split(';')[0]
            $moduleDestDir = Join-Path -Path $psModulePath -ChildPath "HardeningKitty"
            
            if (-not (Test-Path -Path $moduleDestDir)) {
                New-Item -ItemType Directory -Path $moduleDestDir -Force | Out-Null
            }
            
            # Copy all module files to the modules directory
            Copy-Item -Path "$sourceDir\*" -Destination $moduleDestDir -Recurse -Force
            
            Write-Host "Installed HardeningKitty as a system-wide PowerShell module." -ForegroundColor Green
            Write-Host "You can now use 'Invoke-HardeningKitty' directly from any PowerShell session." -ForegroundColor Green
        } else {
            Write-Host "Could not find HardeningKitty.psm1 in the extracted files." -ForegroundColor Red
        }
        
        Write-Host "Hardening Kitty installed successfully." -ForegroundColor Green
    }
}

function Install-Lynix {
    $zipName = "lynix.zip"
    $zipPath = Join-Path -Path $InstallDir -ChildPath $zipName
    $lynixDir = Join-Path -Path $InstallDir -ChildPath "Lynix"
    
    if (Get-ToolFile -FileName $zipName -DestinationPath $zipPath) {
        if (-not (Test-Path -Path $lynixDir)) {
            New-Item -ItemType Directory -Path $lynixDir | Out-Null
        }
        
        Write-Host "Extracting Lynix..." -ForegroundColor Cyan
        Expand-Archive -Path $zipPath -DestinationPath $lynixDir -Force
        Remove-Item -Path $zipPath -Force  # Clean up the zip file
        
        Write-Host "Lynix installed successfully." -ForegroundColor Green
    }
}

function Install-ProcessExplorer {
    $toolName = "procexp.exe"
    $destinationPath = Join-Path -Path $InstallDir -ChildPath $toolName
    
    if (Get-ToolFile -FileName $toolName -DestinationPath $destinationPath) {
        Write-Host "Process Explorer installed successfully." -ForegroundColor Green
    }
}

function Install-TCPView {
    $exeName = "tcpview.exe"
    $chmName = "tcpview.chm"
    $exePath = Join-Path -Path $InstallDir -ChildPath $exeName
    $chmPath = Join-Path -Path $InstallDir -ChildPath $chmName
    
    $exeSuccess = Get-ToolFile -FileName $exeName -DestinationPath $exePath
    $chmSuccess = Get-ToolFile -FileName $chmName -DestinationPath $chmPath
    
    if ($exeSuccess -and $chmSuccess) {
        Write-Host "TCPView installed successfully." -ForegroundColor Green
    }
}

function Add-DirectoryToPath {
    param (
        [string]$Directory
    )

    # Get the current PATH from the environment variables
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
    
    # Check if the directory is already in the PATH
    if ($currentPath -split ";" -contains $Directory) {
        Write-Host "Directory already exists in PATH: $Directory" -ForegroundColor Yellow
        return
    }
    
    # Add the directory to PATH
    $newPath = $currentPath + ";" + $Directory
    [Environment]::SetEnvironmentVariable("PATH", $newPath, "Machine")
    
    Write-Host "Added directory to system PATH: $Directory" -ForegroundColor Green
}

function Update-SessionEnvironment {
    $HWND_BROADCAST = [IntPtr]0xffff
    $WM_SETTINGCHANGE = 0x001A
    $result = [UIntPtr]::Zero
    
    if (-not ("Win32.NativeMethods" -as [Type])) {
        Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @"
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(
    IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
    uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
"@
    }
    
    [Win32.NativeMethods]::SendMessageTimeout(
        $HWND_BROADCAST, $WM_SETTINGCHANGE,
        [UIntPtr]::Zero, "Environment",
        2, 5000, [ref]$result
    ) | Out-Null
    
    # Also update the current session
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    
    Write-Host "Environment variables refreshed system-wide" -ForegroundColor Green
}

# Main installation process
Write-Host "Starting installation of security tools..." -ForegroundColor Magenta

# Install each tool
Install-Autoruns
Install-Chainsaw
Install-HardeningKitty
# Install-Lynix (excluded as requested)
Install-ProcessExplorer
Install-TCPView

# Add the installation directory to PATH
Add-DirectoryToPath -Directory $InstallDir

# No need to add subdirectories separately, as we're adding the specific paths
# in each tool's installation function now


# Broadcast the environment changes to all Windows processes
Update-SessionEnvironment

Write-Host "Installation complete!" -ForegroundColor Magenta
Write-Host "All tools have been installed to $InstallDir and added to PATH." -ForegroundColor Green
Write-Host "The PATH has been updated in the current session and broadcast to other applications." -ForegroundColor Green

