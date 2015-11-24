# .SYNOPSIS
#    Syncs mail-enabled public folder objects from the local Exchange deployment into O365. It uses the local Exchange deployment
#    as master to determine what changes need to be applied to O365. The script will create, update or delete mail-enabled public
#    folder objects on O365 Active Directory when appropriate.
#
# .DESCRIPTION
#    The script must be executed from an Exchange 2007 or 2010 Management Shell window providing access to mail public folders in
#    the local Exchange deployment. Then, using the credentials provided, the script will create a session against Exchange Online,
#    which will be used to manipulate O365 Active Directory objects remotely.
#
#    Copyright (c) 2014 Microsoft Corporation. All rights reserved.
#
#    THIS CODE IS MADE AVAILABLE AS IS, WITHOUT WARRANTY OF ANY KIND. THE ENTIRE RISK
#    OF THE USE OR THE RESULTS FROM THE USE OF THIS CODE REMAINS WITH THE USER.
#
# .PARAMETER Credential
#    Exchange Online user name and password.
#
# .PARAMETER CsvSummaryFile
#    The file path where sync operations and errors will be logged in a CSV format.
#
# .PARAMETER ConnectionUri
#    The Exchange Online remote PowerShell connection uri. If you are an Office 365 operated by 21Vianet customer in China, use "https://partner.outlook.cn/PowerShell".
#
# .PARAMETER Confirm
#    The Confirm switch causes the script to pause processing and requires you to acknowledge what the script will do before processing continues. You don't have to specify
#    a value with the Confirm switch.
#
# .PARAMETER Force
#    Force the script execution and bypass validation warnings.
#
# .PARAMETER WhatIf
#    The WhatIf switch instructs the script to simulate the actions that it would take on the object. By using the WhatIf switch, you can view what changes would occur
#    without having to apply any of those changes. You don't have to specify a value with the WhatIf switch.
#
# .EXAMPLE
#    .\Sync-MailPublicFolders.ps1 -Credential (Get-Credential) -CsvSummaryFile:sync_summary.csv
#    
#    This example shows how to sync mail-public folders from your local deployment to Exchange Online. Note that the script outputs a CSV file listing all operations executed, and possibly errors encountered, during sync.
#
# .EXAMPLE
#    .\Sync-MailPublicFolders.ps1 -Credential (Get-Credential) -CsvSummaryFile:sync_summary.csv -ConnectionUri:"https://partner.outlook.cn/PowerShell"
#    
#    This example shows how to use a different URI to connect to Exchange Online and sync mail-public folders from your local deployment.
#
param(
    [Parameter(Mandatory=$true)]
    [System.Management.Automation.PSCredential] $Credential,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string] $CsvSummaryFile,
    
    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [string] $ConnectionUri = "https://outlook.office365.com/powerShell-liveID",

    [Parameter(Mandatory=$false)]
    [bool] $Confirm = $true,

    [Parameter(Mandatory=$false)]
    [switch] $Force = $false,

    [Parameter(Mandatory=$false)]
    [switch] $WhatIf = $false
)

# Writes a dated information message to console
function WriteInfoMessage()
{
    param ($message)
    Write-Host "[$($(Get-Date).ToString())]" $message;
}

# Writes a dated warning message to console
function WriteWarningMessage()
{
    param ($message)
    Write-Warning ("[{0}] {1}" -f (Get-Date),$message);
}

# Writes a verbose message to console
function WriteVerboseMessage()
{
    param ($message)
    Write-Host "[VERBOSE] $message" -ForegroundColor Green -BackgroundColor Black;
}

# Writes an error importing a mail public folder to the CSV summary
function WriteErrorSummary()
{
    param ($folder, $operation, $errorMessage, $commandtext)

    WriteOperationSummary $folder.Guid $operation $errorMessage $commandtext;
    $script:errorsEncountered++;
}

# Writes the operation executed and its result to the output CSV
function WriteOperationSummary()
{
    param ($folder, $operation, $result, $commandtext)

    $columns = @(
        (Get-Date).ToString(),
        $folder.Guid,
        $operation,
        (EscapeCsvColumn $result),
        (EscapeCsvColumn $commandtext)
    );

    Add-Content $CsvSummaryFile -Value ("{0},{1},{2},{3},{4}" -f $columns);
}

#Escapes a column value based on RFC 4180 (http://tools.ietf.org/html/rfc4180)
function EscapeCsvColumn()
{
    param ([string]$text)

    if ($text -eq $null)
    {
        return $text;
    }

    $hasSpecial = $false;
    for ($i=0; $i -lt $text.Length; $i++)
    {
        $c = $text[$i];
        if ($c -eq $script:csvEscapeChar -or
            $c -eq $script:csvFieldDelimiter -or
            $script:csvSpecialChars -contains $c)
        {
            $hasSpecial = $true;
            break;
        }
    }

    if (-not $hasSpecial)
    {
        return $text;
    }
    
    $ch = $script:csvEscapeChar.ToString([System.Globalization.CultureInfo]::InvariantCulture);
    return $ch + $text.Replace($ch, $ch + $ch) + $ch;
}

# Writes the current progress
function WriteProgress()
{
    param($statusFormat, $statusProcessed, $statusTotal)
    Write-Progress -Activity $LocalizedStrings.ProgressBarActivity `
        -Status ($statusFormat -f $statusProcessed,$statusTotal) `
        -PercentComplete (100 * ($script:itemsProcessed + $statusProcessed)/$script:totalItems);
}

# Create a tenant PSSession against Exchange Online.
function InitializeExchangeOnlineRemoteSession()
{
    WriteInfoMessage $LocalizedStrings.CreatingRemoteSession;

    $oldWarningPreference = $WarningPreference;
    $oldVerbosePreference = $VerbosePreference;

    try
    {
        $VerbosePreference = $WarningPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue;
        $sessionOption = (New-PSSessionOption -SkipCACheck);
        $script:session = New-PSSession -ConnectionURI:$ConnectionUri `
            -ConfigurationName:Microsoft.Exchange `
            -AllowRedirection `
            -Authentication:"Basic" `
            -SessionOption:$sessionOption `
            -Credential:$Credential `
            -ErrorAction:SilentlyContinue;
        
        if ($script:session -eq $null)
        {
            Write-Error ($LocalizedStrings.FailedToCreateRemoteSession -f $error[0].Exception.Message);
            Exit;
        }
        else
        {
            $result = Import-PSSession -Session $script:session `
                -Prefix "EXO" `
                -AllowClobber;

            if (-not $?)
            {
                Write-Error ($LocalizedStrings.FailedToImportRemoteSession -f $error[0].Exception.Message);
                Remove-PSSession $script:session;
                Exit;
            }
        }
    }
    finally
    {
        $WarningPreference = $oldWarningPreference;
        $VerbosePreference = $oldVerbosePreference;
    }

    WriteInfoMessage $LocalizedStrings.RemoteSessionCreatedSuccessfully;
}

# Invokes New-SyncMailPublicFolder to create a new MEPF object on AD
function NewMailEnabledPublicFolder()
{
    param ($localFolder)

    if ($localFolder.PrimarySmtpAddress.ToString() -eq "")
    {
        $errorMsg = ($LocalizedStrings.FailedToCreateMailPublicFolderEmptyPrimarySmtpAddress -f $localFolder.Guid);
        Write-Error $errorMsg;
        WriteErrorSummary $localFolder $LocalizedStrings.CreateOperationName $errorMsg "";
        return;
    }

    # preserve the ability to reply via Outlook's nickname cache post-migration
    $emailAddressesArray = $localFolder.EmailAddresses.ToStringArray() + ("x500:" + $localFolder.LegacyExchangeDN);
           
    $newParams = @{};
    AddNewOrSetCommonParameters $localFolder $emailAddressesArray $newParams;

    [string]$commandText = (FormatCommand $script:NewSyncMailPublicFolderCommand $newParams);

    if ($script:verbose)
    {
        WriteVerboseMessage $commandText;
    }

    try
    {
        $result = &$script:NewSyncMailPublicFolderCommand @newParams;
        WriteOperationSummary $localFolder $LocalizedStrings.CreateOperationName $LocalizedStrings.CsvSuccessResult $commandText;

        if (-not $WhatIf)
        {
            $script:ObjectsCreated++;
        }
    }
    catch
    {
        WriteErrorSummary $localFolder $LocalizedStrings.CreateOperationName $error[0].Exception.Message $commandText;
        Write-Error $_;
    }
}

# Invokes Remove-SyncMailPublicFolder to remove a MEPF from AD
function RemoveMailEnabledPublicFolder()
{
    param ($remoteFolder)    

    $removeParams = @{};
    $removeParams.Add("Identity", $remoteFolder.DistinguishedName);
    $removeParams.Add("Confirm", $false);
    $removeParams.Add("WarningAction", [System.Management.Automation.ActionPreference]::SilentlyContinue);
    $removeParams.Add("ErrorAction", [System.Management.Automation.ActionPreference]::Stop);

    if ($WhatIf)
    {
        $removeParams.Add("WhatIf", $true);
    }
    
    [string]$commandText = (FormatCommand $script:RemoveSyncMailPublicFolderCommand $removeParams);

    if ($script:verbose)
    {
        WriteVerboseMessage $commandText;
    }
    
    try
    {
        &$script:RemoveSyncMailPublicFolderCommand @removeParams;
        WriteOperationSummary $remoteFolder $LocalizedStrings.RemoveOperationName $LocalizedStrings.CsvSuccessResult $commandText;

        if (-not $WhatIf)
        {
            $script:ObjectsDeleted++;
        }
    }
    catch
    {
        WriteErrorSummary $remoteFolder $LocalizedStrings.RemoveOperationName $_.Exception.Message $commandText;
        Write-Error $_;
    }
}

# Invokes Set-MailPublicFolder to update the properties of an existing MEPF
function UpdateMailEnabledPublicFolder()
{
    param ($localFolder, $remoteFolder)

    $localEmailAddresses = $localFolder.EmailAddresses.ToStringArray();
    $localEmailAddresses += ("x500:" + $localFolder.LegacyExchangeDN); # preserve the ability to reply via Outlook's nickname cache post-migration
    $emailAddresses = ConsolidateEmailAddresses $localEmailAddresses $remoteFolder.EmailAddresses $remoteFolder.LegacyExchangeDN;

    $setParams = @{};
    $setParams.Add("Identity", $remoteFolder.DistinguishedName);

    if ($script:mailEnabledSystemFolders.Contains($localFolder.Guid))
    {
        $setParams.Add("IgnoreMissingFolderLink", $true);
    }

    AddNewOrSetCommonParameters $localFolder $emailAddresses $setParams;

    [string]$commandText = (FormatCommand $script:SetMailPublicFolderCommand $setParams);

    if ($script:verbose)
    {
        WriteVerboseMessage $commandText;
    }

    try
    {
        &$script:SetMailPublicFolderCommand @setParams;
        WriteOperationSummary $remoteFolder $LocalizedStrings.UpdateOperationName $LocalizedStrings.CsvSuccessResult $commandText;

        if (-not $WhatIf)
        {
            $script:ObjectsUpdated++;
        }
    }
    catch
    {
        WriteErrorSummary $remoteFolder $LocalizedStrings.UpdateOperationName $_.Exception.Message $commandText;
        Write-Error $_;
    }
}

# Adds the common set of parameters between New and Set cmdlets to the given dictionary
function AddNewOrSetCommonParameters()
{
    param ($localFolder, $emailAddresses, [System.Collections.IDictionary]$parameters)

    $windowsEmailAddress = $localFolder.WindowsEmailAddress.ToString();
    if ($windowsEmailAddress -eq "")
    {
        $windowsEmailAddress = $localFolder.PrimarySmtpAddress.ToString();      
    }

    $parameters.Add("Alias", $localFolder.Alias.Trim());
    $parameters.Add("DisplayName", $localFolder.DisplayName.Trim());
    $parameters.Add("EmailAddresses", $emailAddresses);
    $parameters.Add("ExternalEmailAddress", $localFolder.PrimarySmtpAddress.ToString());
    $parameters.Add("HiddenFromAddressListsEnabled", $localFolder.HiddenFromAddressListsEnabled);
    $parameters.Add("Name", $localFolder.Name.Trim());
    $parameters.Add("OnPremisesObjectId", $localFolder.Guid);
    $parameters.Add("WindowsEmailAddress", $windowsEmailAddress);
    $parameters.Add("ErrorAction", [System.Management.Automation.ActionPreference]::Stop);

    if ($WhatIf)
    {
        $parameters.Add("WhatIf", $true);
    }
}

# Finds out the cloud-only email addresses and merges those with the values current persisted in the on-premises object
function ConsolidateEmailAddresses()
{
    param($localEmailAddresses, $remoteEmailAddresses, $remoteLegDN)

    # Check if the email address in the existing cloud object is present on-premises; if it is not, then the address was either:
    # 1. Deleted on-premises and must be removed from cloud
    # 2. or it is a cloud-authoritative address and should be kept
    $remoteAuthoritative = @();
    foreach ($remoteAddress in $remoteEmailAddresses)
    {
        if ($remoteAddress.StartsWith("SMTP:", [StringComparison]::InvariantCultureIgnoreCase))
        {
            $found = $false;
            $remoteAddressParts = $remoteAddress.Split($script:proxyAddressSeparators); # e.g. SMTP:alias@domain
            if ($remoteAddressParts.Length -ne 3)
            {
                continue; # Invalid SMTP proxy address (it will be removed)
            }

            foreach ($localAddress in $localEmailAddresses)
            {
                # note that the domain part of email addresses is case insensitive while the alias part is case sensitive
                $localAddressParts = $localAddress.Split($script:proxyAddressSeparators);
                if ($localAddressParts.Length -eq 3 -and
                    $remoteAddressParts[0].Equals($localAddressParts[0], [StringComparison]::InvariantCultureIgnoreCase) -and
                    $remoteAddressParts[1].Equals($localAddressParts[1], [StringComparison]::InvariantCulture) -and
                    $remoteAddressParts[2].Equals($localAddressParts[2], [StringComparison]::InvariantCultureIgnoreCase))
                {
                    $found = $true;
                    break;
                }
            }

            if (-not $found)
            {
                foreach ($domain in $script:authoritativeDomains)
                {
                    if ($remoteAddressParts[2] -eq $domain)
                    {
                        $found = $true;
                        break;
                    }
                }

                if (-not $found)
                {
                    # the address on the remote object is from a cloud authoritative domain and should not be removed
                    $remoteAuthoritative += $remoteAddress;
                }
            }
        }
        elseif ($remoteAddress.StartsWith("X500:", [StringComparison]::InvariantCultureIgnoreCase) -and
            $remoteAddress.Substring(5) -eq $remoteLegDN)
        {
            $remoteAuthoritative += $remoteAddress;
        }
    }

    return $localEmailAddresses + $remoteAuthoritative;
}

# Formats the command and its parameters to be printed on console or to file
function FormatCommand()
{
    param ([string]$command, [System.Collections.IDictionary]$parameters)

    $commandText = New-Object System.Text.StringBuilder;
    [void]$commandText.Append($command);
    foreach ($name in $parameters.Keys)
    {
        [void]$commandText.AppendFormat(" -{0}:",$name);

        $value = $parameters[$name];
        if ($value -isnot [Array])
        {
            [void]$commandText.AppendFormat("`"{0}`"", $value);
        }
        elseif ($value.Length -eq 0)
        {
            [void]$commandText.Append("@()");
        }
        else
        {
            [void]$commandText.Append("@(");
            foreach ($subValue in $value)
            {
                [void]$commandText.AppendFormat("`"{0}`",",$subValue);
            }
            
            [void]$commandText.Remove($commandText.Length - 1, 1);
            [void]$commandText.Append(")");
        }
    }

    return $commandText.ToString();
}

################ DECLARING GLOBAL VARIABLES ################
$script:session = $null;
$script:verbose = $VerbosePreference -eq [System.Management.Automation.ActionPreference]::Continue;

$script:csvSpecialChars = @("`r", "`n");
$script:csvEscapeChar = '"';
$script:csvFieldDelimiter = ',';

$script:ObjectsCreated = $script:ObjectsUpdated = $script:ObjectsDeleted = 0;
$script:NewSyncMailPublicFolderCommand = "New-EXOSyncMailPublicFolder";
$script:SetMailPublicFolderCommand = "Set-EXOMailPublicFolder";
$script:RemoveSyncMailPublicFolderCommand = "Remove-EXOSyncMailPublicFolder";
[char[]]$script:proxyAddressSeparators = ':','@';
$script:errorsEncountered = 0;
$script:authoritativeDomains = $null;
$script:mailEnabledSystemFolders = New-Object 'System.Collections.Generic.HashSet[Guid]'; 
$script:WellKnownSystemFolders = @(
    "\NON_IPM_SUBTREE\EFORMS REGISTRY",
    "\NON_IPM_SUBTREE\OFFLINE ADDRESS BOOK",
    "\NON_IPM_SUBTREE\SCHEDULE+ FREE BUSY",
    "\NON_IPM_SUBTREE\schema-root",
    "\NON_IPM_SUBTREE\Events Root");

#load hashtable of localized string
Import-LocalizedData -BindingVariable LocalizedStrings -FileName SyncMailPublicFolders.strings.psd1

################ END OF DECLARATION #################

if (Test-Path $CsvSummaryFile)
{
    Remove-Item $CsvSummaryFile -Confirm:$Confirm -Force;
}

# Write the output CSV headers
$csvFile = New-Item -Path $CsvSummaryFile -ItemType File -Force -ErrorAction:Stop -Value ("#{0},{1},{2},{3},{4}`r`n" -f $LocalizedStrings.TimestampCsvHeader,
    $LocalizedStrings.IdentityCsvHeader,
    $LocalizedStrings.OperationCsvHeader,
    $LocalizedStrings.ResultCsvHeader,
    $LocalizedStrings.CommandCsvHeader);

$localServerVersion = (Get-ExchangeServer $env:COMPUTERNAME -ErrorAction:Stop).AdminDisplayVersion;
if ($localServerVersion.Major -ne 8 -and $localServerVersion.Major -ne 14)
{
    Write-Error ($LocalizedStrings.LocalServerVersionNotSupported -f $localServerVersion) -ErrorAction:Continue;
    Exit;
}

try
{
    InitializeExchangeOnlineRemoteSession;

    WriteInfoMessage $LocalizedStrings.LocalMailPublicFolderEnumerationStart;

    # During finalization, Public Folders deployment is locked for migration, which means the script cannot invoke
    # Get-PublicFolder as that operation would fail. In that case, the script cannot determine which mail public folder
    # objects are linked to system folders under the NON_IPM_SUBTREE.
    $lockedForMigration = (Get-OrganizationConfig).PublicFoldersLockedForMigration;
    $allSystemFoldersInAD = @();
    if (-not $lockedForMigration)
    {
        # See https://technet.microsoft.com/en-us/library/bb397221(v=exchg.141).aspx#Trees
        # Certain WellKnownFolders in pre-E15 are created with prefix such as OWAScratchPad, StoreEvents.
        # For instance, StoreEvents folders have the following pattern: "\NON_IPM_SUBTREE\StoreEvents{46F83CF7-2A81-42AC-A0C6-68C7AA49FF18}\internal1"
        $storeEventAndOwaScratchPadFolders = @(Get-PublicFolder \NON_IPM_SUBTREE -GetChildren -ResultSize:Unlimited | ?{$_.Name -like "StoreEvents*" -or $_.Name -like "OWAScratchPad*"});
        $allSystemFolderParents = $storeEventAndOwaScratchPadFolders + @($script:WellKnownSystemFolders | Get-PublicFolder -ErrorAction:SilentlyContinue);
        $allSystemFoldersInAD = @($allSystemFolderParents | Get-PublicFolder -Recurse -ResultSize:Unlimited | Get-MailPublicFolder -ErrorAction:SilentlyContinue);

        foreach ($systemFolder in $allSystemFoldersInAD)
        {
            [void]$script:mailEnabledSystemFolders.Add($systemFolder.Guid);
        }
    }
    else
    {
        WriteWarningMessage $LocalizedStrings.UnableToDetectSystemMailPublicFolders;
    }

    if ($script:verbose)
    {
        WriteVerboseMessage ($LocalizedStrings.SystemFoldersSkipped -f $script:mailEnabledSystemFolders.Count);
        $allSystemFoldersInAD | Sort Alias | ft -a | Out-String | Write-Host -ForegroundColor Green -BackgroundColor Black;
    }

    $localFolders = @(Get-MailPublicFolder -ResultSize:Unlimited -IgnoreDefaultScope | Sort Guid);
    WriteInfoMessage ($LocalizedStrings.LocalMailPublicFolderEnumerationCompleted -f $localFolders.Length);

    if ($localFolders.Length -eq 0 -and $Force -eq $false)
    {
        WriteWarningMessage $LocalizedStrings.ForceParameterRequired;
        Exit;
    }

    WriteInfoMessage $LocalizedStrings.RemoteMailPublicFolderEnumerationStart;
    $remoteFolders = @(Get-EXOMailPublicFolder -ResultSize:Unlimited | Sort OnPremisesObjectId);
    WriteInfoMessage ($LocalizedStrings.RemoteMailPublicFolderEnumerationCompleted -f $remoteFolders.Length);

    $missingOnPremisesGuid = @();
    $pendingRemoves = @();
    $pendingUpdates = @{};
    $pendingAdds = @{};

    $localIndex = 0;
    $remoteIndex = 0;
    while ($localIndex -lt $localFolders.Length -and $remoteIndex -lt $remoteFolders.Length)
    {
        $local = $localFolders[$localIndex];
        $remote = $remoteFolders[$remoteIndex];

        if ($remote.OnPremisesObjectId -eq "")
        {
            # This folder must be processed based on PrimarySmtpAddress
            $missingOnPremisesGuid += $remote;
            $remoteIndex++;
        }
        elseif ($local.Guid.ToString() -eq $remote.OnPremisesObjectId)
        {
            $pendingUpdates.Add($local.Guid, (New-Object PSObject -Property @{ Local=$local; Remote=$remote }));
            $localIndex++;
            $remoteIndex++;
        }
        elseif ($local.Guid.ToString() -lt $remote.OnPremisesObjectId)
        {
            if (-not $script:mailEnabledSystemFolders.Contains($local.Guid))
            {
                $pendingAdds.Add($local.Guid, $local);
            }

            $localIndex++;
        }
        else
        {
            $pendingRemoves += $remote;
            $remoteIndex++;
        }
    }

    # Remaining folders on $localFolders collection must be added to Exchange Online
    while ($localIndex -lt $localFolders.Length)
    {
        $local = $localFolders[$localIndex];

        if (-not $script:mailEnabledSystemFolders.Contains($local.Guid))
        {
            $pendingAdds.Add($local.Guid, $local);
        }

        $localIndex++;
    }

    # Remaining folders on $remoteFolders collection must be removed from Exchange Online
    while ($remoteIndex -lt $remoteFolders.Length)
    {
        $remote = $remoteFolders[$remoteIndex];
        if ($remote.OnPremisesObjectId  -eq "")
        {
            # This folder must be processed based on PrimarySmtpAddress
            $missingOnPremisesGuid += $remote;
        }
        else
        {
            $pendingRemoves += $remote;
        }
        
        $remoteIndex++;
    }

    if ($missingOnPremisesGuid.Length -gt 0)
    {
        # Process remote objects missing the OnPremisesObjectId using the PrimarySmtpAddress as a key instead.
        $missingOnPremisesGuid = @($missingOnPremisesGuid | Sort PrimarySmtpAddress);
        $localFolders = @($localFolders | Sort PrimarySmtpAddress);

        $localIndex = 0;
        $remoteIndex = 0;
        while ($localIndex -lt $localFolders.Length -and $remoteIndex -lt $missingOnPremisesGuid.Length)
        {
            $local = $localFolders[$localIndex];
            $remote = $missingOnPremisesGuid[$remoteIndex];

            if ($local.PrimarySmtpAddress.ToString() -eq $remote.PrimarySmtpAddress.ToString())
            {
                # Make sure the PrimarySmtpAddress has no duplicate on-premises; otherwise, skip updating all objects with duplicate address
                $j = $localIndex + 1;
                while ($j -lt $localFolders.Length)
                {
                    $next = $localFolders[$j];
                    if ($local.PrimarySmtpAddress.ToString() -ne $next.PrimarySmtpAddress.ToString())
                    {
                        break;
                    }

                    WriteErrorSummary $next $LocalizedStrings.UpdateOperationName ($LocalizedStrings.PrimarySmtpAddressUsedByAnotherFolder -f $local.PrimarySmtpAddress,$local.Guid) "";

                    # If there were a previous match based on OnPremisesObjectId, remove the folder operation from add and update collections
                    $pendingAdds.Remove($next.Guid);
                    $pendingUpdates.Remove($next.Guid);
                    $j++;
                }

                $duplicatesFound = $j - $localIndex - 1;
                if ($duplicatesFound -gt 0)
                {
                    # If there were a previous match based on OnPremisesObjectId, remove the folder operation from add and update collections
                    $pendingAdds.Remove($local.Guid);
                    $pendingUpdates.Remove($local.Guid);
                    $localIndex += $duplicatesFound + 1;

                    WriteErrorSummary $local $LocalizedStrings.UpdateOperationName ($LocalizedStrings.PrimarySmtpAddressUsedByOtherFolders -f $local.PrimarySmtpAddress,$duplicatesFound) "";
                    WriteWarningMessage ($LocalizedStrings.SkippingFoldersWithDuplicateAddress -f ($duplicatesFound + 1),$local.PrimarySmtpAddress);
                }
                elseif ($pendingUpdates.Contains($local.Guid))
                {
                    # If we get here, it means two different remote objects match the same local object (one by OnPremisesObjectId and another by PrimarySmtpAddress).
                    # Since that is an ambiguous resolution, let's skip updating the remote objects.
                    $ambiguousRemoteObj = $pendingUpdates[$local.Guid].Remote;
                    $pendingUpdates.Remove($local.Guid);

                    $errorMessage = ($LocalizedStrings.AmbiguousLocalMailPublicFolderResolution -f $local.Guid,$ambiguousRemoteObj.Guid,$remote.Guid);
                    WriteErrorSummary $local $LocalizedStrings.UpdateOperationName $errorMessage "";
                    WriteWarningMessage $errorMessage;
                }
                else
                {
                    # Since there was no match originally using OnPremisesObjectId, the local object was treated as an add to Exchange Online.
                    # In this way, since we now found a remote object (by PrimarySmtpAddress) to update, we must first remove the local object from the add list.
                    $pendingAdds.Remove($local.Guid);
                    $pendingUpdates.Add($local.Guid, (New-Object PSObject -Property @{ Local=$local; Remote=$remote }));
                }

                $localIndex++;
                $remoteIndex++;
            }
            elseif ($local.PrimarySmtpAddress.ToString() -gt $remote.PrimarySmtpAddress.ToString())
            {
                # There are no local objects using the remote object's PrimarySmtpAddress
                $pendingRemoves += $remote;
                $remoteIndex++;
            }
            else
            {
                $localIndex++;
            }
        }

        # All objects remaining on the $missingOnPremisesGuid list no longer exist on-premises
        while ($remoteIndex -lt $missingOnPremisesGuid.Length)
        {
            $pendingRemoves += $missingOnPremisesGuid[$remoteIndex];
            $remoteIndex++;
        }
    }

    $script:totalItems = $pendingRemoves.Length + $pendingUpdates.Count + $pendingAdds.Count;

    # At this point, we know all changes that need to be synced to Exchange Online. Let's prompt the admin for confirmation before proceeding.
    if ($Confirm -eq $true -and $script:totalItems -gt 0)
    {
        $title = $LocalizedStrings.ConfirmationTitle;
        $message = ($LocalizedStrings.ConfirmationQuestion -f $pendingAdds.Count,$pendingUpdates.Count,$pendingRemoves.Length);
        $yes = New-Object System.Management.Automation.Host.ChoiceDescription $LocalizedStrings.ConfirmationYesOption, `
            $LocalizedStrings.ConfirmationYesOptionHelp;

        $no = New-Object System.Management.Automation.Host.ChoiceDescription $LocalizedStrings.ConfirmationNoOption, `
            $LocalizedStrings.ConfirmationNoOptionHelp;

        [System.Management.Automation.Host.ChoiceDescription[]]$options = $no,$yes;
        $confirmation = $host.ui.PromptForChoice($title, $message, $options, 0);
        if ($confirmation -eq 0)
        {
            Exit;
        }
    }

    # Find out the authoritative AcceptedDomains on-premises so that we don't accidently remove cloud-only email addresses during updates
    $script:authoritativeDomains = @(Get-AcceptedDomain | ?{$_.DomainType -eq "Authoritative" } | foreach {$_.DomainName.ToString()});
    
    # Finally, let's perfom the actual operations against Exchange Online
    $script:itemsProcessed = 0;
    for ($i = 0; $i -lt $pendingRemoves.Length; $i++)
    {
        WriteProgress $LocalizedStrings.ProgressBarStatusRemoving $i $pendingRemoves.Length;
        RemoveMailEnabledPublicFolder $pendingRemoves[$i];
    }

    $script:itemsProcessed += $pendingRemoves.Length;
    $updatesProcessed = 0;
    foreach ($folderPair in $pendingUpdates.Values)
    {
        WriteProgress $LocalizedStrings.ProgressBarStatusUpdating $updatesProcessed $pendingUpdates.Count;
        UpdateMailEnabledPublicFolder $folderPair.Local $folderPair.Remote;
        $updatesProcessed++;
    }

    $script:itemsProcessed += $pendingUpdates.Count;
    $addsProcessed = 0;
    foreach ($localFolder in $pendingAdds.Values)
    {
        WriteProgress $LocalizedStrings.ProgressBarStatusCreating $addsProcessed $pendingAdds.Count;
        NewMailEnabledPublicFolder $localFolder;
        $addsProcessed++;
    }

    Write-Progress -Activity $LocalizedStrings.ProgressBarActivity -Status ($LocalizedStrings.ProgressBarStatusCreating -f $pendingAdds.Count,$pendingAdds.Count) -Completed;
    WriteInfoMessage ($LocalizedStrings.SyncMailPublicFolderObjectsComplete -f $script:ObjectsCreated,$script:ObjectsUpdated,$script:ObjectsDeleted);

    if ($script:errorsEncountered -gt 0)
    {
        WriteWarningMessage ($LocalizedStrings.ErrorsFoundDuringImport -f $script:errorsEncountered,(Get-Item $CsvSummaryFile).FullName);
    }
}
finally
{
    if ($script:session -ne $null)
    {
        Remove-PSSession $script:session;
    }
}
# SIG # Begin signature block
# MIIaxQYJKoZIhvcNAQcCoIIatjCCGrICAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU+L5l1ABvT5AoaVG3yGTLa5/i
# g1+gghV6MIIEuzCCA6OgAwIBAgITMwAAAFrtL/TkIJk/OgAAAAAAWjANBgkqhkiG
# 9w0BAQUFADB3MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSEw
# HwYDVQQDExhNaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EwHhcNMTQwNTIzMTcxMzE1
# WhcNMTUwODIzMTcxMzE1WjCBqzELMAkGA1UEBhMCVVMxCzAJBgNVBAgTAldBMRAw
# DgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# DTALBgNVBAsTBE1PUFIxJzAlBgNVBAsTHm5DaXBoZXIgRFNFIEVTTjpCOEVDLTMw
# QTQtNzE0NDElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZTCC
# ASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALMhIt9q0L/7KcnVbHqJqY0T
# vJS16X0pZdp/9B+rDHlhZlRhlgfw1GBLMZsJr30obdCle4dfdqHSxinHljqjXxeM
# duC3lgcPx2JhtLaq9kYUKQMuJrAdSgjgfdNcMBKmm/a5Dj1TFmmdu2UnQsHoMjUO
# 9yn/3lsgTLsvaIQkD6uRxPPOKl5YRu2pRbRptlQmkRJi/W8O5M/53D/aKWkfSq7u
# wIJC64Jz6VFTEb/dqx1vsgpQeAuD7xsIsxtnb9MFfaEJn8J3iKCjWMFP/2fz3uzH
# 9TPcikUOlkYUKIccYLf1qlpATHC1acBGyNTo4sWQ3gtlNdRUgNLpnSBWr9TfzbkC
# AwEAAaOCAQkwggEFMB0GA1UdDgQWBBS+Z+AuAhuvCnINOh1/jJ1rImYR9zAfBgNV
# HSMEGDAWgBQjNPjZUkZwCu1A+3b7syuwwzWzDzBUBgNVHR8ETTBLMEmgR6BFhkNo
# dHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNyb3Nv
# ZnRUaW1lU3RhbXBQQ0EuY3JsMFgGCCsGAQUFBwEBBEwwSjBIBggrBgEFBQcwAoY8
# aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNyb3NvZnRUaW1l
# U3RhbXBQQ0EuY3J0MBMGA1UdJQQMMAoGCCsGAQUFBwMIMA0GCSqGSIb3DQEBBQUA
# A4IBAQAgU4KQrqZNTn4zScizrcTDfhXQEvIPJ4p/W78+VOpB6VQDKym63VSIu7n3
# 2c5T7RAWPclGcLQA0fI0XaejIiyqIuFrob8PDYfQHgIb73i2iSDQLKsLdDguphD/
# 2pGrLEA8JhWqrN7Cz0qTA81r4qSymRpdR0Tx3IIf5ki0pmmZwS7phyPqCNJp5mLf
# cfHrI78hZfmkV8STLdsWeBWqPqLkhfwXvsBPFduq8Ki6ESus+is1Fm5bc/4w0Pur
# k6DezULaNj+R9+A3jNkHrTsnu/9UIHfG/RHpGuZpsjMnqwWuWI+mqX9dEhFoDCyj
# MRYNviGrnPCuGnxA1daDFhXYKPvlMIIE7DCCA9SgAwIBAgITMwAAAMps1TISNcTh
# VQABAAAAyjANBgkqhkiG9w0BAQUFADB5MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSMwIQYDVQQDExpNaWNyb3NvZnQgQ29kZSBTaWduaW5nIFBD
# QTAeFw0xNDA0MjIxNzM5MDBaFw0xNTA3MjIxNzM5MDBaMIGDMQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMQ0wCwYDVQQLEwRNT1BSMR4wHAYDVQQD
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAw
# ggEKAoIBAQCWcV3tBkb6hMudW7dGx7DhtBE5A62xFXNgnOuntm4aPD//ZeM08aal
# IV5WmWxY5JKhClzC09xSLwxlmiBhQFMxnGyPIX26+f4TUFJglTpbuVildGFBqZTg
# rSZOTKGXcEknXnxnyk8ecYRGvB1LtuIPxcYnyQfmegqlFwAZTHBFOC2BtFCqxWfR
# +nm8xcyhcpv0JTSY+FTfEjk4Ei+ka6Wafsdi0dzP7T00+LnfNTC67HkyqeGprFVN
# TH9MVsMTC3bxB/nMR6z7iNVSpR4o+j0tz8+EmIZxZRHPhckJRIbhb+ex/KxARKWp
# iyM/gkmd1ZZZUBNZGHP/QwytK9R/MEBnAgMBAAGjggFgMIIBXDATBgNVHSUEDDAK
# BggrBgEFBQcDAzAdBgNVHQ4EFgQUH17iXVCNVoa+SjzPBOinh7XLv4MwUQYDVR0R
# BEowSKRGMEQxDTALBgNVBAsTBE1PUFIxMzAxBgNVBAUTKjMxNTk1K2I0MjE4ZjEz
# LTZmY2EtNDkwZi05YzQ3LTNmYzU1N2RmYzQ0MDAfBgNVHSMEGDAWgBTLEejK0rQW
# WAHJNy4zFha5TJoKHzBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1pY3Jv
# c29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNDb2RTaWdQQ0FfMDgtMzEtMjAx
# MC5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY0NvZFNpZ1BDQV8wOC0zMS0yMDEwLmNy
# dDANBgkqhkiG9w0BAQUFAAOCAQEAd1zr15E9zb17g9mFqbBDnXN8F8kP7Tbbx7Us
# G177VAU6g3FAgQmit3EmXtZ9tmw7yapfXQMYKh0nfgfpxWUftc8Nt1THKDhaiOd7
# wRm2VjK64szLk9uvbg9dRPXUsO8b1U7Brw7vIJvy4f4nXejF/2H2GdIoCiKd381w
# gp4YctgjzHosQ+7/6sDg5h2qnpczAFJvB7jTiGzepAY1p8JThmURdwmPNVm52Iao
# AP74MX0s9IwFncDB1XdybOlNWSaD8cKyiFeTNQB8UCu8Wfz+HCk4gtPeUpdFKRhO
# lludul8bo/EnUOoHlehtNA04V9w3KDWVOjic1O1qhV0OIhFeezCCBbwwggOkoAMC
# AQICCmEzJhoAAAAAADEwDQYJKoZIhvcNAQEFBQAwXzETMBEGCgmSJomT8ixkARkW
# A2NvbTEZMBcGCgmSJomT8ixkARkWCW1pY3Jvc29mdDEtMCsGA1UEAxMkTWljcm9z
# b2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5MB4XDTEwMDgzMTIyMTkzMloX
# DTIwMDgzMTIyMjkzMloweTELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEjMCEGA1UEAxMaTWljcm9zb2Z0IENvZGUgU2lnbmluZyBQQ0EwggEiMA0G
# CSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCycllcGTBkvx2aYCAgQpl2U2w+G9Zv
# zMvx6mv+lxYQ4N86dIMaty+gMuz/3sJCTiPVcgDbNVcKicquIEn08GisTUuNpb15
# S3GbRwfa/SXfnXWIz6pzRH/XgdvzvfI2pMlcRdyvrT3gKGiXGqelcnNW8ReU5P01
# lHKg1nZfHndFg4U4FtBzWwW6Z1KNpbJpL9oZC/6SdCnidi9U3RQwWfjSjWL9y8lf
# RjFQuScT5EAwz3IpECgixzdOPaAyPZDNoTgGhVxOVoIoKgUyt0vXT2Pn0i1i8UU9
# 56wIAPZGoZ7RW4wmU+h6qkryRs83PDietHdcpReejcsRj1Y8wawJXwPTAgMBAAGj
# ggFeMIIBWjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBTLEejK0rQWWAHJNy4z
# Fha5TJoKHzALBgNVHQ8EBAMCAYYwEgYJKwYBBAGCNxUBBAUCAwEAATAjBgkrBgEE
# AYI3FQIEFgQU/dExTtMmipXhmGA7qDFvpjy82C0wGQYJKwYBBAGCNxQCBAweCgBT
# AHUAYgBDAEEwHwYDVR0jBBgwFoAUDqyCYEBWJ5flJRP8KuEKU5VZ5KQwUAYDVR0f
# BEkwRzBFoEOgQYY/aHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJv
# ZHVjdHMvbWljcm9zb2Z0cm9vdGNlcnQuY3JsMFQGCCsGAQUFBwEBBEgwRjBEBggr
# BgEFBQcwAoY4aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNy
# b3NvZnRSb290Q2VydC5jcnQwDQYJKoZIhvcNAQEFBQADggIBAFk5Pn8mRq/rb0Cx
# MrVq6w4vbqhJ9+tfde1MOy3XQ60L/svpLTGjI8x8UJiAIV2sPS9MuqKoVpzjcLu4
# tPh5tUly9z7qQX/K4QwXaculnCAt+gtQxFbNLeNK0rxw56gNogOlVuC4iktX8pVC
# nPHz7+7jhh80PLhWmvBTI4UqpIIck+KUBx3y4k74jKHK6BOlkU7IG9KPcpUqcW2b
# Gvgc8FPWZ8wi/1wdzaKMvSeyeWNWRKJRzfnpo1hW3ZsCRUQvX/TartSCMm78pJUT
# 5Otp56miLL7IKxAOZY6Z2/Wi+hImCWU4lPF6H0q70eFW6NB4lhhcyTUWX92THUmO
# Lb6tNEQc7hAVGgBd3TVbIc6YxwnuhQ6MT20OE049fClInHLR82zKwexwo1eSV32U
# jaAbSANa98+jZwp0pTbtLS8XyOZyNxL0b7E8Z4L5UrKNMxZlHg6K3RDeZPRvzkbU
# 0xfpecQEtNP7LN8fip6sCvsTJ0Ct5PnhqX9GuwdgR2VgQE6wQuxO7bN2edgKNAlt
# HIAxH+IOVN3lofvlRxCtZJj/UBYufL8FIXrilUEnacOTj5XJjdibIa4NXJzwoq6G
# aIMMai27dmsAHZat8hZ79haDJLmIz2qoRzEvmtzjcT3XAH5iR9HOiMm4GPoOco3B
# oz2vAkBq/2mbluIQqBC0N1AI1sM9MIIGBzCCA++gAwIBAgIKYRZoNAAAAAAAHDAN
# BgkqhkiG9w0BAQUFADBfMRMwEQYKCZImiZPyLGQBGRYDY29tMRkwFwYKCZImiZPy
# LGQBGRYJbWljcm9zb2Z0MS0wKwYDVQQDEyRNaWNyb3NvZnQgUm9vdCBDZXJ0aWZp
# Y2F0ZSBBdXRob3JpdHkwHhcNMDcwNDAzMTI1MzA5WhcNMjEwNDAzMTMwMzA5WjB3
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSEwHwYDVQQDExhN
# aWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAw
# ggEKAoIBAQCfoWyx39tIkip8ay4Z4b3i48WZUSNQrc7dGE4kD+7Rp9FMrXQwIBHr
# B9VUlRVJlBtCkq6YXDAm2gBr6Hu97IkHD/cOBJjwicwfyzMkh53y9GccLPx754gd
# 6udOo6HBI1PKjfpFzwnQXq/QsEIEovmmbJNn1yjcRlOwhtDlKEYuJ6yGT1VSDOQD
# LPtqkJAwbofzWTCd+n7Wl7PoIZd++NIT8wi3U21StEWQn0gASkdmEScpZqiX5NMG
# gUqi+YSnEUcUCYKfhO1VeP4Bmh1QCIUAEDBG7bfeI0a7xC1Un68eeEExd8yb3zuD
# k6FhArUdDbH895uyAc4iS1T/+QXDwiALAgMBAAGjggGrMIIBpzAPBgNVHRMBAf8E
# BTADAQH/MB0GA1UdDgQWBBQjNPjZUkZwCu1A+3b7syuwwzWzDzALBgNVHQ8EBAMC
# AYYwEAYJKwYBBAGCNxUBBAMCAQAwgZgGA1UdIwSBkDCBjYAUDqyCYEBWJ5flJRP8
# KuEKU5VZ5KShY6RhMF8xEzARBgoJkiaJk/IsZAEZFgNjb20xGTAXBgoJkiaJk/Is
# ZAEZFgltaWNyb3NvZnQxLTArBgNVBAMTJE1pY3Jvc29mdCBSb290IENlcnRpZmlj
# YXRlIEF1dGhvcml0eYIQea0WoUqgpa1Mc1j0BxMuZTBQBgNVHR8ESTBHMEWgQ6BB
# hj9odHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9taWNy
# b3NvZnRyb290Y2VydC5jcmwwVAYIKwYBBQUHAQEESDBGMEQGCCsGAQUFBzAChjho
# dHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY3Jvc29mdFJvb3RD
# ZXJ0LmNydDATBgNVHSUEDDAKBggrBgEFBQcDCDANBgkqhkiG9w0BAQUFAAOCAgEA
# EJeKw1wDRDbd6bStd9vOeVFNAbEudHFbbQwTq86+e4+4LtQSooxtYrhXAstOIBNQ
# md16QOJXu69YmhzhHQGGrLt48ovQ7DsB7uK+jwoFyI1I4vBTFd1Pq5Lk541q1YDB
# 5pTyBi+FA+mRKiQicPv2/OR4mS4N9wficLwYTp2OawpylbihOZxnLcVRDupiXD8W
# mIsgP+IHGjL5zDFKdjE9K3ILyOpwPf+FChPfwgphjvDXuBfrTot/xTUrXqO/67x9
# C0J71FNyIe4wyrt4ZVxbARcKFA7S2hSY9Ty5ZlizLS/n+YWGzFFW6J1wlGysOUzU
# 9nm/qhh6YinvopspNAZ3GmLJPR5tH4LwC8csu89Ds+X57H2146SodDW4TsVxIxIm
# dgs8UoxxWkZDFLyzs7BNZ8ifQv+AeSGAnhUwZuhCEl4ayJ4iIdBD6Svpu/RIzCzU
# 2DKATCYqSCRfWupW76bemZ3KOm+9gSd0BhHudiG/m4LBJ1S2sWo9iaF2YbRuoROm
# v6pH8BJv/YoybLL+31HIjCPJZr2dHYcSZAI9La9Zj7jkIeW1sMpjtHhUBdRBLlCs
# lLCleKuzoJZ1GtmShxN1Ii8yqAhuoFuMJb+g74TKIdbrHk/Jmu5J4PcBZW+JC33I
# acjmbuqnl84xKf8OxVtc2E0bodj6L54/LlUWa8kTo/0xggS1MIIEsQIBATCBkDB5
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSMwIQYDVQQDExpN
# aWNyb3NvZnQgQ29kZSBTaWduaW5nIFBDQQITMwAAAMps1TISNcThVQABAAAAyjAJ
# BgUrDgMCGgUAoIHOMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEEMBwGCisGAQQB
# gjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEWBBRoNMv99q0xuNCR
# iwcsUga9yI0h+TBuBgorBgEEAYI3AgEMMWAwXqA2gDQAUwB5AG4AYwAtAE0AYQBp
# AGwAUAB1AGIAbABpAGMARgBvAGwAZABlAHIAcwAuAHAAcwAxoSSAImh0dHA6Ly93
# d3cubWljcm9zb2Z0LmNvbS9leGNoYW5nZSAwDQYJKoZIhvcNAQEBBQAEggEADlHx
# x+MdGWnieGZMe/LNhkYLsNJpK5iDjqdHVjbhgGDaGxgeGodj/WTSlo4zXxq4dpjF
# i0Zl6gCZQ5PVBU1Vqhuiv8XZ55bpy6iX4atv9TokAMjxT18By1IRDGD6GbpKsc+2
# LjbxZjwUDXvkDQEMeWwmd1G1cJVV/3+Q7RpfWERa0vZNxIlbWhEVufCi1I0sxLES
# JK6nm0KbVquw9Mwvsr5NLK9pplaj7Mb51noVouN5TCMxzmIEsEv9QCLUT+3N1k3r
# ngOXhk+wf6FyZvq2+HknOqu+JVjHuQALTD+Orha4tKxr1H6oHJfslKDvL8h/bHHY
# Ty63wlMAmgAPASMTLaGCAigwggIkBgkqhkiG9w0BCQYxggIVMIICEQIBATCBjjB3
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSEwHwYDVQQDExhN
# aWNyb3NvZnQgVGltZS1TdGFtcCBQQ0ECEzMAAABa7S/05CCZPzoAAAAAAFowCQYF
# Kw4DAhoFAKBdMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkF
# MQ8XDTE1MDMxNzE3NTAzN1owIwYJKoZIhvcNAQkEMRYEFE9Xq+LsT9Czh0lMFNM9
# 9FvD16sHMA0GCSqGSIb3DQEBBQUABIIBAJDrTRRoYmuppm8N/LGSbANa8F0PdpE8
# WCRdgQMr87p1b5NRUn8ofg7nRBCgRGQ/+A/3sKJCyOXS2JpGSQB3yZKjIn8JXa2i
# v9Uib6B406shiBU4wcyMML6OobS1P9KI9nRdjV7q5qmqkZb0Z383ynJ7mQhIZ/bS
# C0yezpcim8kv1ioF4PpI9k+z5nckQGffq57ZISgIqk4gz7+QxyRMc4EfQMOqm9rt
# aJZPnppXXkeU0aQ2EY8wuHv9umPk/78hQHWampGQagdQpyjcYeKytFC10vg1koK0
# RsTQlCb3vsjdqey9bUR5jKAF70evhVRr2dP1ifYMI5grfd0XX2R31EU=
# SIG # End signature block
