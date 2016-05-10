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

Function PrepareWindowsISO
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
		[string]$DestinationISOPath,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$VMwareToolsISO,

#		[Parameter(Mandatory=$True)]
#		[ValidateNotNullOrEmpty()]
#		[string]$vmwareDriversPath,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$SettingsText
	)

    $windowsImagePath = "{0}\image" -f $PreparationPath

    $bootWim = ("{0}\SOURCES\boot.wim" -f $windowsImagePath)
    $installWim = ("{0}\SOURCES\install.wim" -f $windowsImagePath)
    $etfsBoot = ("{0}\boot\etfsboot.com" -f $windowsImagePath)

	# If the preparation path pre-exists, remove it and start clean
	If ((Test-Path $PreparationPath) -eq $True) {
		Try {
		    rmdir $PreparationPath -force -Recurse -Confirm:$False
		} Catch {
			# Catastrophic failed to remove the pre-existing preparation path
			Throw "Failed to remove pre-existing preparation path"
		}
	}

	# Create the root preparation path
	Try {
		mkdir $PreparationPath -force -Confirm:$False
	} Catch {
		return $False
	}

	# Copy the files from the ISO image 
	If ((CopyWindowsISO -sourceImage $SourceImage -destinationPath $windowsImagePath) -eq $False) {
		# Failed to copy the Windows ISO image to the image path
		return $False
	}

	$errorState = $False
	Try {
	    Set-ItemProperty $bootWim -name IsReadOnly -value $false
    } Catch {
		# Failed to remove the Read Only property from the boot.wim file on the ISO.
		$errorState = $True
	}

    # Make VMware drivers available from the Windows PE environment
    #Write-Host "Mounting boot image : " $bootWim
    #$bootImageMountPath = "{0}\bootImageMount" -f $PreparationPath
    #mkdir $bootImageMountPath -force
    #Mount-WindowsImage -ImagePath:$bootWim -Index:1 -Path:$bootImageMountPath
    #Add-WindowsDriver -Driver ("{0}\vmxnet3" -f $vmwareDriversPath) -Path $bootImageMountPath
    #Add-WindowsDriver -Driver ("{0}\pvscsi" -f $vmwareDriversPath) -Path $bootImageMountPath
    #Dismount-WindowsImage -Path:$bootImageMountPath -Save

	# Create the autounattend.xml file in the root of the disc image
	If ($errorState -eq $False)
	{
		Try {
			Copy-Item "C:\inetpub\wwwroot\FileShare\Course Files\autotemplate.xml" ("{0}\autounattend.xml" -f $windowsImagePath)
		} Catch {
			$errorState = $True
		}
	}

	# Copy the automated configuration script to the root of the new image    
	If ($errorState -eq $False)
	{
		Try {
			Copy-Item ("{0}\Templates\ConfigureServer.ps1" -f $scriptRoot) ("{0}\configure.ps1" -f $windowsImagePath)
		} Catch {
			$errorState = $True
		}
	}

	# Copy the settings text to the root of the image  
	If ($errorState -eq $False)
	{
		Try {
		    $SettingsText | Set-Content ("{0}\settings.ps1" -f $windowsImagePath)
		} Catch {
			$errorState = $True
		}
	}

    # Mount VMware ISO and copy setup64.exe
	If ($errorState -eq $False)
	{
		Try {
			# Mount the VMware tools ISO image
		    $mountResult = Mount-DiskImage -ImagePath $VMwareToolsISO -PassThru
			If (!$mountResult) {
				throw "Failed to mount"
			}

			# Get the drive letter of the mounted ISO
			$driveLetter = (Get-Volume -DiskImage $mountResult).DriveLetter

			# Copy the setup64.exe file to the root of the Windows image path
			Try {
				$sourcePath = "{0}:\setup64.exe" -f $driveLetter
				Copy-Item $sourcePath $windowsImagePath -Recurse
			} Catch {
				$errorState = $true
			}

			Dismount-DiskImage -ImagePath $VMwareToolsISO
		} Catch {
			$errorState = $True
		}
	}

	# Create a new ISO file to boot
	If ($errorState -eq $False)
	{
		Try {
			oscdimg "-n" "-h" "-m" ("-b{0}" -f $etfsBoot) $windowsImagePath $DestinationISOPath
		} Catch {
			$errorState = $True
		}
	}

	Try {
		rmdir $PreparationPath -force -Recurse -Confirm:$False
	} Catch {
		# Catastrophic failed to remove the pre-existing preparation path
		Throw "Failed to remove preparation path"
	}

    If ($errorState -eq $True) {
        return $False
    }

    return $True
}

