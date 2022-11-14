param($jobData)

# Get DB Context
$cosmosDbContext = Get-DbContext

# Create Job Item
$jobId = $jobData.id
$job = New-CosmosDbDocument -Context $cosmosDbContext -CollectionId 'job' -DocumentBody ($jobData | ConvertTo-Json) -PartitionKey $jobId   
Write-Host ("Created Job $($job.id)")

return $job
