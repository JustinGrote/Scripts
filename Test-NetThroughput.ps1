#Requires -version 3.0

<#
.SYNOPSIS
Connect to a remote computer via powershell and run two speed tests: One for Internet bandwidth and one to the source computer.

#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName="ComputerName")]$ComputerName,
    [Switch]$InternetOnly,
    $ToolsRootPath="$PSScriptRoot\PerfTools",
    $WarmupSeconds=2,
    $TestDurationSeconds=5,
    $TestParallelStreams=5,
    $TestTCPWindowSize="128K"
)

begin {
    $PSComputerName = $env:COMPUTERNAME
    #Start an iPerf Server for use as a target
    $iPerfProcess = start-process "$ToolsRootPath\iperf.exe" -ArgumentList "-s" -passthru -windowstyle Hidden
}


process {
#Unpack any passed arrays
foreach ($ComputerName in $ComputerName) {

    #Create a result properties hashtable
    $resultProps = [ordered]@{}
    $resultProps.Computername = $ComputerName

    #Make sure remoting is enabled
    try {
    write-verbose "$ComputerName`: Connecting..."
    $RemoteSession = New-PSSession $ComputerName -ErrorAction stop
    if (!($RemoteSession)) {throw "Remote Session is not valid"}


    #Get a temp path on the remote computer to place the required tools
    $RemoteTempPath = Invoke-Command -session $RemoteSession {$env:temp} -ErrorAction stop
    $RemoteTempPathUNC = $RemoteTempPath -replace '^C\:',"\\$ComputerName\C`$"
    }
    catch {
        $connectError = $error[0]
        write-error -message $ConnectError.Message
        return
    }


    #Place the tools on the remote computer
    if (!(test-path $RemoteTempPathUNC\PerfTools\iperf.exe)) {
    write-verbose "$ComputerName`: Copying Performance Test tools"
    Copy-Item $ToolsRootPath $RemoteTempPathUNC -recurse -Force
    }

    if (!($InternetOnly)) {

        #Run a Speed Test to the local computer
        write-verbose "$ComputerName`: Testing Upload Speed to Probe"
        $iPerfResultsJSON = invoke-command -session $remotesession {& $USING:RemoteTempPath\PerfTools\iperf.exe --client $USING:PSComputerName --time $USING:TestDurationSeconds --omit $USING:WarmUpSeconds --json --parallel $USING:TestParallelStreams --window $USING:TestTCPWindowSize }
        $iPerfResults = [string]$iPerfResultsJSON | ConvertFrom-JSON

        write-verbose "$ComputerName`: Testing Download Speed from Probe"
        $iPerfResultsRJSON = invoke-command -session $remotesession {& $USING:RemoteTempPath\PerfTools\iperf.exe --client $USING:PSComputerName --time $USING:TestDurationSeconds --omit $USING:WarmUpSeconds --json --parallel $USING:TestParallelStreams --window $USING:TestTCPWindowSize --reverse }
        $iPerfResultsR = [string]$iPerfResultsRJSON | ConvertFrom-JSON
        
        $ResultProps.DownFromProbeMbps = [math]::Round(($iPerfResultsR.end.sum_received.bits_per_second / 1MB),1)
        $ResultProps.UpToProbeMbps = [math]::Round(($iPerfResults.end.sum_sent.bits_per_second / 1MB),1)
    }

    #Perform an Internet Speed Test and capture the upload and download
    write-verbose "$ComputerName`: Performing Internet Speed Test"
    $speedTestResultsRAW = invoke-command -session $remotesession {& $USING:RemoteTempPath\PerfTools\speedtest.exe -a max -r }
    $speedTestResults = ($speedTestResultsRAW | select -last 1).split('|')
    $ResultProps.DownInternetMbps = [math]::Round(($speedTestResults[4]/1KB),1)
    $ResultProps.UpInternetMbps = [math]::Round(($speedTestResults[5]/1KB),1)


    
    #Show Results
    new-object PSCustomObject -property $ResultProps

    #Cleanup Remote Session
    Remove-PSSession $RemoteSession
} #Foreach
} #Process

end {
    #Cleanup iPerf
    stop-process $iPerfProcess
}




