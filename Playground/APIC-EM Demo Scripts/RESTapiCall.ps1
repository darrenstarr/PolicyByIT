add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

$ipToFind = "10.205.265.2"

$result = Invoke-RestMethod -Uri "https://10.209.31.103/api/v1/ticket"  -Body '{ "username": "admin", "password": "C1sco12345" }' -Method Post -ContentType "application/json"

$ticket = $result.response.serviceTicket

$result = Invoke-RestMethod -Uri ("https://10.209.31.103/api/v1/host?hostIp={0}" -f $ipToFind) -Header @{"X-Auth-Token" = $ticket}  -ContentType "application/json"

$response = $result.response

$result = Invoke-RestMethod -Uri ("https://10.209.31.103/api/v1/network-device/{0}" -f $response.connectedNetworkDeviceId) -Header @{"X-Auth-Token" = $ticket}  -ContentType "application/json"


Write-Host ("IP Address : {0} is located on {1} and connected to interface {2}" -f $ipToFind, $result.response[0].hostName, $response.connectedInterfaceName)