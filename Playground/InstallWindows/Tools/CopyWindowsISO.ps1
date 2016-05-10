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

Function CopyWindowsISO
{
	[CmdletBinding()]
    Param (
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$SourceImage,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$DestinationPath
	)
    
	# Verify the existence of the source image file and return if it doesn't exist
	If ((Test-Path -Path $SourceImage) -eq $False) {
		return $False
	}

	# Verify the existence of the destination path. If it does exist, attempt to create it
	$pathCreatedLocally = $False
	If ((Test-Path -Path $DestinationPath) -eq $false) {
		Try {
			mkdir -Path $DestinationPath -Force -Confirm:$False
			$pathCreatedLocally = $True
		} Catch {
			return $False
		}
	}

	# Attempt to mount the Windows ISO file
    $mountResult = Mount-DiskImage -ImagePath $SourceImage -PassThru
	If (!$mountResult) {
		If ($pathCreatedLocally -eq $True) {
			try {
				rmdir -Path $DestinationPath -Force -Recurse
			} Catch {
				# Catastrophic failure, abort program here
				Exit
			}
		}

		return $False
	}

	# Retrieve volume information about the disk and fail if needed
	$volume = Get-Volume -DiskImage $mountResult
	If (!$volume) {
		Dismount-DiskImage -ImagePath $SourceImage

		If ($pathCreatedLocally -eq $True) {
			try {
				rmdir -Path $DestinationPath -Force -Recurse
			} Catch {
				# Catastrophic failure, abort program here
				Exit
			}
		}
		return $False
	}

	# Attempt to copy all files from the ISO image to the destination directory
	$copyOrDismountFailed = $False
	Try {
	    $sourcePath = "{0}:\*" -f $volume.DriveLetter
		Copy-Item $sourcePath $DestinationPath -Recurse 
	} Catch {
		$copyOrDismountFailed = $True
	}

	# Attempt to dismount the image
	Try {
	    Dismount-DiskImage -ImagePath $SourceImage
	} Catch {
		$copyOrDismountFailed = $True
	}

	# If there was an error during copy or dismounting, exit the program. This was a major failure
	If ($copyOrDismountFailed -eq $True)
	{
		If ($pathCreatedLocally -eq $True) {
			# Delete the destination path if it was created locally
			rmdir -Path $DestinationPath -Force -Recurse -ErrorAction SilentlyContinue
		}

		Exit
	}
	
	return $True
}

