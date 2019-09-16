#[CmdletBinding()]

#command line params:
#search - search string to filter monitors on.
#enabled - to change the state of the filtered monitors.
#usename - filter on the monitor name if set to true, default filter on tags.
#regex - filter with a regex if set to true, defalt filter with wildcards.
#
#exclude search and a list of available tags is returned
#include search and exclude enabled, shows list of matched monitors
#include search and set enabled (either $true or $false), change the state of the matched monitors
#
# Configuration

#token needs ReadConfiguration and WriteConfiguration permissions.

#$env = "xxx"
#$baseurl = "https://xxx/e/$env/api/v1/config"
#or
#$baseurl = "https://xxx.live.dynatrace.com/api/config/v1"

#$token = "xxx"    #needs read/write configuration permissions

# Functions

function restApiGet {
    param ([Parameter(Mandatory=$true)][string]$url)

    Write-Verbose "url [$url]"
    try { 
        $result = Invoke-WebRequest -Headers @{"Authorization"="Api-Token $token"} $url 
        if ( $result.Headers["X-RateLimit-Remaining"] = 0 ) { Write-Output $result.Headers["X-RateLimit-Reset"]; Sleep 1000 }
        $result | ConvertFrom-Json
    } 
    catch { Write-Host "Exception: \n $_ \n ${result} ${result.Headers}" } 
    return $result
}

function restApiPut {
    param ([Parameter(Mandatory=$true)][string]$url, [Parameter(Mandatory=$true)][string]$body)

    Write-Verbose "url [$url] body [$body]"
    try {
        $result = Invoke-WebRequest -Method Put -Headers @{"Content-Type"="application/json"; "Authorization"="Api-Token $token"} -Body $body $url
        $result | ConvertFrom-Json
    }
    catch { "Exception: \n $_ \n $result"+$result.Headers }

    return $result
}

function getAllDashboards {

    $url = "${baseurl}/dashboards"
    restApiGet $url | Select-Object dashboards | Select-Object -ExpandProperty dashboards | Select-Object id, name, owner

}

function getAllDashboardDetails {
    param ([Parameter(Mandatory=$true)][object]$entities)

    $dashboards =@()
    $i=0

    foreach ( $id in $entities | Select-Object dashboards -Expand Id) {
        #if ( $i -eq 50) { break } #DEBUG only get 10 monitors
        $i+=1
        $url = "${baseurl}/dashboards/${id}"
        $result = restApiGet $url
        $dashboards += $result
        Write-Host -NoNewLine "."
        if ( !($i % 80) ) { Write-Host "" }
        Sleep -Milliseconds 5
    }
    Write-Host ""
    $dashboards
    
}


# force TLS1.2 connectivity as it's now required by Dynatrace
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
. C:\Users\christopher.vidler\Documents\Git\dynatraceApiScripts\private.ps1
$token = getToken
$baseurl = getBaseURL
$baseurl = $baseurl + "api/config/v1"


""
"Dynatrce Dashboard API Script"
""

"Connecting to Dynatrace Server and retrieving all Dashboards"
$allDashboards = getAllDashboards
"Found "+$allDashboards.Count+" Dashboards"
if ( $allDashboards.Count -eq 0 ) { "No dashboards found."; break }

$details = getAllDashboardDetails($allDashboards)

""

$line = null
$dashboardlist = @()
foreach ($dashboard in $details) {
    if ($dashboard.id) { 
        $line = "" | select id,shared,link,published,name,owner
        $line.id = $dashboard.id
        $line.shared = $dashboard.dashboardMetadata.shared
        $line.link = $dashboard.dashboardMetadata.sharingDetails.linkShared
        $line.published = $dashboard.dashboardMetadata.sharingDetails.published
        $line.name = $dashboard.dashboardMetadata.name
        $line.owner = $dashboard.dashboardMetadata.owner
        $dashboardlist += $line
        $line = null
    }
}
$dashboardlist | Where owner -eq "christopher.vidler@dynatrace.com" | format-table


""
"Done"
""
