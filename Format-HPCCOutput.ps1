
#This script uses the HP Configuration Collector Output and produces meaningful Poweshell Objects and CSVs out of them for capacity planning.

$hpccfile = "C:\users\jgrote\desktop\SWMALEVA01.xml"

$xmlRAW = [xml](get-content $hpccfile)

$xmlEVA = $xmlRAW.scanmastercollection.collectiondata.eva

$evaDiskGroup = $xmlEVA.diskgroup.object

$evaDisks = $xmlEVA.disk.object

$evaVirtualDisks = $xmleva.virtualdisk.object

$evaDiskGroup | export-csv -notypeinformation "$($xmlEVA.devicename)-diskgroups.csv" 
$evaDisks | export-csv -notypeinformation "$($xmlEVA.devicename)-disks.csv" 
$evaVirtualDisks | export-csv -notypeinformation "$($xmlEVA.devicename)-virtualdisks.csv" 

