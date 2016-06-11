#Add-PSSnapin "Microsoft.Exchange.Management.PowerShell.E2010"

<#
.SYNOPSIS
Creates mailbox databases in batch based on a CSV file. Useful for setting up DAGs across multiple servers.
.DESCRIPTION
This script was designed to aid in the creation of large amounts of mailbox databases and copies (20+). 
It is specifically designed to be very safe, fully supporting -whatif and requiring confirmation for every step unless approved otherwise
Numerous sanity checks, progress, and verbose logging are also implemented
It is also designed to be resumable such that if you enounter an error, you can clean it up, and run the script again to skip everything up to your most recent action
.AUTHOR
Justin Grote <justingrote+powershell@gmail.com>
.NOTES
Tested on Exchange 2016, should work fine on 2013
#>

#region Includes
function Write-VerboseProgress {
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

function Create-MailboxDatabases {

    [CmdletBinding(SupportsShouldProcess)]
    param (
        #Path to the CSV containing the information for mailbox database creation
        [Parameter(Mandatory)][String]$mdbCSVPath,
        #Enter the FQDN of an Exchange Server for the purpose of establishing a remote powershell session. Recommend direct hostname, a load balanced VIP may or may not work depending on your configuration
        #It is assumed you are joined to the domain and can access this server via remote powershell
        [Parameter(Mandatory)][String]$exchangeServer
    )

    $commonParams = @{}

    #Pass thru common parameters to important commands
    if ($PSBoundParameters.whatif) {$commonParams.whatif = $PSBoundParameters.whatif}
    if ($PSBoundParameters.verbose) {$commonParams.verbose = $PSBoundParameters.verbose}
    #We want "stop" to be the default as most errors prevent the script from continuing, thus it should be terminated before they are fixed
    if ($PSBoundParameters.errorAction) {$commonParams.errorAction = $PSBoundParameters.errorAction} else {$commonParams.errorAction = "stop"}
    $mdbCSV = import-csv $mdbCSVPath -ErrorAction stop
    $createMDB = $true
    $exchangeRemotePSCommands = '*-mailboxdatabase*','mount-database'
    $exchangeRemotePSSession = New-PSSession -ErrorAction stop -verbose -ConfigurationName Microsoft.Exchange -ConnectionUri http://$exchangeServer/Powershell/
    $exchangeRemotePSSessionCommands = Import-PSSession -ErrorAction stop -verbose -Session $exchangeRemotePSSession -prefix mdb -CommandName $exchangeRemotePSCommands -AllowClobber
    
    #Do some cleanup if a fatal error is thrown
    trap {
        #write-error $error[0]
        Remove-PSSession $exchangeRemotePSSession -whatif:$false -verbose -confirm:$false
    }

    foreach ($mdbItem in $mdbCSV) {
        $ProgressParams = @{
            Activity = "Creating Mailbox Databases from CSV"
            Status = "Creating " + $mdbItem.DatabaseName
            ID = 1
        }
        Write-VerboseProgress @ProgressParams

        ###Get the full list of servers and create the folders remotely. Assumes you have admin rights to the servers.
        $dagReplicaServers = $mdbitem.dagreplicaservers -split ',' 
        $activationPrefs = $mdbitem.activationprefs -split ','

        $ExchangeServers = @()
        $ExchangeServers += $mdbitem.primaryserver
        $dagReplicaServers | foreach {$ExchangeServers += $PSItem}

        #Sanity Check: duplicate entries in the server list
        if ($ExchangeServers.count -ne ($ExchangeServers | select -unique).count) {throw "$($mdbitem.DatabaseName): There are duplicate server names in the PrimaryServer/DAGReplicaServers list entry"}
        #Sanity Check: activation preference count matches DAG replica servers count
        if ($activationPrefs.count -ne $dagReplicaServers.count) {throw "$($mdbitem.DatabaseName): The number of activationPrefs entries doesn't match the number of dagReplicaServers entries"}
        #Sanity Check: activation preference numbers are unique
        if ($activationPrefs.count -ne ($activationPrefs | select -unique).count) {throw "$($mdbitem.DatabaseName): activationPrefs has duplicate numbers, ensure that they are unique"}

        $MDBRelativePath = $mdbItem.ParentDatabaseFolder + "\" + $mdbItem.DatabaseName + ".edb"
        $MDBRelativeLogPath = $mdbItem.ParentLogFolder
        $MDBLocalPath = $mdbItem.DatabaseDrive + ':\' + $MDBRelativePath 
        $MDBLogLocalPath = $mdbItem.TransactionLogDrive + ':\' + $MDBRelativeLogPath 


        #Check all the paths and create them up front
        $MDBUNCPath = '\\' + $mdbItem.primaryserver + '\' + $mdbItem.DatabaseDrive + '$\' + $MDBRelativePath
        $MDBLogUNCPath = '\\' + $mdbItem.primaryserver + '\' + $mdbItem.TransactionLogDrive + '$\' + $MDBRelativeLogPath
        $MDBPath = $MDBUNCPath
        $MDBLogPath = $MDBLogUNCPath

        $MDBParentPath = split-path $MDBPath -parent
        Write-VerboseProgress @ProgressParams -CurrentOperation "Creating Mailbox Directory $MDBParentPath"
        if (test-path $MDBParentPath) {
            write-warning "$MDBParentPath exists, skipping..."
        } else {
            try {
                $mkdirResult = mkdir @CommonParams $MDBParentPath
            } catch {
                throw $Error[0]
            }
        }
            
        $MDBLogParentPath = $MDBLogPath
        Write-VerboseProgress @ProgressParams -CurrentOperation "Creating Mailbox Log Directory $MDBLogParentPath"
        if (test-path $MDBLogParentPath) {
            write-warning "$MDBLogParentPath exists, skipping..."
        } else {
            try {
                $mkdirResult = mkdir @CommonParams $MDBLogParentPath
            } catch {
                throw $Error[0]
            }
        }

        #Create the primary Mailbox Database


        Write-VerboseProgress @ProgressParams -CurrentOperation ("Creating Mailbox Database " + $mdbItem.DatabaseName + " on " + $mdbitem.primaryserver + " DBPath:$MDBLocalPath LogPath:$MDBLogLocalPath")
        
        #Sanity Checks for Database File
        $createMDB = $true
        if (Test-Path $MDBPath) {
            try {
                Get-mdbMailboxDatabase $mdbItem.DatabaseName -erroraction stop | format-table -autosize name,server,databasecopies,edbfilepath,logfolderpath
            }
            catch {
                throw "A database file for a removed mailbox database was discovered. Move it manually before continuing for safety: $MDBUNCpath"
            } 
            
            write-warning "Mailbox Database $($mdbItem.DatabaseName) already exists. Skipping..."
            $CreateMDB = $false
        }
            
        
        if ($CreateMDB) {
            #Create the Database. Warnings are suppressed to avoid the information store warning
            $WarningPreference = "silentlyContinue"
            $primaryMDB = New-mdbMailboxDatabase @CommonParams -Name $($mdbItem.DatabaseName) -Server $mdbItem.primaryserver -EdbFilePath $MDBLocalPath -LogFolderPath $MDBLogLocalPath -warningaction "SilentlyContinue"
            $WarningPreference = "continue"

            #Wait for AD replication
            Write-VerboseProgress @ProgressParams -CurrentOperation "Waiting 5 seconds for AD Replication"
            if (!($CommonParams.whatif)) {sleep 5}

            #Try to mount. If it doesn't work, wait 30 seconds and try again, then fail for good
            try {
                Write-VerboseProgress @ProgressParams -CurrentOperation ("Mounting Database " + $mdbItem.DatabaseName)
                if (!($CommonParams.whatif)) {$primarymdb | Mount-mdbDatabase @CommonParams}
            } 
            catch {
                Write-VerboseProgress @ProgressParams -CurrentOperation "Initial Mount Attempt Failed. Waiting 30 seconds for AD Replication"
                if (!($CommonParams.whatif)) {sleep 30}
                try {
                    Write-VerboseProgress @ProgressParams -CurrentOperation ("Mounting Database (2nd Attempt) " + $mdbItem.DatabaseName)
                    if (!($CommonParams.whatif)) {$primarymdb | Mount-mdbDatabase @CommonParams}
                } catch {
                    throw $error[0]
                }
            }
        }

        #Create DAG Passive Copies

        #Pair up the servers with their activation orders
        $i=0
        $dagReplicas = foreach ($dagReplicaServerItem in $dagReplicaServers) {
            [PSCustomObject][ordered]@{
                server = $dagReplicaServerItem
                ap = $activationPrefs[$i]
            }
            $i++
        } 

        foreach ($dagReplicaItem in ($dagReplicas | sort ap)) {
            
            #Check all the paths and create them up front
            $MDBUNCPath = '\\' + $dagReplicaItem.server + '\' + $mdbItem.DatabaseDrive + '$\' + $MDBRelativePath
            $MDBLogUNCPath = '\\' + $dagReplicaItem.server + '\' + $mdbItem.TransactionLogDrive + '$\' + $MDBRelativeLogPath
            $MDBPath = $MDBUNCPath
            $MDBLogPath = $MDBLogUNCPath

            $MDBParentPath = split-path $MDBPath -parent
            Write-VerboseProgress @ProgressParams -CurrentOperation "Creating Mailbox Copy Directory $MDBParentPath"
            if (test-path $MDBParentPath) {
                write-warning "$MDBParentPath exists, skipping..."
            } else {
                try {
                    $mkdirResult = mkdir @CommonParams $MDBParentPath
                } catch {
                    throw $Error[0]
                }
            }
            
            $MDBLogParentPath = $MDBLogPath
            Write-VerboseProgress @ProgressParams -CurrentOperation "Creating Mailbox Copy Log Directory $MDBLogParentPath"
            if (test-path $MDBLogParentPath) {
                write-warning "$MDBLogParentPath exists, skipping..."
            } else {
                try {
                    $mkdirResult = mkdir @CommonParams $MDBLogParentPath
                } catch {
                    throw $Error[0]
                }
            }


            #Test if Copy Exists. If it does, skip it
            $CreateMailboxCopy = $true

            #Sanity Check for pre-existing Replica DB File
            if (Test-Path $MDBPath) {
                try {
                    Get-mdbMailboxDatabaseCopyStatus ($mdbItem.DatabaseName + '\' + $dagReplicaItem.server) -erroraction stop | ft identity,status,activecopy,activationpreference
                }
                catch {
                    throw "A database file for a removed mailbox database was discovered. Move it manually before continuing for safety: $replicaMDBPath"                    
                }
                write-warning "Mailbox Database Replica $($mdbItem.DatabaseName) already exists. Skipping..."
                $CreateMailboxCopy = $false
            }

            if ($CreateMailboxCopy) {
                Write-VerboseProgress @ProgressParams -CurrentOperation "Creating Passive Mailbox Database Copy of $($mdbItem.Databasename) on $($dagReplicaItem.server) with ActPref $($dagReplicaItem.ap)"
                $WarningPreference = "silentlycontinue"
                if (!($CommonParams.whatif)) {Get-mdbMailboxDatabase $mdbitem.databasename | where server -match $mdbitem.primaryserver | Add-mdbMailboxDatabaseCopy @CommonParams -MailboxServer $dagReplicaItem.server -ActivationPreference $dagReplicaItem.ap}
                $WarningPreference = "continue"
            }
        }
    }

    #Cleanup
    Remove-PSSession $exchangeRemotePSSession -whatif:$false -verbose -confirm:$false
}


#endregion Main