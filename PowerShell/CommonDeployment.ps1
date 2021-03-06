﻿function Get-InstallableCpexDirectory(){
	Write-Host "************************************************************************"
	Write-Host "Get-InstallableCpexDirectory Version 1.0.0"
	$commonApplicationData = [Environment]::GetFolderPath("CommonApplicationData")
	return "$commonApplicationData\Cireson.Platform.Host\InstallableCpex"
}

function Download-Extension($name, $version, $feedName, $account, $vstsAuth){
	Write-Host "************************************************************************"
	Write-Host "Download-Extension Version 1.0.4"

	$cpexDestination = Get-InstallableCpexDirectory

	if($feedName -eq "nuget.org"){
        $baseNugetUri = "https://www.nuget.org/api/v2/package"
        if($version -eq $null){
            #Leaving version off seems to pull latest full version.
            $getNupkgUri = "$baseNugetUri/$name"
            Download-File -uri $getNupkgUri -destinationDirectory $cpexDestination -fileName "$name.latest.nupkg"
        }else{
            $getNupkgUri = "$baseNugetUri/$name/$version"
            Download-File -uri $getNupkgUri -destinationDirectory $cpexDestination -fileName "$name.$version.nupkg"
        }
    }else{
        $apiVersion = "2.0-preview.1"
        if($version -eq $null){
            $getPackagesUri = "https://$account.feeds.VisualStudio.com/DefaultCollection/_apis/packaging/feeds/$feedName/packages?api-version=$apiVersion"
            $response = Invoke-RestMethod -Method Get -Uri $getPackagesUri -Headers @{Authorization = $vstsAuth.BasicAuthHeader } -Credential $vstsAuth.Credential -ContentType "application/json"
            $package = $response.value | Where-Object{ $_.normalizedName -eq $name}
            $packageId = $package.id
            $packageVersion = $package.versions | Where-Object { $_.isLatest -eq $true }
            $version = $packageVersion.version
        }

        $getFeedUri = "https://$account.feeds.visualstudio.com/DefaultCollection/_apis/packaging/feeds/${feedName}?api-version=2.0-preview.1"
        $response = Invoke-RestMethod -Method Get -Uri $getFeedUri -Headers @{Authorization = $vstsAuth.BasicAuthHeader } -Credential $vstsAuth.Credential -ContentType "application/json"
        $feedId = $response.id

        #https://www.visualstudio.com/en-us/docs/integrate/api/packaging/nuget#download-package - Not for programmatic access?!
        #$getNupkgUri = "https://$account.pkgs.visualstudio.com/defaultcollection/_apis/packaging/feeds/$feedName/nuget/packages/$name/versions/$version/content?api-version=3.0-preview.1"
        #$response = Invoke-RestMethod -Method Get -Uri $getNupkgUri -Headers @{Authorization = $vstsAuth.BasicAuthHeader } -Credential $vstsAuth.Credential -Body (ConvertTo-Json $request)  -ContentType "application/json"

        # Format stolen from the way Visual Studio laods packages
        $getNupkgUri = "https://$account.pkgs.visualstudio.com/_packaging/$feedId/nuget/v3/flat2/$name/$version/$name.$version.nupkg"
        Download-File -uri $getNupkgUri -destinationDirectory $cpexDestination -basicAuthValue $vstsAuth.BasicAuthHeader
    }

	Write-Host "Destination Contains"
	ls $cpexDestination
}

function Create-AuthForVsts($userName, $password){
	Write-Host "************************************************************************"
	Write-Host "Create-AuthForVsts Version 1.0.0"
	$securePassword = ConvertTo-SecureString –String $password –AsPlainText -Force
	$base64Credential = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $username, $password)))
	$securePassword = ConvertTo-SecureString –String $password –AsPlainText -Force
	$credential = New-Object –TypeName "System.Management.Automation.PSCredential" –ArgumentList $username, $securePassword
	return @{
		BasicAuthHeader = "Basic $base64Credential"
		Credential = $credential
	}
}

function Ensure-EmptyRemoteDirectoryExists($session, $directory){
	$ErrorActionPreference = "Stop"
	Write-Host "************************************************************************"
	Write-Host "Ensure-EmptyRemoteDirectoryExists Version 1.0.0"

	Invoke-Command -Session $session -ScriptBlock{ 
		$ErrorActionPreference = "Stop"
		$onDirectory = $Using:directory

		if((Test-Path $onDirectory) -ne $true){
			$result = New-Item $onDirectory -ItemType Directory
			Write-Host "Created $onDirectory" -ForegroundColor Green
		}else{
			Remove-Item -Path "$onDirectory\*" -Recurse -Force
			Write-Host "Cleaned $onDirectory" -ForegroundColor Yellow
		}
	}
}

function Remove-RunningService([string]$serviceName){
	Write-Host "************************************************************************"
	Write-Host "Remove-RunningService Version 1.0.4"

	$processName = "Cireson.Platform.Host"

    $service = Get-WmiObject -Class Win32_Service -Filter "Name='$serviceName'"
	$process = Get-Process -Name $processName -ErrorAction SilentlyContinue
    if($service -ne $null){
        $service
        $complete = $false

        if($service.Status -eq "Degraded"){
			Write-Host "Service degraded."
			Write-Host "Stopping process '$processName'."
            Stop-Process -processname $processName -Force
        }
        elseif($service.State -ne "Stopped"){
            Write-Host "Stopping $serviceName."
            $failed = 0
        
            while($complete -ne $true -and $failed -lt 5){
               try{
                 $result = Stop-Service $serviceName
                 $complete = $true
               }catch{
                 $complete = $false
                 $failed += 1
               }
            }

            if($complete -eq $false){
				Write-Host "Failed to stop service."
				Write-Host "Stopping process '$processName'."
				Stop-Process -processname $processName -Force
            }
        }

        Write-Host "Deleting service $serviceName."
        Write-Host "ReturnValue 0 - The request was accepted"
        Write-Host "ReturnValue 16 - This service is being removed from the system."
        Write-Host "More: https://msdn.microsoft.com/en-us/library/aa389960(v=vs.85).aspx"
        $result = $service.delete()
        $result

		$process = Get-Process -Name $processName -ErrorAction SilentlyContinue
		if($process -ne $null){
			Write-Host "Stopping process '$processName'."
			Stop-Process -processname $processName -Force
		}
    }elseif($process -ne $null){
		Write-Host "$serviceName was not found."
		Write-Host "Stopping process '$processName'."
		Stop-Process -processname $processName -Force
	}
	else{
        Write-Host "$serviceName was not found."
		Write-Host "Process '$processName' was not found."
    }
}

function Create-InboundFirewallRule($displayName, $port){
	Write-Host "************************************************************************"
	Write-Host "Create-InboundFirewallRule Version 1.0.0"
    $rule = Get-NetFirewallRule | Where-Object {$_.DisplayName -eq $displayName}
    if($rule -eq $null){
        New-NetFirewallRule -DisplayName $displayName -Direction Inbound -Action Allow -Protocol "TCP" -LocalPort $port
        "$displayName Rule Created"
    }else{
        Set-NetFirewallRule -DisplayName $displayName -Direction Inbound -Action Allow -Protocol "TCP" -LocalPort $port
        "$displayName Rule Already Exists, Updated"
    }
}

function AddUserToGroup([string]$groupName,[string]$user){
	Write-Host "************************************************************************"
	Write-Host "AddUserToGroup Version 1.0.0"
    $Group = [ADSI]"WinNT://localhost/$groupName,group"   
    $Group.Add("WinNT://$user,user")
}
 
function Create-PlatformConnectionString([string]$sqlServer, [string]$sqlDatabase, [string]$sqlUserName, [string]$sqlPassword){
	Write-Host "************************************************************************"
	Write-Host "Create-PlatformConnectionString Version 1.0.0"
    return "Server=tcp:$sqlServer.database.windows.net,1433;Data Source=$sqlServer.database.windows.net;Initial Catalog=$sqlDatabase;Persist Security Info=False;User ID=$sqlUserName;Password=$sqlPassword;Encrypt=True;Connection Timeout=30;"
}

function Create-ContainedDatabaseUser([string]$connectionString, [string]$sqlServiceUserName, [string]$sqlServiceUserPassword){
	Write-Host "************************************************************************"
	Write-Host "Create-ContainedDatabaseUser Version 1.0.0"
    $connection = New-Object -TypeName System.Data.SqlClient.SqlConnection($connectionString)
    $query = "SELECT result = 1 FROM sys.database_principals WHERE authentication_type = 2 AND name = '$sqlServiceUserName'"
    $command = New-Object -TypeName System.Data.SqlClient.SqlCommand($query, $connection)
    $connection.Open()
    $result = $command.ExecuteScalar()

    if($result -eq 1){
        "********User Already Exists********"
    }else{
        "********Creating Sql User********"
        $query = "Create user $sqlServiceUserName with password = '$sqlServiceUserPassword'; ALTER AUTHORIZATION ON SCHEMA::[db_owner] TO [$sqlServiceUserName]; ALTER ROLE [db_owner] ADD MEMBER [$sqlServiceUserName];"
        $command = New-Object -TypeName System.Data.SqlClient.SqlCommand($query, $connection)
        $command.ExecuteNonQuery() #Other methods are available if you want to get the return value of your query.
    }

    $connection.Close()
}

function Create-TargetDirectory($rootDirectory, $targetVersion){
    Write-Host "************************************************************************"
	Write-Host "Create-TargetDirectory Version 1.0.7"
	$redeployVersion = $targetVersion
	$directory = "$rootDirectory\$targetVersion"
	$num = 0
	While((Test-Path -Path $directory) -eq $true){
		$num = $num + 1
		$redeployVersion = $targetVersion + "-Redeploy" + $num
		$directory = $rootDirectory + "\" + $redeployVersion
	}

    New-Item -Path $directory -ItemType Directory
	While((Test-Path -Path $directory) -ne $true){
		Write-Host "Waiting for target directory to exist." 
		Start-Sleep -s 5
	}

	Write-Host "Created $directory"
	return
}

function Download-Platform($baseDirectory, $platformVersion, $targetDirectory){
	Write-Host "************************************************************************"
	Write-Host "Download-Platform Version 1.0.3"
	Write-Host "TargetDirectory: '$targetDirectory'"
	$platformBaseDirectory = "$baseDirectory\platform"
    if((Test-Path $platformBaseDirectory) -ne $true){
        New-Item $platformBaseDirectory -type directory    
    }
  
    $platform = "$platformBaseDirectory\$platformVersion"

    if((Test-Path $platform) -ne $true){

        New-Item $platform -type directory
  
		try{
			$url = [System.Uri]"https://www.nuget.org/api/v2/package/Cireson.Platform.Core.Host/$platformVersion"
			Write-Output "Url: $url"
  
			$file = "$platform\platform.zip"
			Write-Output "File: $file"

			DownloadFile-WithRetries $url $file

			"Unzipping $file"
			Unzip-File $file "$platform\PackageContents"

			"Removing $file"
			Remove-Item $file -recurse -force

			"Copying Host Zip to $platform"
			Copy-Item -Path "$platform\PackageContents\content\PlatformRuntime\Cireson.Platform.Host.zip" -Destination "$platform\Cireson.Platform.Host.zip"

			"Remove Package Contents"
			Remove-Item "$platform\PackageContents" -Recurse -Force

			"Unzipping Platform Host"
			Unzip-File "$platform\Cireson.Platform.Host.zip" $platform

			"Remove Platform Host Zip"
			Remove-Item "$platform\Cireson.Platform.Host.zip"

			"Platform Host $platformVersion Downloaded"
			"Find at: $platform"
		}catch{
			Remove-Item $platform -Recurse -Force
			throw
		}
	}else{
		"Platform Host $platformVersion Already Exists"
	}

	"Emptying $targetDirectory"
	Remove-Item "$targetDirectory\*" -Recurse -Force

    "Copying Platform Version $platformVersion to $targetDirectory"
    Copy-Item -Path "$platform\*.*" -Destination $targetDirectory
}

function Update-PlatformConfig($targetDirectory, $connectionString){
    Write-Host "************************************************************************"
	Write-Host "Update-PlatformConfig Version 1.0.0"
	$configPath = "$targetDirectory\Cireson.Platform.Host.exe.config"
    [xml]$configFile = Get-Content $configPath
    $cstring = (($configFile.configuration.connectionStrings).add | where {$_.name -eq "CiresonDatabase"})
    $cstring.connectionString = $connectionString
    $configFile.Save($configPath) 
}

function Start-Platform($deploymentVariables, $targetDirectory){
	Write-Host "************************************************************************"
	Write-Host "Start-Platform Version 1.0.0"

	$serviceName = $deploymentVariables.serviceName
	$serviceUserName = $deploymentVariables.serviceUserName
	$serviceUserPassword = $deploymentVariables.serviceUserPassword
	$sslThumbprint = $deploymentVariables.sslThumbPrint
	$masterExtension = $null

	if ($deploymentVariables.PSObject.Properties.Match('masterExtension').Count) {
 		$masterExtension = $deploymentVariables.masterExtension
	}

	$platform = "$targetDirectory\Cireson.Platform.Host.exe"

	$argumentList = "-install", "-sn", $serviceName, "-usr", ".\$serviceUserName", "-pwd", $serviceUserPassword, "-worker"

	if($masterExtension -ne $null){
		$argumentList = $argumentList + "-masterExtension", $masterExtension
	}

	if($sslThumbprint -ne $null){
		$argumentList = $argumentList + "-u", "http://*:80", "-u","https://*:443", "-ssl", $sslThumbprint
	}

	if((Test-Path $platform) -eq $false){
		throw "Platform not found at $platform"
	}else{
		Write-Host "Platform found at $platform" -ForegroundColor Green
	}

	Write-Host "Starting Platfrom at $platform" -ForegroundColor Green
	start-process $platform -ArgumentList $argumentList -wait

	Write-Host "End Start-Platform" -ForegroundColor Green
}

function Start-RemotePlatform($session, $deploymentVariables, $targetDirectory){
	Write-Host "************************************************************************"
	Write-Host "Start-RemotePlatform Version 1.0.6"
	Write-Host "Begin Start-RemotePlatform" -ForegroundColor Green

	Invoke-Command -Session $session -ScriptBlock{ 
        Start-Platform $Using:deploymentVariables $Using:targetDirectory
    }

	Write-Host "End Start-RemotePlatform" -ForegroundColor Green
}

function Restart-RemotePlatform($session, $serviceName){
	Write-Host "************************************************************************"
	Write-Host "Restart-RemotePlatform Version 1.0.4"

	Invoke-Command -Session $session -ScriptBlock{ 
        $ErrorActionPreference = "Stop"
		$processName = "Cireson.Platform.Host"
		$onServiceName = $Using:serviceName

		$service = Get-WmiObject -Class Win32_Service -Filter "Name='$onServiceName'"
		$process = Get-Process -Name $processName -ErrorAction SilentlyContinue

		if($service -eq $null){
			Write-Host "Service, $onServiceName, not found. Redeploy target product."
		}else{
			try{
				Restart-Service -DisplayName $onServiceName
			}catch{
				Write-Host "$onServiceName failed to restart."
				Write-Host "Stopping process '$processName'."
				Stop-Process -processname $processName -Force
				Start-Service -DisplayName $onServiceName
			}
		}
    }
}

function Copy-NuGets($resourceGroupName, $storageAccountName, $productRoot, $tempContainerName, $session, $agentReleaseDirectory, $buildDefinitionName, $deploymentScripts, $remotePowerShellLocation){
	Write-Host "************************************************************************"
	Write-Host "Copy-NuGets Version 1.0.7"

	Import-Module -Name Azure
	
	$storageAccount = Get-AzureRmStorageAccount -ResourceGroupName $resourceGroupName| Where-Object{ $_.StorageAccountName -eq $storageAccountName}
	"----Storage Account----"
	$storageAccount
	$storageAccountKey = Get-AzureRmStorageAccountKey -Name $storageAccount.StorageAccountName -ResourceGroupName $resourceGroupName
    $key = $storageAccountKey | Where-Object{$_.Permissions -eq "FULL"} | Select-Object -First 1
	$storageContext = New-AzureStorageContext -StorageAccountName $storageAccount.StorageAccountName -StorageAccountKey $key.Value
	"----Storage Context----"
	$storageContext

	$version = $env:BUILD_BUILDNUMBER
	
	#$(System.DefaultWorkingDirectory)/Connectors.ConfigMgr (CI - integration)/drop/Cireson.AssetManagement.Connectors.ConfigMgr.Core.0.1.0-rc0051.nupkg
	$nuGets = Get-ChildItem "$agentReleaseDirectory/$buildDefinitionName/drop/" | Where-Object {$_.Name.EndsWith(".nupkg")}

	foreach($nuGet in $nuGets){
		"----Copying $nuGet.FullName to Temp Azure Storage----"
		Set-AzureStorageBlobContent -File $nuGet.FullName  -Container $tempContainerName -Blob $nuGet.Name -Context $storageContext -Force

		$blobUri = $storageContext.BlobEndPoint + "$tempContainerName/" + $nuGet.Name
	
		Invoke-Command -Session $Session -ScriptBlock{ 
			$onBlobUri = $Using:blobUri
			$onFileName = $Using:nuget.Name
			$onVersion = $Using:version
			$onRemotePowerShellLocation = $Using:remotePowerShellLocation
			$onDeploymentScripts = $Using:deploymentScripts

			"Blob URI: $onBlobUri"
			"File Name: $onFileName"
			"Version: $onVersion"

			foreach($uri in $onDeploymentScripts){
				$fileName = $uri.Segments[$uri.Segments.Count-1]
				$module = "$onRemotePowerShellLocation\$fileName"
				Write-Host "`tImporting module $module" -ForegroundColor Green
				Import-Module $module
			}

			$platformHostCpexData = Get-InstallableCpexDirectory
			Write-Output "Remove All Files From $platformHostCpexData"	
			Remove-Item -Path "$platformHostCpexData\*.*" -recurse -force 
			
			Write-Output "Download $onFileName from Azure Storage"
			$file = "$platformHostCpexData\$onFileName"
			$webclient = New-Object System.Net.WebClient
			$webclient.DownloadFile($onBlobUri, $file)
			Write-Output "`tSaved to $file"
		}

		"----Remove Blob from Temp Azure Storage----"
		Remove-AzureStorageBlob -Blob $nuGet.Name -Container $tempContainerName -Context $storageContext
	}
}

function Create-ServiceUser($serviceUserName, $servicePassword){
	Write-Host "************************************************************************"
	Write-Host "Create-ServiceUser Version 1.0.3"
	$user = Get-WmiObject -Class Win32_UserAccount -Namespace "root\cimv2" -Filter "LocalAccount='$True'" | Where-Object { $_.Name -eq $serviceUserName}
	if($user -eq $null){
		"Creating User $serviceUserName($servicePassword)"
		NET USER $serviceUserName $servicePassword /ADD
		$user = Get-WmiObject -Class Win32_UserAccount -Namespace "root\cimv2" -Filter "LocalAccount='$True'" | Where-Object { $_.Name -eq $serviceUserName}
	}else{
		"User $serviceUserName Already Exists"
	}

	$userSettings = @{
		PasswordExpires = 0
	}
	Set-WmiInstance -InputObject $user -Argument $userSettings

	Grant-UserRight $serviceUserName SeServiceLogonRight

	$group = get-wmiobject win32_group -filter "name='Administrators'"
	$user = $group.GetRelated("win32_useraccount") | Where-Object { $_.Name -eq $serviceUserName}
	if($user -eq $null){
		AddUserToGroup -groupName "Administrators" -user $serviceUserName
		"----Added $serviceUserName to Administrators Group----"
	}else{
		"----$serviceUserName Already a Member of Administrators Group----"
	}
}

function Create-DestinationDirectories([string]$root, [string]$targetVersion){
	Write-Host "************************************************************************"
	Write-Host "Create-DestinationDirectories Version 1.0.0"
    $platformHostCpexData = Get-InstallableCpexDirectory
    if((Test-Path $platformHostCpexData) -ne $true){
        New-Item $platformHostCpexData -ItemType Directory
    }
    
    $targetDirectory = "$root\$targetVersion"

    if((Test-Path $root) -ne $true){
        New-Item $root -type directory
    }else{
        Write-Output "$root Exists"
    }

    if((Test-Path $targetDirectory) -ne $true){
        New-Item $targetDirectory -type directory
    }else{
        Write-Output "$targetDirectory Exists"
    }
}

function Push-RemoteDeploymentScripts($session, $uris, $remotePowerShellLocation){
	Write-Host "************************************************************************"
	Write-Host "Push-RemoteDeploymentScripts Version 1.0.1"
	Invoke-Command -Session $session -ScriptBlock{ 
        $ErrorActionPreference = "Stop"
		$onUris = $Using:uris
		$onRemotePowerShellLocation = $Using:remotePowerShellLocation

        function DownloadFile([System.Uri]$uri, $destinationDirectory){
            $fileName = $uri.Segments[$uri.Segments.Count-1]
            $destinationFile = Join-Path $destinationDirectory $fileName

            Write-Host "Downloading $uri to $destinationFile" -ForegroundColor Green

			$fileDownloaded = $false
			$try = 0

			while($fileDownloaded -eq $false){
				try{
					$try = $try + 1
					$webclient = New-Object System.Net.WebClient
					$webclient.DownloadFile($uri,$destinationFile)
					$fileDownloaded = $true
				}catch{
                    Start-Sleep -Seconds 3
					if($try -gt 3){
						throw
					}
				}
			}
        }

        foreach($uri in $onUris){
			DownloadFile -uri $uri -destinationDirectory $onRemotePowerShellLocation
		}
    }
}

function DownloadFile-WithRetries([System.Uri]$uri, $destinationFile){
    Write-Host "Downloading $uri to $destinationFile" -ForegroundColor Green

	$fileDownloaded = $false
	$try = 0

	while($fileDownloaded -eq $false){
		try{
			$try = $try + 1
			$webclient = New-Object System.Net.WebClient
			$webclient.DownloadFile($uri,$destinationFile)
			$fileDownloaded = $true
		}catch{
            Start-Sleep -Seconds 3
			if($try -gt 3){
				throw
			}
		}
	}
}