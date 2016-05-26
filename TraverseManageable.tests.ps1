#requires -module PoshRSJob,SharpSNMP

#region Includes
function Test-TCPPort {
<#
.SYNOPSIS 
    Does a TCP connection on specified port (135 by default)
.LINK
    http://poshcode.org/85
#>
    [CmdletBinding()]
    Param(
        [string]$ComputerName,
        [int]$Port=135,
        [int]$Timeout=3
    )
 

 
    $ErrorActionPreference = "SilentlyContinue"
 
    # Create TCP Client
    $tcpclient = new-Object system.Net.Sockets.TcpClient
 
    # Tell TCP Client to connect to machine on Port
    $iar = $tcpclient.BeginConnect($ComputerName,$Port,$null,$null)
 
    # Set the wait time
    $wait = $iar.AsyncWaitHandle.WaitOne($Timeout*1000,$false)
 
    # Check to see if the connection is done
    if(!$wait)
    {
        # Close the connection and report timeout
        $tcpclient.Close()
        if($verbose){Write-verbose "Connection Timeout"}
        Return $false
    }
    else
    {
        # Close the connection and report the error if there is one
        $error.Clear()
        $tcpclient.EndConnect($iar) | out-Null
        if(!$?){if($verbose){write-verbose $error[0]};$failed = $true}
        $tcpclient.Close()
    }
 
    # Return $true if connection Establish else $False
    if($failed){return $false}else{return $true}
} #Test-TCPPort

function Get-ComputerVirtualStatus {
    <# 
    .SYNOPSIS 
    Validate if a remote server is virtual or physical 
    .DESCRIPTION 
    Uses wmi (along with an optional credential) to determine if a remote computers, or list of remote computers are virtual. 
    If found to be virtual, a best guess effort is done on which type of virtual platform it is running on. 
    .PARAMETER ComputerName 
    Computer or IP address of machine 
    .PARAMETER Credential 
    Provide an alternate credential 
    .EXAMPLE 
    $Credential = Get-Credential 
    Get-RemoteServerVirtualStatus 'Server1','Server2' -Credential $Credential | select ComputerName,IsVirtual,VirtualType | ft 
     
    Description: 
    ------------------ 
    Using an alternate credential, determine if server1 and server2 are virtual. Return the results along with the type of virtual machine it might be. 
    .EXAMPLE 
    (Get-RemoteServerVirtualStatus server1).IsVirtual 
     
    Description: 
    ------------------ 
    Determine if server1 is virtual and returns either true or false. 

    .LINK 
    http://www.the-little-things.net/ 
    .LINK 
    http://nl.linkedin.com/in/zloeber 
    .NOTES 
     
    Name       : Get-RemoteServerVirtualStatus 
    Version    : 1.1.0 12/09/2014
                 - Removed prompt for credential
                 - Refactored some of the code a bit.
                 1.0.0 07/27/2013 
                 - First release 
    Author     : Zachary Loeber 
    #> 
    [cmdletBinding(SupportsShouldProcess = $true)] 
    param( 
        [parameter(Position=0, ValueFromPipeline=$true, HelpMessage="Computer or IP address of machine to test")] 
        [string[]]$ComputerName = $env:COMPUTERNAME, 
        [parameter(HelpMessage="Pass an alternate credential")] 
        [System.Management.Automation.PSCredential]$Credential = $null 
    ) 
    begin {
        $WMISplat = @{} 
        if ($Credential -ne $null) { 
            $WMISplat.Credential = $Credential 
        } 
        $results = @()
        $computernames = @()
    } 
    process { 
        $computernames += $ComputerName 
    } 
    end {
        foreach($computer in $computernames) { 
            $WMISplat.ComputerName = $computer 
            try { 
                $wmibios = Get-WmiObject Win32_BIOS @WMISplat -ErrorAction Stop | Select-Object version,serialnumber 
                $wmisystem = Get-WmiObject Win32_ComputerSystem @WMISplat -ErrorAction Stop | Select-Object model,manufacturer
                $ResultProps = @{
                    ComputerName = $computer 
                    BIOSVersion = $wmibios.Version 
                    SerialNumber = $wmibios.serialnumber 
                    Manufacturer = $wmisystem.manufacturer 
                    Model = $wmisystem.model 
                    IsVirtual = $false 
                    VirtualType = $null 
                }
                if ($wmibios.SerialNumber -like "*VMware*") {
                    $ResultProps.IsVirtual = $true
                    $ResultProps.VirtualType = "Virtual - VMWare"
                }
                else {
                    switch -wildcard ($wmibios.Version) {
                        'VIRTUAL' { 
                            $ResultProps.IsVirtual = $true 
                            $ResultProps.VirtualType = "Virtual - Hyper-V" 
                        } 
                        'A M I' {
                            $ResultProps.IsVirtual = $true 
                            $ResultProps.VirtualType = "Virtual - Virtual PC" 
                        } 
                        '*Xen*' { 
                            $ResultProps.IsVirtual = $true 
                            $ResultProps.VirtualType = "Virtual - Xen" 
                        }
                    }
                }
                if (-not $ResultProps.IsVirtual) {
                    if (($wmisystem.manufacturer -like "*Microsoft*") -and ($wmisystem.model -notmatch "Surface")) 
                    { 
                        $ResultProps.IsVirtual = $true 
                        $ResultProps.VirtualType = "Virtual - Hyper-V" 
                    } 
                    elseif ($wmisystem.manufacturer -like "*VMWare*") 
                    { 
                        $ResultProps.IsVirtual = $true 
                        $ResultProps.VirtualType = "Virtual - VMWare" 
                    } 
                    elseif ($wmisystem.model -like "*Virtual*") { 
                        $ResultProps.IsVirtual = $true
                        $ResultProps.VirtualType = "Unknown Virtual Machine"
                    }
                }
                $results += New-Object PsObject -Property $ResultProps
            }
            catch {
                Throw "Cannot connect to $computer"
            } 
        } 
        return $results 
    } 
} #Get-ComputerVirtualStatus

#endregion

#region Main
$ComputerName = 'localhost'
$SNMPCommunity = 'public'
$SNMPUPTIMEOID = '1.3.6.1.2.1.1.3.0'
$SNMPPort = '1161'
$Probe
$Timeout = 3

Describe "Host Networking" {
    It "Responds to ICMP Ping" {
        Test-Connection -Quiet -Count 2 -ComputerName $ComputerName | Should Be $true
    }
}

Describe "Windows Remote Management" {
    It "Responds to RPC TCP Port within $Timeout seconds" {
        Test-TCPPort -ComputerName $ComputerName -Timeout $Timeout -Port 135 | Should Be $true
    }
    It "Responds to RDP TCP Port within $Timeout seconds" {
        Test-TCPPort -ComputerName $ComputerName -Timeout $Timeout -Port 3389 | Should Be $true
    }

    $MakeModelResult = $null
    It "Returns a WMI Computer Manufacturer and Model within $Timeout seconds" {
        $MakeModelResult = Get-WMIObject -Computername $ComputerName Win32_ComputerSystem -asjob | wait-job -timeout $Timeout | Receive-Job
        $MakeModelResult.Manufacturer | Should Not BeNullOrEmpty
        $MakeModelResult.Model | Should Not BeNullOrEmpty
    }
    It "  RESULT: WMI Manufacturer: $MakeModelResult.Manufacturer" {
        #Placeholder
        $null = $null
    }
    
}

Describe "Host SNMP" {
    It "Responds to an SNMPv2 Get Query for System.SysUptime.0 within $Timeout seconds" {
        $result = (Invoke-SnmpGet -ErrorAction Stop -ComputerName $ComputerName -Community $SNMPCommunity -UDPport $SNMPPort -ObjectIdentifier $SNMPUPTIMEOID -Timeout ($Timeout*1000)).data
        $result | Should Not BeNullOrEmpty
        write-verbose "Host SNMP Uptime: $result"
    }
}

Describe "Windows SNMP Service" {
    It "Windows SNMP Service is Installed" {
        $WMIResult = Get-WMIObject -Computername $ComputerName Win32_Service -Filter "Name='snmp'" -asjob | 
            wait-job -timeout $Timeout | 
            Receive-Job |
            Should Not BeNullOrEmpty
    }

    It "Windows SNMP Service is Running" {
        $WMIResult = Get-WMIObject -Computername $ComputerName Win32_Service -Filter "Name='snmp'" -asjob | 
            wait-job -timeout $Timeout | 
            Receive-Job
        $WmiResult.State | Should Be "Running"
        write-verbose "Host SNMP Windows Service State: $($WmiResult.State)"
    }

    It "Windows SNMP Service is Running" {
        $WMIResult = Get-WMIObject -Computername $ComputerName Win32_Service -Filter "Name='snmp'" -asjob | 
            wait-job -timeout $Timeout | 
            Receive-Job
        $WmiResult.State | Should Be "Running"
    }
}

Describe "Physical Server" {
    It "Is a Physical Server" {
        (Get-ComputerVirtualStatus $ComputerName).IsVirtual | Should Be $False
    }
}

Describe "Virtual Server" {
    It "Is a Virtual Server" {
        (Get-ComputerVirtualStatus $ComputerName).IsVirtual | Should Be $True
    }
}



#endregion Main