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

# Pod to deploy
$PodNumber = 1

# VCenter Server connectivity and credentials
$vcenterServer = "10.100.1.8"
$vcenterServerUsername = "student@nocturnal.local"
$vcenterServerPassword = "C1sco12345"

# vSphere Data Center
$dataCenterName = "Nocturnal"

# vSphere Virtual Distributed Switch Name
$dvsName = "Nocturnal55"

# Host and Storage Assigments for virtual servers
$ad1HostName = "esxi7.nocturnal.local"
$ad1DatastoreName = "Storage"

$ad2HostName = "esxi7.nocturnal.local"
$ad2DatastoreName = "Storage"

$caHostName = "esxi7.nocturnal.local"
$caDatastoreName = "Storage"

$apicEMA_Host = "esxi7.nocturnal.local"
$apicEMA_DataStore = "Storage"

$apicEMB_Host = "esxi7.nocturnal.local"
$apicEMB_DataStore = "Storage"

$prime_Host = "esxi4.nocturnal.local"
$prime_DataStore = "ESXi4 HDD"

$ise_Host = "esxi7.nocturnal.local"
$ise_DataStore = "Second"

# Source files for discs and tools
$windowsServerIso = "C:\inetpub\wwwroot\FileShare\Microsoft\9600.17050.WINBLUE_REFRESH.140317-1640_X64FRE_SERVER_EVAL_EN-US-IR3_SSS_X64FREE_EN-US_DV9.ISO"
$vmwareDriversPath = "C:\inetpub\wwwroot\FileShare\VMware\VMWare Drivers\Drivers"
$vmwareToolsIso = "C:\inetpub\wwwroot\FileShare\VMware\VMware-tools-10.0.0-3000743\vmtools\windows.iso"

# Shared storage between Windows and VMware settings
$vmwareNFSSharePath = "C:\inetpub\wwwroot\FileShare\Course Files"
$vmwareStoreName = "FileShare"
$vmwareStorePath = "[FileShare] /Course Files"
$vmwareCiscoStorePath = "[FileShare] /Cisco"

# IP Address of the external DNS Server
$dnsServer = "10.100.1.5"

#---------------------------------------------------------------------------------------------------------------------------------
# Create names for VMware virtual machines
$podName = "Pod{0}" -f $PodNumber 
$ad1Name = "{0} Active Directory 1" -f $podName 
$ad2Name = "{0} Active Directory 2" -f $podName 
$caName = "{0} Certificate Server" -f $podName 
$apicEMAName = "{0} APIC-EM A" -f $podName 
$apicEMBName = "{0} APIC-EM B" -f $podName 
$iseName = "{0} ISE" -f $podName 
$primeName = "{0} Prime" -f $podName 

$ad1IsoName = "P{0}_ActiveDirectory1.iso" -f $PodNumber
$ad2IsoName = "P{0}_ActiveDirectory2.iso" -f $PodNumber
$caIsoName = "P{0}_CertificateServer.iso" -f $PodNumber

# Configure names for the pod's Active Directory and NetBIOS names
$netbiosDomain = $podName.ToUpper()
$activeDirectoryDomainName = "{0}.local" -f $podName.ToLower()

# Create host names for configuring as computer names and registering in DNS
$ad1ServerName = "{0}AD1" -f $podName
$ad2ServerName = "{0}AD2" -f $podName
$caServerName= "{0}CA" -f $podName

# Create the names for the VMware port groups 
$infrastructurePortGroup = 2031 + ($PodNumber * 100)
$infrastructurePortGroupName = "{0}_{1}_Servers" -f $infrastructurePortGroup, $podName

# TODO : Redundant?
$activeDirectoryDomain = "pod{0}.local" -f $PodNumber

# Define IP addresses for the components of the pod
$serverGatewayIP = "10.20{0}.31.1" -f $PodNumber
$ad1ServerIPAddress = "10.20{0}.31.101" -f $PodNumber
$ad2ServerIPAddress = "10.20{0}.31.102" -f $PodNumber
$caServerIPAddress = "10.20{0}.31.110" -f $PodNumber

# Define a temporary build directory for ISOs
$buildDir = "c:\Temp\PodDeployment2"

# Location of APIC EM File from VMware's perspective
$apicEMVMWarePath = "{0}/{1}" -f $vmwareCiscoStorePath,$apicEM_IsoName

$preparationPath = "{0}\preparation" -f $buildDir
$ad1IsoImage = "{0}\{1}" -f $vmwareNFSSharePath,$ad1IsoName
$ad2IsoImage = "{0}\{1}" -f $vmwareNFSSharePath,$ad2IsoName
$caIsoImage = "{0}\{1}" -f $vmwareNFSSharePath,$caIsoName

#---------------------------------------------------------------------------------------------------------------------------------

Function Get-ScriptDirectory
{
    $Invocation = (Get-Variable MyInvocation -Scope 1).Value
    Split-Path $Invocation.MyCommand.Path
}

$scriptRoot = Get-ScriptDirectory

# Add OSCDimg to the path
# TODO : Find path from registry
$env:Path += ";C:\Program Files (x86)\Windows Kits\8.1\Assessment and Deployment Kit\Deployment Tools\amd64\oscdimg"

# Load VMware modules for PowerShell
# TODO : Find path from registry
. “C:\Program Files (x86)\VMware\Infrastructure\vSphere PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1”

. ("{0}\Tools\CopyWindowsISO.ps1" -f $scriptRoot)
. ("{0}\Tools\FormatSettingsText.ps1" -f $scriptRoot)
. ("{0}\Tools\PrepareWindowsISO.ps1" -f $scriptRoot)

#---------------------------------------------------------------------------------------------------------------------------------

Function GetPortGroup(
    $server,
    $vds,
    $portGroupName,
    $portGroupVLAN
) {
    $portGroup = Get-VDPortgroup -VDSwitch $vds -Name $portGroupName -ErrorAction SilentlyContinue
    if (!$portGroup) {
        $portGroup = New-VDPortgroup -VDSwitch $vds -Name $portGroupName -VlanId $portGroupVLAN -ErrorAction SilentlyContinue
    }

    return $portGroup
}

Function InstallServer
{
	[CmdletBinding()]
    Param (
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		$VCenterServer,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$VMwareHostName,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$VMwareDatastoreName,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		$VMwareFolder,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$VMwareVDSName,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$VMwarePortGroupName,

		[Parameter(Mandatory=$True)]
		[int]$PortGroupVLAN,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$Name,

        # VMware path to the location of the ISO file
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$ISOVMwarePath
	)

    # Get a handle to the VM host to install the VM on
    $vmwareHost = Get-VMHost -Server $VCenterServer -Name $VMwareHostName
    If (!$vmwareHost) {
        return $null
    }

    # Get a handle to the data store
    $vmwareDataStore = Get-Datastore -Server $VCenterServer -Name $VMwareDatastoreName
    Write-Host $vmwareDataStore
    If (!$vmwareDataStore) {
        return $null
    }

    # Get a handle to the VDS
    $vds = Get-VDSwitch -Server $VCenterServer -Name $dvsName
    If (!$vds) {
        return $null
    }

    # Remove any old instances of the given virtual machine
    $oldVM = Get-VM -Name $name -Location $folder -ErrorAction SilentlyContinue
    If ($oldVM) {
        Try {
            Remove-VM -VM $oldVM -Confirm:$false -DeletePermanently 
        } Catch {
            # Failed to delete old virtual machine
            return $null
        }
    }

    # Get a handle to the port group
    $createdPortGroupLocally = $False
    Try {
        $portGroup = Get-VDPortgroup -VDSwitch $vds -Name $VMwarePortGroupName -ErrorAction SilentlyContinue
        if (!$portGroup) {
            $portGroup = New-VDPortgroup -VDSwitch $vds -Name $VMwarePortGroupName -VlanId $PortGroupVLAN -ErrorAction SilentlyContinue
            $createdPortGroupLocally = $True
        }
    } Catch {
        return $null
    }

    # Create the new virtual machine instance
    Try {
        $vm = New-VM -Name $Name -Location $VMwareFolder -Datastore $vmwareDataStore -VMHost $vmwareHost -DiskStorageFormat Thin -DiskGB 40  -NumCpu 2 -MemoryGB 1
        If (!$vm) {
            Throw "Failed to create virtual machine"
        }
    } Catch {
        If ($createdPortGroupLocally -eq $True) {
            Try {
                Remove-VDPortGroup -VDPortGroup $portGroup
            } Catch {
                # Critical error, can't remove the port group which was created
                Exit
            }
        }

        return $null
    }

    # Get the SCSI controller and set the mode to VirtualLsiLogicSAS
    Try {
        $scsiController = Get-HardDisk -VM $vm | Select -First 1 | Get-ScsiController
        If (!$scsiController) {
            Throw "Failed to get handle to SCSI controller"
        }
        Set-ScsiController -ScsiController $scsiController -Type VirtualLsiLogicSAS
    } Catch {
        $vm | Remove-VM -Confirm:$false -DeletePermanently
        return $null
    }

    # Create the NIC and connected it to the infrastructure port group
    Try {
        $vNic = ($vm | New-NetworkAdapter -Portgroup $portGroup -Type Vmxnet3 -StartConnected:$true)
        If (!$vNic) {
            Throw "Failed to create new network adapter"
        }
    } Catch {
        Write-Host "Error: Can't create new network adapter"
        If ($createdPortGroupLocally -eq $True) {
            Try {
                Remove-VDPortGroup -VDPortGroup $portGroup
            } Catch {
                # Critical error, can't remove the port group which was created
                Write-Host "Critical error, can't remove the port group which was created"
                Exit
            }
        }
        Try {
            $vm | Remove-VM -Confirm:$false -DeletePermanently
        } Catch {
            # Critical error, can't remove the virtual machine which was created
            Write-Host "Critical error, can't remove the virtual machine which was created"
            Exit
        }
        return $null
    }

    # Create a new CD drive and mount the image
    Try {
        $cdDrive = ($vm | New-CDDrive -IsoPath $ISOVMwarePath -StartConnected:$true -Confirm:$false) 

        If (!$cdDrive) {
            Throw "Failed to create CD drive and mount image"
        }
    } Catch {
        Write-Host "Failed to create CD drive and mount image"
        If ($createdPortGroupLocally -eq $True) {
            Try {
                Remove-VDPortGroup -VDPortGroup $portGroup
            } Catch {
                # Critical error, can't remove the port group which was created
                Write-Host "Critical error, can't remove the port group which was created"
                Exit
            }
        }
        Try {
            $vm | Remove-VM -Confirm:$false -DeletePermanently
        } Catch {
            Write-Host "Critical error, can't remove the virtual machine which was created"
            # Critical error, can't remove the port group which was created
            Exit
        }
        return $null
    }

    # Boot the Virtual Machine
    Try {
        $vm | Start-VM 
    } Catch {
        If ($createdPortGroupLocally -eq $True) {
            Try {
                Remove-VDPortGroup -VDPortGroup $portGroup
            } Catch {
                # Critical error, can't remove the port group which was created
                Exit
            }
        }
        Try {
            $vm | Remove-VM -Confirm:$false -DeletePermanently
        } Catch {
            # Critical error, can't remove the port group which was created
            Exit
        }
        return $null
    }

    return $vm
}

Function DeployAD1
{
	[CmdletBinding()]
    Param (
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$SourceImage,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$PreparationPath,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$VMwareToolsISO,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$ServerHostName,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$IPAddress,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$GatewayIP,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$DNSServer,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$DomainName,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$NetBIOSDomain
	)

	$settingsText = FormatSettingsText `
		-ServerHostName $ServerHostName `
		-IPAddress $IPAddress `
		-GatewayIP $GatewayIP `
		-DNSServer $DNSServer `
		-DomainName $DomainName `
		-NetbiosDomain $NetBIOSDomain `
		-PrimaryActiveDirectoryServer:$True

	$ad1IsoImage = "{0}\{1}" -f $vmwareNFSSharePath,$ad1IsoName

#		-vmwareDriversPath $vmwareDriversPath `
	$result = PrepareWindowsISO `
		-SourceImage $SourceImage `
		-PreparationPath $PreparationPath `
		-DestinationISOPath $ad1IsoImage `
		-VMwareToolsISO $VMwareToolsISO `
		-SettingsText $settingsText

    If ($result -eq $False) {
        return $False
    }

    return $True
}

Function GetPodFolder(
    $server, 
    $dataCenterName
) {
    $dataCenter = Get-Datacenter -Name $dataCenterName -Server $server
    $apicLabsFolder = Get-Folder -Name "APIC Labs" -Location $dataCenter
    
    $podFolder = Get-Folder -Name $podName -Location $apicLabsFolder -ErrorAction SilentlyContinue

    If (!$podFolder) {
        $podFolder = New-Folder -Location $apicLabsFolder -Name $podName  -ErrorAction SilentlyContinue
    }

    return $podFolder
}

$result = DeployAD1 `
    -SourceImage $windowsServerIso `
    -PreparationPath $preparationPath `
    -VMwareToolsISO $vmwareToolsIso `
    -ServerHostName $ad1ServerName `
    -IPAddress $ad1ServerIPAddress `
    -GatewayIP $serverGatewayIP `
    -DNSServer $dnsServer `
    -DomainName $activeDirectoryDomainName `
    -NetBIOSDomain $netbiosDomain

If  ($result -eq $False) {
    Exit
}

$viServer = Connect-VIServer -Server $vcenterServer -User $vcenterServerUsername -Password $vcenterServerPassword
If (!$viServer) {
    return $null
}
    
$podFolder = GetPodFolder -server $viServer -dataCenterName $dataCenterName
If (!$podFolder) {
    return $null
} 

$ad1ISOVMwarePath = "{0}/{1}" -f $vmwareStorePath, $ad1IsoName

$ad1vm = InstallServer `
    -VCenterServer $viServer `
    -VMwareHostName $ad1HostName `
    -VMwareDatastoreName $ad1DatastoreName `
    -VMwareFolder $podFolder `
    -VMwareVDSName $dvsName `
    -VMwarePortGroupName $infrastructurePortGroupName `
    -PortGroupVLAN $infrastructurePortGroup `
    -Name $ad1Name `
    -ISOVMwarePath $ad1ISOVMwarePath