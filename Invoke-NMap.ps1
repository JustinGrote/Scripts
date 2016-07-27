#Requires -Version 3.0


#region Includes
function ConvertFrom-UnixTimestamp{
    param (
        [int]$UnixTimestamp=0,
        #Specify if you wish the time to be returned as UTC instead of the current timezone
        [switch]$UTC
    )

    #Unix Epoch Start (1/1/1970 12:00:00am UTC)
    [datetime]$origin = new-object DateTime 1970,1,1,0,0,0,([DateTimeKind]::Utc)
    
    $result = $origin.AddSeconds($UnixTimestamp)

    if (!($AsUTC)) {
        $result = [System.TimeZone]::CurrentTimeZone.ToLocalTime($result)
    }

    $result
}
#endRegion Includes

function ConvertFrom-NmapXml {
<#
.Synopsis 
    Parse XML output files of the nmap port scanner (www.nmap.org). 

.Description 
    Parse XML output files of the nmap port scanner (www.nmap.org) and  
    emit custom objects with properties containing the scan data. The 
    script can accept either piped or parameter input.  The script can be
    safely dot-sourced without error as is. 

.Example 
    dir *.xml | Import-NMAPXML

.Example 
	ConvertFrom-NmapXML -path onefile.xml
    ConvertFrom-NmapXML -path *files.xml 

.Example 
    $files = dir *some.xml,others*.xml 
    ConvertFrom-NmapXML -path $files    

.Example 
    ConvertFrom-NmapXML -path scanfile.xml -runstatsonly

.Example 
    ConvertFrom-NmapXML scanfile.xml -OutputDelimiter " "

.Notes 
    Author: Jason Fossen (http://blogs.sans.org/windows-security/)  
    Edited: Justin Grote <justin+powershell NOSPAMAT grote NOSPAMDOT name>
    Version: 3.6.1-JWG1
    Updated: 02.Feb.2011
    LEGAL: MIT LICENSE. SCRIPT PROVIDED "AS IS" WITH NO WARRANTIES OR GUARANTEES OF 
          ANY KIND, INCLUDING BUT NOT LIMITED TO MERCHANTABILITY AND/OR FITNESS FOR
          A PARTICULAR PURPOSE.  ALL RISKS OF DAMAGE REMAINS WITH THE USER, EVEN IF
          THE AUTHOR, SUPPLIER OR DISTRIBUTOR HAS BEEN ADVISED OF THE POSSIBILITY OF
          ANY SUCH DAMAGE.  IF YOUR STATE DOES NOT PERMIT THE COMPLETE LIMITATION OF
          LIABILITY, THEN DELETE THIS FILE SINCE YOU ARE NOW PROHIBITED TO HAVE IT.
#>

    param (
        #An XML object or XML string to process
        [Parameter(Mandatory,ValueFromPipeline)]$InputObject,
        #Only Report the runtime stats for the job
        [Switch]$SummaryOnly,
        #Return the raw XML -> PSObject Conversions rather than formatted/curated output
        [Switch]$Raw
    )	

    process {
        #If an XML string was passed, convert it to XML
        if ($InputObject -isnot [xml]) {
            $InputObject = [xml]$InputObject
        }

        foreach ($xmldoc in $InputObject) {
            if ($Raw) { return $xmldoc }
            
            #Create a new base object to save on typing
            $nmaprun = $xmldoc.nmaprun

            if ($SummaryOnly) {

                $nmaprunPorts = @{}
                    
                #Parse the scanned services list
                $nmapRunServices = foreach ($scanInfoItem in $nmaprun.scaninfo) {
                    #In the original XML, ranges of ports are summarized, e.g., "500-522" 
                    #Desummarize and convert each port into an explicit object
                    foreach ($serviceItem in $($scanInfoItem.services.replace("-","..")).Split(",")) {
                        if ( $serviceItem -like "*..*" ) {
                            $serviceItem = invoke-expression "$serviceItem"
                        }
                        foreach ($service in $serviceItem) {
                            [PSCustomObject][ordered]@{
                                Protocol = $scanInfoItem.protocol
                                ScanType = $scanInfoItem.type
                                Service = [int]$service
                            }
                        }
                    }

                    #Generate the run summary information
                    [PSCustomObject]([Ordered]@{
		                Scanner = $nmaprun.scanner
                        Version = $nmaprun.version
		                Arguments = $nmaprun.args
		                XmlOutputVersion = $nmaprun.xmloutputversion
                        ScanResult = $nmaprun.runstats.finished.exit
		                StartTime = ConvertFrom-UnixTimeStamp $nmaprun.start 
		                FinishedTime = ConvertFrom-UnixTimeStamp $nmaprun.runstats.finished.time
		                ElapsedSeconds = $nmaprun.runstats.finished.elapsed
                        HostsTotal = $nmaprun.runstats.hosts.total
                        HostsUp = $nmaprun.runstats.hosts.up
                        HostsDown = $nmaprun.runstats.hosts.down
                        VerboseLevel = $nmaprun.verbose.level
                        DebugLevel = $nmaprun.verbose.level
                        ServicesScanned = $nmapRunServices
                    })
                } #nmaprunservices = foreach

            } #If SummaryOnly
		
	        # Process each of the <host> nodes from the nmap report.
	        $i = 1  #Counter for <host> nodes processed.
            $itotal = ($nmaprun.host | measure).count
	        foreach ($hostnode in $nmaprun.host) { 
                write-progress -Activity "Parsing NMAP Result" -Status "Processing Scan Entries" -CurrentOperation "Processing $i of $itotal" -PercentComplete (($i/$itotal)*100)
		
		        # Init variables, with $entry being the custom object for each <host>. 
		        $service = " " #service needs to be a single space.
		        $entry = [ordered]@{}

		        # Extract state element of status
		        $entry.Status = $hostnode.status.state.Trim() 
		        if ($entry.Status.length -lt 2) { $entry.Status = $null }

		        # Extract fully-qualified domain name(s), removing any duplicates.  
		        $entry.FQDNs = $hostnode.hostnames.hostname.name | select -Unique
                $entry.FQDN = $entry.FQDNs | select -first 1

		        # Note that this code cheats, it only gets the hostname of the first FQDN if there are multiple FQDNs.
		        if ($entry.FQDN -eq $null) { $entry.HostName = $null }
                elseif ($entry.FQDN -like "*.*") { $entry.HostName = $entry.FQDN.Substring(0,$entry.FQDN.IndexOf(".")) }
		        else { $entry.HostName = $entry.FQDN }

		        # Process each of the <address> nodes, extracting by type.
		        $hostnode.address | foreach-object {
			        if ($_.addrtype -eq "ipv4") { $entry.IPv4 += $_.addr + " "}
			        if ($_.addrtype -eq "ipv6") { $entry.IPv6 += $_.addr + " "}
			        if ($_.addrtype -eq "mac")  { $entry.MAC  += $_.addr + " "}
		        }        
		        if ($entry.IPv4 -eq $null) { $entry.IPv4 = $null } else { $entry.IPv4 = $entry.IPv4.Trim()}
		        if ($entry.IPv6 -eq $null) { $entry.IPv6 = $null } else { $entry.IPv6 = $entry.IPv6.Trim()}
		        if ($entry.MAC  -eq $null) { $entry.MAC  = $null }  else { $entry.MAC  = $entry.MAC.Trim()}


		        # Process all ports from <ports><port>, and note that <port> does not contain an array if it only has one item in it.
		        if ($hostnode.ports.port -eq $null) { $entry.Ports = $null ; $entry.Services = $null } 
		        else 
		        {
			        $entry.Ports = @()
                    $hostnode.ports.port | foreach-object {
				        if ($_.service.name -eq $null) { $service = "unknown" } else { $service = $_.service.name } 
                        $entry.Ports += [ordered]@{
                            Protocol=$_.protocol
                            Port=$_.portid
                            Service=$service
                            State=$_.state.state
                        }

                        # Build Services property. What a mess...but exclude non-open/non-open|filtered ports and blank service info, and exclude servicefp too for the sake of tidiness.
                        if ($_.state.state -like "open*" -and ($_.service.tunnel.length -gt 2 -or $_.service.product.length -gt 2 -or $_.service.proto.length -gt 2)) { $entry.Services += $_.protocol + ":" + $_.portid + ":" + $service + ":" + ($_.service.product + " " + $_.service.version + " " + $_.service.tunnel + " " + $_.service.proto + " " + $_.service.rpcnum).Trim() + " <" + ([Int] $_.service.conf * 10) + "%-confidence>$OutputDelimiter" }
			        }
                    if ($entry.Services -eq $null) { $entry.Services = $null } else { $entry.Services = $entry.Services.Trim() }
		        }


		        # If there is 100% Accuracy OS, show it 
                $CertainOS = $hostnode.os.osmatch | where {$_.accuracy -eq 100} | select -first 1
                if ($CertainOS) {$Entry.OS = $certainOS.name; $Entry.OSDetail = $certainOS} else {$Entry.OS=$null}
		        $entry.BestGuessOS = ($hostnode.os.osmatch | select -first 1).name
                $entry.BestGuessOSPercent = ($hostnode.os.osmatch | select -first 1).accuracy
                $entry.OSGuesses = $hostnode.os.osmatch
		        if (@($entry.OSGuesses).count -lt 1) { $entry.OS = $null }

            
                # Extract script output, first for port scripts, then for host scripts.
                $hostnode.ports.port | foreach-object {
                    if ($_.script -ne $null) { 
                        $entry.Script += "<PortScript id=""" + $_.script.id + """>$OutputDelimiter" + ($_.script.output -replace "`n","$OutputDelimiter") + "$OutputDelimiter</PortScript> $OutputDelimiter $OutputDelimiter" 
                    }
                } 
            
                if ($hostnode.hostscript -ne $null) {
                    $hostnode.hostscript.script | foreach-object {
                        $entry.Script += '<HostScript id="' + $_.id + '">' + $OutputDelimiter + ($_.output.replace("`n","$OutputDelimiter")) + "$OutputDelimiter</HostScript> $OutputDelimiter $OutputDelimiter" 
                    }
                }
            
                if ($entry.Script -eq $null) { $entry.Script = $null } 
		        $i++  #Progress counter...
		        [PSCustomObject]$entry
	        }
            }
    }
}
#$nmapxml = [xml](& nmap -T5 -O --osscan-guess -oX - tinygod www.google.com)
#$testresult = $nmapxml | convertFrom-NmapXML
#$testresult