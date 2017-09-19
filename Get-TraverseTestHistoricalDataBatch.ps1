#requires -version 3
#requires -module Traverse
#requires -module ImportExcel
[CmdletBinding()]

param (
    #Which Devices to gather history for. Use * for all devices. Regex expressions are supported
    [Parameter(ValueFromPipeline)]$devicename = '*',
    #Which user to scope the report to. Requires superuser
    $user,
    #Time Range Start. Defaults to last month
    $historyStart = (get-date -day 1 -hour 0 -minute 0 -second 0).addmonths(-1),
    #Time Range Start. Defaults to last month
    $historyEnd = $historyStart.AddMonths(1)
)

begin {
    #This script requires COnvertTo-FlatObject.ps1 to be in the path
    Invoke-command {& ConvertTo-Flatobject.ps1} -ErrorAction Stop

    if ($user) {
        if ((invoke-traversecommand -api rest 'whoami').data.object.loginname -notmatch $user) {
            #Switch to usercontext (requires superuser)
            $representResult = invoke-traversecommand -api REST 'user.represent' -argumentlist @{loginName="$user"} -ErrorAction stop
        }
    }
}

process {
    foreach ($devicename in $devicename) {
        $cputests = @(get-traversetest -subtype cpu -devicename $devicename | where testName -match 'Overall CPU Load')
        $disktests = @(get-traversetest -subtype disk -devicename $devicename)
        $memtests = @(get-traversetest -subtype phymemory -devicename $devicename)

        $reportTests = $cputests + $disktests + $memtests
        $i = 1
        $reportTests |
            foreach {
                write-progress -activity "Gathering Historical Data ($i of $($reportTests.count))" -status $_.testname -currentoperation $_.deviceName -PercentComplete (($i/$reportTests.count)*100)
                Get-TraverseTestRawHistoricalData -Start $historyStart -end $historyEnd -TestSerial $_.serialNumber -verbose
                $i++
            } |
            foreach {
                $PSItem | select accountName,
                    deviceName,
                    testName,
                    percentile98,
                    percentile95,
                    mean,
                    stdDev,
                    minValue,
                    maxValue,
                    units
            }
    }
}