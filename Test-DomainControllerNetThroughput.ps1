$branchDCs = get-addomaincontroller -filter * | 
    where {$_.site -notmatch "Datacenter" -and $_.site -notmatch "Azure"} | 
    select -expandproperty hostname | sort {get-random}
    
$branchDCs | .\Test-NetThroughput.ps1 -verbose