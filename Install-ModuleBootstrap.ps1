#requires -Version 3.0
<#
.SYNOPSIS
Bootstraps a module from the powershell gallery simply using Nuget.exe. Useful on:
- Systems not running Powershell v5+
- Systems with limited access rights (Azure Functions, etc) where you can't install the PSv4 PackageManagement MSI

.DESCRIPTION
This script is meant to be called from invoke-expression remotely to bootstrap modules into your environment.
In general, I recommend you only use this to bootstrap PSDepend, and then use that for the remaining prerequisites
As it has much better handling and sanity checks than this script.

.EXAMPLE
Install-ModuleBootstrap.ps1
Installs PSDeploy to your default CurrentUser modules directory

.EXAMPLE
Invoke-Command -ArgumentList "PSDeploy" -ScriptBlock ([scriptblock]::Create((new-object net.webclient).DownloadString('http://tinyurl.com/PSIMB'))) -ArgumentList "Pester"
Bootstraps this script from a URL. Useful for Azure Functions

#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact="Low")]
param (
    #Name of the module on PowershellGallery. Defaults to PSDepend if nothing specified.
    [Parameter(ValueFromPipeline=$true)][string[]]$Name = "PSDepend",
    #Path to save the module. Defaults to currentuser default module directory
    [string]$Path = "$([environment]::getfolderpath("mydocuments"))\WindowsPowershell\Modules",
    #Force overwriting the module if it already exists. By default we don't do this for speed.
    [switch]$Force,
    #Add the path to the PSModulesPath user environment variable if it doesn't exist. Generates a warning otherwise.
    [switch]$AddToPSModulesPath
)

#If we are in Azure Functions, initialize HOME environment variable and ~ so path resolves correctly
if ($EXECUTION_CONTEXT_FUNCTIONDIRECTORY) {
    (get-psprovider 'FileSystem').Home = $EXECUTION_CONTEXT_FUNCTIONDIRECTORY
    $env:HOME= $EXECUTION_CONTEXT_FUNCTIONDIRECTORY

    #If a custom path hasn't been specified, set it to Azure Functions Modules directory
    if (-not $MyInvocation.BoundParameters.Path) {
        write-verbose "Detected we are in Azure Functions, setting default path to function module directory"
        $Path = "$EXECUTION_CONTEXT_FUNCTIONDIRECTORY\Modules"
    }
}

#Verify the module path requested exists. Create it if it meets certain default criteria, error otherwise.
if (-not (test-path $Path)) {
    #If it is the default setting or Force is specified, go ahead and create it, otherwise bail out for safety.
    if ((-not $MyInvocation.BoundParameters.Path) -or $Force) {
        mkdir $Path | out-null
    } else {
        throw "You specified a custom path $Path but it does not exist. You must create it first or specify -Force."
    }
}

#Check if the requested module path is in PSModulesPath and if not, either add it if requested or throw a warning
if ( ($env:PSModulePath -split ';') -notcontains (Resolve-Path $Path) ) {
    if ($AddToPSModulesPath) {
        $CurrentValue = [Environment]::GetEnvironmentVariable("PSModulePath", "User")
        [Environment]::SetEnvironmentVariable("PSModulePath", ($Path + ";" + $CurrentValue), "User")
    } else {
        write-warning "Specified path $Path is not in the PSModulePath environment variable. This module will not load automatically in PSv3 or later and you must load it manually with import-module or specify -Import to this command"
    }
}

# Bootstrap nuget if we don't have it
if(-not ($NugetPath = (Get-Command 'nuget.exe' -ErrorAction SilentlyContinue).Path)) {

    #If we are in Azure Functions, set NuGetPath to the App Service tools directory
    #Otherwise try TEMP, then USERPROFILE, then the path argument, then currentdirectory as a last resort
    if ($EXECUTION_CONTEXT_FUNCTIONNAME -and $Tools) {
        $NugetPath = Join-Path $Tools nuget.exe
    } elseif ($ENV:TEMP) {
        $NugetPath = Join-Path $ENV:TEMP nuget.exe
    } elseif ($ENV:USERPROFILE) {
        $NugetPath = Join-Path $ENV:TEMP nuget.exe
    } elseif (Test-Path $Path) {
        $NugetPath = Join-Path $Path nuget.exe
    } else {
        throw "Could not find a valid location to download NUGET.EXE. Define a TEMP or USERPROFILE environment variable or ensure the -path parameter exists"
    }
    
    #Download NuGet if it does not already exist
    if(-not (Test-Path $NugetPath)) { 
        write-verbose "Nuget.exe not found, downloading to $NugetPath..."
        Invoke-WebRequest -uri 'https://dist.nuget.org/win-x86-commandline/latest/nuget.exe' -OutFile $NugetPath
    }
}

#Install the module(s) via nuget.exe
foreach ($moduleNameItem in $Name) {
    if ( (-not (test-path (join-path $Path $ModuleNameItem))) -or ($Force) ) {
        write-verbose "Installing Module $moduleNameItem to $Path"
        if ($PSCmdlet.ShouldProcess( (join-path $path $moduleNameItem), "Install Powershell Module $moduleNameItem via nuget.exe")) {
            $NugetParams = 'install', "$moduleNameItem", '-Source', 'https://www.powershellgallery.com/api/v2/',
                            '-ExcludeVersion', '-NonInteractive', '-Verbosity', 'quiet', '-OutputDirectory', $Path
            & $NugetPath @NugetParams | write-verbose

            #If the module is PSDepend, go ahead and copy nuget.exe into the module directory as it will be required
            if ($moduleNameItem -match 'PSDepend') {
                copy-item $NugetPath $Path\$moduleNameItem -force | out-string | write-verbose
            }
        }
    } else {
        write-verbose "Module $moduleNameItem already exists at $Path and -Force not specified, skipping..."
    }
}

