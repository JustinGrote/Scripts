#requires -version 2.0

####################################################################################################
## Version History:
## 
## Version 2.0 Added Join-Object and removed dependency on ConvertFrom-Hashtable
##             Now works on DataTables!
## Version 1.1 Fixed column uniqueness bug http://poshcode.org/1460
## Version 1.0 First post http://poshcode.org/1459

#.Note
#  This script includes a Join-Object function you could use outside
#.Synopsis
#  Performs a inner join on two collections of objects based on a common key column.
#.Description
#  Takes two sets of objects where there are multiple "rows" and where each set has a shared column where the values match, and generates new objects with all the values from each.
#.Parameter GroupOnColumn
#  The name of the property to merge on. Items with the same value in this column will be combined.
#.Parameter FirstCollection
#  The first set of data
#.Parameter FirstJoinColumn
#  The name of the key id column in the first set
#.Parameter SecondCollection
#  The second set of data
#.Parameter SecondJoinColumn
#  The name of the matching key id column in the second set
#  OPTIONAL. Defaults to the same as FirstJoinColum
#.Example
#  Import-CSV data.csv | Pivot-Objects SamAccountName Attribute Value
#
#  Imports csv data containing multiple rows per-record such that a pair of columns named "Attribute" and "Value" are actually different in each row, and contain a name and value pair for attributes you want to add to the output objects.
#
#.Example
# $FirstCollection = @"
#  FirstName,  LastName,   MailingAddress,    EmployeeID
#  John,       Doe,        123 First Ave,     J8329029
#  Susan Q.,   Public,     3025 South Street, K4367143
#"@.Split("`n") | ConvertFrom-Csv                               
#
# $SecondCollection = @"
#  ID,    Week, HrsWorked,   PayRate,  EmployeeID
#  12276, 12,   40,          55,       J8329029
#  12277, 13,   40,          55,       J8329029
#  12278, 14,   42,          55,       J8329029
#  12279, 12,   35,          40,       K4367143
#  12280, 13,   32,          40,       K4367143
#  12281, 14,   48,          40,       K4367143
#"@.Split("`n") | ConvertFrom-Csv                               
#
# Join-Collections $FirstCollection EmployeeID $SecondCollection | ft -auto        
#
#.Notes
#  Author: Joel Bennett

# function Join-Collections {
PARAM(
   $FirstCollection
,  [string]$FirstJoinColumn
,  $SecondCollection
,  [string]$SecondJoinColumn=$FirstJoinColumn
)
PROCESS {
   $ErrorActionPreference = "Inquire"
   foreach($first in $FirstCollection) {
      $SecondCollection | Where{ $_."$SecondJoinColumn" -eq $first."$FirstJoinColumn" } | Join-Object $first
   }
}
BEGIN {
   function Join-Object {
   Param(
      [Parameter(Position=0)]
      $First
   ,
      [Parameter(ValueFromPipeline=$true)]
      $Second
   )
   BEGIN {
      [string[]] $p1 = $First | gm -type Properties | select -expand Name
   }
   Process {
      $Output = $First | Select $p1
      foreach($p in $Second | gm -type Properties | Where { $p1 -notcontains $_.Name } | select -expand Name) {
         Add-Member -in $Output -type NoteProperty -name $p -value $Second."$p"
      }
      $Output
   }
   }
}
#}