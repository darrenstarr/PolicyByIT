$apicEMServer = "10.209.31.103"
$apicEMUsername = "admin"
$apicEMPassword = "C1sco12345"

#----------------------------------------------------------------------------
$ticketURL = "https://{0}/api/v1/ticket" -f $apicEMServer
$ticketRequest = "{ `"username`": `"" + $apicEMUsername + "`", `"password`": `"" + $apicEMPassword +"`" }" 


$getHostURL = "https://" + $apicEMServer + "/api/v1/host?hostIp={0}" 
$getNetworkDeviceURL = "https://" + $apicEMServer + "/api/v1/network-device/{0}" 

function Get-IPAddress {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$True)]
        [ValidateNotNullOrEmpty()]
        [string]$HostName
    )
    Try {
        $a = [System.Net.Dns]::GetHostEntry($HostName) 
    } Catch {
        return $null
    }

    If ($a) {
        ($IPs = $a.AddressList | Foreach {$_.IPAddressToString}) | Where { -Not $_.Contains(":") } | sort @{Expression={[Version]$_}} -unique 
    } Else {$null}
}

$Computers =  Get-ADComputer  -Filter {(enabled -eq "true") } 

$result = Invoke-RestMethod -Uri $ticketURL  -Body $ticketRequest -Method Post -ContentType "application/json"
$ticket = $result.response.serviceTicket

ForEach ($computer in $Computers) {
    $addresses = Get-IPAddress -HostName $computer.DNSHostName
    If (!$addresses -or $address.Length -eq 0) {
        Continue
    }

    Write-Host ("Computer : {0} ({1})" -f $computer.Name, $computer.DNSHostName)
    ForEach ($address in $addresses) {
        If($address.Contains(":")) {
            Continue
        }
        
        $getHostResult = Invoke-RestMethod -Uri ($getHostURL -f $address) -Header @{"X-Auth-Token" = $ticket}  -ContentType "application/json"
        If($getHostResult.Response.Count -gt 0) {
            ForEach ($hostDevice in $getHostResult) {
                If ($hostDevice.response.Count -eq 0) {
                    continue
                }

                $getNetworkDeviceResult = Invoke-RestMethod -Uri ($getNetworkDeviceURL -f $hostDevice.response[0].connectedNetworkDeviceId) -Header @{"X-Auth-Token" = $ticket}  -ContentType "application/json"

                If (!$getNetworkDeviceResult -or $getNetworkDeviceResult.response.Count -eq 0) {
                    $networkDeviceName = "<unknown>"
                } Else {
                    $networkDeviceName = $getNetworkDeviceResult.response[0].hostName
                }

                Write-Host ("IP Address : {0} is located on {1} and connected to interface {2}" -f $address, $networkDeviceName, $hostDevice.connectedInterfaceName)
            }
        } Else {
            Write-Host ("   IP - {0} not found" -f $address)
        }
    }
}

