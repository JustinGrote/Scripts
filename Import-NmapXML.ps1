#Requires -Version 2.0

<#
.Synopsis 
    Parse XML output files of the nmap port scanner (www.nmap.org). 

.Description 
    Parse XML output files of the nmap port scanner (www.nmap.org) and  
    emit custom objects with properties containing the scan data. The 
    script can accept either piped or parameter input.  The script can be
    safely dot-sourced without error as is. 

.Parameter Path  
    Either 1) a string with or without wildcards to one or more XML output
    files, or 2) one or more FileInfo objects representing XML output files.

.Parameter OutputDelimiter
    The delimiter for the strings in the OS, Ports and Services properties. 
    Default is a newline.  Change it when you want single-line output. 

.Parameter RunStatsOnly
    Only displays general scan information from each XML output file, such
    as scan start/stop time, elapsed time, command-line arguments, etc.

.Parameter ShowProgress
    Prints progress information to StdErr while processing host entries.    

.Example 
    dir *.xml | Import-NMAPXML

.Example 
	 Import-NmapXML -path onefile.xml
    Import-NmapXML -path *files.xml 

.Example 
    $files = dir *some.xml,others*.xml 
    Import-NmapXML -path $files    

.Example 
    Import-NmapXML -path scanfile.xml -runstatsonly

.Example 
    Import-NmapXML scanfile.xml -OutputDelimiter " "

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
    [Parameter(Mandatory=$true,ValueFromPipeline=$true)]$Path, 
    [String] $OutputDelimiter = "`n", 
    [Switch] $RunStatsOnly,
    [Switch] $ShowProgress
)
	
if ($Path -match "/\?|/help|-h|-help|--h|--help") 
{ 
	"`nPurpose: Process nmap XML output files (www.nmap.org).`n"
	"Example: Import-NmapXML scanfile.xml"
    "Example: Import-NmapXML *.xml -runstatsonly `n"
	exit 
}

if ($Path -eq $null) {$Path = @(); $input | foreach { $Path += $_ } } 
if (($Path -ne $null) -and ($Path.gettype().name -eq "String")) {$Path = dir $path} #To support wildcards in $path.  
$1970 = [DateTime] "01 Jan 1970 01:00:00 GMT"

if ($RunStatsOnly)
{
	ForEach ($file in $Path) 
	{
		$xmldoc = new-object System.XML.XMLdocument
		$xmldoc.Load($file)
		$stat = ($stat = " " | select-object FilePath,FileName,Scanner,Profile,ProfileName,Hint,ScanName,Arguments,Options,NmapVersion,XmlOutputVersion,StartTime,FinishedTime,ElapsedSeconds,ScanTypes,TcpPorts,UdpPorts,IpProtocols,SctpPorts,VerboseLevel,DebuggingLevel,HostsUp,HostsDown,HostsTotal)
		$stat.FilePath = $file.fullname
		$stat.FileName = $file.name
		$stat.Scanner = $xmldoc.nmaprun.scanner
		$stat.Profile = $xmldoc.nmaprun.profile
		$stat.ProfileName = $xmldoc.nmaprun.profile_name
		$stat.Hint = $xmldoc.nmaprun.hint
		$stat.ScanName = $xmldoc.nmaprun.scan_name
		$stat.Arguments = $xmldoc.nmaprun.args
		$stat.Options = $xmldoc.nmaprun.options
		$stat.NmapVersion = $xmldoc.nmaprun.version
		$stat.XmlOutputVersion = $xmldoc.nmaprun.xmloutputversion
		$stat.StartTime = $1970.AddSeconds($xmldoc.nmaprun.start) 	
		$stat.FinishedTime = $1970.AddSeconds($xmldoc.nmaprun.runstats.finished.time)
		$stat.ElapsedSeconds = $xmldoc.nmaprun.runstats.finished.elapsed
            
        $xmldoc.nmaprun.scaninfo | foreach {
            $stat.ScanTypes += $_.type + " "
            $services = $_.services  #Seems unnecessary, but solves a problem. 

            if ($services.contains("-"))
            {
                #In the original XML, ranges of ports are summarized, e.g., "500-522", 
                #but the script will list each port separately for easier searching.
                $array = $($services.replace("-","..")).Split(",")
                $temp  = @($array | where { $_ -notlike "*..*" })  
                $array | where { $_ -like "*..*" } | foreach { invoke-expression "$_" } | foreach { $temp += $_ } 
                $temp = [Int32[]] $temp | sort 
                $services = [String]::Join(",",$temp) 
            } 
                    
            switch ($_.protocol)
            {
                "tcp"  { $stat.TcpPorts  = $services ; break }
                "udp"  { $stat.UdpPorts  = $services ; break }
                "ip"   { $stat.IpProtocols = $services ; break }
                "sctp" { $stat.SctpPorts = $services ; break }
            }
        } 
            
        $stat.ScanTypes = $($stat.ScanTypes).Trim()
            
		$stat.VerboseLevel = $xmldoc.nmaprun.verbose.level
		$stat.DebuggingLevel = $xmldoc.nmaprun.debugging.level		
		$stat.HostsUp = $xmldoc.nmaprun.runstats.hosts.up
		$stat.HostsDown = $xmldoc.nmaprun.runstats.hosts.down		
		$stat.HostsTotal = $xmldoc.nmaprun.runstats.hosts.total
		$stat 			
	}
	return #Don't process hosts.  
}
	
ForEach ($file in $Path) {
	If ($ShowProgress) { [Console]::Error.WriteLine("[" + (get-date).ToLongTimeString() + "] Starting $file" ) }

	$xmldoc = new-object System.XML.XMLdocument
	$xmldoc.Load($file)
		
	# Process each of the <host> nodes from the nmap report.
	$i = 0  #Counter for <host> nodes processed.
	$xmldoc.nmaprun.host | foreach-object { 
		$hostnode = $_   # $hostnode is a <host> node in the XML.
		
		# Init variables, with $entry being the custom object for each <host>. 
		$service = " " #service needs to be a single space.
		$entry = [ordered]@{}

		# Extract state element of status:
		$entry.Status = $hostnode.status.state.Trim() 
		if ($entry.Status.length -lt 2) { $entry.Status = "<no-status>" }

		# Extract fully-qualified domain name(s), removing any duplicates.  
        $hostnode.hostnames.hostname | foreach-object { $entry.FQDN += $_.name + " " } 
		$entry.FQDN = [System.String]::Join(" ",@($entry.FQDN.Trim().Split(" ") | sort-object -unique)) #Avoid -Join and -Split for now
		if ($entry.FQDN.Length -eq 0) { $entry.FQDN = "<no-fullname>" }

		# Note that this code cheats, it only gets the hostname of the first FQDN if there are multiple FQDNs.
		if ($entry.FQDN.Contains(".")) { $entry.HostName = $entry.FQDN.Substring(0,$entry.FQDN.IndexOf(".")) }
		elseif ($entry.FQDN -eq "<no-fullname>") { $entry.HostName = "<no-hostname>" }
		else { $entry.HostName = $entry.FQDN }

		# Process each of the <address> nodes, extracting by type.
		$hostnode.address | foreach-object {
			if ($_.addrtype -eq "ipv4") { $entry.IPv4 += $_.addr + " "}
			if ($_.addrtype -eq "ipv6") { $entry.IPv6 += $_.addr + " "}
			if ($_.addrtype -eq "mac")  { $entry.MAC  += $_.addr + " "}
		}        
		if ($entry.IPv4 -eq $null) { $entry.IPv4 = "<no-ipv4>" } else { $entry.IPv4 = $entry.IPv4.Trim()}
		if ($entry.IPv6 -eq $null) { $entry.IPv6 = "<no-ipv6>" } else { $entry.IPv6 = $entry.IPv6.Trim()}
		if ($entry.MAC  -eq $null) { $entry.MAC  = "<no-mac>" }  else { $entry.MAC  = $entry.MAC.Trim() }


		# Process all ports from <ports><port>, and note that <port> does not contain an array if it only has one item in it.
		if ($hostnode.ports.port -eq $null) { $entry.Ports = "<no-ports>" ; $entry.Services = "<no-services>" } 
		else 
		{
			$entry.Ports = @()
            $hostnode.ports.port | foreach-object {
				if ($_.service.name -eq $null) { $service = "unknown" } else { $service = $_.service.name } 
				$entry.Ports += $_.state.state + ":" + $_.protocol + ":" + $_.portid + ":" + $service
                # Build Services property. What a mess...but exclude non-open/non-open|filtered ports and blank service info, and exclude servicefp too for the sake of tidiness.
                if ($_.state.state -like "open*" -and ($_.service.tunnel.length -gt 2 -or $_.service.product.length -gt 2 -or $_.service.proto.length -gt 2)) { $entry.Services += $_.protocol + ":" + $_.portid + ":" + $service + ":" + ($_.service.product + " " + $_.service.version + " " + $_.service.tunnel + " " + $_.service.proto + " " + $_.service.rpcnum).Trim() + " <" + ([Int] $_.service.conf * 10) + "%-confidence>$OutputDelimiter" }
			}
			$entry.Ports = $entry.Ports.Trim()
            if ($entry.Services -eq $null) { $entry.Services = "<no-services>" } else { $entry.Services = $entry.Services.Trim() }
		}


		# If there is 100% Accuracy OS, show it 
        $CertainOS = $hostnode.os.osmatch | where {$_.accuracy -eq 100}
        if ($CertainOS) {$Entry.OS = $certainOS.name} else {$Entry.OS=$null}
		$entry.BestGuessOS = ($hostnode.os.osmatch | select -first 1).name
        $entry.BestGuessOSPercent = ($hostnode.os.osmatch | select -first 1).accuracy
        $entry.OSGuesses = $hostnode.os.osmatch
		#if ($entry.OSGuesses.count -lt 1) { $entry.OS = "<no-os>" }

            
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
            
        if ($entry.Script -eq $null) { $entry.Script = "<no-script>" } 
    
    
		# Emit custom object from script.
		$i++  #Progress counter...
		new-object PSObject -property $entry
	}

	If ($ShowProgress) { [Console]::Error.WriteLine("[" + (get-date).ToLongTimeString() + "] Finished $file, processed $i entries." ) }
}