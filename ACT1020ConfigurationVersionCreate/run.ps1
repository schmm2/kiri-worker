param($configurationVersionData)

# Get DB Context
$cosmosDbContext = Get-DbContext

# Create Item
$configurationVersionId = $configurationVersionData.id
$configurationVersion = New-CosmosDbDocument -Context $cosmosDbContext -CollectionId 'configuration' -DocumentBody ($configurationVersionData | ConvertTo-Json) -PartitionKey $configurationVersionId    
Write-Host ("Created Configuration $($configurationVersion.id)")

return $configuration
