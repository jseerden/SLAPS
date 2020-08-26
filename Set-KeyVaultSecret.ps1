using namespace System.Net

param(
    [Parameter(Mandatory = $true)]
    $Request
)

$keyVaultName = "srdnkeyvault01"

# Azure Key Vault resource to obtain access token
$vaultTokenUri = 'https://vault.azure.net'
$apiVersion1 = '2019-08-01'
$apiVersion2 = '7.0'

# Get Azure Key Vault Access Token using the Function's Managed Service Identity
$authToken = Invoke-RestMethod -Method Get -Headers @{"X-IDENTITY-HEADER"="$env:IDENTITY_HEADER"} -Uri $($env:IDENTITY_ENDPOINT + "?resource=$vaultTokenUri&api-version=$apiVersion1")

# Use Azure Key Vault Access Token to create Authentication Header
$authHeader = @{ Authorization = "Bearer $($authToken.access_token)" }

# Generate a random password
function New-Password {
    $alphabets = 'a,b,c,d,e,f,g,h,i,j,k,m,n,p,q,r,t,u,v,w,x,y,z'
    $numbers = 2..9
    $specialCharacters = '!,@,#,$,%,&,*,?,+'
    $array = @()
    $array += $alphabets.Split(',') | Get-Random -Count 10
    $array[0] = $array[0].ToUpper()
    $array[-1] = $array[-1].ToUpper()
    $array += $numbers | Get-Random -Count 3
    $array += $specialCharacters.Split(',') | Get-Random -Count 3
    ($array | Get-Random -Count $array.Count) -join ""
}

$password = New-Password

# Generate a new body to set a secret in the Azure Key Vault
$body = $request.body | Select-Object -Property * -ExcludeProperty keyName

# Append the random password to the new body
$body | Add-Member -NotePropertyName value -NotePropertyValue "$password"

# Convert the body to JSON
$body = $body | ConvertTo-Json

# Azure Key Vault Uri to set a secret
$vaultSecretUri = "https://$keyVaultName.vault.azure.net/secrets/$($request.Body.keyName)/?api-version=$apiVersion2"

# Set the secret in Azure Key Vault
$null = Invoke-RestMethod -Method PUT -Body $body -Uri $vaultSecretUri -ContentType 'application/json' -Headers $authHeader -ErrorAction Stop

# Return the password in the response
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    Body = $password
})
