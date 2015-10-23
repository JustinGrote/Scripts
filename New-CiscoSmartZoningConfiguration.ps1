<#
.SYNOPSIS
    Generates a Cisco Smart Zoning Configuration from a CSV for devices that don't support Smart Zoning (such as Nexus 5500).
.AUTHOR
    Justin Grote <jgrote@allieddigital.net>
.PARAMETER InputFile
    Path to CSV file containing device name and wwn informatino
    CSV Columns:
        Name - The descriptive name of the device. This can be anything
        WWN - The WWN ID of the device to be zoned
        Type - Specify either Host or Storage. If left blank, the device alias will be created but no zoning for the device will occur
.PARAMETER OutputFile
    Path where to output the finalized configuration
.PARAMETER VSAN
    Which VSAN the configuration should belong to
.PARAMETER ZoneSetName
    The name of the Zoneset to add the zones to

#>

param (

[Parameter(Mandatory=$true)]$InputFile = "testscript",
[Parameter(Mandatory=$true)]$OutputFile = "NexusB.ciscocfg",
$VSAN = 100,
$ZoneSetName = "Production"

)

$INDENT = "  "

$DeviceTable = import-csv $InputFile

if (!($devicetable.type -match "Storage")) {throw "You must have at least one entry in the CSV with a Device Type of Storage"}

#Generate the Device Alias Database
$config = @()
$config += "device-alias database"
foreach ($Device in $DeviceTable) {
    $config += $INDENT + "device-alias name " + $Device.Name + " pwwn " + $Device.WWN
    
}
$config += "device-alias commit"
$config += "`n"

#Generate the Zones
$SANStorages = $DeviceTable | where {$_.type -match "Storage"}
$SANHosts = $DeviceTable | where {$_.type -match "Host"}
$ZoneNames = @()
foreach ($SANStorage in $SANStorages) {
    foreach ($SANHost in $SANHosts) {
        $ZoneName = $SANHost.Name + "__" + $SANStorage.Name
        $ZoneNames += $ZoneName
        $config += "zone name " + $SANHost.Name + "__" + $SANStorage.Name + " vsan " + $VSAN
        $config += $INDENT + "member device-alias " + $SANHost.Name
        $config += $INDENT + "member device-alias " + $SANStorage.Name
        $config += " "
    }
}


#Generate the Zoneset
$config += "zoneset name " + $ZoneSetName + " vsan " + $VSAN
foreach ($ZoneName in $ZoneNames) {
    $config += $INDENT + "member " + $ZoneName
}


$config > $OutputFile