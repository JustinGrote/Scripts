function get-TraverseDeviceTestCount ($TraverseDevice) {
foreach ($devicename in $TraverseDevice.devicename) {
    
    $testresult = Invoke-RestMethod -uri "https://bsm.allieddigital.net/api/rest/command/test.list?devicename=$devicename" -WebSession $TraverseSessionREST -UseBasicParsing
    [int]$testcount = ($testresult.split("`n") | select -first 1).replace("OK 203 request accepted, records returned: ",$null)
    $returnProps = [ordered]@{}
    $returnProps.devicename = $devicename
    $returnProps.testcount = $testcount

    new-object PSObject -Property $returnProps
}

}