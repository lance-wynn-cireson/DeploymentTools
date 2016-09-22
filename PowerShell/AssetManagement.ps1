﻿function Create-RemoteSession($machineHostName, $machineUserName, $machinePassword){
    $password = ConvertTo-SecureString –String $machinePassword –AsPlainText -Force
    $credential = New-Object –TypeName "System.Management.Automation.PSCredential" –ArgumentList $machineUserName, $password
    $SessionOptions = New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck
    $targetMachine = "https://${machineHostName}:5986"
    return New-PSSession -ConnectionUri $targetMachine -Credential $credential –SessionOption $SessionOptions
}

function Ready-DeploymentEnvironment([hashtable]$deploymentVariables){
    $session = Create-RemoteSession $deploymentVariables.targetMachineHostName $deploymentVariables.targetMachineUserName $deploymentVariables.targetMachinePassword
    Invoke-Command -Session $session -ScriptBlock{ 
        $ErrorActionPreference = "Stop"
        $deploymentToolsPath = "c:\DeploymentTools"
        $onDeploymentVariables = $Using:deploymentVariables
        
        if((Test-Path $deploymentToolsPath) -ne $true){
            New-Item $deploymentToolsPath -ItemType Directory
        }else{
            Remove-Item -Path "$deploymentToolsPath\*" -Recurse -Force
        }

        Get-ChildItem $deploymentToolsPath
  
        function DownloadFile([System.Uri]$uri, $destinationDirectory){
            $fileName = $uri.Segments[$uri.Segments.Count-1]
            $destinationFile = Join-Path $destinationDirectory $fileName

            "Downloading $uri to $destinationFile"

            $webclient = New-Object System.Net.WebClient
            $webclient.DownloadFile($uri,$destinationFile)
        }

        $userRights = [System.Uri]"https://raw.githubusercontent.com/Cireson/DeploymentTools/master/PowerShell/UserRights.ps1"
        $utility = [System.Uri]"https://raw.githubusercontent.com/Cireson/DeploymentTools/master/PowerShell/Utility.ps1"
        $amComponents = [System.Uri]"https://raw.githubusercontent.com/Cireson/DeploymentTools/master/PowerShell/AssetManagement-Components.ps1"

        DownloadFile -uri $userRights -destinationDirectory $deploymentToolsPath
        DownloadFile -uri $utility -destinationDirectory $deploymentToolsPath
        DownloadFile -uri $amComponents -destinationDirectory $deploymentToolsPath
    }
}

function Ready-TargetEnvironment([hashtable]$deploymentVariables){
    $session = Create-RemoteSession $deploymentVariables.targetMachineHostName $deploymentVariables.targetMachineUserName $deploymentVariables.targetMachinePassword
    Invoke-Command -Session $session -ScriptBlock{ 
        $ErrorActionPreference = "Stop"
        $onDeploymentVariables = $Using:deploymentVariables

        $deploymentToolsPath = "c:\DeploymentTools"
        $rootDirectory = "c:\AmRoot"
        
        Import-Module "$deploymentToolsPath\Utility.ps1"
        Import-Module "$deploymentToolsPath\UserRights.ps1"
        Import-Module "$deploymentToolsPath\AssetManagement-Components.ps1"

        Get-PowerShellVersion

        Create-DestinationDirectories -root $rootDirectory -targetVersion $onDeploymentVariables.targetVersion

        $adminConnectionString = Create-PlatformConnectionString -sqlServer $onDeploymentVariables.azureSqlServerName -sqlDatabase $onDeploymentVariables.azureSqlDatabase -sqlUserName $onDeploymentVariables.azureSqlAdministratorUserName -sqlPassword $onDeploymentVariables.azureSqlAdministratorPassword
        $connectionString = Create-PlatformConnectionString -sqlServer $onDeploymentVariables.azureSqlServerName -sqlDatabase $onDeploymentVariables.azureSqlDatabase -sqlUserName $onDeploymentVariables.azureSqlUserName -sqlPassword $onDeploymentVariables.azureSqlUserPassword
        $targetDirectory = Create-TargetDirectory $rootDirectory $onDeploymentVariables.targetVersion

        Create-ContainedDatabaseUser -connectionString $adminConnectionString -sqlServiceUserName $onDeploymentVariables.azureSqlUserName -sqlServiceUserPassword $onDeploymentVariables.azureSqlUserPassword

        Remove-RunningService -serviceName "Platform_AM"

        Create-InboundFirewallRule "Http 80" "80"
        Create-InboundFirewallRule "Https 443" "443"

        Create-ServiceUser -serviceUserName $onDeploymentVariables.serviceUserName -servicePassword $onDeploymentVariables.serviceUserPassword

        Download-Platform -baseDirectory $rootDirectory -platformVersion $onDeploymentVariables.platformVersion -targetDirectory $targetDirectory

        Update-PlatformConfig -targetDirectory $targetDirectory -connectionString $connectionString
    }
}