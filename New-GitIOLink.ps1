#Generates a shorthand Git.IO Link from a GitHub link

[CmdletBinding()]
param (
    #The URI you wish to make a Git.IO link
    [Parameter(Mandatory)][String]$URI,
    #An optional vanity name for the new URL that will come after the http://git.io/ part
    [String]$Name
)

$GitIOURI = "https://git.io"

$result =  invoke-webrequest -method POST "$GitIOURI" -body @{url="$URI";code="$Name"}
$result.headers.location