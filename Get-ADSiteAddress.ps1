
#region Includes
function check-ipformat([string]$ip) {
	#check for a properly formated IPv4 address being provided.  Future update can include Ipv6 regex
		if (-not ($ip -match "^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$")) {
			#write-error "The Ip address provided: $ip  is not a valid IPv4 address format"
			return $false
		} else { 
			$octetsegments = $ip.split(".")
			
			#Check the values of the ip address format to ensure it is between 0 and 255
			foreach ($octet in $octetsegments) {
				if ([int]$octet -lt 0 -or [int]$octet -gt 254) {
					return $false
				}
			}
			return $true 
		}
}


function get-networkID ([string]$ipaddr, [string]$subnetmask) {
	

	if (-not (&check-ipformat $ipaddr)) {
		Write-Host -ForegroundColor "yellow" "IP address provided is not a valid IPv4 address format"
		Write-Host
		return $null
	}
	
	if (-not (&check-subnetformat $subnetmask)) {
		Write-Host -ForegroundColor "yellow" "Subnet mask provided is not a valid format"
		Write-Host
		return $null
	}
	
	$ipoctets = $ipaddr.split(".")
	$subnetoctets = $subnetmask.split(".")
	$result = ""
	
	for ($i = 0; $i -lt 4; $i++) {
		$result += $ipoctets[$i] -band $subnetoctets[$i]
		$result += "."
	}
	$result = $result.substring(0,$result.length -1)
	return $result
	
}
	
function check-subnetformat([string]$subnet) {
	if (-not ($subnet -match "^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$")) {
		Write-Error "The subnet mask provided does not match IPv4 format"
		return $false
	} else {
		$octetsegments = $subnet.split(".")
		#Check each octet from last to first.  If an octet does not contain 0, check to see
		#if it is valid octet value for subnet masks.  Then check to make sure that all preceeding
		#octets are 255
		$foundmostsignficant = $false
		for ($i = 3; $i -ge 0; $i--) {
			if ($octetsegments[$i] -ne 0) {
				if ($foundmostsignificant -eq $true -and $octetsegments[$i] -ne 255) {
					Write-Error "The subnet mask has an invalid value"
					return $false
				} else {
					if ((255,254,252,248,240,224,192,128) -contains $octetsegments[$i]) {
						$foundmostsignficant = $true
					} else {
						Write-Error "The subnet mask has an invalid value"
						return $false
					} 
					
				}
			}
		}
		return $true
	}
}
	
function get-subnetMask-byLength ([int]$length) {
	if ($length -eq $null -or $length -gt 32 -or $length -lt 0) {
		Write-Error "get-subnetMask-byLength: Invalid subnet mask length provided.  Please provide a number between 0 and 32"
		return $null
	}
	
	switch ($length) {
	 "32" { return "255.255.255.255" }
	 "31" { return "255.255.255.254" }
	 "30" { return "255.255.255.252" }
	 "29" { return "255.255.255.248" }
	 "28" { return "255.255.255.240" }
	 "27" { return "255.255.255.224" }
	 "26" { return "255.255.255.192" }
	 "25" { return "255.255.255.128" }
	 "24" { return "255.255.255.0" }
	 "23" { return "255.255.254.0" }
	 "22" { return "255.255.252.0" }
	 "21" { return "255.255.248.0" }
	 "20" { return "255.255.240.0" }
	 "19" { return "255.255.224.0" }
	 "18" { return "255.255.192.0" }
	 "17" { return "255.255.128.0" }
	 "16" { return "255.255.0.0" }
	 "15" { return "255.254.0.0" }
	 "14" { return "255.252.0.0" }
	 "13" { return "255.248.0.0" }
	 "12" { return "255.240.0.0" }
	 "11" { return "255.224.0.0" }
	 "10" { return "255.192.0.0" }
	 "9" { return "255.128.0.0" }
	 "8" { return "255.0.0.0" }
	 "7" { return "254.0.0.0"}
	 "6" { return "252.0.0.0"}
	 "5" { return "248.0.0.0"}
	 "4" { return "240.0.0.0"}
	 "3" { return "224.0.0.0"}
	 "2" { return "192.0.0.0"}
	 "1" { return "128.0.0.0"}
	 "0" { return "0.0.0.0"}
	
	}
	
}

function get-MaskLength-bySubnet ([string]$subnet) {
	if ($subnet -eq $null -or (-not(&check-subnetformat $subnet))) {
		Write-Error "Invalid subnet passed to get-MaskLength-bySubnet in networklib"
		return $null
	}
	
	switch ($subnet) {
	"255.255.255.255" {return 32}
	"255.255.255.254" {return 31}
	"255.255.255.252" {return 30}
	"255.255.255.248" {return 29}
	"255.255.255.240" {return 28}
	"255.255.255.224" {return 27}
	"255.255.255.192" {return 26}
	"255.255.255.128" {return 25}
	"255.255.255.0"  {return 24}
	"255.255.254.0"  {return 23}
	"255.255.252.0"  {return 22}
	"255.255.248.0"  {return 21}
	"255.255.240.0" {return 20}
	"255.255.224.0" {return 19}
	"255.255.192.0" {return 18}
	"255.255.128.0" {return 17}
	"255.255.0.0"  {return 16}
	"255.254.0.0" {return 15}
	"255.252.0.0" {return 14}
	"255.248.0.0" {return 13}
	"255.240.0.0" {return 12}
	"255.224.0.0" {return 11}
	"255.192.0.0" {return 10}
	"255.128.0.0" {return 9}
	"255.0.0.0" {return 8}
	"254.0.0.0" {return 7}
	"252.0.0.0" {return 6}
	"248.0.0.0" {return 5}
	"240.0.0.0"  {return 4}
	"224.0.0.0" {return 3}
	"192.0.0.0" {return 2}
	"128.0.0.0" {return 1}
	"0.0.0.0"  {return 0}
	
	}

}

function Get-ADSiteByIP{
	Param(
		[Parameter(Mandatory=$true,HelpMessage="IP Address")][validatepattern('^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$')]$ip,
		[Parameter(Mandatory=$false,HelpMessage="Netmask")]$nmask,
		[Parameter(Mandatory=$false,HelpMessage="Mask length")][validaterange(0,32)][int]$nmlength
	)
	
	$forest = [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest()
	$mytopleveldomain = $forest.schema.name
	$mytopleveldomain = $mytopleveldomain.substring($mytopleveldomain.indexof("DC="))
	$mytopleveldomain = "LDAP://cn=subnets,cn=sites,cn=configuration," + $mytopleveldomain
	$de = New-Object directoryservices.DirectoryEntry($mytopleveldomain)
	$ds = New-Object directoryservices.DirectorySearcher($de)
	$ds.propertiestoload.add("cn") > $null
	$ds.propertiestoLoad.add("siteobject") > $null
	
	$startMaskLength = 32
	
	#we can take network masks in both length and full octet format.  
	#We need to use both.  LDAP searches
	#use length, and network ID generation is by full octet format.
	
	if ($nmask -ne $null -or $nmlength -ne $null) {
		if ($nmask -ne $null) {
			if (-not(&check-subnetformat $nmask)) {
				Write-Error "Subnet provided is not a valid subnet"
				exit
			} else {
				$startmasklength = &get-MaskLength-bySubnet $nmask
			}
		}
	
	}
	
	for ($i = $startMaskLength; $i -ge 0; $i--) {
		#loop through netmasks from /32 to /0 looking for a subnet match in AD
		
		#Go through all masks from longest to shortest
		$mask = &get-subnetMask-byLength $i
		$netwID = &get-networkID $ip $mask
		
		#ldap search for the network
		$ds.filter = "(&(objectclass=subnet)(objectcategory=subnet)(cn=" + $netwID + "/" + $i + "))"
		$fu = $ds.findone()
		if ($fu -ne $null) {
			
			#if a match is found, return it since it is the longest length (closest match)
			Write-Verbose "Found Subnet in AD at site:"
			$result = get-adobject -identity "$($fu.properties.siteobject)" -properties location,managedby,description
			return $result | select @{Name="Device IP Address";Expression={$ip}},@{name="SiteName";Expression={$PSItem.name}},Location,managedby
		}
		$fu = $null
	}
	
	#if we have arrived at this point, the subnet does not exist in AD
	
	write-warning "This device with IP address $ip is not associated with an AD subnet. Check that an AD subnet exists for this device in AD Sites and Services and that the subnet is associated with a site"
} #Get-ADSiteByIP

function Get-SiteContactByHostname ($hostname) {
    write-host -foregroundcolor cyan "Gathering information. This may take a minute or two..."

    #Get the AD site based on Hostname. Only match on first IP address result
    if (check-ipformat $hostname) {
        $siteresult = Get-adsitebyIP $hostname
    } else {
        $siteresult = Get-adsitebyIP @((resolve-dnsname $hostname).ipaddress)[0]
    }

    write-host -foregroundcolor Green "Site Information"
    write-host -foregroundcolor Green "----------------"
    $siteresult | format-list
    $office = $null
    #If managedby exists, use that for the office search
    if ($siteresult.managedby) {$office = $siteresult.managedby -replace "(CN=)(.*?),.*",'$2'} 
        else {$office = $siteresult.sitename}

    #If the site has a description, use that instead (some sites have spaces in their name and don't match user office attribute)
    $objADSite = get-adreplicationsite $office
    if ($objADSite.description) {$office = $objadsite.description}

    #Get the Contacts by title for the site
    $contactresult = get-aduser -filter {enabled -eq $true -and office -like $office -and (title -like "*Business Operations*" -or title -like "*Executive Director*") } `
        -properties title,emailaddress,telephonenumber,mobile | `
        where {$PSItem.distinguishedname -notmatch "Ex-Employees"}

    #Sort the contacts in this order: Director, Manager, Executive.
    $contacts = @()
    $contacts += ($contactresult | where {$_.title -match "Director" -and $_.title -match "Business"})
    $contacts += ($contactresult | where {$_.title -match "Manager"})
    $contacts += ($contactresult | where {$_.title -match "Executive"})

    write-host -foregroundcolor Cyan "Site Contacts"
    write-host -foregroundcolor Cyan "-------------"
    $contacts | fl name,title,emailaddress,telephonenumber,mobile
}

#endregion Includes


#region Main
$env:ADPS_LoadDefaultDrive = 0
import-module activedirectory -cmdlet Get-ADObject,Get-ADUser,Get-ADReplicationSite,Get-ADReplicationSubnet
$hostname = read-host "Enter Hostname or IP"

Get-SiteContactByHostname $hostname


#End Script
Write-Host -foregroundcolor Gray "Press any key to exit ..."
$x = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

#endregion Main