function Test-TCPPort {

Param([string]$srv,$port=135,$timeout=3000,[switch]$verbose)

# Test-Port.ps1
# Does a TCP connection on specified port (135 by default)

$ErrorActionPreference = "SilentlyContinue"

# Create TCP Client
$tcpclient = new-Object system.Net.Sockets.TcpClient

# Tell TCP Client to connect to machine on Port
$iar = $tcpclient.BeginConnect($srv,$port,$null,$null)

# Set the wait time
$wait = $iar.AsyncWaitHandle.WaitOne($timeout,$false)

# Check to see if the connection is done
if(!$wait)
{
    # Close the connection and report timeout
    $tcpclient.Close()
    if($verbose){Write-Host "Connection Timeout"}
    Return $false
}
else
{
    # Close the connection and report the error if there is one
    $error.Clear()
    $tcpclient.EndConnect($iar) | out-Null
    if(!$?){if($verbose){write-host $error[0]};$failed = $true}
    $tcpclient.Close()
}

# Return $true if connection Establish else $False
if($failed){return $false}else{return $true}

}