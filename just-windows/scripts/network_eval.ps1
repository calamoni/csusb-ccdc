<#
.SYNOPSIS
    Comprehensive network security analysis for Windows systems.
.DESCRIPTION
    Performs detailed analysis of network connections, listening ports, 
    process activity and more to identify security concerns.
#>

# Script initialization
$ErrorActionPreference = "SilentlyContinue"
$FormatEnumerationLimit = -1

# ----------------- HELPER FUNCTIONS -----------------

function Print-Header {
    param([string]$Title)
    
    Write-Output "============================================================" -ForegroundColor Cyan
    Write-Output "==== $Title ====" -ForegroundColor Cyan
    Write-Output "============================================================" -ForegroundColor Cyan
}

function Print-SubHeader {
    param([string]$Title)
    
    Write-Output "---- $Title ----" -ForegroundColor Yellow
}

function Get-Timestamp {
    return Get-Date -Format "yyyy-MM-dd HH:mm:ss"
}

function Categorize-Service {
    param([int]$Port)
    
    switch ($Port) {
        # Authentication & Directory Services
        {$_ -in @(88, 389, 636, 464, 749)} { return "DIRECTORY/AUTH" }
        
        # Web Services
        {$_ -in @(80, 443, 8080, 8443, 8000)} { return "WEB" }
        
        # Remote Access
        {$_ -in @(22, 23, 3389)} { return "REMOTE ACCESS" }
        
        # Database Services
        {$_ -in @(1433, 1521, 3306, 5432, 6379, 27017, 27018, 27019)} { return "DATABASE" }
        
        # Mail Services
        {$_ -in @(25, 465, 587, 110, 143, 993, 995)} { return "MAIL" }
        
        # File Sharing
        {$_ -in @(21, 445, 2049, 137, 138, 139)} { return "FILE SHARING" }
        
        # Name Resolution
        {$_ -in @(53, 5353, 5355)} { return "DNS/RESOLUTION" }
        
        # Application Services
        {$_ -in @(8005, 8009, 8081, 8181, 9000, 9090)} { return "APPLICATION" }
        
        # Monitoring & Management
        {$_ -in @(161, 162, 10000, 28038, 38401)} { return "MGMT/MONITOR" }
        
        # Time Services
        {$_ -in @(123, 323)} { return "TIME" }
        
        # High ports (typically ephemeral)
        {$_ -ge 49152 -and $_ -le 65535} { return "EPHEMERAL" }
        
        default { return "OTHER" }
    }
}

function Get-PortDescription {
    param([int]$Port)
    
    switch ($Port) {
        # Common TCP ports
        20 { return "FTP Data" }
        21 { return "FTP Control" }
        22 { return "SSH" }
        23 { return "Telnet" }
        25 { return "SMTP" }
        53 { return "DNS" }
        80 { return "HTTP" }
        88 { return "Kerberos" }
        110 { return "POP3" }
        135 { return "RPC" }
        137 { return "NetBIOS Name" }
        138 { return "NetBIOS Datagram" }
        139 { return "NetBIOS Session" }
        143 { return "IMAP" }
        389 { return "LDAP" }
        443 { return "HTTPS" }
        445 { return "SMB" }
        464 { return "Kerberos Password" }
        465 { return "SMTPS" }
        587 { return "SMTP Submission" }
        636 { return "LDAPS" }
        993 { return "IMAPS" }
        995 { return "POP3S" }
        1433 { return "MS SQL" }
        1434 { return "MS SQL Browser" }
        1521 { return "Oracle DB" }
        3306 { return "MySQL" }
        3389 { return "RDP" }
        5432 { return "PostgreSQL" }
        5900 { return "VNC" }
        5985 { return "WinRM HTTP" }
        5986 { return "WinRM HTTPS" }
        6379 { return "Redis" }
        8080 { return "HTTP Alt" }
        8443 { return "HTTPS Alt" }
        27017 { return "MongoDB" }
        default { return "Unknown" }
    }
}

function Classify-PortSecurity {
    param([int]$Port)
    
    switch ($Port) {
        # Standard ports
        {$_ -in @(53, 80, 443, 3306, 5432, 25, 587, 993, 995, 110, 143, 8080, 8443, 631)} {
            return "STANDARD"
        }
        
        # Review ports
        {$_ -in @(21, 23, 445, 1433, 3389, 5900, 6379, 27017)} {
            return "REVIEW"
        }
        
        # Unusual ports
        default {
            return "UNUSUAL"
        }
    }
}

# ----------------- MAIN SCRIPT -----------------

# Begin the scan
Print-Header "NETWORK SECURITY ANALYSIS REPORT"
Write-Output "Host: $env:COMPUTERNAME"
Write-Output "Time: $(Get-Timestamp)"
Write-Output "Analysis mode: Comprehensive"
Write-Output ""

# ------- ESTABLISHED CONNECTIONS ANALYSIS -------
Print-Header "ESTABLISHED CONNECTION ANALYSIS"

Print-SubHeader "External Connection Summary (by destination)"
$establishedConnections = Get-NetTCPConnection -State Established | 
    Where-Object { $_.RemoteAddress -ne "127.0.0.1" -and $_.RemoteAddress -ne "::1" }

$establishedConnectionStats = $establishedConnections | 
    Group-Object -Property RemoteAddress | 
    Sort-Object -Property Count -Descending | 
    Select-Object -First 15

foreach ($stat in $establishedConnectionStats) {
    Write-Output "$($stat.Count) connections to $($stat.Name)"
}

Print-SubHeader "Connections by Process (count)"
$processTcpConnections = $establishedConnections | Group-Object -Property OwningProcess | 
    Sort-Object -Property Count -Descending

foreach ($proc in $processTcpConnections) {
    $processID = $proc.Name
    $processInfo = Get-Process -Id $processID -ErrorAction SilentlyContinue
    $processName = if ($processInfo) { $processInfo.ProcessName } else { "Unknown" }
    $count = $proc.Count
    
    $status = if ($count -gt 20) {
        "[HIGH]"
    } elseif ($count -gt 5) {
        "[MODERATE]"
    } else {
        ""
    }
    
    Write-Output "$count connections: $processName (PID: $processID) $status"
}
Write-Output ""

# ------- SERVICE CATEGORIZATION SUMMARY -------
Print-Header "SERVICE CATEGORIZATION SUMMARY"

$listeningPorts = Get-NetTCPConnection -State Listen
$listeningUdpPorts = Get-NetUDPEndpoint

# Initialize category counters
$categoryCount = @{
    "DIRECTORY/AUTH" = 0
    "WEB" = 0
    "REMOTE ACCESS" = 0
    "DATABASE" = 0
    "MAIL" = 0
    "FILE SHARING" = 0
    "DNS/RESOLUTION" = 0
    "APPLICATION" = 0
    "MGMT/MONITOR" = 0
    "TIME" = 0
    "OTHER" = 0
}

# Count services by category
foreach ($port in $listeningPorts) {
    $localPort = $port.LocalPort
    $category = Categorize-Service -Port $localPort
    $categoryCount[$category]++
}

foreach ($port in $listeningUdpPorts) {
    $localPort = $port.LocalPort
    $category = Categorize-Service -Port $localPort
    $categoryCount[$category]++
}

# Display service category summary
Write-Output "Service role breakdown:"
foreach ($category in $categoryCount.Keys) {
    if ($categoryCount[$category] -gt 0) {
        Write-Output "- $category Services: $($categoryCount[$category]) ports"
    }
}
Write-Output ""

# For each category with services, list the specific services
foreach ($category in $categoryCount.Keys) {
    if ($categoryCount[$category] -gt 0) {
        Print-SubHeader "$category Services"
        
        # Group ports by process for this category
        $categoryProcesses = @{}
        
        # Process TCP ports for this category
        $categoryTcpPorts = $listeningPorts | Where-Object {
            $category -eq (Categorize-Service -Port $_.LocalPort)
        }
        
        foreach ($port in $categoryTcpPorts) {
            $processId = $port.OwningProcess
            $isEphemeral = $port.LocalPort -ge 49152
            
            if (-not $categoryProcesses.ContainsKey($processId)) {
                $processInfo = Get-Process -Id $processId -ErrorAction SilentlyContinue
                $processName = if ($processInfo) { $processInfo.ProcessName } else { "Unknown" }
                
                $categoryProcesses[$processId] = @{
                    "ProcessName" = $processName
                    "TcpRegular" = @()
                    "TcpEphemeral" = @()
                    "UdpRegular" = @()
                    "UdpEphemeral" = @()
                }
            }
            
            if ($isEphemeral) {
                $categoryProcesses[$processId].TcpEphemeral += $port
            } else {
                $categoryProcesses[$processId].TcpRegular += $port
            }
        }
        
        # Process UDP ports for this category
        $categoryUdpPorts = $listeningUdpPorts | Where-Object {
            $category -eq (Categorize-Service -Port $_.LocalPort)
        }
        
        foreach ($port in $categoryUdpPorts) {
            $processId = $port.OwningProcess
            $isEphemeral = $port.LocalPort -ge 49152
            
            if (-not $categoryProcesses.ContainsKey($processId)) {
                $processInfo = Get-Process -Id $processId -ErrorAction SilentlyContinue
                $processName = if ($processInfo) { $processInfo.ProcessName } else { "Unknown" }
                
                $categoryProcesses[$processId] = @{
                    "ProcessName" = $processName
                    "TcpRegular" = @()
                    "TcpEphemeral" = @()
                    "UdpRegular" = @()
                    "UdpEphemeral" = @()
                }
            }
            
            if ($isEphemeral) {
                $categoryProcesses[$processId].UdpEphemeral += $port
            } else {
                $categoryProcesses[$processId].UdpRegular += $port
            }
        }
        
        # Now display the results for each process
        foreach ($processEntry in $categoryProcesses.GetEnumerator()) {
            $processId = $processEntry.Key
            $processData = $processEntry.Value
            $processName = $processData.ProcessName
            
            # Show TCP regular ports
            foreach ($port in $processData.TcpRegular) {
                $portNumber = $port.LocalPort
                $portDesc = Get-PortDescription -Port $portNumber
                Write-Output "TCP Port $portNumber ($portDesc): Process $processName (PID: $processId)"
            }
            
            # Summarize TCP ephemeral ports if there are more than 20
            if ($processData.TcpEphemeral.Count -gt 0) {
                if ($processData.TcpEphemeral.Count -gt 20) {
                    $minPort = ($processData.TcpEphemeral | Measure-Object -Property LocalPort -Minimum).Minimum
                    $maxPort = ($processData.TcpEphemeral | Measure-Object -Property LocalPort -Maximum).Maximum
                    Write-Output "$processName has $($processData.TcpEphemeral.Count) TCP ephemeral ports in range $minPort-$maxPort" -ForegroundColor Yellow
                } else {
                    # Show each ephemeral port if there are just a few
                    foreach ($port in $processData.TcpEphemeral) {
                        $portNumber = $port.LocalPort
                        Write-Output "TCP Port $portNumber (Ephemeral): Process $processName (PID: $processId)"
                    }
                }
            }
            
            # Show UDP regular ports
            foreach ($port in $processData.UdpRegular) {
                $portNumber = $port.LocalPort
                $portDesc = Get-PortDescription -Port $portNumber
                Write-Output "UDP Port $portNumber ($portDesc): Process $processName (PID: $processId)"
            }
            
            # Summarize UDP ephemeral ports if there are more than 20
            if ($processData.UdpEphemeral.Count -gt 0) {
                if ($processData.UdpEphemeral.Count -gt 20) {
                    $minPort = ($processData.UdpEphemeral | Measure-Object -Property LocalPort -Minimum).Minimum
                    $maxPort = ($processData.UdpEphemeral | Measure-Object -Property LocalPort -Maximum).Maximum
                    Write-Output "$processName has $($processData.UdpEphemeral.Count) UDP ephemeral ports in range $minPort-$maxPort" -ForegroundColor Yellow
                } else {
                    # Show each ephemeral port if there are just a few
                    foreach ($port in $processData.UdpEphemeral) {
                        $portNumber = $port.LocalPort
                        Write-Output "UDP Port $portNumber (Ephemeral): Process $processName (PID: $processId)"
                    }
                }
            }
        }
        
        Write-Output ""
    }
}

# ------- LISTENING PORTS ANALYSIS -------
Print-Header "LISTENING PORTS ANALYSIS"

Print-SubHeader "TCP Listening Ports"

# Get all TCP ports and group them by process
$portGroupsByProcess = $listeningPorts | Group-Object -Property OwningProcess

# First list all the important, non-ephemeral ports individually
foreach ($processGroup in $portGroupsByProcess) {
    $processId = $processGroup.Name
    $processInfo = Get-Process -Id $processId -ErrorAction SilentlyContinue
    $processName = if ($processInfo) { $processInfo.ProcessName } else { "Unknown" }
    
    # Split the ports for this process into non-ephemeral and ephemeral
    $nonEphemeralPorts = $processGroup.Group | Where-Object { $_.LocalPort -lt 49152 } | Sort-Object -Property LocalPort
    $ephemeralPorts = $processGroup.Group | Where-Object { $_.LocalPort -ge 49152 }
    $ephemeralCount = $ephemeralPorts.Count
    
    # Display each non-ephemeral port individually
    foreach ($port in $nonEphemeralPorts) {
        $portNumber = $port.LocalPort
        $portSecurity = Classify-PortSecurity -Port $portNumber
        $category = Categorize-Service -Port $portNumber
        $localAddress = $port.LocalAddress
        
        if ($localAddress -eq "0.0.0.0" -or $localAddress -eq "::") {
            $exposureLevel = "[EXTERNAL]"
        } else {
            $exposureLevel = "[INTERNAL]"
        }
        
        Write-Output "Port $portNumber ($localAddress): $processName (PID: $processId) [$portSecurity] [$category] $exposureLevel"
    }
    
    # Summarize ephemeral ports for this process, if any
    if ($ephemeralCount -gt 0) {
        # Count how many external vs internal
        $externalEphemeral = $ephemeralPorts | Where-Object { $_.LocalAddress -eq "0.0.0.0" -or $_.LocalAddress -eq "::" } | Measure-Object | Select-Object -ExpandProperty Count
        $internalEphemeral = $ephemeralCount - $externalEphemeral
        
        # Get the min and max port numbers for context
        $minEphemeralPort = ($ephemeralPorts | Measure-Object -Property LocalPort -Minimum).Minimum
        $maxEphemeralPort = ($ephemeralPorts | Measure-Object -Property LocalPort -Maximum).Maximum
        
        $exposureSummary = "[$externalEphemeral external, $internalEphemeral internal]"
        
        Write-Output "$processName (PID: $processId): $ephemeralCount ephemeral TCP ports in range $minEphemeralPort-$maxEphemeralPort $exposureSummary" -ForegroundColor Yellow
    }
}

Print-SubHeader "UDP Listening Endpoints"

# Get all UDP endpoints and group them by process
$udpPortGroupsByProcess = $listeningUdpPorts | Group-Object -Property OwningProcess

# Process each group
foreach ($processGroup in $udpPortGroupsByProcess) {
    $processId = $processGroup.Name
    $processInfo = Get-Process -Id $processId -ErrorAction SilentlyContinue
    $processName = if ($processInfo) { $processInfo.ProcessName } else { "Unknown" }
    
    # Split the ports for this process into non-ephemeral and ephemeral
    $nonEphemeralPorts = $processGroup.Group | Where-Object { $_.LocalPort -lt 49152 } | Sort-Object -Property LocalPort
    $ephemeralPorts = $processGroup.Group | Where-Object { $_.LocalPort -ge 49152 }
    $ephemeralCount = $ephemeralPorts.Count
    
    # Display each non-ephemeral port individually
    foreach ($port in $nonEphemeralPorts) {
        $portNumber = $port.LocalPort
        $portSecurity = Classify-PortSecurity -Port $portNumber
        $category = Categorize-Service -Port $portNumber
        $localAddress = $port.LocalAddress
        
        if ($localAddress -eq "0.0.0.0" -or $localAddress -eq "::") {
            $exposureLevel = "[EXTERNAL]"
        } else {
            $exposureLevel = "[INTERNAL]"
        }
        
        Write-Output "Port $portNumber ($localAddress): $processName (PID: $processId) [$portSecurity] [$category] $exposureLevel"
    }
    
    # Summarize ephemeral ports for this process, if any
    if ($ephemeralCount -gt 0) {
        # Count how many external vs internal
        $externalEphemeral = $ephemeralPorts | Where-Object { $_.LocalAddress -eq "0.0.0.0" -or $_.LocalAddress -eq "::" } | Measure-Object | Select-Object -ExpandProperty Count
        $internalEphemeral = $ephemeralCount - $externalEphemeral
        
        # Get the min and max port numbers for context
        $minEphemeralPort = ($ephemeralPorts | Measure-Object -Property LocalPort -Minimum).Minimum
        $maxEphemeralPort = ($ephemeralPorts | Measure-Object -Property LocalPort -Maximum).Maximum
        
        $exposureSummary = "[$externalEphemeral external, $internalEphemeral internal]"
        
        Write-Output "$processName (PID: $processId): $ephemeralCount ephemeral UDP ports in range $minEphemeralPort-$maxEphemeralPort $exposureSummary" -ForegroundColor Yellow
    }
}
Write-Output ""

# ------- PROCESS NETWORK ACTIVITY ANALYSIS -------
Print-Header "PROCESS NETWORK ACTIVITY ANALYSIS"

Print-SubHeader "Processes With Most Connections"
$allTcpProcesses = Get-NetTCPConnection | Group-Object -Property OwningProcess
$allUdpProcesses = Get-NetUDPEndpoint | Group-Object -Property OwningProcess

$combinedProcesses = @{}

foreach ($proc in $allTcpProcesses) {
    $processId = $proc.Name
    $processInfo = Get-Process -Id $processId -ErrorAction SilentlyContinue
    
    if ($processInfo) {
        $processName = $processInfo.ProcessName
        $connCount = $proc.Count
        
        if ($combinedProcesses.ContainsKey($processId)) {
            $combinedProcesses[$processId].Connections += $connCount
        } else {
            $combinedProcesses[$processId] = @{
                ProcessName = $processName
                Connections = $connCount
                CPU = $processInfo.CPU
                Memory = [math]::Round(($processInfo.WorkingSet / 1MB), 2)
                User = (Get-WmiObject -Class Win32_Process -Filter "ProcessId = '$processId'").GetOwner().User
            }
        }
    }
}

foreach ($proc in $allUdpProcesses) {
    $processId = $proc.Name
    $processInfo = Get-Process -Id $processId -ErrorAction SilentlyContinue
    
    if ($processInfo) {
        $processName = $processInfo.ProcessName
        $connCount = $proc.Count
        
        if ($combinedProcesses.ContainsKey($processId)) {
            $combinedProcesses[$processId].Connections += $connCount
        } else {
            $combinedProcesses[$processId] = @{
                ProcessName = $processName
                Connections = $connCount
                CPU = $processInfo.CPU
                Memory = [math]::Round(($processInfo.WorkingSet / 1MB), 2)
                User = (Get-WmiObject -Class Win32_Process -Filter "ProcessId = '$processId'").GetOwner().User
            }
        }
    }
}

# Sort by connection count and display
$sortedProcesses = $combinedProcesses.GetEnumerator() | 
    Sort-Object -Property { $_.Value.Connections } -Descending

foreach ($proc in $sortedProcesses) {
    $processId = $proc.Key
    $processName = $proc.Value.ProcessName
    $connCount = $proc.Value.Connections
    $cpuUsage = if ($proc.Value.CPU) { [math]::Round($proc.Value.CPU, 2) } else { 0 }
    $memoryUsage = $proc.Value.Memory
    $user = $proc.Value.User
    
    $status = if ($connCount -gt 20) {
        "[HIGH]"
    } elseif ($connCount -gt 10) {
        "[MODERATE]"
    } else {
        ""
    }
    
    Write-Output "$processName (PID: $processId, User: $user) - $connCount connections $status - CPU: $cpuUsage%, MEM: $memoryUsage MB"
}
Write-Output ""

# ------- SUSPICIOUS CONNECTION PATTERNS -------
Print-Header "SUSPICIOUS CONNECTION PATTERNS"

Print-SubHeader "Top External IPs"
$topExternalIPs = $establishedConnections | 
    Group-Object -Property RemoteAddress | 
    Where-Object { $_.Name -ne "127.0.0.1" -and $_.Name -ne "::1" -and -not $_.Name.StartsWith("fe80:") } |
    Sort-Object -Property Count -Descending | 
    Select-Object -First 10

foreach ($ip in $topExternalIPs) {
    $count = $ip.Count
    $address = $ip.Name
    
    # Try to do a DNS lookup
    try {
        $dnsInfo = [System.Net.Dns]::GetHostEntry($address).HostName
        Write-Output "$count connections to $address ($dnsInfo)"
    } catch {
        Write-Output "$count connections to $address"
    }
}

Print-SubHeader "High Port Connections (potentially suspicious)"
$highPortConnections = $establishedConnections | 
    Where-Object { $_.RemotePort -ge 40000 } | 
    Sort-Object -Property RemotePort |
    Select-Object -First 10

foreach ($conn in $highPortConnections) {
    $remoteIP = $conn.RemoteAddress
    $remotePort = $conn.RemotePort
    $localPort = $conn.LocalPort
    $processId = $conn.OwningProcess
    $processInfo = Get-Process -Id $processId -ErrorAction SilentlyContinue
    $processName = if ($processInfo) { $processInfo.ProcessName } else { "Unknown" }
    
    Write-Output "Connection to $remoteIP`:$remotePort from local port $localPort - Process: $processName (PID: $processId)"
}
Write-Output ""

# ------- INTERFACES AND ROUTES -------
Print-Header "NETWORK INTERFACE SUMMARY"

Print-SubHeader "Network Interfaces"
$networkAdapters = Get-NetAdapter | Where-Object Status -eq 'Up'

foreach ($adapter in $networkAdapters) {
    $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex | 
                Where-Object AddressFamily -eq 'IPv4'
    
    Write-Output "Interface: $($adapter.Name) ($($adapter.InterfaceDescription))"
    Write-Output "  MAC Address: $($adapter.MacAddress)"
    Write-Output "  Status: $($adapter.Status)"
    Write-Output "  Speed: $([math]::Round($adapter.LinkSpeed / 1000000)) Mbps"
    
    foreach ($ip in $ipConfig) {
        Write-Output "  IPv4 Address: $($ip.IPAddress)/$($ip.PrefixLength)"
    }
    
    # Get default gateway
    $gateway = Get-NetRoute -InterfaceIndex $adapter.ifIndex | 
               Where-Object { $_.DestinationPrefix -eq '0.0.0.0/0' }
    
    if ($gateway) {
        Write-Output "  Default Gateway: $($gateway.NextHop)"
    }
    
    Write-Output ""
}

Print-SubHeader "Routing Table"
$routes = Get-NetRoute | Where-Object AddressFamily -eq 'IPv4' | 
          Sort-Object -Property DestinationPrefix
          
Write-Output "Destination     Gateway         Interface       Metric"
Write-Output "-----------     -------         ---------       ------"
foreach ($route in $routes) {
    $destPrefix = $route.DestinationPrefix.PadRight(15)
    $nextHop = $route.NextHop.PadRight(15)
    $ifIndex = (Get-NetAdapter -InterfaceIndex $route.InterfaceIndex).Name.PadRight(15)
    $metric = $route.RouteMetric
    
    Write-Output "$destPrefix $nextHop $ifIndex $metric"
}
Write-Output ""

# ------- DNS CONFIGURATION -------
Print-Header "DNS CONFIGURATION"

Print-SubHeader "DNS Client Configuration"
$dnsServers = Get-DnsClientServerAddress | 
              Where-Object { $_.AddressFamily -eq 2 -and $_.ServerAddresses } |
              Select-Object -Property InterfaceAlias, ServerAddresses

foreach ($dns in $dnsServers) {
    Write-Output "Interface: $($dns.InterfaceAlias)"
    Write-Output "  DNS Servers: $($dns.ServerAddresses -join ', ')"
}

Print-SubHeader "DNS Resolution Test"
try {
    $dnsTest = Resolve-DnsName -Name "google.com" -Type A -ErrorAction Stop | 
               Select-Object -First 1 -Property Name, IPAddress

    Write-Output "DNS Resolution Test (google.com):"
    Write-Output "  Name: $($dnsTest.Name)"
    Write-Output "  IP Address: $($dnsTest.IPAddress)"
} catch {
    Write-Output "DNS Resolution Test failed: $_"
}
Write-Output ""

# ------- LOCAL PORT SCAN -------
Print-Header "LOCAL PORT SCAN SUMMARY"

Print-SubHeader "Open Ports on localhost"
$localPorts = $listeningPorts | 
              Where-Object { $_.LocalAddress -eq "127.0.0.1" -or $_.LocalAddress -eq "::1" } |
              Sort-Object -Property LocalPort

foreach ($port in $localPorts) {
    $portNumber = $port.LocalPort
    $processId = $port.OwningProcess
    $processInfo = Get-Process -Id $processId -ErrorAction SilentlyContinue
    $processName = if ($processInfo) { $processInfo.ProcessName } else { "Unknown" }
    $category = Categorize-Service -Port $portNumber
    
    Write-Output "Port $portNumber`: $processName (PID: $processId) [$category]"
}
Write-Output ""


# ------- FIREWALL CONFIGURATION -------
Print-Header "WINDOWS FIREWALL CONFIGURATION"

Print-SubHeader "Firewall Profiles Status"
$firewallProfiles = Get-NetFirewallProfile

foreach ($profile in $firewallProfiles) {
    $status = if ($profile.Enabled) { "Enabled" } else { "Disabled" }
    Write-Output "$($profile.Name) Profile: $status"
    Write-Output "  Default Inbound Action: $($profile.DefaultInboundAction)"
    Write-Output "  Default Outbound Action: $($profile.DefaultOutboundAction)"
}

Print-SubHeader "Potentially Risky Firewall Rules"
$inboundRules = Get-NetFirewallRule | 
                Where-Object { 
                    $_.Direction -eq "Inbound" -and 
                    $_.Enabled -eq $true -and 
                    $_.Action -eq "Allow"
                }

$riskyRules = $inboundRules | Where-Object {
    ($_.DisplayName -match "Remote|Admin|Management|RDP|SSH|Telnet|Database|SQL|MySQL") -or
    ($_.Profile -eq "Any" -or $_.Profile -eq "Public")
}

if ($riskyRules) {
    foreach ($rule in $riskyRules) {
        $ports = $rule | Get-NetFirewallPortFilter
        $addresses = $rule | Get-NetFirewallAddressFilter
        
        Write-Output "Rule: $($rule.DisplayName)"
        Write-Output "  Direction: $($rule.Direction)"
        Write-Output "  Action: $($rule.Action)"
        Write-Output "  Profile: $($rule.Profile)"
        
        if ($ports) {
            Write-Output "  Protocol: $($ports.Protocol)"
            if ($ports.LocalPort) {
                Write-Output "  Local Ports: $($ports.LocalPort -join ', ')"
            }
            if ($ports.RemotePort) {
                Write-Output "  Remote Ports: $($ports.RemotePort -join ', ')"
            }
        }
        
        if ($addresses) {
            if ($addresses.RemoteAddress -contains "Any") {
                Write-Output "  Remote Address: Any [HIGH RISK]"
            } else {
                Write-Output "  Remote Address: $($addresses.RemoteAddress -join ', ')"
            }
        }
        
        Write-Output ""
    }
} else {
    Write-Output "No obviously risky firewall rules found."
}
Write-Output ""

# ------- SMB SHARES ANALYSIS -------
Print-Header "SMB SHARES ANALYSIS"

Print-SubHeader "Shared Folders"
$shares = Get-WmiObject -Class Win32_Share | Where-Object { $_.Name -notmatch '^\w\$' }

foreach ($share in $shares) {
    $shareName = $share.Name
    $sharePath = $share.Path
    $shareDesc = $share.Description
    
    # Assess risk level
    $riskLevel = "STANDARD"
    if ($shareName -in @("C$", "ADMIN$", "IPC$")) {
        $riskLevel = "ADMIN"
    } elseif ($sharePath -match "^[A-Z]:\\$") {
        $riskLevel = "CRITICAL" # Root drive shares
    }
    
    Write-Output "Share: $shareName"
    Write-Output "  Path: $sharePath"
    if ($shareDesc) { Write-Output "  Description: $shareDesc" }
    Write-Output "  Risk Level: [$riskLevel]"
    
    # Try to get permissions
    try {
        $acl = Get-Acl -Path $sharePath -ErrorAction Stop
        $permissions = $acl.Access | Where-Object { $_.IdentityReference -match "Everyone|ANONYMOUS|Authenticated Users" }
        
        if ($permissions) {
            Write-Output "  SECURITY CONCERN: Found overly permissive access:" -ForegroundColor Red
            foreach ($perm in $permissions) {
                Write-Output "    $($perm.IdentityReference) has $($perm.FileSystemRights) rights" -ForegroundColor Red
            }
        }
    } catch {
        Write-Output "  Unable to retrieve permissions: $($_.Exception.Message)"
    }
    
    Write-Output ""
}

# ------- SCHEDULED TASKS ANALYSIS -------
Print-Header "SCHEDULED TASKS ANALYSIS"

Print-SubHeader "Potentially Suspicious Scheduled Tasks"
$tasks = Get-ScheduledTask | Where-Object { 
    $_.State -eq "Ready" -and
    ($_.TaskPath -notmatch "Microsoft|Windows" -or $_.Actions.Execute -match "powershell|cmd|wscript|cscript") 
}

if ($tasks) {
    foreach ($task in $tasks) {
        $taskInfo = $task | Get-ScheduledTaskInfo
        $lastRunTime = if ($taskInfo.LastRunTime -gt [DateTime]::MinValue) { $taskInfo.LastRunTime } else { "Never" }
        
        Write-Output "Task: $($task.TaskName)"
        Write-Output "  Path: $($task.TaskPath)"
        Write-Output "  Last Run: $lastRunTime"
        Write-Output "  Run As: $($task.Principal.UserId)"
        
        $actions = $task.Actions
        foreach ($action in $actions) {
            Write-Output "  Action: $($action.Execute) $($action.Arguments)"
        }
        
        $triggers = $task.Triggers
        if ($triggers) {
            Write-Output "  Triggers:"
            foreach ($trigger in $triggers) {
                $triggerType = $trigger.GetType().Name
                Write-Output "    $triggerType"
            }
        }
        
        Write-Output ""
    }
} else {
    Write-Output "No suspicious scheduled tasks found."
}
Write-Output ""

# ------- CONCLUSION -------
Print-Header "SECURITY ANALYSIS SUMMARY"

# Count suspicious ports
$suspiciousPortsList = @(21, 23, 1433, 1434, 3306, 3389, 5432, 5900, 5901)
$suspiciousPorts = $listeningPorts | 
                   Where-Object { $_.LocalPort -in $suspiciousPortsList -and ($_.LocalAddress -eq "0.0.0.0" -or $_.LocalAddress -eq "::") } |
                   Measure-Object |
                   Select-Object -ExpandProperty Count

$highConnIPs = $establishedConnections | 
               Group-Object -Property RemoteAddress |
               Where-Object { $_.Count -gt 10 } |
               Measure-Object |
               Select-Object -ExpandProperty Count

Write-Output "Analysis completed at $(Get-Timestamp)"
Write-Output "Potentially vulnerable services exposed: $suspiciousPorts"
Write-Output "High-connection external IPs: $highConnIPs"
Write-Output ""

# Overall security posture assessment
$securityConcerns = 0
$securityConcerns += $suspiciousPorts
$securityConcerns += if ($webCount -gt 0 -and (Get-NetFirewallRule | Where-Object { $_.DisplayName -match "HTTP" -and $_.Enabled -eq $true -and $_.Action -eq "Allow" })) { 1 } else { 0 }
$securityConcerns += if ((Get-Service | Where-Object { $_.DisplayName -match "Remote Desktop" -and $_.Status -eq "Running" })) { 1 } else { 0 }
$securityConcerns += if ((Get-NetFirewallProfile | Where-Object { -not $_.Enabled })) { 2 } else { 0 }

# Add a flag specifically for high-port DNS concerns
$dnsHighPortConcern = $false
$dnsProcesses = Get-Process -Name dns -ErrorAction SilentlyContinue
if ($dnsProcesses) {
    $dnsProcessIds = $dnsProcesses.Id
    $dnsExternalPorts = $listeningPorts | Where-Object { 
        $_.OwningProcess -in $dnsProcessIds -and 
        ($_.LocalAddress -eq "0.0.0.0" -or $_.LocalAddress -eq "::") -and
        $_.LocalPort -gt 50000
    } | Measure-Object | Select-Object -ExpandProperty Count
    
    if ($dnsExternalPorts -gt 50) {
        Write-Output ""
        Write-Output "NOTE: High number of ephemeral DNS ports detected ($dnsExternalPorts ports)" -ForegroundColor Cyan
        Write-Output "This is often normal behavior for busy DNS servers, but you may want to check for DNS" -ForegroundColor Cyan
        Write-Output "amplification attack potential by reviewing your DNS configuration." -ForegroundColor Cyan
        Write-Output ""
        
        $dnsHighPortConcern = $true
    }
}

# ------- SECURITY ROLE PROFILE -------
Print-Header "SYSTEM SECURITY ROLE PROFILE"

# Determine system role based on listening ports
$webServerPorts = @(80, 443, 8080, 8443)
$dbServerPorts = @(1433, 3306, 5432, 1521)
$mailServerPorts = @(25, 587, 110, 143, 993, 995)
$fileServerPorts = @(445, 139, 137, 138)
$domainControllerPorts = @(389, 636, 88, 464)

$listeningPortNumbers = $listeningPorts.LocalPort

$webCount = $listeningPortNumbers | Where-Object { $_ -in $webServerPorts } | Measure-Object | Select-Object -ExpandProperty Count
$dbCount = $listeningPortNumbers | Where-Object { $_ -in $dbServerPorts } | Measure-Object | Select-Object -ExpandProperty Count
$mailCount = $listeningPortNumbers | Where-Object { $_ -in $mailServerPorts } | Measure-Object | Select-Object -ExpandProperty Count
$fileCount = $listeningPortNumbers | Where-Object { $_ -in $fileServerPorts } | Measure-Object | Select-Object -ExpandProperty Count
$dcCount = $listeningPortNumbers | Where-Object { $_ -in $domainControllerPorts } | Measure-Object | Select-Object -ExpandProperty Count

# Determine likely role
if ($dcCount -ge 3) {
    Write-Output "LIKELY ROLE: DOMAIN CONTROLLER"
    Write-Output "This system appears to be running Active Directory domain services."
    Write-Output "Security recommendations:"
    Write-Output "- Ensure LDAPS (636) is used rather than unencrypted LDAP (389) where possible"
    Write-Output "- Verify Kerberos configuration is using strong encryption"
    Write-Output "- Implement proper Group Policy security settings"
    Write-Output "- Regularly monitor security logs for suspicious authentication attempts"
    Write-Output "- Ensure the system is properly patched with the latest updates"
} elseif ($webCount -ge 2) {
    Write-Output "LIKELY ROLE: WEB SERVER"
    Write-Output "This system appears to be running web services."
    Write-Output "Security recommendations:"
    Write-Output "- Ensure web applications are regularly patched and updated"
    Write-Output "- Verify proper TLS configuration on HTTPS ports"
    Write-Output "- Consider implementing a web application firewall"
    Write-Output "- Disable unnecessary services and features"
    Write-Output "- Check for secure configurations in web server software"
} elseif ($dbCount -gt 0) {
    Write-Output "LIKELY ROLE: DATABASE SERVER"
    Write-Output "This system appears to be running database services."
    Write-Output "Security recommendations:"
    Write-Output "- Restrict database access to specific IP addresses where possible"
    Write-Output "- Ensure databases are regularly backed up and patches applied"
    Write-Output "- Verify proper authentication mechanisms are enforced"
    Write-Output "- Enable database auditing for sensitive operations"
    Write-Output "- Use strong encryption for data at rest and in transit"
} elseif ($mailCount -ge 2) {
    Write-Output "LIKELY ROLE: MAIL SERVER"
    Write-Output "This system appears to be running mail services."
    Write-Output "Security recommendations:"
    Write-Output "- Implement proper SPF, DKIM, and DMARC records"
    Write-Output "- Ensure TLS is properly configured for mail transport"
    Write-Output "- Monitor for suspicious mail relay attempts"
    Write-Output "- Configure proper spam filtering"
    Write-Output "- Ensure mail server software is regularly updated"
} elseif ($fileCount -ge 3) {
    Write-Output "LIKELY ROLE: FILE SERVER"
    Write-Output "This system appears to be running file sharing services."
    Write-Output "Security recommendations:"
    Write-Output "- Implement proper file and share permissions"
    Write-Output "- Consider enabling SMB encryption for sensitive data"
    Write-Output "- Disable older, insecure SMB versions (SMBv1)"
    Write-Output "- Regularly audit file access"
    Write-Output "- Implement proper backup solutions"
} else {
    Write-Output "LIKELY ROLE: MULTI-PURPOSE SERVER"
    Write-Output "This system appears to be running multiple types of services."
    Write-Output "Security recommendations:"
    Write-Output "- Consider separating services to different servers where appropriate"
    Write-Output "- Ensure each service is properly secured and isolated"
    Write-Output "- Implement proper network segmentation"
    Write-Output "- Regularly audit all running services"
    Write-Output "- Disable unnecessary features and roles"
}
Write-Output ""

if ($securityConcerns -ge 3) {
    Write-Output "OVERALL SECURITY ASSESSMENT: HIGH CONCERN"
    Write-Output "Multiple security issues detected that require immediate attention."
} elseif ($securityConcerns -ge 1) {
    Write-Output "OVERALL SECURITY ASSESSMENT: MODERATE CONCERN"
    Write-Output "Some security issues detected that should be reviewed."
} else {
    Write-Output "OVERALL SECURITY ASSESSMENT: LOW CONCERN"
    Write-Output "No obvious security issues detected, but regular monitoring is still recommended."
}
