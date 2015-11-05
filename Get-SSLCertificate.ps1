[CmdletBinding()]
param(
        [parameter(Mandatory,ValueFromPipeline)][string[]]$ComputerName,
        [int]$TCPPort=443,
        [int]$Timeoutms=3000
)


process { foreach ($computer in $computerName) {
    $port = $TCPPort
    write-verbose "$computer`: Connecting on port $port"
    [Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
    $req = [Net.HttpWebRequest]::Create("https://$computer`:$port/")
    $req.Timeout = $Timeoutms
    try {$req.GetResponse() | Out-Null} catch {write-error "Couldn't connect to $computer on port $port"; continue}
    if (!($req.ServicePoint.Certificate)) {write-error "No Certificate returned on $computer"; continue}
    $certinfo = $req.ServicePoint.Certificate

    $returnobj = [ordered]@{
        ComputerName = $computer;
        Port = $port;
        Subject = $certinfo.Subject;
        Thumbprint = $certinfo.GetCertHashString();
        Issuer = $certinfo.Issuer;
        SerialNumber = $certinfo.GetSerialNumberString();
        Issued = [DateTime]$certinfo.GetEffectiveDateString();
        Expires = [DateTime]$certinfo.GetExpirationDateString();
    }

    new-object PSCustomObject -Property $returnobj
} }