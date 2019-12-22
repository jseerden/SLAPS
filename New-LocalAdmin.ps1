# New-LocalUser is only available in a x64 PowerShell process. We need to restart the script as x64 bit first.
# Based on a template created by Oliver Kieselbach @ https://gist.github.com/okieselbach/4f11ba37a6848e08e8f82d9f2ffff516
$exitCode = 0

if (-not [System.Environment]::Is64BitProcess) {
    # start new PowerShell as x64 bit process, wait for it and gather exit code and standard error output
    $sysNativePowerShell = "$($PSHOME.ToLower().Replace("syswow64", "sysnative"))\powershell.exe"

    $processStartInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processStartInfo.FileName = $sysNativePowerShell
    $processStartInfo.Arguments = "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $processStartInfo.RedirectStandardError = $true
    $processStartInfo.RedirectStandardOutput = $true
    $processStartInfo.CreateNoWindow = $true
    $processStartInfo.UseShellExecute = $false

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processStartInfo
    $process.Start()

    $exitCode = $process.ExitCode

    $standardError = $process.StandardError.ReadToEnd()
    if ($standardError) {
        Write-Error -Message $standardError 
    }
}
else {
    #region Configuration
    # Define the userName for the Local Administrator
    $userName = "local-admin"

    # Azure Function Uri (containing "azurewebsites.net") for storing Local Administrator secret in Azure Key Vault
    $uri = 'https://myfunctions.azurewebsites.net/api/Set-KeyVaultSecret?code=s0mer4nd0mstr1ng/pIZPg=='
    #endregion

    # Hide the $uri (containing "azurewebsites.net") from logs to prevent manipulation of Azure Key Vault
    $intuneManagementExtensionLogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log"
    Set-Content -Path $intuneManagementExtensionLogPath -Value (Get-Content -Path $intuneManagementExtensionLogPath | Select-String -Pattern "azurewebsites.net" -notmatch)

    # start logging to TEMP in file "scriptname.log"
    $null = Start-Transcript -Path "$env:TEMP\$($(Split-Path $PSCommandPath -Leaf).ToLower().Replace(".ps1",".log"))"

    # Azure Function Request Body. Azure Function will strip the keyName and add a secret value. https://docs.microsoft.com/en-us/rest/api/keyvault/setsecret/setsecret
    $body = @"
    {
        "keyName": "$env:COMPUTERNAME",
        "contentType": "Local Administrator Credentials",
        "tags": {
            "Username": "$userName"
        }
    }
"@

    # Use TLS 1.2 connection
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # Trigger Azure Function.
    try {
        $password = Invoke-RestMethod -Uri $uri -Method POST -Body $body -ContentType 'application/json' -ErrorAction Stop
    }
    catch {
        Write-Error "Failed to submit Local Administrator configuration. StatusCode: $($_.Exception.Response.StatusCode.value__). StatusDescription: $($_.Exception.Response.StatusDescription)"
    }

    # Convert password to Secure String
    $securePassword = ConvertTo-SecureString $password -AsPlainText -Force

    # Create a new Local User, change the password if it already exists.
    try {
        New-LocalUser -Name $userName -Password $securePassword -PasswordNeverExpires:$true -AccountNeverExpires:$true -ErrorAction Stop
    }
    catch {
        # If it already exists, catch it and continue.
        if ($_.CategoryInfo.Reason -eq 'UserExistsException') {
            Write-Output "Local Admin '$userName' already exists. Changing password."
            $userExists = $true
        }
        else {
            $exitCode = -1
            Write-Error $_
        }
    }

    if ($userExists) {
        # Change the password of the Local Administrator
        try {
            Set-LocalUser -Name $userName -Password $securePassword
        }
        catch {
            $exitCode = -1
            Write-Error $_
        }
    } 
    else {
        # Add the new Local User to the Local Administrators group
        try {
            Add-LocalGroupMember -SID 'S-1-5-32-544' -Member $userName
            Write-Output "Added Local User '$userName' to Local Administrators Group"
        }
        catch {
            $exitCode = -1
            Write-Error $_
        }
    }

    $null = Stop-Transcript
}

exit $exitCode