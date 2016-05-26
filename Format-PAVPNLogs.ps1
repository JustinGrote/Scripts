function Format-PAVPNLogs ($logPath) {

#region HelperFunctions
    function Get-LocalSPI ($description) {
        $SPI = (Select-String -InputObject $description -Pattern '0x[0-9A-Z]{8}' -AllMatches).matches.value
        if ($SPI.count -eq 1) {$SPI}
        if ($SPI.count -gt 1) {$SPI[0]}
    }

    function Get-TimeSinceLastEvent  {
        param (
            $logobject, 
            $vpnLogEntries, 
            [string]$vpnevent
        )


        if ($logObject.eventid -match "ipsec-key-install") {
            $currentTimeStamp = [DateTime]($LogObject."Receive Time")
            
            if ($vpnevent -match "ipsec-key-delete") {
                $lastEvent = $vpnLogEntries | 
                    where {$PSItem.object -like $logobject.object} |
                    where {$PSItem.eventid -eq $vpnevent -and [DateTime]($PSItem."Receive Time") -le $currentTimeStamp} |
                    sort "Receive Time" -descending | 
                    select -first 1
            }

            #Fix for Palo Alto logs only being granular to the second, so sort conflicts arise if two events occur in same second
            if ($vpnevent -match "ipsec-key-install") {
                $lastEvent = $vpnLogEntries | 
                    where {$PSItem.object -like $logobject.object} |
                    where {$PSItem.eventid -match $vpnevent -and [DateTime]($PSItem."Receive Time") -lt $currentTimeStamp} |
                    sort "Receive Time" -descending | 
                    select -first 1
            }
            
            write-debug "Last Event: 0"
            
            if ($lastEvent) {
                $lastEventTimeStamp = [DateTime]($lastEvent."Receive Time")
                new-timespan -start $lastEventTimeStamp -end $currentTimeStamp
            }
        } else {"N/A"}

    }

#endregion HelperFunctions

    $vpnLog = import-csv $logPath | where eventid -match "ipsec-key"| select -first 100
    $vpnLog | foreach {
        [PSCustomObject]@{
            Timestamp=[DateTime]$PSItem."Receive Time"
            Tunnel=$PSItem.object
            EventID=$PSItem.eventid
            Severity=$PSItem.severity
            Description=$PSItem.description
            SPI=Get-LocalSPI ($PSItem.description)
            TimeSinceLastDelete=(Get-TimeSinceLastEvent $PSItem $vpnLog "ipsec-key-delete")
            TimeSinceLastInstall=(Get-TimeSinceLastEvent $PSItem $vpnLog "ipsec-key-install")
        } #PSCustomObject
    } #Foreach
}

(Format-PAVPNLogs .\log.csv) | where tunnel -match "Winkler_Gateway" | sort timestamp

