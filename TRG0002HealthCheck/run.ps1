using namespace System.Net

# Input bindings are passed in via param block.
param($request, $triggerMetadata)

# Variables
$keyVaultName = $($env:KeyVaultName)

# Build response message
$responseMessage = [PSCustomObject]@{ 
    backendApi = @{
        status  = $true;
        message = "Health check triggered in backend";
    }
    keyvault   = @{
        status  = $false;
        message = "";
    }
    database   = @{
        status  = $false;
        message = "";
    }
}

# Check KeyVault

try{
    $secrets = Get-AzKeyVaultSecret -VaultName $keyVaultName
    $responseMessage.keyvault.status = $true
    $responseMessage.keyvault.message = "found $($secrets.length) secrets in db"
}
catch{
    console.log("TRG0002HealthCheck", "unable to access keyvault")
    $responseMessage.database.message = "unable to access keyvault"
}

# Check Database Connection 
$cosmosDbContext = Get-DbContext

try {    
    $collections = Get-CosmosDbCollection -Context $cosmosDbContext
    $responseMessage.database.status = $true
    $responseMessage.database.message = "found $($collections.length) collections in db"
}
catch {
    console.log("TRG0002HealthCheck", "unable to access db")
    $responseMessage.database.message = "unable to access db"
}


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body       = $responseMessage | ConvertTo-Json
})