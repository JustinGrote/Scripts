#requires -modules ImportExcel

#region Includes
Function ConvertTo-FlatObject {
    <#
    .SYNOPSIS
        Flatten an object to simplify discovery of data

    .DESCRIPTION
        Flatten an object.  This function will take an object, and flatten the properties using their full path into a single object with one layer of properties.

        You can use this to flatten XML, JSON, and other arbitrary objects.
        
        This can simplify initial exploration and discovery of data returned by APIs, interfaces, and other technologies.

        NOTE:
            Use tools like Get-Member, Select-Object, and Show-Object to further explore objects.
            This function does not handle certain data types well.  It was original designed to expand XML and JSON.

    .PARAMETER InputObject
        Object to flatten
    
    .PARAMETER Exclude
        Exclude any nodes in this list.  Accepts wildcards.

        Example:
            -Exclude price, title

    .PARAMETER ExcludeDefault
        Exclude default properties for sub objects.  True by default.
        
        This simplifies views of many objects (e.g. XML) but may exclude data for others (e.g. if flattening a process, ProcessThread properties will be excluded)

    .PARAMETER Include
        Include only leaves in this list.  Accepts wildcards.

        Example:
            -Include Author, Title

    .PARAMETER Value
        Include only leaves with values like these arguments.  Accepts wildcards.
    
    .PARAMETER MaxDepth
        Stop recursion at this depth.

    .INPUTS
        Any object

    .OUTPUTS
        System.Management.Automation.PSCustomObject

    .EXAMPLE

        #Pull unanswered PowerShell questions from StackExchange, Flatten the data to date a feel for the schema
        Invoke-RestMethod "https://api.stackexchange.com/2.0/questions/unanswered?order=desc&sort=activity&tagged=powershell&pagesize=10&site=stackoverflow" |
            ConvertTo-FlatObject -Include Title, Link, View_Count

            $object.items[0].owner.link : http://stackoverflow.com/users/1946412/julealgon
            $object.items[0].view_count : 7
            $object.items[0].link       : http://stackoverflow.com/questions/26910789/is-it-possible-to-reuse-a-param-block-across-multiple-functions
            $object.items[0].title      : Is it possible to reuse a &#39;param&#39; block across multiple functions?
            $object.items[1].owner.link : http://stackoverflow.com/users/4248278/nitin-tyagi
            $object.items[1].view_count : 8
            $object.items[1].link       : http://stackoverflow.com/questions/26909879/use-powershell-to-retreive-activated-features-for-sharepoint-2010
            $object.items[1].title      : Use powershell to retreive Activated features for sharepoint 2010
            ...

    .EXAMPLE

        #Set up some XML to work with
        $object = [xml]'
            <catalog>
               <book id="bk101">
                  <author>Gambardella, Matthew</author>
                  <title>XML Developers Guide</title>
                  <genre>Computer</genre>
                  <price>44.95</price>
               </book>
               <book id="bk102">
                  <author>Ralls, Kim</author>
                  <title>Midnight Rain</title>
                  <genre>Fantasy</genre>
                  <price>5.95</price>
               </book>
            </catalog>'

        #Call the flatten command against this XML
            ConvertTo-FlatObject $object -Include Author, Title, Price
    
            #Result is a flattened object with the full path to the node, using $object as the root.
            #Only leaf properties we specified are included (author,title,price)

                $object.catalog.book[0].author : Gambardella, Matthew
                $object.catalog.book[0].title  : XML Developers Guide
                $object.catalog.book[0].price  : 44.95
                $object.catalog.book[1].author : Ralls, Kim
                $object.catalog.book[1].title  : Midnight Rain
                $object.catalog.book[1].price  : 5.95

        #Invoking the property names should return their data if the orginal object is in $object:
            $object.catalog.book[1].price
                5.95

            $object.catalog.book[0].title
                XML Developers Guide

    .EXAMPLE

        #Set up some XML to work with
            [xml]'<catalog>
               <book id="bk101">
                  <author>Gambardella, Matthew</author>
                  <title>XML Developers Guide</title>
                  <genre>Computer</genre>
                  <price>44.95</price>
               </book>
               <book id="bk102">
                  <author>Ralls, Kim</author>
                  <title>Midnight Rain</title>
                  <genre>Fantasy</genre>
                  <price>5.95</price>
               </book>
            </catalog>' |
                ConvertTo-FlatObject -exclude price, title, id
    
        Result is a flattened object with the full path to the node, using XML as the root.  Price and title are excluded.

            $Object.catalog                : catalog
            $Object.catalog.book           : {book, book}
            $object.catalog.book[0].author : Gambardella, Matthew
            $object.catalog.book[0].genre  : Computer
            $object.catalog.book[1].author : Ralls, Kim
            $object.catalog.book[1].genre  : Fantasy

    .EXAMPLE
        #Set up some XML to work with
            [xml]'<catalog>
               <book id="bk101">
                  <author>Gambardella, Matthew</author>
                  <title>XML Developers Guide</title>
                  <genre>Computer</genre>
                  <price>44.95</price>
               </book>
               <book id="bk102">
                  <author>Ralls, Kim</author>
                  <title>Midnight Rain</title>
                  <genre>Fantasy</genre>
                  <price>5.95</price>
               </book>
            </catalog>' |
                ConvertTo-FlatObject -Value XML*, Fantasy

        Result is a flattened object filtered by leaves that matched XML* or Fantasy

            $Object.catalog.book[0].title : XML Developers Guide
            $Object.catalog.book[1].genre : Fantasy

    .EXAMPLE
        #Get a single process with all props, flatten this object.  Don't exclude default properties
        Get-Process | select -first 1 -skip 10 -Property * | ConvertTo-FlatObject -ExcludeDefault $false

        #NOTE - There will likely be bugs for certain complex objects like this.
                For example, $Object.StartInfo.Verbs.SyncRoot.SyncRoot... will loop until we hit MaxDepth. (Note: SyncRoot is now addressed individually)

    .NOTES
        I have trouble with algorithms.  If you have a better way to handle this, please let me know!

    .FUNCTIONALITY
        General Command
    #>
    [cmdletbinding()]
    param(
        
        [parameter( Mandatory = $True,
                    ValueFromPipeline = $True)]
        [PSObject[]]$InputObject,

        [string[]]$Exclude = "",

        [bool]$ExcludeDefault = $True,

        [string[]]$Include = $null,

        [string[]]$Value = $null,

        [int]$MaxDepth = 10
    )
    Begin
    {
        #region FUNCTIONS

            #Before adding a property, verify that it matches a Like comparison to strings in $Include...
            Function IsIn-Include {
                param($prop)
                if(-not $Include) {$True}
                else {
                    foreach($Inc in $Include)
                    {
                        if($Prop -like $Inc)
                        {
                            $True
                        }
                    }
                }
            }

            #Before adding a value, verify that it matches a Like comparison to strings in $Value...
            Function IsIn-Value {
                param($val)
                if(-not $Value) {$True}
                else {
                    foreach($string in $Value)
                    {
                        if($val -like $string)
                        {
                            $True
                        }
                    }
                }
            }

            Function Get-Exclude {
                [cmdletbinding()]
                param($obj)

                #Exclude default props if specified, and anything the user specified.  Thanks to Jaykul for the hint on [type]!
                    if($ExcludeDefault)
                    {
                        Try
                        {
                            $DefaultTypeProps = @( $obj.gettype().GetProperties() | Select -ExpandProperty Name -ErrorAction Stop )
                            if($DefaultTypeProps.count -gt 0)
                            {
                                Write-Verbose "Excluding default properties for $($obj.gettype().Fullname):`n$($DefaultTypeProps | Out-String)"
                            }
                        }
                        Catch
                        {
                            Write-Verbose "Failed to extract properties from $($obj.gettype().Fullname): $_"
                            $DefaultTypeProps = @()
                        }
                    }
                    
                    @( $Exclude + $DefaultTypeProps ) | Select -Unique
            }

            #Function to recurse the Object, add properties to object
            Function Recurse-Object {
                [cmdletbinding()]
                param(
                    $Object,
                    [string[]]$path = '$Object',
                    [psobject]$Output,
                    $depth = 0
                )

                # Handle initial call
                    Write-Verbose "Working in path $Path at depth $depth"
                    Write-Debug "Recurse Object called with PSBoundParameters:`n$($PSBoundParameters | Out-String)"
                    $Depth++

                #Exclude default props if specified, and anything the user specified.                
                    $ExcludeProps = @( Get-Exclude $object )

                #Get the children we care about, and their names
                    $Children = $object.psobject.properties | Where {$ExcludeProps -notcontains $_.Name }
                    Write-Debug "Working on properties:`n$($Children | select -ExpandProperty Name | Out-String)"

                #Loop through the children properties.
                foreach($Child in @($Children))
                {
                    $ChildName = $Child.Name
                    $ChildValue = $Child.Value

                    Write-Debug "Working on property $ChildName with value $($ChildValue | Out-String)"
                    # Handle special characters...
                        if($ChildName -match '[^a-zA-Z0-9_]')
                        {
                            $FriendlyChildName = "{$ChildName}"
                        }
                        else
                        {
                            $FriendlyChildName = $ChildName
                        }

                    #Add the property.
                        if((IsIn-Include $ChildName) -and (IsIn-Value $ChildValue) -and $Depth -le $MaxDepth)
                        {
                            $ThisPath = @( $Path + $FriendlyChildName ) -join "."
                            $Output | Add-Member -MemberType NoteProperty -Name $ThisPath -Value $ChildValue
                            Write-Verbose "Adding member '$ThisPath'"
                        }

                    #Handle null...
                        if($ChildValue -eq $null)
                        {
                            Write-Verbose "Skipping NULL $ChildName"
                            continue
                        }

                    #Handle evil looping.  Will likely need to expand this.  Any thoughts on a better approach?
                        if(
                            (
                                $ChildValue.GetType() -eq $Object.GetType() -and
                                $ChildValue -is [datetime]
                            ) -or
                            (
                                $ChildName -eq "SyncRoot" -and
                                -not $ChildValue
                            )
                        )
                        {
                            Write-Verbose "Skipping $ChildName with type $($ChildValue.GetType().fullname)"
                            continue
                        }

                    #Check for arrays
                        $IsArray = @($ChildValue).count -gt 1
                        $count = 0
                        
                    #Set up the path to this node and the data...
                        $CurrentPath = @( $Path + $FriendlyChildName ) -join "."

                    #Exclude default props if specified, and anything the user specified.                
                        $ExcludeProps = @( Get-Exclude $ChildValue )

                    #Get the children's children we care about, and their names.  Also look for signs of a hashtable like type
                        $ChildrensChildren = $ChildValue.psobject.properties | Where {$ExcludeProps -notcontains $_.Name }
                        $HashKeys = if($ChildValue.Keys -notlike $null -and $ChildValue.Values)
                        {
                            $ChildValue.Keys
                        }
                        else
                        {
                            $null
                        }
                        Write-Debug "Found children's children $($ChildrensChildren | select -ExpandProperty Name | Out-String)"

                    #If we aren't at max depth or a leaf...                   
                    if(
                        (@($ChildrensChildren).count -ne 0 -or $HashKeys) -and
                        $Depth -lt $MaxDepth
                    )
                    {
                        #This handles hashtables.  But it won't recurse... 
                            if($HashKeys)
                            {
                                Write-Verbose "Working on hashtable $CurrentPath"
                                foreach($key in $HashKeys)
                                {
                                    Write-Verbose "Adding value from hashtable $CurrentPath['$key']"
                                    $Output | Add-Member -MemberType NoteProperty -name "$CurrentPath['$key']" -value $ChildValue["$key"]
                                    $Output = Recurse-Object -Object $ChildValue["$key"] -Path "$CurrentPath['$key']" -Output $Output -depth $depth 
                                }
                            }
                        #Sub children?  Recurse!
                            else
                            {
                                if($IsArray)
                                {
                                    foreach($item in @($ChildValue))
                                    {  
                                        Write-Verbose "Recursing through array node '$CurrentPath'"
                                        $Output = Recurse-Object -Object $item -Path "$CurrentPath[$count]" -Output $Output -depth $depth
                                        $Count++
                                    }
                                }
                                else
                                {
                                    Write-Verbose "Recursing through node '$CurrentPath'"
                                    $Output = Recurse-Object -Object $ChildValue -Path $CurrentPath -Output $Output -depth $depth
                                }
                            }
                        }
                    }
                
                $Output
            }

        #endregion FUNCTIONS
    }
    Process
    {
        Foreach($Object in $InputObject)
        {
            #Flatten the XML and write it to the pipeline
                Recurse-Object -Object $Object -Output $( New-Object -TypeName PSObject )
        }
    }
}

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

function Get-ADSiteContacts ([string]$objADSite) {
    
}

function Get-SiteContactByHostname ($hostname) {
    write-host -foregroundcolor cyan "Gathering information. This may take a minute or two..."

    #Get the AD site based on Hostname. Only match on first IP address result
    if (check-ipformat $hostname) {
        $siteresult = Get-adsitebyIP $hostname
    } else {
        $siteresult = Get-adsitebyIP @((resolve-dnsname $hostname).ipaddress)[0]
    }

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

$finalresult = foreach ($siteresult in (Get-ADReplicationSite -filter * -properties Location | sort name)) {
    $office = $null
    #If managedby exists, use that for the office search
    if ($siteresult.managedby) {$office = $siteresult.managedby -replace "(CN=)(.*?),.*",'$2'} 
        else {$office = $siteresult.name}

    #If the site has a description, use that instead (some sites have spaces in their name and don't match user office attribute)
    $objADSite = get-adreplicationsite $office -Properties Name,Location,Managedby,Description
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

    $i = 1
    foreach ($contactItem in $contacts) {
        #Create custom objects for each contact, and keep their priority for sorting purposes
        [PSCustomObject][ordered]@{
            Site = $siteresult.Name
            SiteDescription = $siteresult.Description
            SiteLocation = $siteresult.location
            ManagedBy = $office
            ContactOrder = $i
            ContactName = $contactItem.name
            Title = $contactItem.title
            Email = $contactItem.emailaddress
            OfficePhone = $contactItem.telephonenumber
            MobilePhone = $contactItem.mobile
        }
        $i++
    }
}

$tempOutputPath = "$env:temp\ADSiteContacts.xlsx"
$finalresult | export-excel $tempOutputPath -TableName SiteContacts -AutoSize
#Get the hostname for use in the source email address
$myFQDN=(Get-WmiObject win32_computersystem).DNSHostName+"."+(Get-WmiObject win32_computersystem).Domain

Send-MailMessage -to 'jgrote@allieddigital.net' -subject "Customer Site Contact List $(get-date)" -from "GetADSiteContacts@$myFQDN" -Attachments $tempOutputPath -Body "Please see attached Excel Sheet. This information generated from Active Directory by Powershell Script $($myinvocation.mycommand.name)" -SmtpServer localhost

#endregion Main