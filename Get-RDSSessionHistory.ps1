function Get-RDSSessionHistory {

param(
    [string]$ComputerName = "localhost",
    [int]$MaxEvents=($MAXEVENTSDEFAULT=100),
    [switch]$LogonOnly,
    [datetime]$Before,
    [datetime]$After,
    [switch]$Brief

)
$ErrorActionPreference = "Stop"
$LogName = 'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational'
$Results = @()

#Construct the filter
$FilterHashTable = @{}
$FilterHashTable += @{logname=$LogName}
if ($LogonOnly) {$FilterHashTable += @{id=21} }
if ($Before) {$FilterHashTable += @{endtime=$before} }
if ($After) {$FilterHashTable += @{starttime=$after} }

if ($maxEvents = $MAXEVENTSDEFAULT) {write-warning "By default Get-RDSSessionHistory only returns the first $MAXEVENTSDEFAULT events. You can adjust this by specifying the -maxevents parameter"}

write-verbose "Collecting $MaxEvents RDS events from $ComputerName"
$Events = Get-WinEvent -computername $ComputerName -FilterHashTable $FilterHashTable -MaxEvents $MaxEvents
foreach ($Event in $Events) {
    $EventXml = [xml]$Event.ToXML()


    $ResultProps = @{
        Computer    = $Computername
        Time        = $Event.TimeCreated.ToString()
        'Event ID'  = $Event.Id
        'Desc'      = ($Event.Message -split "`n")[0]
        Username    = $EventXml.Event.UserData.EventXML.User
        'Source IP' = $EventXml.Event.UserData.EventXML.Address
        'Details'   = $Event.Message
    } #ResultProps

    $Results += (New-Object PSObject -Property $ResultProps)
}

#Filter the results appropriately based on switches. Could do this during the event query to be more efficient, this is easier.
if ($LogonOnly) {$results = $results | where {$_."Event ID" -eq 21}}
if ($brief) {$results = $results | ft -AutoSize computer,username,sourceip,"Event ID",time}


return $results

} #Get-RDSSessionHistory

Get-RDSSessionHistory