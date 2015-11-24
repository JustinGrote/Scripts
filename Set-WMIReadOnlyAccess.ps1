<#
.SYNOPSIS
    Configure WMI for the particular AD Identity (User or Group) on the computer for read only access.
.DESCRIPTION
    This script sets up a user for WMI read-only access without giving them admin rights. 
.NOTES
    Refactored by Justin Grote <jgrote@allieddigital.net>
    Core Logic by Niklas Akerlund 2012-08-22
.LINK
    http://vniklas.djungeln.se/2012/08/22/set-up-non-admin-account-to-access-wmi-and-performance-data-remotely-with-powershell/

#>

[CmdletBinding(
    SupportsShouldProcess
)]

Param (
    [Parameter(Mandatory)]
    [string]$Identity,
    [Parameter(ValueFromPipeline)]
    [string]$ComputerName = $env:Computername    
)

#region Includes

<#
.SYNOPSIS
    Function that resolves SAMAccount and can exit script if resolution fails
#>
function Resolve-SamAccount {
param(
    [string]$SamAccount
)
    process {
        try
        {
            $ADResolve = ([adsisearcher]"(samaccountname=$Identity)").findone().properties['samaccountname']
        }
        catch
        {
            $ADResolve = $null
        }

        if (!$ADResolve) {
            throw "User `'$SamAccount`' not found in AD, please specify a valid user"
        }
            
        $ADResolve
    }
} #function Resolve-SAMAccount

function Add-LocalGroupMember {
    <#
    .SYNOPSIS   
    Script to add an AD User or group to the Local Administrator group
    
    .DESCRIPTION 
    The script can use either a plaintext file or a computer name as input and will add the trustee (user or group) as an administrator to the computer
	
    .PARAMETER InputFile
    A path that contains a plaintext file with computer names

    .PARAMETER Computer
    This parameter can be used instead of the InputFile parameter to specify a single computer or a series of
    computers using a comma-separated format
	
    .PARAMETER Trustee
    The SamAccount name of an AD User or AD Group that is to be added to the Local Administrators group

    .NOTES   
    Name: Add-LocalGroupMember
    Author: Justin Grote (Modified from Original Author)
    Original Author: Jaap Brasser

    .LINK
    http://www.jaapbrasser.com

    .EXAMPLE   
    .\Add-LocalGroupMember -Computer Server01 -Trustee JaapBrasser

    Description:
    Will set the the JaapBrasser account as a Local Administrator on Server01

    .EXAMPLE   
    .\Add-LocalGroupMember -Computer 'Server01,Server02' -Trustee Contoso\HRManagers

    Description:
    Will set the HRManagers group in the contoso domain as Local Administrators on Server01 and Server02

    .EXAMPLE   
    .\Add-LocalGroupMember -InputFile C:\ListofComputers.txt -Trustee User01

    Description:
    Will set the User01 account as a Local Administrator on all servers and computernames listed in the ListofComputers file
    #>
    param(
        [Parameter(ParameterSetName='InputFile')]
        [string]
        $InputFile,

        [Parameter(ParameterSetName='Computer')]
        [string] $ComputerName = $env:ComputerName,

        [Parameter(Mandatory)]
        [string] $Identity,

        [Parameter(Mandatory)]
        [string] $GroupName
    )
    <#
    .SYNOPSIS
        Function that resolves SAMAccount and can exit script if resolution fails
    #>
    function Resolve-SamAccount {
    param(
        [string]
            $SamAccount,
        [boolean]
            $Exit
    )
        process {
            try
            {
                $ADResolve = ([adsisearcher]"(samaccountname=$Identity)").findone().properties['samaccountname']
            }
            catch
            {
                $ADResolve = $null
            }

            if (!$ADResolve) {
                throw "User `'$SamAccount`' not found in AD, please specify a valid user"
            }
            
            $ADResolve
        }
    } #function Resolve-SAMAccount

    if ($Identity -notmatch '\\') {
        $ADResolved = (Resolve-SamAccount -SamAccount $Identity -Exit:$true)
        $Identity = 'WinNT://',"$env:userdomain",'/',$ADResolved -join ''
    } else {
        $ADResolved = ($Identity -split '\\')[1]
        $DomainResolved = ($Identity -split '\\')[0]
        $Identity = 'WinNT://',$DomainResolved,'/',$ADResolved -join ''
    }

    if (!$InputFile) {
	    [string[]]$ComputerName = $ComputerName.Split(',')
	    $ComputerName | ForEach-Object {
		    Write-Verbose "Adding `'$ADResolved`' to $GroupName group on `'$_`'"
		    try {
			    ([ADSI]"WinNT://$_/$GroupName,group").add($Identity)
		    } catch {
			    Write-Warning "$_"
		    }	
	    }
    }
    else {
	    if (!(Test-Path -Path $InputFile)) {
		    Write-Warning "Input file not found, please enter correct path"
		    exit
	    }
	    Get-Content -Path $InputFile | ForEach-Object {
		    Write-Host "Adding `'$ADResolved`' to $GroupName group on `'$_`'"
		    try {
			    ([ADSI]"WinNT://$_/$GroupName,group").add($Identity)
		    } catch {
			    Write-Warning "$_"
		    }        
	    }
    }
} #Add-LocalGroupMember

Function Set-WmiNamespaceSecurity {
    <#
    .SYNOPSIS
    Set WMI Permissions for a security entity
    .NOTES 
    Copyright (c) Microsoft Corporation.  All rights reserved. 
    For personal use only.  Provided AS IS and WITH ALL FAULTS

    Modifications made by vNicklas are included.
    .LINK
    http://blogs.msdn.com/b/wmi/archive/2009/07/27/scripting-wmi-namespace-security-part-3-of-3.aspx
    .LINK
    http://vniklas.djungeln.se/2012/08/22/set-up-non-admin-account-to-access-wmi-and-performance-data-remotely-with-powershell/
    .EXAMPLE
    Set-WmiNamespaceSecurity root/cimv2 add steve Enable,RemoteAccess
    #>
 
    Param ( [parameter(Mandatory=$true,Position=0)][string] $namespace,
        [parameter(Mandatory=$true,Position=1)][string] $operation,
        [parameter(Mandatory=$true,Position=2)][string] $account,
        [parameter(Position=3)][string[]] $permissions = $null,
        [bool] $allowInherit = $false,
        [bool] $deny = $false,
        [string] $computer = ".",
        [System.Management.Automation.PSCredential] $credential = $null)
   
    Process {
        $ErrorActionPreference = "Stop"
 
        Function Get-AccessMaskFromPermission($permissions) {
            $WBEM_ENABLE            = 1
                    $WBEM_METHOD_EXECUTE = 2
                    $WBEM_FULL_WRITE_REP   = 4
                    $WBEM_PARTIAL_WRITE_REP              = 8
                    $WBEM_WRITE_PROVIDER   = 0x10
                    $WBEM_REMOTE_ACCESS    = 0x20
                    $WBEM_RIGHT_SUBSCRIBE = 0x40
                    $WBEM_RIGHT_PUBLISH      = 0x80
        	    $READ_CONTROL = 0x20000
        	    $WRITE_DAC = 0x40000
       
            $WBEM_RIGHTS_FLAGS = $WBEM_ENABLE,$WBEM_METHOD_EXECUTE,$WBEM_FULL_WRITE_REP,
                $WBEM_PARTIAL_WRITE_REP,$WBEM_WRITE_PROVIDER,$WBEM_REMOTE_ACCESS,
                $READ_CONTROL,$WRITE_DAC
            $WBEM_RIGHTS_STRINGS = "Enable","MethodExecute","FullWrite","PartialWrite",
                "ProviderWrite","RemoteAccess","ReadSecurity","WriteSecurity"
 
            $permissionTable = @{}
 
            for ($i = 0; $i -lt $WBEM_RIGHTS_FLAGS.Length; $i++) {
                $permissionTable.Add($WBEM_RIGHTS_STRINGS[$i].ToLower(), $WBEM_RIGHTS_FLAGS[$i])
            }
       
            $accessMask = 0
 
            foreach ($permission in $permissions) {
                if (-not $permissionTable.ContainsKey($permission.ToLower())) {
                    throw "Unknown permission: $permission" + "Valid permissions: $($permissionTable.Keys)"
                }
                $accessMask += $permissionTable[$permission.ToLower()]
            }
       
            $accessMask
        }
 
        if ($PSBoundParameters.ContainsKey("Credential")) {
            $remoteparams = @{ComputerName=$computer;Credential=$credential}
        } else {
            $remoteparams = @{ComputerName=$computerName}
        }
       
        $invokeparams = @{Namespace=$namespace;Path="__systemsecurity=@"} + $remoteParams
 
        $output = Invoke-WmiMethod @invokeparams -Name GetSecurityDescriptor
        if ($output.ReturnValue -ne 0) {
            throw "GetSecurityDescriptor failed: $($output.ReturnValue)"
        }
 
        $acl = $output.Descriptor
        $OBJECT_INHERIT_ACE_FLAG = 0x1
        $CONTAINER_INHERIT_ACE_FLAG = 0x2
 
        $computerName = (Get-WmiObject @remoteparams Win32_ComputerSystem).Name
   
        if ($account.Contains('\')) {
            $domainaccount = $account.Split('\')
            $domain = $domainaccount[0]
            if (($domain -eq ".") -or ($domain -eq "BUILTIN")) {
                $domain = $computerName
            }
            $accountname = $domainaccount[1]
        } elseif ($account.Contains('@')) {
            $domainaccount = $account.Split('@')
            $domain = $domainaccount[1].Split('.')[0]
            $accountname = $domainaccount[0]
        } else {
            $domain = $computerName
            $accountname = $account
        }
 
        $getparams = @{Class="Win32_Account";Filter="Domain='$domain' and Name='$accountname'"}
 
        $win32account = Get-WmiObject @getparams
 
        if ($win32account -eq $null) {
            throw "Account was not found: $account"
        }
 
        switch ($operation) {
            "add" {
                if ($permissions -eq $null) {
                    throw "-Permissions must be specified for an add operation"
                }
                $accessMask = Get-AccessMaskFromPermission($permissions)
   
                $ace = (New-Object System.Management.ManagementClass("win32_Ace")).CreateInstance()
                $ace.AccessMask = $accessMask
                if ($allowInherit) {
                    $ace.AceFlags = $OBJECT_INHERIT_ACE_FLAG + $CONTAINER_INHERIT_ACE_FLAG
                } else {
                    $ace.AceFlags = 0
                }
                       
                $Identity = (New-Object System.Management.ManagementClass("win32_Trustee")).CreateInstance()
                $Identity.SidString = $win32account.Sid
                $ace.Trustee = $Identity
           
                $ACCESS_ALLOWED_ACE_TYPE = 0x0
                $ACCESS_DENIED_ACE_TYPE = 0x1
 
                if ($deny) {
                    $ace.AceType = $ACCESS_DENIED_ACE_TYPE
                } else {
                    $ace.AceType = $ACCESS_ALLOWED_ACE_TYPE
                }
 
                $acl.DACL += $ace.psobject.immediateBaseObject
	    
            }
       
            "delete" {
                if ($permissions -ne $null) {
                    throw "Permissions cannot be specified for a delete operation"
                }
       
                [System.Management.ManagementBaseObject[]]$newDACL = @()
                foreach ($ace in $acl.DACL) {
                    if ($ace.Trustee.SidString -ne $win32account.Sid) {
                        $newDACL += $ace.psobject.immediateBaseObject
                    }
                }
 
                $acl.DACL = $newDACL.psobject.immediateBaseObject
            }
       
            default {
                throw "Unknown operation: $operation`nAllowed operations: add delete"
            }
        }
 
        $setparams = @{Name="SetSecurityDescriptor";ArgumentList=$acl.psobject.immediateBaseObject} + $invokeParams
 
        $output = Invoke-WmiMethod @setparams
        if ($output.ReturnValue -ne 0) {
            throw "SetSecurityDescriptor failed: $($output.ReturnValue)"
        }
    }
} #function Set-WmiNameSpaceSecurity

#endregion Includes


#region Main

$WMIPermissionLocalGroups = "Distributed COM Users","Performance Monitor Users"

if ($pscmdlet.ShouldProcess("$ComputerName", "$Identity`: Add WMI Read-Only Access")) {
    $WMIPermissionLocalGroups | foreach {
        Add-LocalGroupMember -ComputerName $ComputerName -GroupName $PSItem -Identity $Identity
    }

    $WMINamespaceSecurityParams = @{
        Namespace = "root/CIMv2"
        Account = $Identity
        Computer = $ComputerName
    }
    Set-WMINamespaceSecurity @WMINamespaceSecurityParams -Operation add -Permissions Enable,MethodExecute,ReadSecurity,RemoteAccess
}
    
#endregion Main