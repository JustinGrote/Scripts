<#Windows PowerShell Code####################################################### 
 .SYNOPSIS  
    Archive Log Files: Manually specify any folder(s) or automatically parse IIS  
    log file folders, group by day/month and archive them with 7-Zip. Verify 
    the archives and delete the original log files. The compressed archive will  
    be about 4.5% (or less) of the size of the original log files. 
 
.DESCRIPTION  
    Archive files by location as defined by either: 
    - Automatically discovering all IIS site's logfile folders using the  
      WebAdministration module, or 
    - Manually specifying target folders  
 
    Parse through the folder contents to find the previous month's or day's  
    files. Archive them, verify the archive and delete the original files.  
    The resulting compressed archive will be about 4.5% (or less) of the size  
    of the original log files. Optionally remove archives older than a user  
    defined number of days. 
             
    This script is best used by setting a scheduled task to run it during  
    off-peak times because the compression process will max out all available  
    cores unless you tell 7-Zip not to do so (in its own settings, not from this 
    script.) 
 
    7-Zip version 15 or higher is required for this script to work. 
    http://www.7-zip.org/download.html 
 
    Important! In Windows Server 2012+ you may need to run this script with  
    administrator privileges and/or remove UAC controls on IIS log file folders 
    to successfully archive them. 
 
    You have a royalty-free right to use, modify, reproduce, and distribute this 
    script file in any way you find useful, provided that you agree to give  
    credit to the creator owner, and you agree that the creator owner has no  
    warranty, obligations, or liability for such use.  
 
.NOTES  
    File Name  : compress-remove-logs.ps1  
    Version    : 2.4.4 
    Date       : 20160526 
    Author     : Bernie Salvaggio 
    Email      : BernieSalvaggio(at)gmail(dot)com 
    Twitter    : @BernieSalvaggio 
    Website    : http://www.BernieSalvaggio.com/ 
    Requires   : PowerShell V2, V3 or V4 
  
###############################################################################> 


# Build the base pieces for emailing results 
$ServerName = gc env:computername 
$SmtpClient = new-object system.net.mail.smtpClient 
$MailMessage = New-Object system.net.mail.mailmessage 
$MailMessage.Body = "" 
 
################################################################################ 
####################### BEGIN USER CONFIGURABLE SETTINGS ####################### 
 
# Mail server settings. Change according to your environment. 
# You have the option of receiving error notifications via email and/or writing  
# them to a log file. The settings for determining when you receive emails 
# and if a logfile is used are the next two after these email server settings 
$SmtpClient.Host = "192.168.1.2" 
$MailMessage.from = ($ServerName + "@yourdomain.com") 
$MailMessage.To.add("username@yourdomain.com") 
$MailMessage.Subject = $ServerName + " Log File Archive Results" 
 
# When should this script email you? 
# both -> Email on both success and failure 
# failure -> Only email on failure 
# never -> Don't send any emails from this script (not recommended, see above) 
# Note: A "failure" could be a hard failure, e.g., can't find the path to 7-Zip, 
#       or a soft failure, e.g., no files found to archive in a specified path 
$MailMessageDetermination = "both" 
 
# Path to logfile - Make sure this script has permissions to write here 
# Set to "" if you don't want to use a log file 
$Logfile = "C:\temp\LogfileArchiving-Log.txt" 
 
# Folder for the temp file that stores the list of files for 7-Zip to archive 
$TempFolder = "C:\temp" 
 
# Path to the 7-Zip executable 
# Note: 7z.dll must also be in this folder for 7-Zip to work 
$7z = "C:\Program Files (x86)\7-Zip\7z.exe" 
 
# Select 7-Zip compression method 
# zip -> Traditional zip compression 
# ppmd-> Specialized compression method for text files. Creates a 7-Zip archive,  
#        which requires 7-Zip to open it. The resulting archive will generally 
#        be about 50% smaller than using traditional zip compression 
$CompressionMethod = "ppmd" 
 
# Note: Only required if you set $CompressionMethod = "ppmd" above 
# How much RAM should PPMd use? (in MB, max=256, 7-Zip default = 24) 
$PPMdRAM = "128" 
 
# Set to $true if you would like to run the script in Test Mode, which performs  
# all actions as normal but DOES NOT delete the original files you're archiving 
# Note: Test mode should be run from the command line to see the results of the  
# -WhatIf operations - email messaging is not altered for test mode 
$TestMode = $true 
 
# If you would like to automatically remove the archives that this script creates,  
# set the following to true and then define how old the archives should be (in  
# days) to be deleted 
# Note: This option only deletes .zip or .7z files, depending on the compression  
#       method that you selected above 
# Note 2: Archive dates are set based on the most recent file's date in the archive. 
#         So if a file date is 20150105 and you set it up below to delete archives  
#         older than 120 days, the archive will be created and immediately deleted. 
#         So you may want to leave this setting as $false until you've done a few 
#         runs and decided what you want to do with your old archives. 
$RemoveOldArchives = $false 
$RemoveArchivesDaysOld = 120 
 
# Extension of files to archive. Don't change this variable unless: 
# 1. You're using this script to back up files other than IIS log files, 
# 2. You've set $UseWebAdministrationSnapIn = $false and... 
# 3. You've manually specified targets below 
$FileExtension = ".log" 
 
# Name to begin the filename of the resulting archive 
$TargetTypeName = "ProgramName-Logs-" 
 
# Archive Date Grouping - Specify how to group the archives 
# month -> Archive all past log files by month, excluding the current month 
# day ->   Archive all past log files by day, excluding the most recent 2 days  
$ArchiveGrouping = "month" 
 
# Archive Storage Location - Use this variable to specify a single location 
# to save all archives. Subfolders will be created using the unique name  
# assigned to each target. 
# 
# If you prefer that the archives are stored in the same folder as the 
# files being archived, change this line to $ArchiveStorage = "" 
$ArchiveStorage = "C:\ArchiveStorage" 
 
# $true:  Use the Web Administration (IIS) provider to automatically archive  
#          log files for all IIS sites. Requires IIS 7 or 7.5 
# $false: Manually specify target log file folder(s) (in the next section) 
$UseWebAdministrationSnapIn = $true 
 
<#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ 
The following settings are ONLY used if you set $UseWebAdministrationSnapIn 
(above) to $false so you can ignore them if it's set to $true 
 
If you don't want this script to automatically archive the log files for ALL of  
your IIS sites, set $UseWebAdministrationSnapIn=$false above, and manually  
specify the log file folders and their respective backup folders below. 
 
If you use these settings, and modify the $FileExtension variable above, you  
can use this script to archive any folders/files, not just IIS log files. 
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#> 
if (!$UseWebAdministrationSnapIn) { 
    $Targets = @() 
    # The folder(s) (targets) you want to archive 
    # Duplicate the following four lines for each target you want to archive 
    $Properties = @{ArchiveTargetName="Site 1";  
                    ArchiveTargetFolder="C:\inetpub\logs\LogFiles\W3SVC1\"} # Don't forget the trailing \  
    $Newobject = New-Object PSObject -Property $Properties 
    $Targets += $Newobject 
} 
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ 
 
################################################################################ 
######################## END USER CONFIGURABLE SETTINGS ######################## 
################################################################################ 
 
function Send-Email { 
    switch ($MailMessageDetermination) { 
        both { $SmtpClient.Send($MailMessage); break } 
        failure { if ($ErrorTrackerEmail) { $SmtpClient.Send($MailMessage) }; break } 
        never { break } 
        default { $SmtpClient.Send($MailMessage) } 
    } 
} 
 
# Test to make sure the log file is writeable 
if ($Logfile) { 
    Try { [io.file]::OpenWrite($Logfile).close() } 
    Catch {  
        $MailMessage.Body += "Error: Could not write to logfile path $Logfile" 
        $ErrorTrackerEmail = $true 
        Send-Email 
        Exit 
    } 
} 
 
$LogDate = get-date -Format "yyyyMMdd" 
 
function Write-Log { 
    param([string]$LogEntry) 
 
    $LogEntry = $LogDate + ": " + $LogEntry 
    $MailMessage.Body += $LogEntry 
    if ($Logfile) { Add-content $Logfile -value $LogEntry.replace("`n","") } 
} 
 
if ($UseWebAdministrationSnapIn) { 
    # Check IIS version and load the WebAdministration module accordingly 
    $iisVersion = Get-ItemProperty "HKLM:\software\microsoft\InetStp"; 
    if ($iisVersion.MajorVersion -ge 7) { 
        if ($iisVersion.MinorVersion -ge 5 -or $iisVersion.MajorVersion -eq 8) { 
            Import-Module WebAdministration  
        } else {  
            if (-not (Get-PSSnapIn | Where {$_.Name -eq "WebAdministration"})) { 
                Add-PSSnapIn WebAdministration  
            } 
        } 
        # Grab a list of the IIS sites 
        $Sites = get-item IIS:\Sites\* 
        $Targets = @() 
        foreach ($Site in $Sites) {  
            # Grab the site's base log file directory  
            $SiteDirectory = $Site.logFile.Directory 
            # That returns %SystemDrive% as text instead of the value of the  
            # env variable, which PoSH chokes on, so replace it correctly 
            $SiteDirectory = $SiteDirectory.replace("%SystemDrive%",$env:SystemDrive) 
            # Set the site's actual log file folder (the W3SVC## or FTPSVC## dir) 
            if ($Site.Bindings.Collection.Protocol -like "*ftp*")  
                 { $SiteLogfileDirectory = $SiteDirectory+"\FTPSVC"+$Site.ID } 
            else { $SiteLogfileDirectory = $SiteDirectory+"\W3SVC"+$Site.ID } 
             
            # Create/Add site name and logfile directory to a hash table, then  
            # feed it into a multi-dimension array 
            $Properties = @{ArchiveTargetName=$Site.Name;  
                            ArchiveTargetFolder=$SiteLogfileDirectory} 
            $Newobject = New-Object PSObject -Property $Properties 
            $Targets += $Newobject 
        } 
    } else { 
        Write-Log "IIS 7 or higher is required to use the WebAdministration SnapIn" 
        $ErrorTrackerEmail = $true 
        Send-Email 
        Exit 
    } 
} 
 
# Get today's date 
$CurrentDate = Get-Date 
 
# Prepping to strip invalid file/folder name characters from ArchiveTargetName 
$InvalidChars = [io.path]::GetInvalidFileNameChars() 
 
# Set the dates needed for archiving by month or day,  
# depending on what was set above for $ArchiveGrouping 
Switch($ArchiveGrouping) { 
    "month" { 
        $ArchiveGroupingString = "{0:yyyy}{0:MM}" 
        $ArchiveDate = $CurrentDate.AddMonths(-1).ToString("yyyyMM") 
    } 
    "day" { 
        $ArchiveGroupingString = "{0:yyyy}{0:MM}{0:dd}" 
        $ArchiveDate = $CurrentDate.AddDays(-2).ToString("yyyyMMdd") 
    } 
    Default { 
        Write-Log "Invalid Archive Grouping selected. You selected '$ArchiveGrouping'. Valid options are month and day." 
        $ErrorTrackerEmail = $true 
        Send-Email 
        Exit 
    } 
} 
 
# Set the date for old archive file removal if that was specified above 
if ($RemoveOldArchives) { [DateTime]$OldArchiveRemovalDate = $CurrentDate.AddDays(-$RemoveArchivesDaysOld) } 
 
# Test the temp folder path to make sure it exists, create it if it doesn't,  
# and set the temp file for archive contents 
if (!(Test-Path $TempFolder)) { New-Item $TempFolder -type directory } 
$ArchiveList = "$TempFolder\listfile.txt" 
 
# Temp file to write the 7-Zip verify results, later feed into the email message 
$ArchiveResults = "$TempFolder\archive-results.txt" 
 
# Set some details based on which compression method was selected 
if ($CompressionMethod -eq "zip") { 
    $ArchiveExtension = ".zip" 
} elseif ($CompressionMethod -eq "ppmd") { 
    $ArchiveExtension = ".7z" 
    # Build the switch to set PPMd as the compression method with the amount of RAM specified above 
    $PPMdSwitch = "-m0=PPMd:mem"+$PPMdRAM+"m" 
} else { 
    Write-Log "Error: Invalid compression method specified. Valid options are zip or ppmd. You specified $CompressionMethod" 
    $ErrorTrackerEmail = $true 
    Send-Email 
    Exit 
} 
 
# Tracker in case no files are found to archive 
$FilesFound = $false 
 
# Tracker for success or failure so the script knows when to email results 
$ErrorTrackerEmail = $false 
 
# Test the path to the 7-Zip executable 
if (!(Test-Path $7z)) {  
    Write-Log "Error: 7-Zip not found at $7z" 
    $ErrorTrackerEmail = $true 
    Send-Email 
    Exit 
} 
 
# Test to make sure we're trying to use the right version of 7-Zip (15+) 
[single]$7zVersion = (Get-Item $7z).VersionInfo.FileVersion 
if ($7zVersion -lt 15) { 
    Write-Log "Error: 7-Zip version 15 or higher is required by this script. You are running version $7zVersion." 
    $ErrorTrackerEmail = $true 
    Send-Email 
    Exit 
} 
 
# Test the path to the archive storage location if it has been set 
if ($ArchiveStorage) {  
    if (!(Test-Path $ArchiveStorage) -and ($ArchiveStorage -ne "")) {  
            Write-Log "Error: The specified archive storage location does not exist at $ArchiveStorage.  
            Please create the requested folder and try again." 
        $ErrorTrackerEmail = $true 
        Send-Email 
        Exit 
    } 
} 
 
# Begin looping through all the Targets and do the actual archiving work 
$TargetsCounter = $Targets.count 
For ($x=0; $x -lt $TargetsCounter; $x++) { 
     
    # Replace invalid file/folder name characters in the target name with dashes 
    $TargetName = $Targets[$x].ArchiveTargetName -replace "[$InvalidChars]","-" 
    $TargetArchiveFolder = $Targets[$x].ArchiveTargetFolder 
     
    # Check for and create folder for $TargetName if($ArchiveStorage) 
    if ($ArchiveStorage -ne "") {  
        $ArchiveStorageTarget = $ArchiveStorage+"\"+$TargetName 
        if (!(Test-Path $ArchiveStorageTarget)) {  
            New-Item $ArchiveStorageTarget -type directory  
        } 
    } elseif ($ArchiveStorage -eq "") {  
        # Default to keeping log file archives in the log files source folder 
        $ArchiveStorageTarget = $TargetArchiveFolder 
    } 
     
    # Used for tracking if no files meeting the backup criteria are found 
    $FilesFound = $false 
     
    Write-Log "------------------------------------------------------------------------------------------`n`n" 
 
    # Check to make sure the $TargetArchiveFolder actually exists 
    if (!(Test-Path $TargetArchiveFolder)) {  
        Write-Log "The requested target archive folder of $TargetArchiveFolder does not exist. Please check the requested location and try again.`n`n"  
        $ErrorTrackerEmail = $true 
    } else { 
        # Directory list, minus folders, last write time <= archive date, group files by month or day as defined above 
        dir $TargetArchiveFolder | where {  
            !$_.PSIsContainer -and $_.extension -eq $FileExtension -and $ArchiveGroupingString -f $_.LastWriteTime -le $ArchiveDate  
        } | group {  
            $ArchiveGroupingString -f $_.LastWriteTime  
        } | foreach { 
            $FilesFound = $true 
             
            # Generate the list of files to compress 
            $_.group | foreach {$_.fullname} | out-file $ArchiveList -encoding utf8 
             
            # Create the full path of the archive file to be created 
            $ArchiveFileName = $ArchiveStorageTarget+"\"+$TargetTypeName+$_.name+$ArchiveExtension 
             
            # Archive the list of files 
            if ($CompressionMethod -eq "zip") { 
                $null = & $7z a -tzip -mx8 -y -stl $ArchiveFileName `@$ArchiveList 
            } elseif ($CompressionMethod -eq "ppmd") { 
                $null = & $7z a -t7z -stl $PPMdSwitch $ArchiveFileName `@$ArchiveList 
            }  
            # Check if the operation succeeded 
            if ($LASTEXITCODE -eq 0) { 
                # If it succeeded, double check with 7-Zip's Test feature 
                $null = & $7z t $ArchiveFileName | out-file $ArchiveResults 
                if ($LASTEXITCODE -eq 0) { 
                    # Success, write the contents of the verify command to the email 
                    foreach ($txtLine in Get-Content $ArchiveResults) { 
                        Write-Log "$txtLine `n" 
                    } 
                    Write-Log "`n`n" 
                    if ($TestMode) { 
                        # Show what files would be deleted 
                        $_.group | Remove-Item -WhatIf 
                    } else { 
                        # Delete the original files 
                        $_.group | Remove-Item 
                    } 
                } else { 
                    # The verify of the archive failed 
                    Write-Log "`nThere was an error verifying the 7-Zip  
                        archive $ArchiveFileName`n`n" 
                    $ErrorTrackerEmail = $true 
                } 
            } else { 
                # Creating the archive failed 
                Write-Log "`nThere was an error creating the 7-Zip  
                    archive $ArchiveFileName`n`n" 
                $ErrorTrackerEmail = $true 
            } 
        } 
         
        if (!$FilesFound) { 
            # No files found to parse 
            Write-Log "Info: No files found to archive in $TargetArchiveFolder`n`n" 
            $ErrorTrackerEmail = $true 
        } 
         
        # Test if temp files exist and remove them 
        if (Test-Path $ArchiveList) { Remove-Item $ArchiveList } 
        if (Test-Path $ArchiveResults) { Remove-Item $ArchiveResults } 
    } 
} 
 
# If the option to remove old archives is set to $true in the settings section, do so 
if ($RemoveOldArchives) { 
    # Loop through just like we do to archive files 
    For ($x=0; $x -lt $TargetsCounter; $x++) { 
        # Replace invalid file/folder name characters in the target name with dashes 
        $TargetName = $Targets[$x].ArchiveTargetName -replace "[$InvalidChars]","-" 
        $TargetArchiveFolder = $Targets[$x].ArchiveTargetFolder 
         
        # If a single target folder for archives has been defined... 
        if ($ArchiveStorage) { $ArchiveStorageTarget = $ArchiveStorage+"\"+$TargetName }  
        # If archives are being stored in the logs source folder 
        else { $ArchiveStorageTarget = $TargetArchiveFolder } 
 
        # Grab all files that aren't folders, last write time older than specified above, with a .zip extension         
        dir $ArchiveStorageTarget | where {!$_.PSIsContainer} | where {$_.LastWriteTime -lt $OldArchiveRemovalDate -and $_.extension -eq $ArchiveExtension } | foreach {  
            if ($TestMode) { Remove-Item "$ArchiveStorageTarget\$_" -WhatIf } 
            else { Remove-Item "$ArchiveStorageTarget\$_" } 
            # Because it displayed as text when including it in the $MailMessage below without first putting it in a new variable... 
            $FileLastWriteTime = $_.LastWriteTime 
            # Write the results to an email 
            Write-Log "Old archive file removed`nPath/Name: $ArchiveStorageTarget\$_ `nDate: $FileLastWriteTime `n`n" 
        } 
    } 
} 
 
# Mail out the results 
Send-Email 