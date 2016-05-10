# The MIT License (MIT)
# Copyright (c) 2016 Darren R. Starr
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy of this software 
# and associated documentation files (the "Software"), to deal in the Software without restriction, 
# including without limitation the rights to use, copy, modify, merge, publish, distribute, 
# sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is 
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all copies or 
# substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING 
# BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND 
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, 
# DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
# ====================================================================================================

# Configure Server is a script which should never be run directly but instead is inserted by InstallWindows.ps1
# onto a Windows ISO to continue following AutoUnattend.xml for automated deployment of the base data center
# components of a Windows infrastructure.

. d:\settings.ps1

Function RunAgainOnReboot
{
    Set-ItemProperty `
		"HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" `
		"ConfigureServer" `
		('C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Unrestricted -File "D:\configure.ps1"')
}

Function CheckAndConfigureHostName(
) {
    If ($env:COMPUTERNAME -like "ScriptStation") {
        Exit
    }

    If (-Not ($env:COMPUTERNAME -eq $hostName)) {
        RunAgainOnReboot
        Rename-Computer -NewName $hostName -Force -Restart
    }
}

Import-Module NetAdapter

Function DetectAndInstallVMWareTools(
) {
    $adapter = Get-NetAdapter -Name "Ethernet0"
    If (!$adapter) {
        RunAgainOnReboot
        D:\setup64.exe /s '/v"/qn"' /l C:\Windows\Temp\vmware_tools_install.log
        Sleep -Seconds 30
        Exit
        # Restart-Computer -Force -Confirm:$false        
    }
}

Function SetServerIPAddress(
) {
    $MaskBits = 24 # This means subnet mask = 255.255.255.0
    $Dns = $dnsServer
    $IPType = "IPv4"
    
    # Retrieve the network adapter that you want to configure
    $adapter = Get-NetAdapter -Name "Ethernet0"
    
    # Disable DHCP on the interface
    $adapter | Set-NetIPInterface -DHCP Disabled

    # Remove any existing IP, gateway from our ipv4 adapter
    If (($adapter | Get-NetIPConfiguration).IPv4Address.IPAddress) {
        $adapter | Remove-NetIPAddress -AddressFamily $IPType -Confirm:$false
    }
    
    If (($adapter | Get-NetIPConfiguration).Ipv4DefaultGateway) {
        $adapter | Remove-NetRoute -AddressFamily $IPType -Confirm:$false
    }    
    
     # Configure the IP address and default gateway
    $adapter | New-NetIPAddress `
        -AddressFamily $IPType `
        -IPAddress $IP `
        -PrefixLength $MaskBits `
        -DefaultGateway $gatewayIP 

    # Configure the DNS client server IP addresses
    $adapter | Set-DnsClientServerAddress -ServerAddresses $DNS
}

Function InstallActiveDirectory(
) {
    Add-WindowsFeature -Name "AD-Domain-Services" 
    Add-WindowsFeature -Name "RSAT-AD-AdminCenter" -IncludeAllSubFeature
    Add-WindowsFeature -Name "RSAT-ADDS-Tools" -IncludeAllSubFeature
    Add-WindowsFeature -Name “RSAT-AD-PowerShell” -IncludeAllSubFeature

    Import-Module ADDSDeployment

    $safeModePassword = ConvertTo-SecureString -Force -AsPlainText -String "C1sco12345"
    Install-ADDSForest `
        -CreateDNSDelegation:$false `
        -DatabasePath "C:\Windows\NTDS" `
        -DomainMode "Win2012R2" `
        -DomainName $domainName `
        -DomainNetBIOSName $netbiosDomain `
        -ForestMode "Win2012R2" `
        -InstallDNS:$true `
        -LogPath "C:\Windows\NTDS" `
        -NoRebootOnCompletion:$false `
        -SysvolPath "C:\Windows\SYSVOL" `
        -Force:$true `
        -SafeModeAdministratorPassword $safeModePassword
}

Function PromoteSecondaryADServer(
) {
    Add-WindowsFeature -Name "AD-Domain-Services" 
    Add-WindowsFeature -Name "RSAT-AD-AdminCenter" -IncludeAllSubFeature
    Add-WindowsFeature -Name "RSAT-ADDS-Tools" -IncludeAllSubFeature
    Add-WindowsFeature -Name “RSAT-AD-PowerShell” -IncludeAllSubFeature

    Import-Module ADDSDeployment
    
    $safeModePassword = ConvertTo-SecureString -Force -AsPlainText -String "C1sco12345"
    $creds = New-Object System.Management.Automation.PSCredential(("Administrator@{0}" -f $domainName), $safeModePassword)
    Install-ADDSDomainController `
        -NoGlobalCatalog:$false `
        -CreateDnsDelegation:$false `
        -Credential $creds `
        -CriticalReplicationOnly:$false `
        -DatabasePath "C:\Windows\NTDS" `
        -DomainName $domainName `
        -InstallDns:$true `
        -LogPath "C:\Windows\NTDS" `
        -NoRebootOnCompletion:$false `
        -SiteName "Default-First-Site-Name" `
        -SysvolPath "C:\Windows\SYSVOL" `
        -Force:$true `
        -SafeModeAdministratorPassword $safeModePassword
}

Function CreateADCertServer(
) {
    Get-WindowsFeature -Name AD-Certificate | Install-WindowsFeature
    Install-AdcsCertificationAuthority -Confirm:$false 
}

Function JoinDomain(
) {
    Import-Module ServerManager
    Add-WindowsFeature -Name “RSAT-AD-PowerShell” -IncludeAllSubFeature
    Import-Module ActiveDirectory
    # TODO : Fix me... failing to find AD at this point
    $computerHandle = Get-ADComputer -Filter { Name -eq $hostName } 
    If (!$computerHandle) {
        RunAgainOnReboot
        $creds = New-Object System.Management.Automation.PSCredential(("Administrator@{0}" -f $domainName), (ConvertTo-SecureString -AsPlainText -Force -String "C1sco12345"))
        Add-Computer -DomainName $domainName -Credential $creds -Server ("{0}.{1}" -f $adServerHostName, $domainName)
        Sleep -Seconds 30
        Restart-Computer -Force -Confirm:$false
    } 
}

CheckAndConfigureHostName
DetectAndInstallVMWareTools
SetServerIPAddress

If ($installAD -eq $True) {
    InstallActiveDirectory
}
If ($joinAD -eq $True) {
    JoinDomain
}
If ($installSecondaryAD -eq $True) {
    PromoteSecondaryADServer
}
If ($installCertificateServices -eq $True) {
    CreateADCertServer
}

