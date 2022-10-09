using namespace System.Net

param($payload)

# Variables
$graphBaseUrl = "https://graph.microsoft.com/beta"
$url = "$graphBaseUrl$($payload.url)"
$accessToken = $payload.accessToken
$tokenType = $payload.tokenType
$queryResults = @()  # Create an empty array to store the result.
$resourceUrl = $payload.resourceUrl

# Expand Attributes
if($payload.expandAttributes) {
    $expandAttributes = $payload.expandAttributes | ConvertFrom-Json
    $url = $url + "?`$expand="

    foreach($expandAttribut in $expandAttributes){
        $url = $url + $expandAttribut + ","
    }
}

# Safe Url for return value
$queryUrl = $url

# Build Header
$Header = @{
    Authorization = "$tokenType $accessToken"
}

# Get Data
try {  
    do {
        $results = Invoke-RestMethod -Headers $Header -Uri $url -UseBasicParsing -Method "GET" -ContentType "application/json"
        
        if ($results.PSobject.Properties.name -contains "value") {
            # Value property exist add elements to Result Array
            $queryResults += $results.value
        }else {
            # Value property does not exist, return entire result 
            $queryResults = $results
        }
        $url = $results.'@odata.nextlink'
    } until (!($url))
}
catch {
    Write-Host $Error[0]
    Write-Warning "unable to query Graph Data";
    Write-Warning "url: $url";
}

$response = @{
    result = $queryResults
    url = $queryUrl
    resourceUrl = $resourceUrl
}

return $response