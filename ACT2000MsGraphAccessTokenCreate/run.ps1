using namespace System.Net

param($Payload)

##### Variables

$TenantId = $Payload.TenantId
$SecretName = $Payload.AppId
$KeyVaultName = $($env:KeyVaultName)
$API = "https://graph.microsoft.com"

# test Keyvault

if (!$KeyVaultName) {
    Write-Host "keyvault name undefined";
    return
}
else {
    Write-Host "KeyVault: $KeyVaultName";
}


Write-Host "Getting secret: $SecretName from key vault: $KeyVaultName"

try {
    $secret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -SecretName $SecretName -AsPlainText
    
    try {
        # Get AAD Token
        $Response = Invoke-RestMethod -Uri https://login.microsoftonline.com/$($TenantId)/oauth2/token `
            -Method Post `
            -Body "grant_type=client_credentials&client_id=$SecretName&client_secret=$secret&resource=$API"

        $Token = @{token_type = $Response.token_type; access_token = $Response.access_token }
        Write-Host "Token found $($Token.access_token)"
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

return $Token
