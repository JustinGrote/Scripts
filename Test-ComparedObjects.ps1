

workflow Test-ComparedObjects {
    $differences = compare-object -ReferenceObject (get-content .\ADSL-DiscoveredList.txt) -DifferenceObject (get-content .\SSB-ProvidedServerList.txt)

    foreach -throttle 20 -parallel ($computer in $differences) {
        write-verbose "test"
        InlineScript { 
            $result = @{}
            $result.add("Hostname",$computer.inputobject)
            $result.SideIndicator = $computer.sideindicator
            $result.IsPingable = test-connection $Using:computer.inputobject -quiet -erroraction silentlycontinue

            new-object PSObject -Property $result
        } #Sequence
    } #Foreach

}