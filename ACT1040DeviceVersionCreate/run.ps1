param($deviceVersionData)

# Get DB Context
$cosmosDbContext = Get-DbContext

# Create Item
$deviceVersionDataId = $deviceVersionData.id
$deviceVersion = New-CosmosDbDocument -Context $cosmosDbContext -CollectionId 'deviceVersion' -DocumentBody ($deviceVersionData | ConvertTo-Json) -PartitionKey $deviceVersionDataId    
Write-Host ("Created Device $($deviceVersion.id)")

return $deviceVersion
