<#
.SYNOPSIS
    This script provisions a new Azure network and a site-to-site tunnel configuration. It includes some sensible defaults that can be adjusted via the parameters.

.PARAMETER ResourceGroup
    The name of the Azure Resource Group you wish to deploy to. If one does not exist it will be created.

.PARAMETER ResourcePrefix
    A Prefix to append to resources created by this script. Not to be confused with an address prefix, this is simply a descriptive string e.g. "TestSystem1" Defaults to the name of the resource group if not specified.

.PARAMETER vnetAddressPrefix
    The Address range of your azure virtual network. Must be broad enough to encompass all subnets defined. Defaults to 172.30.0.0/16

.Parameter Location
    The Azure Datacenter location you wish to deploy to, e.g. "Central US". 
    To see a list of current Azure Datacenter locations that support virtual networks: (get-azurelocation | where {$_.name -eq 'Microsoft.Network/virtualNetworks'}).locations

.Parameter LocalGatewayIPAddress
    The IP Address of your local VPN Gateway. This is usually your firewall or router's WAN IP address.

.Parameter LocalSiteName
    The name of your local site, for descriptive purposes. Defaults to "Local"

.Parameter LocalAddressPrefix
    The Address range of your local network. Make this as broad as possible to include your onsite subnet and control access via firewall rules.

.Parameter AddressPrefix
    The overall subnet definition that you wish to use in prefix notation. All subnets must fit within this larger address prefix.

.Parameter Subnets
    A hashtable list of the subnets in prefix notation that you wish to define. Each will be made available via the tunnel. One must be named "GatewaySubnet". Default is @{GatewaySubnet = '172.30.0.0/24';Default='172.30.2.0/23'}

.NOTES
    Based on https://azure.microsoft.com/en-us/documentation/articles/vpn-gateway-create-site-to-site-rm-powershell/

#>
[Cmdletbinding(SupportsShouldProcess, ConfirmImpact="Low")]

param (
    [Parameter(Mandatory=$true)]$ResourceGroup,
    [Parameter(Mandatory=$true)]$location,
    [Parameter(Mandatory=$true)]$localGatewayIPAddress,
    [Parameter(Mandatory=$true)]$localAddressPrefix,
    $localSiteName = "Local",
    $resourcePrefix = $resourceGroup,
    $vnetAddressPrefix = '172.30.0.0/16',
    $subnets = @{GatewaySubnet = '172.30.0.0/24';Default='172.30.2.0/23'}

)

## START Progress Bar Config
#Determine how many progress steps there are in the script and set that to a variable. This is imperfect but works. Loops should use write-progress parentid
$Script:progressScriptStep=0
$Script:progressScriptMax = 6
$progressActivity = "Create Azure Site to Site Virtual Network" 
write-progress $progressActivity -percentcomplete $((($Script:progressScriptStep / $Script:progressScriptMax) * 100); $Script:progressScriptStep++)
### END Dynamic Progress Bar

Switch-AzureMode -Name AzureResourceManager -warningaction silentlycontinue

#Create a new resource group if it does not already exist
if (!(Get-AzureResourceGroup $resourcegroup -erroraction SilentlyContinue)) {
    if ($PSCmdlet.ShouldProcess($resourcegroup, 'Create Resource Group')) {  
        write-progress $progressActivity "Creating Resource Group $resourcegroup" -percentcomplete $((($Script:progressScriptStep / $Script:progressScriptMax) * 100); $Script:progressScriptStep++)
        $resourceGroupResult = New-AzureResourceGroup -Name $resourceGroup -Location $location
    } #If
}# If


#Create subnet definitions for each subnet listed in the hashtable
$subnetResult = if ($subnets.keys -notcontains 'GatewaySubnet') {throw {"You need to define a GatewaySubnet in $subnets parameter"}} 
else { $subnetConfigs = $subnets.keys | foreach {
        New-AzureVirtualNetworkSubnetConfig -name $PSItem -AddressPrefix $subnets.item($PSItem)
    } #Foreach
} #ShouldProcess

if ($PSCmdlet.ShouldProcess("$resourcePrefix-VNet", 'Create Azure Virtual Network')) {  
    write-progress $progressActivity "Creating Azure Virtual Network $resourcePrefix-VNet" -percentcomplete $((($Script:progressScriptStep / $Script:progressScriptMax) * 100); $Script:progressScriptStep++)
    $vnet = New-AzureVirtualNetwork -Name "$resourcePrefix-VNet" -ResourceGroupName $resourceGroup -Location $location -AddressPrefix $vnetAddressPrefix -Subnet $subnetConfigs
} #ShouldProcess

if ($PSCmdlet.ShouldProcess("$resourcePrefix-LNG-$localsitename", 'Create Azure Local Network Gateway')) {  
    write-progress $progressActivity "Creating Azure Local Network Gateway $resourcePrefix-LNG-$localsitename" -percentcomplete $((($Script:progressScriptStep / $Script:progressScriptMax) * 100); $Script:progressScriptStep++)
    $local = New-AzureLocalNetworkGateway -Name "$resourcePrefix-LNG-$localsitename" -ResourceGroupName $resourceGroup -Location $location -GatewayIpAddress $localGatewayIPAddress -AddressPrefix $localAddressPrefix
} #ShouldProcess

if ($PSCmdlet.ShouldProcess("$resourcePrefix-VNetGW-PIP", 'Create Azure Virtual Network Gateway Public IP Address')) { 
    write-progress $progressActivity "Creating Azure Virtual Network Gateway Public IP Address $resourcePrefix-VNetGW-PIP" -percentcomplete $((($Script:progressScriptStep / $Script:progressScriptMax) * 100); $Script:progressScriptStep++)
    $gwpip = New-AzurePublicIpAddress -Name "$resourcePrefix-VNetGW-PIP" -ResourceGroupName $resourceGroup -Location $location -AllocationMethod Dynamic -IdleTimeoutInMinutes 20 -DomainNameLabel ("$resourceprefix-VNetGW").tolower()
} #ShouldProcess

if ($PSCmdlet.ShouldProcess("$resourcePrefix-VNetGW", 'Create Azure Virtual Network Gateway ')) { 
    write-progress $progressActivity "Creating Azure Virtual Network Gateway $resourcePrefix-VNetGW (note: This step can take 15-30 minutes to complete)" -percentcomplete $((($Script:progressScriptStep / $Script:progressScriptMax) * 100); $Script:progressScriptStep++)
    $gwsubnet = Get-AzureVirtualNetworkSubnetConfig -Name 'GatewaySubnet' -VirtualNetwork $vnet
    $gwipconfig = New-AzureVirtualNetworkGatewayIpConfig -Name "$ResourcePrefix-VNetGWIPConfig" -SubnetId $gwsubnet.Id -PublicIpAddressId $gwpip.Id 
    $gateway1 = New-AzureVirtualNetworkGateway -Name "$ResourcePrefix-VNetGW" -ResourceGroupName $resourceGroup -Location $location -IpConfigurations $gwipconfig -GatewayType Vpn -VpnType RouteBased
} #ShouldProcess

if ($PSCmdlet.ShouldProcess("$resourcePrefix-VNet-to-$localSiteName", 'Create Azure Virtual Network Gateway Connection between $resourcePrefix and $localSiteName')) { 
    write-progress $progressActivity "Creating Azure Virtual Network Connection $resourcePrefix-VNet-to-$localSiteName" -percentcomplete $((($Script:progressScriptStep / $Script:progressScriptMax) * 100); $Script:progressScriptStep++)
    New-AzureVirtualNetworkGatewayConnection -Name "$ResourcePrefix-VNet-to-$localSiteName" -ResourceGroupName $resourceGroup -Location $location -VirtualNetworkGateway1 $gateway1 -LocalNetworkGateway2 $local -ConnectionType IPsec
} #ShouldProcess


$resultParams = @{}
$resultParams.GatewayName = $gateway1.Name
$resultParams.PublicIPAddress = "Test"