[CmdletBinding()]

param([parameter(Mandatory=$true,ValueFromPipeline=$true)][string[]]$HostName,[int]$port=443)


process { foreach ($computername in $HostName) {
    #Create a TCP Socket to the computer and a port number
    write-verbose "Connecting to $computername on $port"
    $tcpsocket = New-Object Net.Sockets.TcpClient($computerName, $port)

    #test if the socket got connected
    if(!$tcpsocket)
    {
        Write-Error "Error Opening Connection: $port on $computername Unreachable"
        exit 1
    }
    else
    {
        #Socket Got connected get the tcp stream ready to read the certificate
        write-verbose "Successfully Connected to $computername on $port" 
        $tcpstream = $tcpsocket.GetStream()
        Write-verbose "Reading SSL Certificate...." 
        #Create an SSL Connection 
        $sslStream = New-Object System.Net.Security.SslStream($tcpstream,$false)
        #Force the SSL Connection to send us the certificate
        $sslStream.AuthenticateAsClient($computerName)

        #Read the certificate
        $certinfo = New-Object system.security.cryptography.x509certificates.x509certificate2($sslStream.RemoteCertificate)
    }

    $returnobj = [ordered]@{
        ComputerName = $computername
        Port = $port
        Subject = $certinfo.Subject;
        Issuer = $certinfo.Issuer;
        DNSNameList = $certinfo.DnsNameList;
        EnhancedKeyUsageList = $certinfo.EnhancedKeyUsageList;
        SerialNumber = $certinfo.SerialNumber;
        Thumbprint = $certinfo.Thumbprint;
        Issued = $certinfo.NotBefore
        Expires = $certinfo.NotAfter
    }

    new-object PSCustomObject -Property $returnobj
} }