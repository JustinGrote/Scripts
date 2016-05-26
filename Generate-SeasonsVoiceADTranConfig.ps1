
function Generate-SeasonsVoiceADTranConfig {

param (
    #The AD Site Name for the switch. Example: "DesPlaines"
    [Parameter(Mandatory)][string]$SiteName,
    #The Number corresponding to the site. Generally the third Octet of the IP address. Example: If devices have 10.1.5.x addresses at the branch, "5"
    [Parameter(Mandatory)][int]$SiteNumber,
    #Specify this parameter to increment the switch count, in the event there is more than one switch at the site.
    [int]$SwitchNumber=1,
    #where to output the Config files. Defaults to the current Directory
    $OutputDir = "."
)

$SwitchName = "$SiteName-L3VSwitch$SwitchNumber"
$SwitchIP = $SwitchNumber-1
#Skip .21 IP
if ($SwitchIP -eq 1) {$SwitchIP++}

$config = @"
hostname "$SwitchName"
enable password encrypted 4443385ea19069ff01772adff6277c58e63f
!
clock timezone -6-Central-Time
clock no-auto-correct-DST 
!
ip subnet-zero
ip classless
ip routing
!
!
ip route-cache express
!
auto-config
!
event-history on
no logging forwarding
no logging email
!
service password-encryption
!
username "ati" password encrypted "1d159b892ef1bb01644714274072fd1ae35b" 
username "admin" password encrypted "3a3369a67f110c35b2c1604d5ad31b5a2cc9" 
!
!
!
!
!
!
no dot11ap access-point-control
no dos-protection
no desktop-auditing dhcp
no network-forensics ip dhcp
!
!
!
!
ip dhcp excluded-address 10.2.$SiteNumber.101 10.2.$SiteNumber.250
ip dhcp excluded-address 10.2.$SiteNumber.1 10.2.$SiteNumber.50
!
ip dhcp pool "Voice"
  network 10.2.$SiteNumber.0 255.255.255.0
  dns-server 100.127.255.146 100.127.255.18
  default-router 10.2.$SiteNumber.2
  ntp-server 100.127.255.144
  option 66 ascii https://pub-xs.hvs.att.com/dms/Clearspan24
qos queue-type wrr 1 2 3 expedite
!
qos dscp-cos 0 8 16 24 32 34 46 48 to 0 1 2 3 4 5 6 7
! DSCP to CoS mapping only operates on ports that have 'qos trust cos' applied
!
spanning-tree priority 0
!
!
!
!
vlan 1
  name "Default" 
!
vlan 2
  name "Voice" 
!
interface eth 0/1
  ip address dhcp hostname "$SwitchName"
  no shutdown
!
!
interface gigabit-switchport 0/1
  description ATT SBC
  spanning-tree bpdufilter enable
  no shutdown
  switchport access vlan 2
!
interface gigabit-switchport 0/2
  description ATT SBC
  spanning-tree bpdufilter enable
  no shutdown
  switchport access vlan 2
!
interface gigabit-switchport 0/3
  no shutdown
  switchport access vlan 2
  no lldp send-and-receive
!
interface gigabit-switchport 0/4
  no shutdown
  switchport access vlan 2
  no lldp send-and-receive
!
interface gigabit-switchport 0/5
  no shutdown
  switchport access vlan 2
  no lldp send-and-receive
!
interface gigabit-switchport 0/6
  no shutdown
  switchport access vlan 2
  no lldp send-and-receive
!
interface gigabit-switchport 0/7
  no shutdown
  switchport access vlan 2
  no lldp send-and-receive
!
interface gigabit-switchport 0/8
  no shutdown
  switchport access vlan 2
  no lldp send-and-receive
!
interface gigabit-switchport 0/9
  no shutdown
  switchport access vlan 2
  no lldp send-and-receive
!
interface gigabit-switchport 0/10
  no shutdown
  switchport access vlan 2
  no lldp send-and-receive
!
interface gigabit-switchport 0/11
  no shutdown
  switchport access vlan 2
  no lldp send-and-receive
!
interface gigabit-switchport 0/12
  no shutdown
  switchport access vlan 2
  no lldp send-and-receive
!
interface gigabit-switchport 0/13
  no shutdown
  switchport access vlan 2
  no lldp send-and-receive
!
interface gigabit-switchport 0/14
  no shutdown
  switchport access vlan 2
  no lldp send-and-receive
!
interface gigabit-switchport 0/15
  no shutdown
  switchport access vlan 2
  no lldp send-and-receive
!
interface gigabit-switchport 0/16
  no shutdown
  switchport access vlan 2
  no lldp send-and-receive
!
interface gigabit-switchport 0/17
  no shutdown
  switchport access vlan 2
  no lldp send-and-receive
!
interface gigabit-switchport 0/18
  no shutdown
  switchport access vlan 2
!
interface gigabit-switchport 0/19
  no shutdown
  switchport access vlan 2
!
interface gigabit-switchport 0/20
  no shutdown
  switchport access vlan 2
!
interface gigabit-switchport 0/21
  no shutdown
  switchport access vlan 2
!
interface gigabit-switchport 0/22
  no shutdown
  switchport access vlan 2
!
interface gigabit-switchport 0/23
  description "Uplink: Fortigate"
  no shutdown
  switchport mode trunk
!
interface gigabit-switchport 0/24
  description "Uplink: Fortigate"
  no shutdown
  switchport mode trunk
!
!
interface vlan 1
  ip address  10.1.$SiteNumber.2$SwitchIP  255.255.255.0 
  ip route-cache express
  no shutdown
!
interface vlan 2
  ip address  10.2.$SiteNumber.2$SwitchIP  255.255.255.0 
  ip route-cache express
  no shutdown
!
ip route 0.0.0.0 0.0.0.0 10.1.$SiteNumber.2
!
no tftp server
no tftp server overwrite
http server
no http secure-server
snmp agent
no ip ftp server
ip ftp server default-filesystem flash
no ip scp server
no ip sntp server
!
snmp-server location "$SwitchName"
snmp-server community QJzMCJfCCdkNS4aaMQ2F RO
!
line con 0
  no login
!
line telnet 0 4
  login local-userlist
  shutdown
line ssh 0 4
  login local-userlist
  no shutdown
!
sntp server 192.168.2.5 version 3
sntp server 192.168.2.6 version 3
!
end
"@
$outputPath = $OutputDir + "\$SwitchName.config"

write-verbose "Config Generated, outputting to $outputPath"
$config > $outputPath
}




import-excel 'C:\users\jgrote\sharepoint\SeasonsHospice\Projects\SwitchDeployment\Seasons Switch Deployment SiteList.xlsx' | foreach {
    $SiteInfo = $PSItem
    foreach ($SwitchNumber in (1..$Siteinfo.switches))  {
        Generate-SeasonsVoiceADTranConfig -SiteName $SiteInfo.SiteName -SiteNumber $Sinteinfo.SiteNumber -SwitchNumber $SwitchNumber -OutputDir C:\Users\JGrote\AppData\Local\Temp\Temp -verbose
    }
} #Foreach