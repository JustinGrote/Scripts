#requires -module Traverse,ImportExcel
[CmdletBinding(SupportsShouldProcess)]

param (
    #Hostname of Traverse Server
    [String]$Hostname="bsm.allieddigital.net",
    #Proxy Username to use for traverse filtering purposes. Specify a user who only has rights to see the appropriate systems
    [String]$Username="SA-Traverse-SSB",
    #Start of report period. Default is the first day of the previous month.
    $Start = (get-date ([DateTime]::Now.addmonths(-1)) -day 1 -hour 0 -minute 0 -second 0 -millisecond 0),
    #End of report period. Default is the last day of the previous month
    $End = (get-date -day 1 -hour 0 -minute 0 -second 0 -millisecond 0).adddays(-1),
    #Output Path for the resulting excel report
    $Path = ".\$Username-StorageReport-$(get-date -format 'yyyyMMddhhss').json",
    #Disk Test Name match. Normally don't need to change this.
    $TestName = '*Space*Util',
    #Only use the first x tests returned from Traverse. Useful for testing.
    [int]$ResultSize = 10000,
    #Only place the top N results into the report
    [int]$TopN = 10000
)


if (!$TraverseSessionREST) { connect-traversebve $Hostname }
write-progress -Activity "Generating Traverse Disk Usage Reports" -Status "Fetching Disk Test Definitions from Traverse"
$tests = get-traversetest -UserName $Username -devicename * -subtype *disk* -testname '*Space*Util' | 
    select -first $ResultSize

if (!($PSCmdlet.ShouldProcess("$($tests.count) Test Objects","Fetch Historical Data"))) {return}

#Get the raw data from the selected tests
$i = 1
$rawdata = foreach ($testItem in $tests) {
    write-progress -Activity "Generating Traverse Disk Usage Reports" -Status "Fetching Raw Historical Data" -CurrentOperation "$i of $($tests.count): $($testItem.deviceName)\$($testItem.testName)" -PercentComplete ([int32](($i/$tests.count)*100))
    $rawDataItem = get-traversetestRawHistoricalData $testItem.serialNumber -Start $Start -end $End

    #Add Custom Fields
    $rawDataItem | Add-Member -force -type NoteProperty -name "startValue" -value ($RawDataItem.values | where average -ge 0 | sort timestamp | select -first 1).average
    $rawDataItem | Add-Member -force -type NoteProperty -name "endValue" -value ($RawDataItem.values | where average -ge 0 | sort timestamp | select -last 1).average
    $rawDataItem | Add-Member -force -type NoteProperty -name "deltaValue" -value ($rawDataItem.endvalue - $rawDataItem.startValue)

    $rawDataItem

    $i++
}

$rawData | ConvertTo-Json -compress -depth 5 > $path