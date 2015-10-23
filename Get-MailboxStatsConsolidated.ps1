$ou="OU=Seasons Users,DC=seasons,dc=local"


#$aduserlist = foreach ($dn in $userfolders) {
#    get-aduser -searchbase $dn -properties lastlogondate,enabled,msexchmailboxguid -filter {msexchmailboxguid -like "*"} | where {$_.enabled -eq $true}
#}

$results=@()
$i=0
$increment=100

$aduserlist = get-mailbox -OrganizationalUnit $ou -resultsize unlimited

while ($i -lt $aduserlist.count) {
    write-verbose "Working Batch $i"
    $mbxs = $aduserlist[$i..($i+$increment)]

    $mbxstats = $mbxs | get-mailboxstatistics

    $stats1 = $mbxs | select `
        exchangeguid,
        identity,
        displayname,
        distinguishedname,
        primarysmtpaddress,
        database,
        whenchanged `
        | sort exchangeguid


    $stats2 = $mbxstats | select `
        @{name="ExchangeGuid";expression={$_.identity.mailboxguid}},     #Required to match mailbox entries for join
        lastlogofftime,
        lastlogontime,
        itemcount,
        #Some ugly parsing required to get mailbox into the right format due to it being deserialized remotely.
        @{name="SizeMB";expression={[int64]($_.TotalItemSize.Value).ToString().TrimEnd(" bytes)").Split("(")[1]/1MB}} `
        | sort exchangeguid

    #Script Requires Join-Collections Script in current directory
    $output = & 'Join-Collections.ps1' $stats1 "ExchangeGUID" $stats2

    $results += $output

    $i += $increment+1

}

$results | export-csv -notypeinformation mailboxstatsdetailed.csv
