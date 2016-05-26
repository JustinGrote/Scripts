function Write-VerboseProgress
{
<#
.Synopsis
   Simple Wrapper to write to both Progress and Verbose at the same time, for the simple reason that you can't log progress input.
.DESCRIPTION
   Currently quick and dirty with nearly no error checking or formatting.
#>

    [CmdletBinding()]
    Param
    (
        [string]$Activity,
        [string]$Status,
        [int]$ID,
        [switch]$Completed,
        [string]$CurrentOperation,
        [int]$ParentID,
        [int]$PercentComplete,
        [int]$SecondsRemaining,
        [int]$SourceID

    )

    write-progress @PSBoundParameters


    #TODO: Make this cleaner so it looks more like log lines you would expect.
    [String]$VerboseMessage = ""
    foreach ($Param in $PSBoundParameters.GetEnumerator()) { 
        $VerboseMessage += $Param.Key + ": " + $Param.Value + " | "
    }
    #Trim off unnecessary extra characters
    $VerboseMessage = $VerboseMessage.Substring(0,$VerboseMessage.Length-2)

    write-verbose $VerboseMessage

}