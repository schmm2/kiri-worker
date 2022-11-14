using namespace System.Net

param($payload)

Write-Host $payload

##### Variables
$tenantId = $payload.TenantId
$secretName = $payload.AppId
$keyVaultName = $($env:KeyVaultName)
$api = "https://graph.microsoft.com"

# test Keyvault

if (!$keyVaultName) {
    Write-Host "keyvault name undefined";
    return
}
else {
    Write-Host "KeyVault: $keyVaultName";
}


Write-Host "Getting secret: $secretName from key vault: $keyVaultName"

try {
    $secret = Get-AzKeyVaultSecret -VaultName $keyVaultName -SecretName $secretName -AsPlainText -ErrorAction Stop
    
    try {
        # Get AAD Token
        $response = Invoke-RestMethod -Uri https://login.microsoftonline.com/$($tenantId)/oauth2/token `
            -Method Post `
            -Body "grant_type=client_credentials&client_id=$SecretName&client_secret=$secret&resource=$api"

        $token = @{token_type = $Response.token_type; access_token = $response.access_token }
        Write-Host "Token found"
    }
    catch {
        Return 'unable to generate token'
        Write-Host $Error[0]
    }
}
catch {
    Write-Host "unable to retrive secret"
    Write-Host $Error[0]
}

return $token
