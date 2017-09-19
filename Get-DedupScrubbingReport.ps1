#################### HELP MENU ####################
<#
    .SYNOPSIS
    This script generates Data Deduplication Scrubbing report based on scrubbing channel event logs. It can also generate report from Dedup Operational/Diagnostic channels.

    .DESCRIPTION
    This script parses event logs of the recent certain number of days in Data Deduplication channels and generates a html report. Number of days can be specified by users.
    The report can be collected from specified folder which is taken as input.
    All the unwanted event IDs are imported from a predefined XML file and will be filtered out from the final report. 
    -ScrubbingOnly switch can be turned on/off to decide to process scrubbing events only or not.

    .EXAMPLE
    1. Collect events only from Scrubbing channel of recent 5 days. Remove all the unwanted events. 

        .\Get-DedupScrubbingReport.ps1 -DirOfReport "c:\deduptest\Scrubbing"
                    -NumOfDays 5 -ObsoleteEventsXMLFullPath "c:\deduptest\obsoleteEvents.xml" -ScrubbingOnly:$true

    2. Collect events from Scrubbing/Operational/Diagnostic channels. The default number of days are 30. All events are kept. 

        .\Get-DedupScrubbingReport.ps1 -DirOfReport "c:\deduptest\Scrubbing" -ScrubbingOnly:$false

    .AUTHOR
    CINDY CAO

    Version 1.0
    Dec 3, 2013
#>

#################### ARGUMENTS ####################
param(
    [Parameter(Mandatory=$True)]
    [string]$DirOfReport,
    
    [Parameter(Mandatory=$False)]
    [Int32]$NumOfDays = 30,

    [Parameter(Mandatory=$False)]
    [string]$ObsoleteEventsXMLFullPath = $null,
    
    [Parameter(Mandatory=$False)]
    [bool]$ScrubbingOnly = $true
    
)

#################### HTML TABLE FORMAT ####################
$style = "<style>"
$style = $style + "BODY{background-color:#FFFFFF;}"
$style = $style + "TABLE{ border-width: 1px;border-style: solid;border-color: #91B9D1;border-collapse: separate; font-size: 10pt; font-color: #000000; font-family: Arial; background-color:#FFFFFF; min-width: 80px;}"
$style = $style + "TH{background-color:#384F60;color: #FFFFFF;border-width: 1px;border-style: solid;border-color: #91B9D1;  text-align: center; padding-top: 2px;padding-bottom: 2px;padding-left: 2px;padding-right: 2px;min-width: 80px;}"
$style = $style + "TD{background-color:#E0F0FF;border-width: 1px;border-style: solid;border-color: #91B9D1; text-align: center;min-width: 80px;}"
$style = $style + "</style>"

$ItemStyleBegin = "<p style='font-size: 10pt; color: #978C30; font-family: Arial;'><strong><i><u>"
$ItemStyleEnd = "</u></i></strong></p>"

#################### CREATE LOG FOLDER ####################
function create-folder($path)
{    
  # Create folder name with timestamp

    $date = get-date -format D|% {$_.split(',').trim()}
  $date[1] = $date[1].split(' ')[0] + '_' + $date[1].split(' ')[1]
  $dir = $path+'\' + $date[1] + '_' + $date[2]

    $dir = $path+'\' + (Get-Date –Format yyyyMMMd).ToString()
    try
    {
        if(!(test-path $dir)){
        $dir=   New-Item -ItemType directory -Path $dir
        }
        ######################################################################
        #  Some errors don't throw, like invalid parameter, so force the throw,
        #  Errors like out of space, etc, should throw automatically
        #  In our case it could be an invalid directory path etc
        ######################################################################
        if($dir -eq $null)
        {
            throw $error[0].Exception
        }     
    }
    catch 
    {   
        write-host "caught a system exception :$error[0].Exception"
        break
    }
    finally
    {
        write-host "Report Path: $dir" 
    }


    if($dir -eq $null)
    {
        throw $error[0].Exception
    }  

    return $dir
}

#################### CREATE OUT FILE ####################
function create-output([string]$dir)
{  
  # Create output file path with timestamp  
  $output = $dir + '\' + (Get-Date -Format hh_mm_ss).ToString() + '.html'  
  write-host "Report file name: $output"  
  return $output
}
 
#################### GENERATE REPORT TITLE ####################
function get-title($config,$result)
{
  #Format title and body
  $config=[string]$config
  set-content $result "<div id='title'><h2>Data Deduplication Scrubbing Report&nbsp- Last&nbsp$config days</h2></div>"
  add-content $result "<p style='text-indent: 2em; font-size: 10pt;'>"
  add-content $result "Report was created at: "
  get-date|add-content $result
  add-content $result "</p>"
}

#################### GENERATE MACHINE DETAILS ####################
function Get-MachineInfo($result)
{
  add-content $result $ItemStyleBegin
  add-content $result "Machine Details"
  add-content $result $ItemStyleEnd
  
  # get machine name
  $sysinfo = systeminfo
  $line = $sysinfo|? {$_ -match "Host Name"}
  add-content $result "<p style='text-indent: 2em; font-size: 10pt;padding-top: 0pt;'>"
  $line |add-content $result 
  add-content $result "</p>"
  $line = $sysinfo |? {$_ -match "Domain"}
  add-content $result "<p style='text-indent: 2em; font-size: 10pt;padding-top: 0pt;'>"
  $line |add-content $result 
  add-content $result "</p>"  
    
  # multi-processor support
  add-content $result "<p style='text-indent: 2em; font-size: 10pt;padding-top: 0pt;'>"
  add-content $result "Processor: "
  $processor = get-wmiobject win32_processor
  $NumberOfCores = 0
  $NumberOfLogProc = 0
  for($i=0;$i -lt $processor.deviceid.Length;$i++){
    $NumberOfCores += $processor.numberofcores[$i]
    $NumberOfLogProc += $processor.numberoflogicalprocessors[$i]
  }
  add-content $result $processor.name
  $cores = "Cores: "+"<font style='color: #304CFF;'><b>"+[string]$NumberOfCores+"</b></font>"
  add-content $result $cores
  $logical = "Logical Processors: "+"<font style='color: #304CFF;'><b>"+[string]$NumberOfLogProc+"</b></font>"
  add-content $result $logical
  add-content $result "</p>"

  # get memory info    
  $line = $sysinfo |? {$_ -match "Memory"}
  add-content $result "<p style='text-indent: 2em; font-size: 10pt;padding-top: 0pt;'>"
  $line |add-content $result
  add-content $result "</p>"

}

#################### PARSE ONE EVENT CHANNEL ####################
function parse_eventlog($eventchannel, $deprecated, $result)
{
  # define hash table for event types
  $eventhash = @{"error"=1;"warning"=2;"information"=3}

  # get events of last certain number of days
  $firstday = (get-date) - (new-timespan -day $NumOfDays)
  $eventobj = get-winevent -filterhashtable @{logname = $eventchannel; starttime = $firstday} -EA silentlycontinue
   
  add-content $result "<br/>"
  add-content $result "<div id='evtlgrpt'>"
  add-content $result $ItemStyleBegin
  add-content $result $eventchannel
  add-content $result $ItemStyleEnd

  if( $eventobj -eq $null -or $eventobj.Count -eq 0 )
  {
      add-content $result "<p style='text-indent: 2em; font-size: 10pt;'>No qualified event from this channel</p>"
  }
  else
  {
      # group events by ID
      $grpobj = $eventobj |group-object id

      # create table for report
      $rpttb = new-object system.data.datatable "Dedup Scrubbing Report"

      # create columns for table
      $col1 = new-object system.data.datacolumn EventID, ([int])
      $col2 = new-object system.data.datacolumn EventType, ([string])
      $col3 = new-object system.data.datacolumn Message, ([string])
      $col4 = new-object system.data.datacolumn Occurrence, ([int])
      $col5 = new-object system.data.datacolumn Priority, ([int])
      $col6 = new-object system.data.datacolumn LastEventTime, ([DateTime])

      # add columns
      $rpttb.columns.add($col1)
      $rpttb.columns.add($col2)
      $rpttb.columns.add($col3)
      $rpttb.columns.add($col4)
      $rpttb.columns.add($col5)
      $rpttb.columns.add($col6)
    
      # create row and copy information from $grpobj to each row and add row to table
      foreach($line in $grpobj){
        if($deprecated -ne $null)
        {
            if($deprecated.item($line.name).length -gt 1){
                continue
            }
        }    

        $row = $rpttb.newrow()
        $row.eventid = $line.name
        $row.eventtype = $line.group[0].leveldisplayname
        $row.message = $line.group[0].message
        $row.occurrence = $line.count
        $row.priority = $eventhash[$row.eventtype]
        $row.lasteventtime = $line.group[0].timecreated    
        $rpttb.rows.add($row)
      }
  
      # convert to html with certain format
      if($rpttb.Rows.Count -lt 1){
        add-content $result "<p style='text-indent: 2em; font-size: 10pt;'>No qualified event from this channel</p>"
      }

      # sort events by message type and event id
      $rpttb |sort-object priority, eventid, lasteventtime |convertto-html -head $style EventID,EventType,Message,Occurrence,LastEventTime |
      add-content $result  
  
      add-content $result "</div>"
  }
  
}

#################### PARSE XML OF DEPRECATED EVENTS ####################
function get-obsolete($file)
{
  $xmldata = [xml](gc $file)
  $inputhash = @{}
  $xmldata.eventlog.event |% {$inputhash += @{$_.id=@{"level"=$_.level},@{"reason"=$_.reason}}}
  write-host "### get-obsolete done ###"
  return $inputhash
 }

#################### PARSE EVENT LOGS ####################
function get-events($deprecated,$output)
{ 
  if($ScrubbingOnly)
  {
    $lognametable = @("Microsoft-Windows-Deduplication/Scrubbing")
  }
  else
  {
    $lognametable = @("Microsoft-Windows-Deduplication/Scrubbing",
                    "Microsoft-Windows-Deduplication/Operational", 
                    "Microsoft-Windows-Deduplication/Diagnostic")
  }
  
  for($i = 0;$i -lt $lognametable.count; $i++){
    parse_eventlog $lognametable[$i] $deprecated $output
  }
  write-host "### get-events done ###"
}

#################### DEBUG PRINT ####################
function debug-print([string]$msg)
{
    write-host "Line $($MyInvocation.ScriptLineNumber)"
    write-host $msg
}

#################### MAIN ####################
function main
{  
  # Print usage example 
  write-host "Usage example: .\Get-DedupScrubbingReport.ps1 -DirOfReport `"c:\deduptest\Scrubbing`"  
                    -NumOfDays 30 -ObsoleteEventsXMLFullPath `"c:\deduptest\obsoleteEvents.xml`" -ScrubbingOnly:`$true" -ForegroundColor DarkYellow
  
  # Check Dedup feature
  $FeatureInstalled = $false

  $feature = Get-WindowsFeature FS-Data-Deduplication
  if ( $feature -ne $null ) 
  {
      $FeatureInstalled = $Feature.Installed
  }

  if($FeatureInstalled -eq $false)
  {
      debug-print "Dedup feature has not been installed, exit ......"
      return
  }

  # Sanity check of report directory
  if([string]::IsNullOrEmpty($DirOfReport)){
    debug-print "Invalid directory of report"
    return 
  }
  else{    
    write-host "Directory of report: $DirOfReport"       
  }

  # Sanity check of report name
  if(![string]::IsNullOrEmpty($NumOfDays))
  {
    write-host "Last $NumOfDays days"
  }

  # Sanity check of number of days of the event logs to be parsed
  if($NumOfDays -lt 1 -or $NumOfDays -ge $([int32]::MaxValue))
  {
    debug-print "Invalid value of number of days."
    return
  }  
  else
  {
    write-host "Number of days: $NumOfDays"
  }
  
  # Sanity check of XML full path of obsolete events    
  if(![string]::IsNullOrEmpty($ObsoleteEventsXMLFullPath))
  {
    write-host "XML full path of obsolete events is $ObsoleteEventsXMLFullPath"
  }

  # Check -ScrubbingOnly switch
  if($ScrubbingOnly)
  {
    write-host "Only collect event logs from Dedup Scrubbing channel ..."
  }
  else
  {
    write-host "Collect event logs from Dedup Scrubbing/Operational/Diagnostic channels ..."
  }
    
  # Create folder for event logs and scrubbing report 
  $dir = create-folder $DirOfReport

  # Create scrubbing report
  $output = create-output $dir

  # Create subject of scrubbing report
  get-title $NumOfDays $output
  
  # Parse obsolete events
  $obsolete = @{}
  if(![string]::IsNullOrEmpty($ObsoleteEventsXMLFullPath))
  {
    $obsolete = get-obsolete $ObsoleteEventsXMLFullPath
  }   
    
  # Generate machine information
  get-machineinfo $output              
  
  # Parse event logs
  get-events $obsolete $output
  

}

main


