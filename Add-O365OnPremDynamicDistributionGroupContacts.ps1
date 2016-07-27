#requires -version 3.0

######################################################################################################
#                                                                                                    #
# Name:        Recreate-DDGs.ps1                                                                     #
#                                                                                                    #
# Version:     1.1                                                                                   #
#                                                                                                    #
# Description: Created cloud-only contact objects in Exchange Online to represent on-premises        #
#              dynamic distribution groups.                                                          #
#                                                                                                    #
# Author:      Joseph Palarchio                                                                      #
#                                                                                                    #
# Usage:       Additional information on the usage of this script can found at the following         #
#              blog post:  http://blogs.perficient.com/microsoft/?p=23559                            #
#                                                                                                    #
# Disclaimer:  This script is provided AS IS without any support. Please test in a lab environment   #
#              prior to production use.                                                              #
#                                                                                                    #
######################################################################################################



$CloudCredential = Get-Credential

Write-Host "Getting Dynamic Distribution Groups..." -foregroundcolor white
Set-AdServerSettings -ViewEntireForest $True
$DDGs = Get-DynamicDistributionGroup
Write-Host "  Dynamic Distribution Groups Found:" ($DDGs).count -foregroundcolor green

# Connect to Exchange Online with "Cloud" prefix
Write-Host "Connecting To Exchange Online..." -foregroundcolor white
$Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://ps.outlook.com/powershell -Credential $CloudCredential -Authentication Basic -AllowRedirection -WarningAction SilentlyContinue
Import-PSSession $Session -Prefix Cloud -DisableNameChecking | Out-Null

# Create Contacts in Exchange Online
foreach ($DDG in $DDGs) {
  Write-Host "  Creating Contact Object For:" $DDG.DisplayName.ToString() -foregroundcolor green
  New-CloudMailContact -ExternalEmailAddress $DDG.PrimarySmtpAddress.ToString() -Name $DDG.Name.ToString() -Alias $DDG.Alias.ToString() -DisplayName $DDG.DisplayName.ToString() | Out-Null
  Set-CloudMailContact $DDG.Name -EmailAddresses @{Add=("X500:"+$DDG.LegacyExchangeDn)} -CustomAttribute1 "On-Premises DDG" -RequireSenderAuthenticationEnabled $true 
}

# Disconnect Exchange Online Session
Write-Host "Disconnecting From Exchange Online..." -foregroundcolor white
Remove-PSSession $Session
