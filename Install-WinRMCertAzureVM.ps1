<#
.SYNOPSIS

Downloads and installs the certificate created or initially uploaded during creation of a Windows based Windows Azure Virtual Machine.

.DESCRIPTION

Downloads and installs the certificate created or initially uploaded during creation of a Windows based Windows Azure Virtual Machine.
Running this script installs the downloaded certificate into your local machine certificate store (why it requires PowerShell to run elevated). 
This allows you to connect to remote machines without disabling SSL checks and increasing your security. 

.PARAMETER SubscriptionName

The name of the subscription stored in WA PowerShell to use. Use quotes around subscription names with spaces. 
Download and configure the Windows Azure PowerShell cmdlets first and use Get-AzureSubscription | Select SubscriptionName to identify the name.

.PARAMETER ServiceName

The name of the cloud service the virtual machine is deployed in.

.PARAMETER Name

The name of the virtual machine to install the certificate for. 

.EXAMPLE

.\InstallWinRMCertAzureVM.ps1 -SubscriptionName "my subscription" -ServiceName "mycloudservice" -Name "myvm1" 

#>

param([string] $SubscriptionName, [string] $ServiceName, [string] $Name)

Function IsAdmin
{
    $IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()` 
        ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator") 
    
    return $IsAdmin
}



Function InstallWinRMCertificateForVM()
{
    param([string] $CloudServiceName, [string] $Name)
	if((IsAdmin) -eq $false)
	{
		Write-Error "Must run PowerShell elevated to install WinRM certificates."
		return
	}
	
    Write-Host "Installing WinRM Certificate for remote access: $CloudServiceName $Name"
	$WinRMCert = (Get-AzureVM -ServiceName $CloudServiceName -Name $Name | select -ExpandProperty vm).DefaultWinRMCertificateThumbprint
	$AzureX509cert = Get-AzureCertificate -ServiceName $CloudServiceName -Thumbprint $WinRMCert -ThumbprintAlgorithm sha1

	$certTempFile = [IO.Path]::GetTempFileName()
	$AzureX509cert.Data | Out-File $certTempFile

	# Target The Cert That Needs To Be Imported
	$CertToImport = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $certTempFile

	$store = New-Object System.Security.Cryptography.X509Certificates.X509Store "Root", "LocalMachine"
	$store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
	$store.Add($CertToImport)
	$store.Close()
	
	Remove-Item $certTempFile
}


Select-AzureSubscription $SubscriptionName
InstallWinRMCertificateForVM -CloudServiceName $ServiceName -Name $Name
