#region Main
function Test-Snmp {
    <#
    .SYNOPSIS
        Connects to a local or remote computer and gets the status of the SNMP agent. 
    .DESCRIPTION
        Designed as a healthtest to verify configuration and connectivity. Will return "true" for each non-result test. If a test listing, it is assumed to have not run, which may occur (for instance, if a system is not pingable, there's no point running a SNMP test).
    .NOTES
        Makes the following assumptions when checking the Windows SNMP config.
        * Computer is pingable
        * Computer has remote registry enabled
        * Computer is domain joined
        * Currently logged in credentials have administrative rights on the remote Computer

        The UDP Port Test is unreliable, as it will return "true" if the port is filtered rather than simply closed.
    .EXAMPLE
	Test-Snmp -computername demo.snmplabs.com
    #>

    [CmdletBinding()]
    param (
        #The DNS Hostname or IP Address of the system you wish to test. You may specify an array for multiple devices. Defaults to "localhost" if not specified.
        [Parameter(ValueFromPipeline)][String]$ComputerName = "localhost",

        #SNMP Community to test with. Defaults to "public" if not specified
        [String]$Community = "public",
        
		#SNMP OID to validate SNMP GET functionality. Defaults to "1.3.6.1.2.1.1.3.0" (System.SysUptime.0) if not specified.
	    [string[]]$ObjectIdentifier = "1.3.6.1.2.1.1.3.0",

        #UDP Port to use to perform SNMP queries. Defaults to 161 if not specified.
		[Parameter(Mandatory=$False)]
	    [int]$UDPPort = 161,

        #Check Microsoft SNMP config (only if SNMP tests fail). See Notes for Caveats
        [Switch]$CheckWindowsConfig,

        #Skip the ping check. Useful if the SNMP host is behind a firewall that blocks ICMP but SNMP is still available via UDP.
        [Switch]$NoPing
    )

    process {
        foreach ($Computer in $ComputerName) {
            Write-VerboseProgress -Activity "Test-Snmp" -status "$Computer" -CurrentOperation "Initializing Scan"
            #Create Array for Test Results and initialize all test variables for consistent objects
            $SNMPTestResultProps = [ordered]@{}
            $SNMPTestResultProps.ComputerName = $Computer
            $SNMPTestResultProps.Ping = $null
            $SNMPTestResultProps.SNMPGet = $null
            $SNMPTestResultProps.ResultSNMPGet = $null

            #Additional Properties for Windows Config check
            if ($CheckWindowsConfig) {
                $SNMPTestResultProps.RPCPort = $null
                $SNMPTestResultProps.WMIModel = $null
                $SNMPTestResultProps.ResultWMIModel = $null
                $SNMPTestResultProps.Registry = $null
            }

            #Ping to see if system is online. Stop here if it isn't.
            if (!$NoPing) {
                Write-VerboseProgress -Activity "Test-Snmp" -status "$Computer" -CurrentOperation "Pinging $Computer"

                try {
                    $SNMPTestResultProps.Ping = test-connection $Computer -count 2 -quiet -ErrorAction stop
                    if (!$SNMPTestResultProps.Ping) {throw "FAILED"}
                }
                catch {
                    $SNMPTestResultProps.Ping = $_.Exception.Message
                    return [PSCustomObject]$SNMPTestResultProps
                }
            }

            #Check if we can get the OID (SNMP system uptime by default and all systems should support this, so this not working is considered a failure)
            try {
                Write-VerboseProgress -Activity "Test-Snmp" -status "$Computer" -CurrentOperation "Performing SNMPv2 Get Test to port $UDPPort for $ObjectIdentifier using community $Community"
                $ResultSNMPGetRaw = Invoke-SnmpGet -ComputerName $Computer -Community $Community -ObjectIdentifier $ObjectIdentifier -UDPport $UDPPort -ErrorAction Stop
                $ResultSNMPGet = $ResultSNMPGetRaw.data

                if ($ResultSNMPGet -match "NoSuchInstance") {throw "OID Wasn't found on System"}
                if (!$ResultSNMPGet) {throw "No Data Returned"}

                $SNMPTestResultProps.SNMPGet = ($ResultSNMPGet -ne $null)
                $SNMPTestResultProps.ResultSNMPGet = $ResultSNMPGet
            }
            catch {
                $SNMPTestResultProps.SNMPGet = $_.Exception.Message
                $SNMPTestResultProps.ResultSNMPGet = $false
            }
            
            #Optional Microsoft Tests. Only run if SNMP Get Failed to save time.
            if ($CheckWindowsConfig -and ($SNMPTestResultProps.SNMPGet -ne $true)) {

                #RPC Port Test. Registry test has a long timeout that's not easily configurable, this is a fast way to avoid that.
                try {
                    Write-VerboseProgress -Activity "Test-Snmp" -status "$Computer" -CurrentOperation "Testing RPC Port"
                    #Uses Private Function Test-TCPPort as it's faster, cannot rely on test-netconnection as it's too new still.
                    $SNMPTestResultProps.RPCPort = Test-TCPPort -srv $Computer -InformationLevel Quiet
                    if (!$SNMPTestResultProps.RPCPort) {throw "FAILED"}
                }
                catch {
                    $SNMPTestResultProps.RPCPort = $_.Exception.Message
                    return [PSCustomObject]$SNMPTestResultProps
                }

                #Test WMI by fetching the Computer Model. Using the Job is an ugly workaround for Get-WMIObject's lack of a timeout.
                try {
                    Write-VerboseProgress -Activity "Test-Snmp" -status "$Computer" -CurrentOperation "Fetching Computer Make/Model via WMI"
                    $WMIGetComputerSystemJob = get-wmiobject Win32_ComputerSystem -computername $Computer -asjob -ErrorAction stop | wait-job -timeout 3 | receive-job
                }
                catch {
                    $SNMPTestResultProps.RPCPort = $_.Exception.Message
                    return [PSCustomObject]$SNMPTestResultProps                    
                }


                #Registry Access Test
                try {
                    Write-VerboseProgress -Activity "Test-Snmp" -status "$Computer" -CurrentOperation "Attempting Registry Connection"
                    $ErrorActionPreference = "Stop"
                    $RemoteRegistry = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey("LocalMachine",$Computer)
                    $ErrorActionPreference = "Continue"
                    $SNMPTestResultProps.Registry = ($RemoteRegistry -is [Microsoft.Win32.RegistryKey])
                    if (!$SNMPTestResultProps.Registry) {throw "FAILED"}
                }
                catch {
                    $SNMPTestResultProps.Registry = $_.Exception.Message
                    return [PSCustomObject]$SNMPTestResultProps
                }

            }
            
            #Return Full results if it worked
            [PSCustomObject]$SNMPTestResultProps
        }
    }


} #Test-Snmp
#endregion
