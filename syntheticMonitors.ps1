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
# in private.ps1 include 
# - $token = API token, and 
# - $baseurl = https://xxx.live.dynatrace.com/ (SaaS) or https://fqdn/e/xxx/ (Managed)


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

function getAllMonitors {

    $url = "${baseurl}/monitors"
    restApiGet $url | Select-Object monitors | Select-Object -ExpandProperty monitors | Select-Object entityId, type, enabled, name

}

function getAllMonitorDetails {
    param ([Parameter(Mandatory=$true)][object]$entities)

    $monitors =@()
    $i=0

    foreach ( $monitorId in $entities | Select-Object entityId -Expand entityId) {
        #if ( $i -eq 50) { break } #DEBUG only get 10 monitors
        $i+=1
        $url = "${baseurl}/monitors/${monitorId}"
        $result = restApiGet $url
        $monitors += $result
        Write-Host -NoNewLine "."
        if ( !($i % 80) ) { Write-Host "" }
        Sleep -Milliseconds 5
    }
    Write-Host ""
    $monitors
}

function getAllTags {
    param ([Parameter(Mandatory=$true)][object]$monitors)

    return @( $monitors | Select-Object -Expand tags | Select-Object @{name="tag";expression={$_.key}} -Unique | Sort-Object -Property tag )

}

function filterMonitors { 
    param ([Parameter(Mandatory=$true)][object]$monitors, [Parameter(Mandatory=$true)][string]$filter, [Parameter(Mandatory=$true)][boolean]$usename=$false, [Parameter(Mandatory=$true)][boolean]$regex=$false)

    if ( -not $usename -and -not $regex ) {
        return @( $monitors | Where-Object { $_.tags.key -Like $filter} | Select-Object | Sort-Object -Property name )
    } elseif ( $usename -and -not $regex ) {
        return @( $monitors | Where-Object { $_.name -Like $filter} | Select-Object | Sort-Object -Property name )
    } elseif ( -not $usename -and $regex ) {
        return @( $monitors | Where-Object { $_.tags.key -Match $filter} | Select-Object | Sort-Object -Property name )
    } elseif ( $usename -and $regex ) {
        return @( $monitors | Where-Object { $_.name -Match $filter} | Select-Object | Sort-Object -Property name )
    } 

}

function getTagFilter {
    param ([Parameter(Mandatory=$true)][object]$allTags, [Parameter(Mandatory=$true, HelpMessage={Write-Output "Select a tag from: ${allTags}"})][string]$tag)

    if ( -not $allTags -Like $tag ) {
        throw [System.Data.ObjectNotFoundException]::New("Tag not found: $tag")
    } 
    
    return $tag

}

function changeMonitor {
    param ([Parameter(Mandatory=$true)][object]$monitor, [Parameter(Mandatory=$true)][boolean]$enabled=$True)

    $url = "${baseurl}/monitors/"+$monitor.entityId

    #change the enabled state
    $monitor.enabled = $enabled

    #grab the existing tags object
    $tags = $monitor.tags

    #remove the objects we don't need/can't send in a PUT
    $monitor = $monitor | Select-Object -Property * -ExcludeProperty entityId, createdFrom, anomalyDetection, managementZones, requests, automaticallyAssignedApps
    
    #re-init the tags object as a blank array (PUT method and GET response format the tags differently :(
    $monitor.tags = [string[]]@()
    #re-populate the tags array with the key names fom the previously saved object.
    foreach ($tag in $tags) {
        $monitor.tags += $tag.key
    }

    $body = $monitor | ConvertTo-Json -Depth 10
    restApiPut $url $body

}

function changeMonitors {
    param ([Parameter(Mandatory=$true)][object]$monitors, [Parameter(Mandatory=$true)][boolean]$enabled=$True)

    foreach ($monitor in $monitors) {

        if ( $monitor.enabled -ne $enabled ) {

            changeMonitor $monitor $enabled
            $monitor.name + " now $enabled."
            Sleep -Milliseconds 5

        } else {

            $monitor.name + " already $enabled, no change needed"

        }

    }

}



# force TLS1.2 connectivity as it's now required by Dynatrace
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

#start of main code
. C:\Users\christopher.vidler\Documents\Git\dynatraceApiScripts\private.ps1
$token = getToken
$baseurl = getBaseURL
$baseurl = $baseurl + "api/v1/synthetic"


#parse parameters
Write-Verbose "search [$search] usename [$usename] regex [$regex] enabled [$enabled]"
if (($search -eq $null) -or ($search -eq "")) { $search = $null }
if ($regex -eq $null) { $regex = $false }
if ($usename -eq $null) { $usename = $false }
if ($usename -eq $true) { $searchscope = "name" } else { $searchscope = "tag"}
if ($regex -eq $true) { $searchtype = "regex" } else { $searchtype = "wildcard"}


"Connecting to Dynatrace Server and retrieving all Synthetic monitors"
$allMonitors = getAllMonitors
"Found "+$allMonitors.Count+" Synthetic monitors"
if ( $allMonitors.Count -eq 0 ) { break }
""
"Connecting to Dynatrace Server and retrieving details on all Synthetic monitors - this'll take a while"
$allMonitorDetails = getAllMonitorDetails $allMonitors

if ($search -eq $null) {
    # search is undefined, report list of available tags and quit.
    ""
    "All unique tags:"
    $allTags = getAllTags $allMonitorDetails | Select-Object -ExpandProperty tag
    Write-Output $allTags
    ""
    break
} else {

    $tagFilter = getTagFilter $allTags $search

    ""
    "Filtering ${searchscope}s on '${tagfilter}' using ${searchtype}:"
    $filteredMonitors = filterMonitors $allMonitorDetails $tagfilter $usename $regex | Select-Object
    Write-Output $filteredMonitors | Select-Object name, enabled
    ""
    
    if ( $filteredMonitors -eq $null ) {

        "No matching synthetic monitors found. Aborting"
        break

    } elseif ( $enabled -ne $null ) {

        ""
        "Changing state on " + $filteredMonitors.Count + " Synthetic monitors"
        changeMonitors $filteredMonitors $enabled
        ""

    } elseif ( $enabled -eq $null ) {
        "No action taken."
    }

}

""
"Done"
""
