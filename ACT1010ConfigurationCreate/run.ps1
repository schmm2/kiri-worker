param($configurationData)

# Get DB Context
$cosmosDbContext = Get-DbContext

# Create Item
$configurationId = $configurationData.id
$configuration = New-CosmosDbDocument -Context $cosmosDbContext -CollectionId 'configuration' -DocumentBody ($configurationData | ConvertTo-Json) -PartitionKey $configurationId    
Write-Host ("Created Configuration $($configuration.id)")

return $configuration
