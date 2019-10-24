# Serverless Local Administrator Password Solution (SLAPS)

## New-LocalAdmin.ps1
Script that needs to be deployed (in SYSTEM context) to Windows 10 Clients.

## Set-KeyVaultSecret.ps1
Script for Azure Functions App v2

**HTTP Method:** POST

**Example Request Body:**
```json
{
    "keyName": "TEST-PC01",
    "contentType": "Local Administrator Credentials",
    "tags": {
        "Username": "localadmin"
    }
}
```