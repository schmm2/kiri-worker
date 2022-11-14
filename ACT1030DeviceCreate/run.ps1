param($deviceData)

# Get DB Context
$cosmosDbContext = Get-DbContext

# Create Item
$deviceDataId = $deviceData.id
$device = New-CosmosDbDocument -Context $cosmosDbContext -CollectionId 'device' -DocumentBody ($deviceData | ConvertTo-Json) -PartitionKey $deviceDataId    
Write-Host ("Created Device $($device.id)")

return $device
