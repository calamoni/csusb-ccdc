# Description: This script downloads and installs the Wazuh agent on Windows.

# Usage: .\wazuh_agent_install.ps1 -ManagerIP <Wazuh_Manager_IP>


param(
    [Parameter(Mandatory = $true)]
    [string]$ManagerIP
)

try {
    Write-Host "Downloading Wazuh agent..."
    Invoke-WebRequest -Uri "https://packages.wazuh.com/4.x/windows/wazuh-agent-4.9.2-1.msi" -OutFile "$env:tmp\wazuh-agent"
    
    Write-Host "Installing Wazuh agent..."
    $process = Start-Process msiexec.exe -ArgumentList "/i $env:tmp\wazuh-agent /q WAZUH_MANAGER='$ManagerIP'" -Wait -PassThru -NoNewWindow
    
    if ($process.ExitCode -eq 0) {
        Write-Host "Installation successful. Starting Wazuh service..."
        
        # Try both service names
        try {
            Start-Service -Name "WazuhSvc" -ErrorAction Stop
            Write-Host "WazuhSvc service started successfully"
        }
        catch {
            try {
                Start-Service -Name "Wazuh" -ErrorAction Stop
                Write-Host "Wazuh service started successfully"
            }
            catch {
                throw "Failed to start Wazuh service. Please start the service manually."
            }
        }
    }
    else {
        throw "Installation failed with exit code: $($process.ExitCode)"
    }
}
catch {
    Write-Error "Error during installation: $_"
    exit 1
}

Write-Host "Installation and configuration completed. Please check Windows Event Viewer for any issues."
