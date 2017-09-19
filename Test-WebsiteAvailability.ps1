param (
    [Parameter(Mandatory)][String[]]$computername
)


$computername | start-rsjob -throttle 20 {
    $computername = "$_.scag.ca.gov"
    $SSLCertScript = "C:\Users\JGrote.ALLIEDDIGITAL\Documents\WindowsPowershell\Scripts\Get-RemoteSSLCertificate.ps1"
    [PSCustomObject][Ordered]@{
        ComputerName = $computername
        PING = (test-connection $computername -quiet)
        HTTP = (Test-NetConnection -CommonTCPPort HTTP -ComputerName $computername).tcptestsucceeded
        SSL = (Test-NetConnection -Port 443 -ComputerName $computername).tcptestsucceeded
        SSLCertExpires = (& $SSLCertScript $computername).notAfter
    }
} | wait-rsjob -showprogress | receive-rsjob | ogv -passthru | export-excel -tablename "PublicSites" $home\desktop\sites.xlsx