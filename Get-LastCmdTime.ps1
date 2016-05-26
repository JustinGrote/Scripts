
 <#
.SYNOPSIS

Outputs the execution time of the the last command in history.

.DESCRIPTION

Calculates and outputs the time difference of the last command in history.

The difference will be outputted in a "human" format if the Humanizer module 
(https://www.powershellgallery.com/packages/PowerShellHumanizer/2.0) is 
installed. 

.EXAMPLE

Outputs the execution time of the the last command in history.

Get-LastCmdTime.

.NOTES

Returns $null if the history buffer is empty.
#>
 function Get-LastCmdTime
 {
    $diffPromptTime = $null
   
    $lastCmd = Get-History -Count 1
    if ($lastCmd -ne $null) {
        $diff = $lastCmd.EndExecutionTime - $lastCmd.StartExecutionTime
        try 
        {
        # assumes humanize has been installed:
          $diffPromptTime = $diff.Humanize()
        }
        catch
        {
          $diffPromptTime = $diff.ToString("hh\:mm\:ss")
        }
        $diffPromptTime
    }
 }