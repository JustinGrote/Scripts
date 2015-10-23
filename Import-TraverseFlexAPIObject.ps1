

function convert-TraverseFlexToPSObject ($RESTResult) {
    #Format the devices into powershell objects
    $devices = $RESTResult.split("`n") | select -skip 1
    foreach ($device in $devices) {
        #Convert to a hash table by making name-value pairs one per line and removing extraneous quotes
        $deviceParams = convertfrom-stringdata $device.replace("`,` ","`n").replace("`"","")
        $device = new-object PSObject -property $deviceParams
        $device
    } #Foreach
}

#Obtain the results
Invoke-RestMethod -Uri https://bsm.allieddigital.net/api/rest/command/login?jgrote/ncc1701EE -SessionVariable RESTSession
$devices = Invoke-RestMethod -Uri https://bsm.allieddigital.net/api/rest/command/devices.list -websession $RESTSession
$PSdevices = convert-TraverseFlexToPSObject $devices