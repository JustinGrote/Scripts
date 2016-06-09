Add-PSSnapin "Microsoft.Exchange.Management.PowerShell.E2010"

<#
.SYNOPSIS
Creates mailbox databases in batch based on a CSV file. Useful for setting up DAGs across multiple servers
#>

[CmdletBinding(SupportsShouldProcess)]

$mdbCSV = import-csv ToyotaTestLayout.csv

#region Includes
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
#endregion Includes

#region Main

foreach ($mdbItem in $mdbCSV) {
    $ProgressParams = @{
        Activity = "Creating Mailbox Databases from CSV"
        Status = "Creating" + $mdbItem.DatabaseName
        ID = 1
    }
    Write-VerboseProgress @ProgressParams

    $MDBPath = $mdbItem.DatabaseDrive + "\" + $mdbItem.ParentDatabaseFolder + "\" + $mdbItem.DatabaseName + ".edb"
    $MDBLogPath = $mdbItem.TransactionLogDrive + "\" + $mdbItem.ParentLogFolder + "\" + $mdbItem.DatabaseName + "_LOG"
    
    #Create the Mailbox Database Folder
    $MDBParentPath = split-path $MDBPath -parent
    Write-VerboseProgress @ProgressParams -CurrentOperation "Creating Mailbox Directory $MDBParentPath"
    if (test-path $MDBParentPath) {
        write-warning "$MDBParentPath exists, skipping..."
    } else {
        try {
            $mkdirResult = mkdir $MDBParentPath
            if ($mkdirResult -isnot [System.IO.DirectoryInfo]) {throw "mkdir $MDBParentPath Failed"}
        } catch {
            throw $Error[0]
        }
    }

    #Create the Mailbox Database Log Folder
    $MDBLogParentPath = split-path $MDBLogPath -parent
    Write-VerboseProgress @ProgressParams -CurrentOperation "Creating Mailbox Log Directory $MDBLogParentPath"
    if (test-path $MDBLogParentPath) {
        write-warning "$MDBLogParentPath exists, skipping..."
    } else {
        try {
            $mkdirResult = mkdir $MDBLogParentPath
            if ($mkdirResult -isnot [System.IO.DirectoryInfo]) {throw "mkdir $MDBLogParentPath Failed"}
        } catch {
            throw $Error[0]
        }
    }
}



#endregion Main





<#



$db = $mdbCSV

$TSfldr=$DB.TransactionLogDrive+"\"+$DB.ParentLogFolder

if(Test-Path $TSfldr) {
    New-Item $TSfldr -ItemType Directory
}

if($DBDrivePresent-eq$true){
    Write-Host "Database Drive is present" -ForegroundColor Cyan
    $DBfldr=$DB.DatabaseDrive+"\"+$DB.ParentDatabaseFolder
    $DBFolderPresent= Test-Path $DBfldr

    if($DBFolderPresent-eq$false){

                          

    Write-Host "Creating Database Folder" -ForegroundColor Yellow

    New-Item $DBfldr -ItemType Directory

                          

    }

                          

    $DBPath=$DBfldr+"\"+$DB.DatabaseName+".edb"

    $LogPath=$TSfldr+"\"+$DB.DatabaseName+"_LOG"

                          

    Write-Host "Creating Mailbox Database" -ForegroundColor Blue

                          

    New-MailboxDatabase -Name $DB.DatabaseName -Server $DB.PrimaryServer -EdbFilePath $DBPath -LogFolderPath $LogPath

    CountDown

    Write-Host "Mounting Mailbox Database" -ForegroundColor Green

    Mount-Database -Identity $DB.DatabaseName

                          

    $DagReplicas=$DB.DAGReplicaServers.Replace(",","`n");

    $ActPrefs=$DB.ActivationPrefs.Replace(",","`n");

                          

    $arr=$DagReplicas.split("`n")

    $ap=$ActPrefs.split("`n")

                           

    foreach ($elementin$arr){

                    foreach ($prefin$ap){

                        Write-Host "Adding DAG Copies" -ForegroundColor White

                        Add-MailboxDatabaseCopy -Identity $DB.DatabaseName -MailboxServer $element -ActivationPreference $pref -ErrorActionSilentlyContinue

                    }

                                 

    }

                          

}else{

    Write-Host "Error: Database Drive Specified is not present" -ForegroundColor Red

}

}else{

                    

Write-Host "Error: Transaction Drive Specified is not present" -ForegroundColor Red

                    

}

}

}

$File=Select-FileDialog -Title "Import an CSV file" -Directory "c:\"

parse_CSVData $File

#>