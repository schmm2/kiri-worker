# Connection to Cosmos DB
function Get-DbContext() {
    $primaryKey = ConvertTo-SecureString -String "$($env:CosmosDBSecureString)" -AsPlainText -Force -Verbose 
    $accountName = $env:CosmosDBAccountName
    $dbName = $env:CosmosDBName

    $cosmosDbContext = New-CosmosDbContext -Account $accountName -Database $dbName -Key $primaryKey

    return $cosmosDbContext
}