param($context)

###################################
# Variables
###################################

$output = @()
$tenantId = '1ea0c7b0-8b82-4500-8a55-2abb8980cd54' # Temp

# DB Context
$cosmosDbContext = Get-DbContext

###################################
# Functions
###################################

function Get-HashFromString {
    param (
        $string
    )

    $hash = [System.Security.Cryptography.HashAlgorithm]::Create("sha1").ComputeHash([System.Text.Encoding]::UTF8.GetBytes($string))
    $hashString = [System.BitConverter]::ToString($hash) 
    return $hashString
}

function Find-ConfigurationTypeOfConfiguration {
    param (
        $configuration,
        $url,
        $cosmosDbContext
    )
    
    if($configuration["@odata.type"]){
        # Write-Host ("oData Type: " + $configuration["@odata.type"])
        $configurationTypeName = $configuration["@odata.type"].replace("#microsoft.graph.", "");
    } else {
        # Graph Exceptions
        # Exception: Some resource do not contain a odata property (example: App Protection Policy)
        # we take the url, use the last part => resource identifier and remove the plural 's' if it exists
        $graphResourceUrlArray = $url.split('/');
        $configurationTypeName = $graphResourceUrlArray[$graphResourceUrlArray.length - 1];
        
         # remove plurar s
        if ($configurationTypeName.Substring($configurationTypeName.length - 1) -eq "s") {
            $configurationTypeName = $configurationTypeName.Substring(0,$configurationTypeName.length -1)
        }
    }

    if($configurationTypeName){
        # Write-Host "found ConfigurationType Name $configurationTypeName"

        # Query ConfigurationType from Database
        $query = "SELECT * FROM configurationType c WHERE (c.name = '$configurationTypeName')"
        $configurationType = Get-CosmosDbDocument -Context $cosmosDbContext -CollectionId 'configurationType' -Query $query -QueryEnableCrossPartition $true
    }

    return $configurationType
}

function Import-Configuration {
    param (
        $configuration,
        $tenantDbId,
        $cosmosDbContext,
        $url
    )
    $importErrors = @()

    $configurationId = $configuration.id;
    $storeNewConfigurationVersion = $false;
    $configurationObjectFromGraph = $configuration
    $configurationObjectFromGraphJSON = $configuration | ConvertTo-Json;
    
    # Deep Resolve GraphItems     
    <#$payloadGetGraphData = [PSCustomObject]@{
        'url'         = $msGraphResource.resource
        'accessToken' = $accessTokenObject.access_token
        'tokenType'   = $accessTokenObject.token_type
        'expandAttributes' =  ($msGraphResource.expandAttributes | ConvertTo-Json)
    }
    Invoke-DurableActivity -FunctionName 'ACT2001MsGraphGet' -Input $payloadGetGraphData -NoWait#>

    # Lookup configuration in Database
    $query = "SELECT * FROM configuration c WHERE (c.configurationId = '$configurationId')"
    $configurationInDb = Get-CosmosDbDocument -Context $cosmosDbContext -CollectionId 'configuration' -Query $query -QueryEnableCrossPartition $true -MaxItemCount 1
    $configurationDbId = $configurationInDb.id

    if (!$configurationDbId) {  
        Write-Host "New configuration found $configurationId"

        # Get ConfigurationType Name
        $configurationType = Find-ConfigurationTypeOfConfiguration -configuration $configurationObjectFromGraph -url $url -cosmosDbContext $cosmosDbContext
        
        if($configurationType.id){    
            Write-Host "Found configurationType $($configurationType.name)"

            # Create Mainconfiguration Object in DB
            $newConfigurationDbId = $([Guid]::NewGuid().ToString())
            $newConfiguration = @{
                id       = $newConfigurationDbId
                configurationId = $configurationId 
                tenant   = $tenantDbId
                configurationType = $configurationType.id
            }
            New-CosmosDbDocument -Context $cosmosDbContext -CollectionId 'configuration' -DocumentBody ($newConfiguration | ConvertTo-Json) -PartitionKey $newConfigurationDbId    
            $configurationDbId = $newConfigurationDbId  
            
        }  else{
            ### handle Import errors
            Write-Host "unable to proceed, no configurationType Name found"
            $importErrors += @{
                error =  "no configurationType Name found"
                config =  $configurationObjectFromGraph
            }
            continue
        }
    }
    else {
        Write-Host "Configuration already stored"
    }

    # Get newest configuration version
    $query = "SELECT * FROM configurationVersion c WHERE (c.configuration = '$configurationDbId')"
    $configurationVersions = Get-CosmosDbDocument -Context $cosmosDbContext -CollectionId 'configurationVersion' -Query $query -QueryEnableCrossPartition $true
    $newestTimeStamp = ($configurationVersions | measure-object -Property _ts -maximum).maximum
    # Filter deviceVersion, find highest timeStamp = newest configVersion
    $newestConfigurationVersionInDB = $configurationVersions | Where-Object { $_._ts -eq $newestTimeStamp }
    #Write-Host ($newestConfigurationVersionInDB | ConvertTo-Json)

    if($newestConfigurationVersionInDB){
        # Version Comparison
        # Not all configs can be compared the same
        # if the same version is already stored skp this element
        Write-Host "Existing Config Version found, compare version"

        # compare my lastModified Date
        if ($configurationObjectFromGraph.lastModifiedDateTime -and ($newestConfigurationVersionInDB.graphModifiedAt -eq $configurationObjectFromGraph.lastModifiedDateTime)) {
            Write-Host "Equal modified date, skip"
            continue;
        } # compare graph version
        elseif ($configurationObjectFromGraph.version -and ($newestConfigurationVersionInDB.graphVersion -eq $configurationObjectFromGraph.version)) {
            Write-Host "Equal Graph Version, skip"
            continue;
        } # compare hash
        else { 
            $hashString = Get-HashFromString -string $configurationObjectFromGraphJSON
            if ($hashString -eq $newestConfigurationVersionInDB.version) {
                Write-Host "Equal Version (Hash), skip"
                continue
            }
        } 
        $storeNewConfigurationVersion = $true
    }else{
            # no configuration version stored yet
            Write-Host "No configuration version stored yet"
            $storeNewConfigurationVersion = $true
    }

    # Add ConfigurationVersion  
    if($storeNewConfigurationVersion -eq $true){
        Write-Host "New Config Version found, add to database"

        $hashString = Get-HashFromString -string $configurationObjectFromGraphJSON
    
        $newConfigurationVersionDbId = $([Guid]::NewGuid().ToString())
        $newConfigurationVersion = @{
            id = $newConfigurationVersionDbId
            graphVersion = $configurationObjectFromGraph.version
            displayName =  $configurationObjectFromGraph.displayName
            graphModifiedAt =  $configurationObjectFromGraph.lastModifiedDateTime
            value =  $configurationObjectFromGraphJSON
            version = $hashString
            configuration = $configurationDbId
        }
        New-CosmosDbDocument -Context $cosmosDbContext -CollectionId 'configurationVersion' -DocumentBody ($newConfigurationVersion | ConvertTo-Json) -PartitionKey $newConfigurationVersionDbId        
    }
    else {
        Write-Host "Newest Configuration Version already stored"
    }
    

    return $importErrors
}
function Import-Device {
    param (
        $device,
        $tenantDbId,
        $cosmosDbContext
    )

    #Write-Host ($device | ConvertTo-Json)

    $deviceId = $device.id;
    $storeNewDeviceVersion = $false;
    $deviceObjectFromGraph = $device
    $deviceObjectFromGraphJSON = $device | ConvertTo-Json;
    
    $query = "SELECT * FROM device c WHERE (c.deviceId = '$deviceId')"
    $deviceInDb = Get-CosmosDbDocument -Context $cosmosDbContext -CollectionId 'device' -Query $query -QueryEnableCrossPartition $true -MaxItemCount 1
    $deviceDbId = $deviceInDb.id
    # Write-Host ($deviceInDb | ConvertTo-Json)

    # Device already store
    if (!$deviceDbId) {   
        Write-Host "New Device found $deviceId"

        # Create Main Device Object in DB
        $newDeviceDbId = $([Guid]::NewGuid().ToString())
        $newDevice = @{
            id       = $newDeviceDbId
            deviceId = $deviceId
            tenant   = $tenantDbId
        }
        New-CosmosDbDocument -Context $cosmosDbContext -CollectionId 'device' -DocumentBody ($newDevice | ConvertTo-Json) -PartitionKey $newDeviceDbId      
        $deviceDbId = $newDeviceDbId
    }
    else {
        Write-Host "Device already stored"
    }

    # Get newest device version
    $query = "SELECT * FROM deviceVersion c WHERE (c.device = '$deviceDbId')"
    $deviceVersions = Get-CosmosDbDocument -Context $cosmosDbContext -CollectionId 'deviceVersion' -Query $query -QueryEnableCrossPartition $true
    $newestTimeStamp = ($deviceVersions | measure-object -Property _ts -maximum).maximum
    # Filter deviceVersion, find highest timeStamp = newest deviceVersion
    $deviceVersion = $deviceVersions | Where-Object { $_._ts -eq $newestTimeStamp }
    #Write-Host ($deviceVersion | ConvertTo-Json)
    
    # Sort Properties to the Hash Values can be generated all the time with the same property order
    # Todo: Doenst seem to work all the time, fix in the future
    $deviceObjectFromGraphJSON  = $deviceObjectFromGraphJSON | Select-Object ($deviceObjectFromGraphJSON | Get-Member -MemberType NoteProperty).Name | ConvertTo-Json
    
    # Calcuate hash
    $hash = [System.Security.Cryptography.HashAlgorithm]::Create("sha1").ComputeHash([System.Text.Encoding]::UTF8.GetBytes($deviceObjectFromGraphJSON))
    $hashString = [System.BitConverter]::ToString($hash) 
    #Write-Host $hashString

    if ($deviceVersion.version) {
        # Compare Hash, if different store new version
        if ($hashString -ne ($deviceVersion.version)) {
            Write-Host "Hash do not match. Stored: $($deviceVersion.version), New: $hashString"
            Write-Host "Device DB Id: $($deviceVersion.device), JSON deviceid: $($deviceObjectFromGraphJSON.id)"
            # Hash value not equal, store new version
            $storeNewDeviceVersion = $true
        } 
    }
    else {
        # no device version stored yet
        Write-Host "No device version stored yet"
        $storeNewDeviceVersion = $true
    }

    if ($storeNewdeviceVersion -eq $true) {
        Write-Host "Newer Device Version found"
        $newDeviceVersionDbId = $([Guid]::NewGuid().ToString())
        
        $newDeviceVersion = @{
            id           = $newDeviceVersionDbId
            device       = $deviceDbId
            version      = $hashString
            value        = $deviceObjectFromGraphJSON
            deviceName   = $deviceObjectFromGraph.deviceName
            manufacturer = $deviceObjectFromGraph.manufacturer ? $deviceObjectFromGraph.manufacturer : ''
            operatingSystem = $deviceObjectFromGraph.operatingSystem ? $deviceObjectFromGraph.operatingSystem : ''
            osVersion = $deviceObjectFromGraph.osVersion ? $deviceObjectFromGraph.osVersion : ''
            upn = $deviceObjectFromGraph.userPrincipalName ? $deviceObjectFromGraph.userPrincipalName : ''
        }
        New-CosmosDbDocument -Context $cosmosDbContext -CollectionId 'deviceVersion' -DocumentBody ($newDeviceVersion | ConvertTo-Json) -PartitionKey $newDeviceVersionDbId      
    }
    else {
        Write-Host "Newest Version already stored"
    }

    #############################
    # Cleanup, old deviceVersions
    #############################           
    $dateTime = (Get-Date).ToUniversalTime()
    $unixTimeStamp = [System.Math]::Truncate((Get-Date -Date $DateTime -UFormat %s))

    # Calculate Threshold from before all versions should be deleted  
    $olderThanThreshold = $unixTimeStamp - 60 # 1min
    $deviceVersionsToCleanup = $deviceVersions | Where-Object { $_._ts -lt $olderThanThreshold }
    Write-Host "Cleanup, device: $deviceDbId has $($deviceVersionsToCleanup.length) deviceVersions to clean" 
    
    # Remove old docs
    foreach( $deviceVersionToCleanup in  $deviceVersionsToCleanup){
        Remove-CosmosDbDocument -Context $cosmosDbContext -CollectionId 'deviceVersion' -Id $deviceVersionToCleanup.id -PartitionKey $deviceVersionToCleanup.id   
        Write-Host "Remove deviceVersion $($deviceVersionToCleanup.id)" 
    }
}


###################################
# Create Job element
###################################

$jobId = $([Guid]::NewGuid().ToString())
$jobData = @"
{
    "id": `"$jobId`",
    "type":  "TENENAT_REFRESH",
    "state":  "STARTED",
    "tenant":  `"$tenantId`"
}
"@
$job = New-CosmosDbDocument -Context $cosmosDbContext -CollectionId 'job' -DocumentBody $jobData -PartitionKey $jobId   

# Get all Tenants
$query = "SELECT * FROM tenant c WHERE (c.tenantId = '$($tenantId)')"
$tenant = Get-CosmosDbDocument -Context $cosmosDbContext -CollectionId 'tenant' -Query $query -QueryEnableCrossPartition $true -MaxItemCount 1
if (!$tenant.id) { Write-Host "unable to find tenant in database"; return $output } else { Write-Host "found tenant $($tenant.name)" }

# Build payload 
$payloadToken = [PSCustomObject]@{
    'TenantId' = $tenantId 
    'AppId'    = $tenant.appId
}

# get access token for tenant
$accessTokenObject = Invoke-DurableActivity -FunctionName 'ACT2000MsGraphAccessTokenCreate' -Input $payloadToken
if (!$accessTokenObject) { Write-Host "unable to get token", return $output } else { Write-Host "token generated" }

###################################
# Get Graph Data
###################################

# get msGraphResources
$query = "SELECT * FROM msGraphResource"
$msGraphResources = Get-CosmosDbDocument -Context $cosmosDbContext -CollectionId 'msGraphResource' -Query $query -QueryEnableCrossPartition $true

# for each graph resource initiate handling
$parallelTasks = @()

foreach ($msGraphResource in $msGraphResources) {
    Write-Host "Handle $($msGraphResource.name)"
    
    # Get Data from Graph
    $payloadGetGraphData = [PSCustomObject]@{
        'url'         = $msGraphResource.resource
        'resourceUrl' = $msGraphResource.resource
        'accessToken' = $accessTokenObject.access_token
        'tokenType'   = $accessTokenObject.token_type
    }
    $parallelTasks += Invoke-DurableActivity -FunctionName 'ACT2001MsGraphGet' -Input $payloadGetGraphData -NoWait
}

$graphResults = Wait-ActivityFunction -Task $parallelTasks
Write-Host "Completed Initial Data gathering"

#Write-Host ($graphResults| ConvertTo-Json)

###################################
# Deep Resolve
# some data returned contains empty fields (for example deviceManagementScript -> scriptContent)
# some fields can't be queried by $expand
# solution: take each item and query it directly again -> $resource/$itemId
# with the response we can replace the existing but incomplete value from the previous query
###################################

$parallelTasksDeepResolve = @()

foreach ($graphResult in $graphResults) {
    foreach($graphItem in $graphResult.result){
        $graphItemUrl = "$($graphResult.resourceUrl)/$($graphItem.id)"

        # Get Data from Graph
        $payloadGetGraphData = [PSCustomObject]@{
            'url'         = $graphItemUrl
            'resourceUrl' = $graphResult.resourceUrl
            'accessToken' = $accessTokenObject.access_token
            'tokenType'   = $accessTokenObject.token_type
            'expandAttributes' =  ($msGraphResource.expandAttributes | ConvertTo-Json)
        }
        $parallelTasksDeepResolve += Invoke-DurableActivity -FunctionName 'ACT2001MsGraphGet' -Input $payloadGetGraphData -NoWait
    }
}

$graphResultsDeepResolve = Wait-ActivityFunction -Task $parallelTasksDeepResolve
Write-Host "Completed Deep Resolve"

# Write-Host ($graphResults | ConvertTo-Json)

###################################
# Import Data
###################################

foreach ($graphResult in $graphResultsDeepResolve) {
    switch ($graphResult.resourceUrl) {
        '/deviceManagement/managedDevices' {
            Import-Device -device $graphResult.Result -tenantDbId $tenant.id -cosmosDbContext $cosmosDbContext
            Break
        }
        Default {
            $importErrors = Import-Configuration -configuration $graphResult.Result -tenantDbId $tenant.id -cosmosDbContext $cosmosDbContext -url $graphResult.ResourceUrl
            if($importErrors.length -gt 0){
                Write-Host ($importErrors | ConvertTo-Json)
            }
            Break
        }
    }
}

Write-Host "Completed Data Import"

$output
