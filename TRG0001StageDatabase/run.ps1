using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

Write-Host "TRG0001StageDatabase: start"

##################################
# Create Database Collections
##################################

$cosmosDbContext = Get-DbContext

$collectionsToCreate = @('configuration', 'configurationType', 'configurationVersion', 'job', 'msGraphResource', 'device', 'deviceVersion', 'deviceWarranty', 'tenant', 'deployment')
$existingCollections = Get-CosmosDbCollection -Context $cosmosDbContext

foreach ($collectionToCreate in $collectionsToCreate) {
    if ($existingCollections.id -eq $collectionToCreate) {
        Write-Host "$collectionToCreate already exists"
    }
    else {
        Write-Host "$collectionToCreate not found, create now"
        New-CosmosDbCollection -Context $cosmosDbContext -Id $collectionToCreate -PartitionKey 'id' 
    }
}

##################################
# Fill Default Values
##################################

$msGraphResources = Get-Content "static\msgraphresources.json" | ConvertFrom-Json
Write-Host "loaded $($msGraphResources.length) graph resources from file"

$newMsGraphResources = 0
$newConfigurationTypes = 0

foreach($msGraphResource in $msGraphResources){
    $msGraphResourceDbId = $null
    $query = "SELECT * FROM msGraphResource c WHERE (c.name = '$($msGraphResource.name)')"
    $docs = Get-CosmosDbDocument -Context $cosmosDbContext -CollectionId 'msGraphResource' -Query $query -QueryEnableCrossPartition $true -MaxItemCount 1
    
    # resource does already exist
    if($docs.length -gt 0){
        Write-Host "msGraphResource $($msGraphResource.name) already exists"
        $msGraphResourceDbId = $docs[0].id
    }else{
        Write-Host "msGraphResource $($msGraphResource.name) not found"

        $id = $([Guid]::NewGuid().ToString())

        # Todo: Find a better way to escape the data
        $msGraphResourceCreated = @"
        {
            `"id"`: `"$id`",
            `"name`": `"$($msgraphResource.name)`",
            `"resource`": `"$($msgraphResource.resource)`",
            `"version`": `"$($msgraphResource.version)`",
            `"category`": `"$($msgraphResource.category ? $msgraphResource.category : "configuration")`",
            `"expandAttributes`": [$($msgraphResource.expandAttributes ? ($msgraphResource.expandAttributes | ConvertTo-Json): "")],
            `"transformRulesCreate`": [$($msgraphResource.transformRulesCreate ? ($msgraphResource.transformRulesCreate | ConvertTo-Json) : "")],
            `"transformRulesPatch`": [$($msgraphResource.transformRulesPatch ? ($msgraphResource.transformRulesPatch | ConvertTo-Json): "")],
            `"nameAttribute`": `"$($msgraphResource.nameAttribute ? $msgraphResource.nameAttribute : "displayName")`"
          }
"@
        try{
            $newMsGraphResource = New-CosmosDbDocument -Context $cosmosDbContext -CollectionId 'msGraphResource' -DocumentBody $msGraphResourceCreated -PartitionKey $id   
            $msGraphResourceDbId = $newMsGraphResource.id
            $newMsGraphResources++
        }catch{
            Write-Error "Unable to create object in db"
            Write-Host $msGraphResourceCreated
        }
    }

    foreach($configurationType in $msGraphResource.configurationTypes){
        $query = "SELECT * FROM configurationType c WHERE (c.name = '$($configurationType.name)')"
        $docs = Get-CosmosDbDocument -Context $cosmosDbContext -CollectionId 'configurationType' -Query $query -QueryEnableCrossPartition $true -MaxItemCount 1
        
        if($docs.length -gt 0){
            Write-Host "configurationtype $($configurationType.name) already exists"
        }else{
            Write-Host "configurationtype$($configurationType.name) not found"

            $id = $([Guid]::NewGuid().ToString())

            $configurationTypeCreated = @"
            {
                `"id`": `"$id`",
                `"name`": `"$($configurationType.name)`",
                `"platform`": `"$($configurationType.platform)`",
                `"category`": `"$($configurationType.category)`",
                `"msGraphResource`": `"$msGraphResourceDbId`"
            }
"@
            New-CosmosDbDocument -Context $cosmosDbContext -CollectionId 'configurationType' -DocumentBody $configurationTypeCreated -PartitionKey $id   
            $newConfigurationTypes++
        }
    }
}


$body = @"
{
    "newConfigurationTypes": $newConfigurationTypes,
    "newMsGraphResources": $newMsGraphResources
}
"@

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body       = $body
})