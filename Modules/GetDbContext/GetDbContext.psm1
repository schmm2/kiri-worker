# Connection to Cosmos DB
function Get-DbContext() {
    $primaryKey = ConvertTo-SecureString -String "$($env:CosmosDBSecureString)" -AsPlainText -Force -Verbose 
    $accountName = $env:CosmosDBAccountName
    $dbName = $env:CosmosDBName

    # Create connection to sql instance, not the specific database
    $cosmosDbContext = New-CosmosDbContext -Account $accountName -Key $primaryKey

    # Get all DBs
    $activeDatabases = Get-CosmosDbDatabase -Context $cosmosDbContext

    if($activeDatabases.id -eq $dbName){
        Write-Host "Datbase $dbName already exists"
    }else{
        Write-Host "Database $dbName does not exist yet"
        New-CosmosDbDatabase -Context $cosmosDbContext -Id $dbName
    }

    # Create connection to actual database
    $cosmosDbContext = New-CosmosDbContext -Account $accountName -Key $primaryKey -Database $dbName
    
    return $cosmosDbContext
}