function Convert-HashTableToXML() {
<#
.SYNOPSIS
COnverts one or more Powershell hashtables into a simple XML format.

.DESCRIPTION
Creates simpler and more human-readable output for a hashtable than Export-CliXML or ConvertTo-XML.
This is useful for instance when storing attributes or configuration variables for output to other 
program or storage in an AD CustomAttribute.

This command will create appropriate subnodes if you have nested hashtables.

.NOTES
Adapted from original script by Blindrood (https://gallery.technet.microsoft.com/scriptcenter/Export-Hashtable-to-xml-in-122fda31)

.PARAMETER InputObject
A Powershell hashtable that contains the name-value pairs you wish to convert to XML elements

.PARAMETER Root
Allows you to specify the root XML element definition.

.PARAMETER OutPath
Path to an output XML file, if desired. If not specified, outputs directly to the pipeline

.EXAMPLE
Create a Hashtable

PS C:\> $Configuration = @{ 
    'Definitions' = @{ 
        'ConnectionString' = 'sql=srv01;port=223' 
        'MonitoringLevel' = 'MonitoringLevelValue' 
    } 
    'Conventions' = @{ 
        'MyConvention' = 'This is my convention' 
        'Option' = 'Zip' 
        'ServerType' = 'sql' 
        'Actions' = @{ 
            'SpecificAction' = 'DoNothing' 
            'DefaultAction' = 'Destroy it All' 
        } 
        'ExceptionAction' = 125 
        'Period' = New-TimeSpan -Seconds 20 
    } 
    'ServiceAccount' = @{ 
        'UserName' = 'mydomain.com\thisisme' 
        'Password' = '123o123' 
    } 
    'GroupConfiguration' = @{ 
        'AdminsGroup' = 'mydomain.com\thisisAdminsGroup' 
        'UsersGroup' = 'mydomain.com\thisisUsersGroup' 
    } 
} 

.EXAMPLE
Export the 
$Configuration | Out-HashTableToXml -Root 'Configuration' -File $env:temp\test.xml

-----------------
Test.XML Contents
-----------------

<Configuration> 
  <Conventions> 
    <ExceptionAction>125</ExceptionAction> 
    <ServerType>sql</ServerType> 
    <Actions> 
      <SpecificAction>DoNothing</SpecificAction> 
      <DefaultAction>Destroy it All</DefaultAction> 
    </Actions> 
    <Period>00:00:20</Period> 
    <Option>Zip</Option> 
    <MyConvention>This is my convention</MyConvention> 
  </Conventions> 
  <GroupConfiguration> 
    <UsersGroup>mydomain.com\thisisUsersGroup</UsersGroup> 
    <AdminsGroup>mydomain.com\thisisAdminsGroup</AdminsGroup> 
  </GroupConfiguration> 
  <Definitions> 
    <MonitoringLevel>MonitoringLevelValue</MonitoringLevel> 
    <ConnectionString>sql=srv01;port=223</ConnectionString> 
  </Definitions> 
  <ServiceAccount> 
    <Password>123o123</Password> 
    <UserName>mydomain.com\thisisme</UserName> 
  </ServiceAccount> 
</Configuration>


#>

Param(
	[Parameter(ValueFromPipeline = $true, Position = 0)]
	[System.Collections.Hashtable]$InputObject,

    [ValidateScript({Test-Path $_ -IsValid})] 
    [System.String]$OutPath,

	[System.String]$Root="PSHashTable"
)

Begin{
	$ScriptBlock = {
		Param($Elem, $Root)
		if( $Elem.Value -is [System.Collections.Hashtable] ){
			$RootNode = $Root.AppendChild($Doc.CreateNode([System.Xml.XmlNodeType]::Element,$Elem.Key,$Null))
			$Elem.Value.GetEnumerator() | ForEach-Object {
				$Scriptblock.Invoke( @($_, $RootNode) )
			}
		}
		else{
			$Element = $Doc.CreateElement($Elem.Key)
			$Element.InnerText = if($Elem.Value -is [Array]) {
				$Elem.Value -join ','
			}
			else{
				$Elem.Value | Out-String
			}
			$Root.AppendChild($Element) | Out-Null	
		}
	}	
} #Begin

Process{
	$Doc = [xml]"<$($Root)></$($Root)>"
	$InputObject.GetEnumerator() | ForEach-Object {
		$scriptblock.Invoke( @($_, $doc.DocumentElement) )
	}
	d
    #Output the formatted XML document if OutPath is specified, otherwise send to pipeline
    if ($OutPath) {$doc.save($OutPath)}
    else {$doc}
} #Process

} #Out-HashTableToXML