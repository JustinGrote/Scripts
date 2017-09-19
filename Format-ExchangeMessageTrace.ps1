<#
.SYNOPSIS
Takes an Exchange Extended Message Trace and parses it into usable powershell objects
#>
[CmdletBinding()]
param (
    #Path to the extended message trace CSV
    [Parameter(Mandatory)][String[]]$CSVPath
)

process {
    foreach ($CSVPathItem in $CSVPath) {
        $emt = import-csv $CSVPathItem -ErrorAction Stop
        foreach ($emtItem in $emt) {
            #Convert the report line item into a hashtable to add more properties
            $emtProps = $emtItem.psobject.properties |
                foreach -begin {$h=[ordered]@{}} -process {$h."$($_.Name)" = $_.Value} -end {$h}

            #Blank out Extended Properties. Makes sure all objects have these properties for sort/filter purposes
            $emtProps.SpamFilterReport = $null

            $emtCustomData = $emtItem.custom_data -split ';'
            foreach ($emtCustomDataItem in $emtCustomData) {
                $ResultProps = [ordered]@{}
                if ($emtCustomDataItem -match '^S:([A-Z]{3,4})=(.*)') {
                    $ResultProps.Agent = $matches[1]
                    $emtCustomDataItem = $matches[2]
                }

                #Parser for the Spam Filter Agent
                if ($ResultProps.Agent -match 'SFA') {
                    $ResultProps.Agent = "SpamFilter"
                    $SFAData = $emtCustomDataItem.split("|")

                    #Spam Engine (SUM) means multiple
                    $ResultProps.Engine = $SFAData[0]

                    #Ascribe all individual properties
                    $SFAData |
                        where {$PSItem -notmatch '^(SUM|SFS|LAT)'} |
                        foreach {
                            $SFADataItem = $PSItem -split '='
                            if ($SFADataItem.count -eq 0) {
                                write-error "SFA No Value Found"
                                return;
                            }
                            if ($SFADataItem.count -ne 2) {
                                $SFAValue = $null
                            } else {
                                $SFAValue = $SFADataItem[1]
                            }
                            $ResultProps.($SFADataItem[0]) = $SFAValue
                        }

                    #Convert the matched Spam Rules to an arrayed property
                    $ResultProps.SFS = @()
                    $SFAData |
                        where {$PSItem -match 'SFS'} |
                        foreach {
                            $ResultProps.SFS += ($PSItem -split '=')[1]
                        }

                    #Convert the matched LAT to an arrayed property
                    $ResultProps.LAT = @()
                    $SFAData |
                        where {$PSItem -match 'LAT'} |
                        foreach {
                            $ResultProps.LAT += ($PSItem -split '=')[1]
                        }
                    #Construct the final result and output it
                    $emtProps.SpamFilterReport = [PSCustomObject]$ResultProps
                }
            }
            [PSCustomObject]$emtProps
        }
    }
}
