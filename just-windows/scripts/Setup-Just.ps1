param(
    [string]$BaseDir = "C:\KeyboardKowboys"
)

# Import Win32 API for broadcasting environment changes
if (-not ("Win32.NativeMethods" -as [Type])) {
    Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @"
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(
    IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
    uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
"@
}

# Function to broadcast environment changes system-wide
function Update-SessionEnvironment {
    $HWND_BROADCAST = [IntPtr]0xffff
    $WM_SETTINGCHANGE = 0x001A
    $result = [UIntPtr]::Zero
    
    [Win32.NativeMethods]::SendMessageTimeout(
        $HWND_BROADCAST, $WM_SETTINGCHANGE,
        [UIntPtr]::Zero, "Environment",
        2, 5000, [ref]$result
    ) | Out-Null
    
    # Also update the current session
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    
    Write-Host "Environment variables refreshed system-wide" -ForegroundColor Green
}

# Function to add a directory to PATH
function Add-DirectoryToPath {
    param (
        [string]$Directory,
        [string]$PathType = "User" # Can be "User" or "Machine"
    )

    # Get the current PATH from the environment variables
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", $PathType)
    
    # Check if the directory is already in the PATH
    if ($currentPath -split ";" -contains $Directory) {
        Write-Host "Directory already exists in PATH: $Directory" -ForegroundColor Yellow
        return
    }
    
    # Add the directory to PATH
    $newPath = $currentPath + ";" + $Directory
    [Environment]::SetEnvironmentVariable("PATH", $newPath, $PathType)
    
    Write-Host "Added directory to $PathType PATH: $Directory" -ForegroundColor Green
}

# Display script info
Write-Host "Setting up Keyboard Kowboys environment at: $BaseDir" -ForegroundColor Green

# Create necessary subdirectories based on the Justfile
$Directories = @(
    $BaseDir,
    "$BaseDir\scripts",
    "$BaseDir\ops",
    "$BaseDir\backups",
    "$BaseDir\tools",
    "$BaseDir\configs",
    "$BaseDir\logs",
    "$BaseDir\bin"  # Added bin directory for executables
)

# Create the directories
foreach ($Dir in $Directories) {
    if (-not (Test-Path -Path $Dir)) {
        Write-Host "Creating directory: $Dir" -ForegroundColor Yellow
        New-Item -Path $Dir -ItemType Directory -Force | Out-Null
    } else {
        Write-Host "Directory already exists: $Dir" -ForegroundColor Cyan
    }
}

# Set permissions (Administrators get full control)
$Acl = Get-Acl -Path $BaseDir
$Ar = New-Object System.Security.AccessControl.FileSystemAccessRule('Administrators', 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
$Acl.SetAccessRule($Ar)
Set-Acl -Path $BaseDir -AclObject $Acl

# Create temporary directory for downloading files
$TmpDir = Join-Path -Path $env:TEMP -ChildPath "KKowboys_$(Get-Random)"
New-Item -Path $TmpDir -ItemType Directory -Force | Out-Null

try {
    # Download the zip file
    $ZipUrl = "https://github.com/CSUSB-CISO/csusb-ccdc/releases/download/CCDC-2024-2025/just-win.zip"
    $ZipFile = Join-Path -Path $TmpDir -ChildPath "just-win.zip"
    
    Write-Host "Downloading Keyboard Kowboys files..." -ForegroundColor Green
    
    # Check if we need to use .NET WebClient (PowerShell < 6) or Invoke-WebRequest
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        $WebClient = New-Object System.Net.WebClient
        $WebClient.DownloadFile($ZipUrl, $ZipFile)
    } else {
        Invoke-WebRequest -Uri $ZipUrl -OutFile $ZipFile -UseBasicParsing
    }
    
    # Check if download was successful
    if (-not (Test-Path -Path $ZipFile)) {
        throw "Failed to download the zip file. Please check your internet connection."
    }
    
    # Extract files to a temporary directory to examine the structure
    $ExtractTempDir = Join-Path -Path $TmpDir -ChildPath "extract_temp"
    Write-Host "Examining zip contents..." -ForegroundColor Green
    
    # Extract the ZIP file
    Expand-Archive -Path $ZipFile -DestinationPath $ExtractTempDir -Force
    
    # Check what was extracted
    $Items = Get-ChildItem -Path $ExtractTempDir
    foreach ($Item in $Items) {
        Write-Host "Found in zip: $($Item.Name)" -ForegroundColor Gray
    }
    
    # Check if "just-windows" directory exists in the zip contents
    $JustWindowsDir = Join-Path -Path $ExtractTempDir -ChildPath "just-windows"
    if (Test-Path -Path $JustWindowsDir) {
        Write-Host "Found 'just-windows' directory in the zip contents" -ForegroundColor Green
        
        # Check for Justfile in the just-windows directory
        $JustfilePaths = @(
            (Join-Path -Path $JustWindowsDir -ChildPath "Justfile"),
            (Join-Path -Path $JustWindowsDir -ChildPath "justfile")
        )
        
        $JustfileFound = $false
        foreach ($JustfilePath in $JustfilePaths) {
            if (Test-Path -Path $JustfilePath) {
                Write-Host "Found Justfile at $JustfilePath, copying files..." -ForegroundColor Green
                Copy-Item -Path $JustfilePath -Destination (Join-Path -Path $BaseDir -ChildPath "Justfile") -Force
                $JustfileFound = $true
                break
            }
        }
        
        # Copy scripts if they exist
        $ScriptsDir = Join-Path -Path $JustWindowsDir -ChildPath "scripts"
        if (Test-Path -Path $ScriptsDir) {
            Write-Host "Copying scripts from $ScriptsDir to $BaseDir\scripts" -ForegroundColor Green
            Copy-Item -Path "$ScriptsDir\*" -Destination "$BaseDir\scripts" -Recurse -Force
        }
        
        # If Justfile not found, copy all contents
        if (-not $JustfileFound) {
            Write-Host "Could not find Justfile inside just-windows directory, copying all content" -ForegroundColor Yellow
            Copy-Item -Path "$JustWindowsDir\*" -Destination $BaseDir -Recurse -Force
        }
    } else {
        Write-Host "No 'just-windows' directory found, copying all extracted files to $BaseDir" -ForegroundColor Yellow
        Copy-Item -Path "$ExtractTempDir\*" -Destination $BaseDir -Recurse -Force
    }
    
    # Define the bin directory
    $BinDir = "$BaseDir\bin"
    
    # Install 'just' if not already installed
    if (-not (Get-Command -Name "just" -ErrorAction SilentlyContinue)) {
        Write-Host "Installing 'just' command..." -ForegroundColor Green
        
        $JustVersion = "1.40.0"
        $JustArch = "x86_64-pc-windows-msvc"
        
        # Check architecture
        if ([Environment]::Is64BitOperatingSystem -eq $false) {
            $JustArch = "i686-pc-windows-msvc"
        }
        
        $JustUrl = "https://github.com/casey/just/releases/download/$JustVersion/just-$JustVersion-$JustArch.zip"
        $JustZipFile = Join-Path -Path $TmpDir -ChildPath "just.zip"
        $JustExtractDir = Join-Path -Path $TmpDir -ChildPath "just_extract"
        
        Write-Host "Downloading just $JustVersion for $JustArch..." -ForegroundColor Yellow
        
        # Download Just
        if ($PSVersionTable.PSVersion.Major -lt 6) {
            $WebClient = New-Object System.Net.WebClient
            $WebClient.DownloadFile($JustUrl, $JustZipFile)
        } else {
            Invoke-WebRequest -Uri $JustUrl -OutFile $JustZipFile -UseBasicParsing
        }
        
        # Create directory for extraction
        New-Item -Path $JustExtractDir -ItemType Directory -Force | Out-Null
        
        # Extract Just
        Expand-Archive -Path $JustZipFile -DestinationPath $JustExtractDir -Force
        
        # Install just to our bin directory
        $JustExe = Join-Path -Path $JustExtractDir -ChildPath "just.exe"
        $TargetExe = Join-Path -Path $BinDir -ChildPath "just.exe"
        
        Write-Host "Installing just to: $TargetExe" -ForegroundColor Green
        Copy-Item -Path $JustExe -Destination $TargetExe -Force
        
        Write-Host "just installed successfully to $TargetExe" -ForegroundColor Green
    } else {
        Write-Host "just is already installed." -ForegroundColor Green
        
        # Copy just.exe to our bin directory if found in PATH
        $existingJust = Get-Command -Name "just" -ErrorAction SilentlyContinue
        if ($null -ne $existingJust) {
            $TargetExe = Join-Path -Path $BinDir -ChildPath "just.exe"
            Write-Host "Copying existing just from $($existingJust.Source) to bin directory..." -ForegroundColor Green
            Copy-Item -Path $existingJust.Source -Destination $TargetExe -Force
        }
    }
    
    # If Justfile was not found in the zip, create a simple one based on the provided Justfile
    $JustfilePath = Join-Path -Path $BaseDir -ChildPath "Justfile"
    if (-not (Test-Path -Path $JustfilePath)) {
        Write-Host "No Justfile found, creating a simple one..." -ForegroundColor Yellow
        
        $JustfileContent = @"
set shell := ["powershell.exe", "-c"]

base_dir := "$($BaseDir.Replace('\', '/'))"
scripts_dir := base_dir + "/scripts"
ops_dir := base_dir + "/ops"
backup_dir := base_dir + "/backups"
tools_dir := base_dir + "/tools"
config_dir := base_dir + "/configs"
log_dir := base_dir + "/logs"
bin_dir := base_dir + "/bin"

# Display available commands with descriptions
default:
    @just --list

# Initialize directory structure (run once or after reset)
init:
    powershell -Command "Write-Host 'Setting up keyboard kowboys operation environment...' -ForegroundColor Green; \
    \$Dirs = @('{{base_dir}}', '{{scripts_dir}}', '{{ops_dir}}', '{{backup_dir}}', '{{tools_dir}}', '{{config_dir}}', '{{log_dir}}', '{{bin_dir}}'); \
    foreach (\$Dir in \$Dirs) { \
        if (-not (Test-Path \$Dir)) { \
            New-Item -Path \$Dir -ItemType Directory -Force | Out-Null; \
            Write-Host ('Created directory: ' + \$Dir) -ForegroundColor Yellow; \
        } else { \
            Write-Host ('Directory already exists: ' + \$Dir) -ForegroundColor Cyan; \
        } \
    } \
    # Set appropriate permissions \
    \$Acl = Get-Acl -Path '{{base_dir}}'; \
    \$Ar = New-Object System.Security.AccessControl.FileSystemAccessRule('Administrators', 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'); \
    \$Acl.SetAccessRule(\$Ar); \
    Set-Acl -Path '{{base_dir}}' -AclObject \$Acl; \
    Write-Host 'Directory structure created at {{base_dir}}' -ForegroundColor Green;"
"@
        
        # Write the Justfile
        $JustfileContent | Out-File -FilePath $JustfilePath -Encoding utf8 -Force
    }
    
    # Look for any executable files in tools directory and copy to bin directory
    $ToolsDir = Join-Path -Path $BaseDir -ChildPath "tools"
    if (Test-Path -Path $ToolsDir) {
        Write-Host "Checking for tool executables to copy to bin directory..." -ForegroundColor Green
        $Executables = Get-ChildItem -Path $ToolsDir -Include "*.exe", "*.ps1" -Recurse -ErrorAction SilentlyContinue
        foreach ($Exe in $Executables) {
            $TargetPath = Join-Path -Path $BinDir -ChildPath $Exe.Name
            Write-Host "Copying $($Exe.Name) to bin directory..." -ForegroundColor Cyan
            Copy-Item -Path $Exe.FullName -Destination $TargetPath -Force
        }
    }
    
    # Add our bin directory to PATH - both User and Machine level for maximum compatibility
    Write-Host "Adding bin directory to PATH..." -ForegroundColor Green
    Add-DirectoryToPath -Directory $BinDir -PathType "User"
    
    # Try to add to machine PATH if we have admin rights
    try {
        Add-DirectoryToPath -Directory $BinDir -PathType "Machine"
    } catch {
        Write-Host "Could not add to Machine PATH (requires admin rights). User PATH was updated." -ForegroundColor Yellow
    }
    
    # Add scripts directory to PATH as well
    $ScriptsDirPath = Join-Path -Path $BaseDir -ChildPath "scripts"
    if (Test-Path -Path $ScriptsDirPath) {
        Write-Host "Adding scripts directory to PATH..." -ForegroundColor Green
        Add-DirectoryToPath -Directory $ScriptsDirPath -PathType "User"
        
        # Try to add to machine PATH if we have admin rights
        try {
            Add-DirectoryToPath -Directory $ScriptsDirPath -PathType "Machine"
        } catch {
            Write-Host "Could not add scripts to Machine PATH (requires admin rights). User PATH was updated." -ForegroundColor Yellow
        }
    }
    
    # Broadcast the environment changes
    Write-Host "Broadcasting environment changes..." -ForegroundColor Green
    Update-SessionEnvironment
    
    # Done
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "Keyboard Kowboys environment has been set up successfully!" -ForegroundColor Green
    Write-Host "Base directory: $BaseDir" -ForegroundColor Green
    Write-Host "Bin directory: $BinDir" -ForegroundColor Green
    Write-Host "" -ForegroundColor Green
    
    # Test if just is available in current session
    if (Get-Command -Name "just" -ErrorAction SilentlyContinue) {
        Write-Host "just command is available in the current session" -ForegroundColor Green
        Write-Host "To use just, simply run:" -ForegroundColor Yellow
        Write-Host "  just --list" -ForegroundColor Yellow
    } else {
        Write-Host "just should be available at: $BinDir\just.exe" -ForegroundColor Green
        Write-Host "You can run it directly as: $BinDir\just.exe --list" -ForegroundColor Yellow
    }
    
    # Show current PATH for verification
    Write-Host "" -ForegroundColor Green
    Write-Host "Current PATH includes:" -ForegroundColor Cyan
    $EnvPath = $env:PATH -split ";"
    foreach ($PathEntry in $EnvPath) {
        if ($PathEntry -eq $BinDir -or $PathEntry -eq $ScriptsDirPath) {
            Write-Host "  $PathEntry" -ForegroundColor Green
        }
    }
    
    Write-Host "==========================================================" -ForegroundColor Cyan
} finally {
    # Clean up
    if (Test-Path -Path $TmpDir) {
        Remove-Item -Path $TmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
