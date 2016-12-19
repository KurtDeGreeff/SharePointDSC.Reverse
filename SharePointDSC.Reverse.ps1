<##############################################################
 # This script is used to analyze an existing SharePoint (2013, 2016 or greater), and to produce the resulting PowerShell DSC Configuration Script representing it. Its purpose is to help SharePoint Admins and Devs replicate an existing SharePoint farm in an isolated area in order to troubleshoot an issue. This script needs to be executed directly on one of the SharePoint server in the far we wish to replicate. Upon finishing its execution, this Powershell script will prompt the user to specify a path to a FOLDER where the resulting PowerShell DSC Configuraton (.ps1) script will be generated. The resulting script will be named "SP-Farm.DSC.ps1" and will contain an exact description, in DSC notation, of the various components and configuration settings of the current SharePoint Farm. This script can then be used in an isolated environment to replicate the SharePoint server farm. The script could also be used as a simple textual (while in a DSC notation format) description of what the configuraton of the SharePoint farm looks like. This script is meant to be community driven, and everyone is encourage to participate and help improve and mature it. It is not officially endorsed by Microsoft, and support is 'offered' on a best effort basis by its contributors. Bugs suggestions should be reported through the issue system on GitHub. They will be looked at as time permits.
 # v1.5.0.0 - Nik Charlebois
 ##############################################################>
<## Script Settings #>
$VerbosePreference = "SilentlyContinue"

<## Scripts Variables #>
$Script:dscConfigContent = ""
$SPDSCSource = "C:\Program Files\WindowsPowerShell\Modules\SharePointDSC\"
$SPDSCVersion = "1.5.0.0"
$Script:SPDSCPath = $SPDSCSource + $SPDSCVersion
$Global:spFarmAccount = ""

<## This is the main function for this script. It acts as a call dispatcher, calling th various functions required in the proper order to get the full farm picture. #>
function Orchestrator
{
    Check-Prerequisites

    $relPath = "ReverseDSC.Util.psm1"
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath $relPath -Resolve) -Force

    $Global:spFarmAccount = Get-Credential -Message "Credentials with Farm Admin Rights"
    Store-Credentials $Global:spFarmAccount

    <# Ensure the user executing the script is not the same as the farm admin account provided #>    
    $Global:spCentralAdmin = Get-SPWebApplication -IncludeCentralAdministration | Where{$_.DisplayName -like '*Central Administration*'}
    $spFarm = Get-SPFarm
    $spServers = $spFarm.Servers

    $totalSteps = 7 + ($spServers.Count * 18)
    $currentStep = 1

    Write-Progress -Activity "Scanning Operating System Version..." -PercentComplete ($currentStep/$totalSteps*100)
    Read-OperatingSystemVersion
    $currentStep++

    Write-Progress -Activity "Scanning SQL Server Version..." -PercentComplete ($currentStep/$totalSteps*100)
    Read-SQLVersion
    $currentStep++

    Write-Progress -Activity "Scanning Patch Levels..." -PercentComplete ($currentStep/$totalSteps*100)
    Read-SPProductVersions
    $currentStep++

    $Script:dscConfigContent += "Configuration SharePointFarm`r`n"
    $Script:dscConfigContent += "{`r`n"

    Write-Progress -Activity "Configuring Credentials..." -PercentComplete ($currentStep/$totalSteps*100)
    Set-ObtainRequiredCredentials
    $currentStep++

    Write-Progress -Activity "Configuring Dependencies..." -PercentComplete ($currentStep/$totalSteps*100)
    Set-Imports
    $currentStep++

    Write-Progress -Activity "Configuring Variables..." -PercentComplete ($currentStep/$totalSteps*100)
    Set-VariableSection
    $currentStep++

    $serverNumber = 1
    foreach($spServer in $spServers)
    {
        <## SQL servers are returned by Get-SPServer but they have a Role of 'Invalid'. Therefore we need to ignore these. The resulting PowerShell DSC Configuration script does not take into account the configuration of the SQL server for the SharePoint Farm at this point in time. We are activaly working on giving our users an experience that is as painless as possible, and are planning on integrating the SQL DSC Configuration as part of our feature set. #>
        if($spServer.Role -ne "Invalid")
        {
            $Script:dscConfigContent += "`r`n    node " + $spServer.Name + "`r`n    {`r`n"

            Write-Progress -Activity ("[" + $spServer.Name + "] Setting Up Configuration Settings...") -PercentComplete ($currentStep/$totalSteps*100)
            Set-ConfigurationSettings
            $currentStep++

            <# If this is the first server in the farm, then generate the SPCreateFarm config section. Otherwise, generate the 
               SPJoinFarm one. #>
            if($serverNumber -eq 1)
            {
                Write-Progress -Activity ("[" + $spServer.Name + "] Scanning the SharePoint Farm...") -PercentComplete ($currentStep/$totalSteps*100)
                Read-SPFarm
            }
            else
            {
                Write-Progress -Activity ("[" + $spServer.Name + "] Scanning the SharePoint Farm...") -PercentComplete ($currentStep/$totalSteps*100)
                Read-SPJoinFarm
            }
            $currentStep++

            if($serverNumber -eq 1)
            {
                Write-Progress -Activity ("[" + $spServer.Name + "] Scanning Web Application(s)...") -PercentComplete ($currentStep/$totalSteps*100)
                Read-SPWebApplications
            }
            $currentStep++

            if($serverNumber -eq 1)
            {
                Write-Progress -Activity ("[" + $spServer.Name + "] Scanning Managed Path(s)...") -PercentComplete ($currentStep/$totalSteps*100)
                Read-SPManagedPaths
            }
            $currentStep++

            if($serverNumber -eq 1)
            {
                Write-Progress -Activity ("[" + $spServer.Name + "] Scanning Managed Account(s)...") -PercentComplete ($currentStep/$totalSteps*100)
                Read-SPManagedAccounts
            }
            $currentStep++

            if($serverNumber -eq 1)
            {
                Write-Progress -Activity ("[" + $spServer.Name + "] Scanning Application Pool(s)...") -PercentComplete ($currentStep/$totalSteps*100)
                Read-SPServiceApplicationPools
            }
            $currentStep++

            if($serverNumber -eq 1)
            {
                Write-Progress -Activity ("[" + $spServer.Name + "] Scanning Site Collection(s)...") -PercentComplete ($currentStep/$totalSteps*100)
                Read-SPSites
            }
            $currentStep++

            Write-Progress -Activity ("[" + $spServer.Name + "] Scanning Service Instance(s)...") -PercentComplete ($currentStep/$totalSteps*100)
            Read-SPServiceInstance -Server $spServer.Name
            $currentStep++

            if($serverNumber -eq 1)
            {
                Write-Progress -Activity ("[" + $spServer.Name + "] Scanning Diagnostic Logging Settings...") -PercentComplete ($currentStep/$totalSteps*100)
                Read-DiagnosticLoggingSettings
            }
            $currentStep++

            if($serverNumber -eq 1)
            {
                Write-Progress -Activity ("[" + $spServer.Name + "] Scanning Usage Service Application...") -PercentComplete ($currentStep/$totalSteps*100)
                Read-UsageServiceApplication
            }
            $currentStep++

            if($serverNumber -eq 1)
            {
                Write-Progress -Activity ("[" + $spServer.Name + "] Scanning State Service Application...") -PercentComplete ($currentStep/$totalSteps*100)
                Read-StateServiceApplication
            }
            $currentStep++

            if($serverNumber -eq 1)
            {
                Write-Progress -Activity ("[" + $spServer.Name + "] Scanning User Profile Service Application(s)...") -PercentComplete ($currentStep/$totalSteps*100)
                Read-UserProfileServiceapplication
            }
            $currentStep++

            if($serverNumber -eq 1)
            {
                Write-Progress -Activity ("[" + $spServer.Name + "] Cache Account(s)...") -PercentComplete ($currentStep/$totalSteps*100)
                Read-CacheAccounts
            }
            $currentStep++

            if($serverNumber -eq 1)
            {
                Write-Progress -Activity ("[" + $spServer.Name + "] Scanning Secure Store Service Application(s)...") -PercentComplete ($currentStep/$totalSteps*100)
                Read-SecureStoreServiceApplication
            }
            $currentStep++

            if($serverNumber -eq 1)
            {
                Write-Progress -Activity ("[" + $spServer.Name + "] Scanning Business Connectivity Service Application(s)...") -PercentComplete ($currentStep/$totalSteps*100)
                Read-BCSServiceApplication
            }
            $currentStep++

            if($serverNumber -eq 1)
            {
                Write-Progress -Activity ("[" + $spServer.Name + "] Scanning Search Service Application(s)...") -PercentComplete ($currentStep/$totalSteps*100)
                Read-SearchServiceApplication
            }
            $currentStep++

            if($serverNumber -eq 1)
            {
                Write-Progress -Activity ("[" + $spServer.Name + "] Scanning Managed Metadata Service Application(s)...") -PercentComplete ($currentStep/$totalSteps*100)
                Read-ManagedMetadataServiceApplication
            }
            $currentStep++

            Write-Progress -Activity ("[" + $spServer.Name + "] Configuring Local Configuration Manager (LCM)...") -PercentComplete ($currentStep/$totalSteps*100)
            Set-LCM
            $currentStep++

            $Script:dscConfigContent += "`r`n    }`r`n"
            $serverNumber++
        }
    }    
    $Script:dscConfigContent += "`r`n}`r`n"
    Write-Progress -Activity "[$spServer.Name] Setting Configuration Data..." -PercentComplete ($currentStep/$totalSteps*100)
    Set-ConfigurationData
    $currentStep++
    $Script:dscConfigContent += "SharePointFarm -ConfigurationData `$ConfigData"
}

function Check-Prerequisites
{
    <# Validate the PowerShell Version #>
    if($psVersionTable.PSVersion.Major -eq 4)
    {
        Write-Host "PowerShell v4 detected. While this script will work just fine with v4, it is highly recommended you upgrade to PowerShell v5 to get the most out of DSC" -BackgroundColor Yellow -ForegroundColor Black
    }
    elseif($psVersionTable.PSVersion.Major -lt 4)
    {
        Write-Host "We are sorry, PowerShell v3 or lower is not supported by the Reverse DSC Engine" -BackgroundColor Yellow -ForegroundColor Black
        exit
    }

    <# Check to see if the SharePointDSC module is installed on the machine #>
    $spDSCCheck = Get-DSCResource -Module "SharePointDSC" | ?{$_.Version -eq $SPDSCVersion}
    if($spDSCCheck.Length -eq 0)
    {        
        $cmd = Get-Command Install-Module
        if($psVersionTable.PSVersion.Major -ge 5 -or !$cmd)
        {
            $shouldInstall = Read-Host "The SharePointDSC module could not be found on the machine. Do you wish to download and install it (y/n)?"
            if($shouldInstall.ToLower() -eq "y")
            {
                Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
                Install-Module SharePointDSC -RequiredVersion $SPDSCVersion -Confirm:$false -SkipPublisherCheck:$true
            }
            else
            {
                Write-Host "We are sorry, but the script cannot continue without the SharePoint DSC module installed." -BackgroundColor Yellow -ForegroundColor Black
                exit
            }
        }
        else
        {
            Write-Host "We could not find the PackageManagement modules on the machine. Please make sure you download and install it at https://www.microsoft.com/en-us/download/details.aspx?id=51451 before executing this script" -BackgroundColor Yellow -ForegroundColor Black
        }
    }
}

function Read-OperatingSystemVersion
{
    $servers = Get-SPServer
    $Script:dscConfigContent += "<#`r`n    Operating Systems in this Farm`r`n-------------------------------------------`r`n"
    $Script:dscConfigContent += "    Products and Language Packs`r`n"
    $Script:dscConfigContent += "-------------------------------------------`r`n"
    foreach($spServer in $servers)
    {
        $serverName = $spServer.Name
        try{
            $osInfo = Get-CimInstance Win32_OperatingSystem  -ComputerName $serverName| Select-Object @{Label="OSName"; Expression={$_.Name.Substring($_.Name.indexof("W"),$_.Name.indexof("|")-$_.Name.indexof("W"))}} , Version ,OSArchitecture -ErrorAction SilentlyContinue
            $Script:dscConfigContent += "    [" + $serverName + "]: " + $osInfo.OSName + "(" + $osInfo.OSArchitecture + ")    ----    " + $osInfo.Version + "`r`n"
        }
        catch{}
    }    
    $Script:dscConfigContent += "#>`r`n`r`n"
}

function Read-SQLVersion
{
    $uniqueServers = @()
    $sqlServers = Get-SPDatabase | select Server -Unique
    foreach($sqlServer in $sqlServers)
    {
        $serverName = $sqlServer.Server.Name

        if($serverName -eq $null)
        {
            $serverName = $sqlServer.Server
        }
        
        if(!($uniqueServers -contains $serverName))
        {
            $sqlVersionInfo = Invoke-SQL -Server $serverName -dbName "Master" -sqlQuery "SELECT @@VERSION AS 'SQLVersion'"
            $uniqueServers += $serverName.ToString()
            $Script:dscConfigContent += "<#`r`n    SQL Server Product Versions Installed on this Farm`r`n-------------------------------------------`r`n"
            $Script:dscConfigContent += "    Products and Language Packs`r`n"
            $Script:dscConfigContent += "-------------------------------------------`r`n"
            $Script:dscConfigContent += "    [" + $serverName + "]: " + $sqlVersionInfo.SQLversion + "`r`n#>`r`n`r`n"
        }
    }
}

function Set-VariableSection
{
    $Script:dscConfigContent += "            `$Script:passphrase = Read-Host 'Farm Passphrase' -AsSecureString;`r`n"
}

<## This function ensure all required Windows Features are properly installed on the server. #>
<# TODO: Replace this by a logic that reads the feature from te actual server and writes them down instead of simply assuming they are required. #>
function Set-ConfigurationSettings
{
    #$Script:dscConfigContent += "        xCredSSP CredSSPServer `r`n        {`r`n            Ensure = `"Present`";`r`n            Role = `"Server`";`r`n        }`r`n"
    #$Script:dscConfigContent += "        xCredSSP CredSSPClient `r`n        {`r`n            Ensure = `"Present`";`r`n            Role = `"Client`";`r`n            DelegateComputers = `"*." + (Get-WmiObject Win32_ComputerSystem).Domain + "`";`r`n        }`r`n`r`n"

    #$Script:dscConfigContent += "        xWebAppPool RemoveDotNet2Pool         `r`n        {`r`n            Name = `".NET v2.0`";`r`n            Ensure = `"Absent`";`r`n        }`r`n"
    #$Script:dscConfigContent += "        xWebAppPool RemoveDotNet2ClassicPool  `r`n        {`r`n            Name = `".NET v2.0 Classic`";`r`n            Ensure = `"Absent`";`r`n        }`r`n"
    #$Script:dscConfigContent += "        xWebAppPool RemoveDotNet45Pool        `r`n        {`r`n            Name = `".NET v4.5`";`r`n            Ensure = `"Absent`";`r`n        }`r`n"
    #$Script:dscConfigContent += "        xWebAppPool RemoveDotNet45ClassicPool `r`n        {`r`n            Name = `".NET v4.5 Classic`";`r`n            Ensure = `"Absent`";`r`n        }`r`n"
    #$Script:dscConfigContent += "        xWebAppPool RemoveClassicDotNetPool   `r`n        {`r`n            Name = `"Classic .NET AppPool`";`r`n            Ensure = `"Absent`";`r`n        }`r`n"
    #$Script:dscConfigContent += "        xWebAppPool RemoveDefaultAppPool      `r`n        {`r`n            Name = `"DefaultAppPool`";`r`n            Ensure = `"Absent`";`r`n        }`r`n"
    #$Script:dscConfigContent += "        xWebSite    RemoveDefaultWebSite      `r`n        {`r`n            Name = `"Default Web Site`";`r`n            Ensure = `"Absent`";`r`n            PhysicalPath = `"C:\inetpub\wwwroot`";`r`n        }`r`n"
}

function Set-ConfigurationData
{
    $Script:dscConfigContent += "`$ConfigData = @{`r`n"
    $Script:dscConfigContent += "    AllNodes = @(`r`n"

    $spFarm = Get-SPFarm
    $spServers = $spFarm.Servers

    $tempConfigDataContent = ""
    foreach($spServer in $spServers)
    {
        $tempConfigDataContent += "    @{`r`n"
        $tempConfigDataContent += "        NodeName = `"" + $spServer.Name + "`";`r`n"
        $tempConfigDataContent += "        PSDscAllowPlainTextPassword =`$true;`r`n"
        $tempConfigDataContent += "    },`r`n"
    }

    # Remove the last ',' in the array
    $tempConfigDataContent = $tempConfigDataContent.Remove($tempConfigDataContent.LastIndexOf(","), 1)
    $Script:dscConfigContent += $tempConfigDataContent
    $Script:dscConfigContent += ")}`r`n"
}

<## This function ensures all required DSC Modules are properly loaded into the current PowerShell session. #>
function Set-Imports
{
    $Script:dscConfigContent += "    Import-DscResource -ModuleName PSDesiredStateConfiguration`r`n"
    $Script:dscConfigContent += "    Import-DscResource -ModuleName SharePointDSC -ModuleVersion '$SPDSCVersion'`r`n"
}

<## This function really is optional, but helps provide valuable information about the various software components installed in the current SharePoint farm (i.e. Cummulative Updates, Language Packs, etc.). #>
function Read-SPProductVersions
{    
    $Script:dscConfigContent += "<#`r`n    SharePoint Product Versions Installed on this Farm`r`n-------------------------------------------`r`n"
    $Script:dscConfigContent += "    Products and Language Packs`r`n"
    $Script:dscConfigContent += "-------------------------------------------`r`n"

    if($PSVersionTable.PSVersion -like "2.*")
    {
        $RegLoc = Get-ChildItem HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall
        $Programs = $RegLoc | where-object { $_.PsPath -like "*\Office*" } | foreach {Get-ItemProperty $_.PsPath}        

        foreach($program in $Programs)
        {
            $Script:dscConfigContent += "    " +  $program.DisplayName + " -- " + $program.DisplayVersion + "`r`n"
        }
    }
    else
    {
        $regLoc = Get-ChildItem HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall
        $programs = $regLoc | where-object { $_.PsPath -like "*\Office*" } | foreach {Get-ItemProperty $_.PsPath} 
        $components = $regLoc | where-object { $_.PsPath -like "*1000-0000000FF1CE}" } | foreach {Get-ItemProperty $_.PsPath} 

        foreach($program in $programs)
        { 
            $productCodes = $_.ProductCodes
            $component = @() + ($components |     where-object { $_.PSChildName -in $productCodes } | foreach {Get-ItemProperty $_.PsPath})
            foreach($component in $components)
            {
                $Script:dscConfigContent += "    " + $component.DisplayName + " -- " + $component.DisplayVersion + "`r`n"
            }        
        }
    }
    $Script:dscConfigContent += "#>`r`n"
}

<## This function declares the xSPCreateFarm object required to create the config and admin database for the resulting SharePoint Farm. #>
function Read-SPFarm ($modulePath, $params){
    if($modulePath -ne $null)
    {
        $module = Resolve-Path $modulePath
    }
    else {
        $module = Resolve-Path ($Script:SPDSCPath + "\DSCResources\MSFT_SPCreateFarm\MSFT_SPCreateFarm.psm1")
        Import-Module $module
    }
        
    $Script:dscConfigContent += "        SPCreateFarm CreateSPFarm`r`n        {`r`n"

    if($params -eq $null)
    {
        $params = Get-DSCFakeParameters -FilePath $module -FarmAccount $Global:spFarmAccount
    }    

    <# If not SP2016, remove the server role param. #>
    if ((Get-SPDSCInstalledProductVersion).FileMajorPart -ne 16) {
        $params.Remove("ServerRole")
    }

    <# Can't have both the InstallAccount and PsDscRunAsCredential variables present. Remove InstallAccount if both are there. #>
    if($params.Contains("InstallAccount"))
    {
        $params.Remove("InstallAccount")
    }

    $results = Get-TargetResource @params

    <# Remove the default generated PassPhrase and ensure the resulting Configuration Script will prompt user for it. #>
    $results.Remove("Passphrase");    
    $Script:dscConfigContent += "            Passphrase = New-Object System.Management.Automation.PSCredential ('Passphrase', `$passphrase);`r`n"

    $Script:dscConfigContent += Get-DSCBlock -Params $results -ModulePath $module
    $Script:dscConfigContent += "`r`n        }`r`n"
}

<## This function declares the xSPCreateFarm object required to create the config and admin database for the resulting SharePoint Farm. #>
function Read-SPJoinFarm ($modulePath, $params){
    if($modulePath -ne $null)
    {
        $module = Resolve-Path $modulePath
    }
    else {
        $module = Resolve-Path ($Script:SPDSCPath + "\DSCResources\MSFT_SPJoinFarm\MSFT_SPJoinFarm.psm1")
        Import-Module $module
    }
        
    $Script:dscConfigContent += "        SPJoinFarm JoinFarm`r`n        {`r`n"

    if($params -eq $null)
    {
        $params = Get-DSCFakeParameters -FilePath $module -FarmAccount $Global:spFarmAccount
    }    

    <# If not SP2016, remove the server role param. #>
    if ((Get-SPDSCInstalledProductVersion).FileMajorPart -ne 16) {
        $params.Remove("ServerRole")
    }

    <# Can't have both the InstallAccount and PsDscRunAsCredential variables present. Remove InstallAccount if both are there. #>
    if($params.Contains("InstallAccount"))
    {
        $params.Remove("InstallAccount")
    }

    $results = Get-TargetResource @params

    <# Remove the default generated PassPhrase and ensure the resulting Configuration Script will prompt user for it. #>
    $results.Remove("Passphrase");    
    $Script:dscConfigContent += "            Passphrase = New-Object System.Management.Automation.PSCredential ('Passphrase', `$passphrase);`r`n"

    $Script:dscConfigContent += Get-DSCBlock -Params $results -ModulePath $module
    $Script:dscConfigContent += "`r`n        }`r`n"
}


<## This function obtains a reference to every Web Application in the farm and declares their properties (i.e. Port, Associated IIS Application Pool, etc.). #>
function Read-SPWebApplications ($modulePath, $params){
    Write-Verbose "Reading Information about all Web Applications..."
    if($modulePath -ne $null)
    {
        $module = Resolve-Path $modulePath
    }
    else {
        $module = Resolve-Path ($Script:SPDSCPath + "\DSCResources\MSFT_SPWebApplication\MSFT_SPWebApplication.psm1")
        Import-Module $module
    }    

    $spWebApplications = Get-SPWebApplication | Sort-Object -Property Name

    if($params -eq $null)
    {
        $params = Get-DSCFakeParameters -FilePath $module
    }
    
    foreach($spWebApp in $spWebApplications)
    {
        $Script:dscConfigContent += "        SPWebApplication " + $spWebApp.Name.Replace(" ", "") + "`r`n        {`r`n"      

        $params.Name = $spWebApp.Name
        $results = Get-TargetResource @params

    
        $Script:dscConfigContent += Get-DSCBlock -Params $results -ModulePath $module
        $Script:dscConfigContent += "`r`n        }`r`n"
    }
}

<## This function loops through every IIS Application Pool that are associated with the various existing Service Applications in the SharePoint farm. ##>
function Read-SPServiceApplicationPools ($modulePath, $params){
    if($modulePath -ne $null)
    {
        $module = Resolve-Path $modulePath
    }
    else {
        $module = Resolve-Path ($Script:SPDSCPath + "\DSCResources\MSFT_SPServiceAppPool\MSFT_SPServiceAppPool.psm1")
        Import-Module $module
    }
    
    $spServiceAppPools = Get-SPServiceApplicationPool | Sort-Object -Property Name

    if($params -eq $null)
    {
        $params = Get-DSCFakeParameters -FilePath $module
    }

    foreach($spServiceAppPool in $spServiceAppPools)
    {
        $Script:dscConfigContent += "        SPServiceAppPool " + $spServiceAppPool.Name.Replace(" ", "") + "`r`n"
        $Script:dscConfigContent += "        {`r`n"
        $params.Name = $spServiceAppPool.Name
        $results = Get-TargetResource @params    
        $Script:dscConfigContent += Get-DSCBlock -Params $results -ModulePath $module
        $Script:dscConfigContent += "        }`r`n"
    }
}

<## This function retrieves a list of all site collections, no matter what Web Application they belong to. The Url attribute helps the xSharePoint DSC Resource determine what Web Application they belong to. #>
function Read-SPSites ($modulePath, $params){
    if($modulePath -ne $null)
    {
        $module = Resolve-Path $modulePath
    }
    else {
        $module = Resolve-Path ($Script:SPDSCPath + "\DSCResources\MSFT_SPSite\MSFT_SPSite.psm1")
        Import-Module $module
    }    
    $spSites = Get-SPSite -Limit All

    if($params -eq $null)
    {
        $params = Get-DSCFakeParameters -FilePath $module
    }

    $siteGuid = $null
    $siteTitle = $null
    foreach($spsite in $spSites)
    {
        $siteGuid = [System.Guid]::NewGuid().toString()
        $siteTitle = $spSite.RootWeb.Title
        if($siteTitle -eq $null)
        {
            $siteTitle = "SiteCollection"
        }
        $Script:dscConfigContent += "        SPSite " + $siteTitle.Replace(" ", "") + "-" + $siteGuid + "`r`n"
        $Script:dscConfigContent += "        {`r`n"
        $params.Url = $spsite.Url
        $results = Get-TargetResource @params

        <# If the current Quota ID is 0, it means no quota templates were used. Remove param in that case. #>
        if($spsite.Quota.QuotaID -eq 0)
        {
            $results.Remove("QuotaTemplate")
        }

        $Script:dscConfigContent += Get-DSCBlock -Params $results -ModulePath $module
        $Script:dscConfigContent += "        }`r`n"
    }
}

<## This function generates a list of all Managed Paths, no matter what their associated Web Application is. The xSharePoint DSC Resource uses the WebAppUrl attribute to identify what Web Applicaton they belong to. #>
function Read-SPManagedPaths ($modulePath, $params){
    if($modulePath -ne $null)
    {
        $module = Resolve-Path $modulePath
    }
    else {
        $module = Resolve-Path ($Script:SPDSCPath + "\DSCResources\MSFT_SPManagedPath\MSFT_SPManagedPath.psm1")
        Import-Module $module
    }   

    $spWebApps = Get-SPWebApplication

    if($params -eq $null)
    {
        $params = Get-DSCFakeParameters -FilePath $module
    }
    foreach($spWebApp in $spWebApps)
    {
        $spManagedPaths = Get-SPManagedPath -WebApplication $spWebApp.Url | Sort-Object -Property Name

        foreach($spManagedPath in $spManagedPaths)
        {
            if($spManagedPath.Name.Length -gt 0 -and $spManagedPath.Name -ne "sites")
            {
                $Script:dscConfigContent += "        SPManagedPath " + $spWebApp.Name.Replace(" ", "") + "Path" + $spManagedPath.Name + "`r`n"
                $Script:dscConfigContent += "        {`r`n"
                if($spManagedPath.Name -ne $null)
                {
                    $params.RelativeUrl = $spManagedPath.Name
                }                
                $params.WebAppUrl = $spWebApp.Url
                $params.HostHeader = $false;
                $results = Get-TargetResource @params    
                $Script:dscConfigContent += Get-DSCBlock -Params $results -ModulePath $module
                $Script:dscConfigContent += "        }`r`n"
            }            
        }

        $spManagedPaths = Get-SPManagedPath -HostHeader | Sort-Object -Property Name
        foreach($spManagedPath in $spManagedPaths)
        {
            if($spManagedPath.Name.Length -gt 0 -and $spManagedPath.Name -ne "sites")
            {
                $Script:dscConfigContent += "        SPManagedPath " + $spWebApp.Name.Replace(" ", "") + "Path" + $spManagedPath.Name + "`r`n"
                $Script:dscConfigContent += "        {`r`n"
                
                if($spManagedPath.Name -ne $null)
                {
                    $params.RelativeUrl = $spManagedPath.Name
                } 
                if($params.ContainsKey("Explicit"))
                {
                    $params.Explicit = ($spManagedPath.Type -eq "ExplicitInclusion")
                }
                else
                {
                    $params.Add("Explicit", ($spManagedPath.Type -eq "ExplicitInclusion"))
                }
                $params.HostHeader = $true;
                $params.WebAppUrl = $spWebApp.Url
                $results = Get-TargetResource @params
                $Script:dscConfigContent += Get-DSCBlock -Params $results -ModulePath $module
                $Script:dscConfigContent += "        }`r`n"
            }            
        }
    }
}

<## This function retrieves all Managed Accounts in the SharePoint Farm. The Account attribute sets the associated credential variable (each managed account is declared as a variable and the user is prompted to Manually enter the credentials when first executing the script. See function "Set-ObtainRequiredCredentials" for more details on how these variales are set. #>
function Read-SPManagedAccounts ($modulePath, $params){
    if($modulePath -ne $null)
    {
        $module = Resolve-Path $modulePath
    }
    else {
        $module = Resolve-Path ($Script:SPDSCPath + "\DSCResources\MSFT_SPManagedAccount\MSFT_SPManagedAccount.psm1")
        Import-Module $module
    }    

    $managedAccounts = Get-SPManagedAccount

    if($params -eq $null)
    {
        $params = Get-DSCFakeParameters -FilePath $module
    }

    foreach($managedAccount in $managedAccounts)
    {
        $managedCreds = Retrieve-Credentials $managedAccount.UserName
        $params["Account"] = $managedCreds
        $Script:dscConfigContent += "        SPManagedAccount " + (Check-Credentials $managedAccount.Username).Replace("$","") + "`r`n"
        $Script:dscConfigContent += "        {`r`n"
        $results = Get-TargetResource @params
        $Script:dscConfigContent += Get-DSCBlock -Params $results -ModulePath $module
        $Script:dscConfigContent += "        }`r`n"
    }
}

<## This function retrieves all Services in the SharePoint farm. It does not care if the service is enabled or not. It lists them all, and simply sets the "Ensure" attribute of those that are disabled to "Absent". #>
function Read-SPServiceInstance ($modulePath, $params){
    if($modulePath -ne $null)
    {
        $module = Resolve-Path $modulePath
    }
    else {
        $module = Resolve-Path ($Script:SPDSCPath + "\DSCResources\MSFT_SPServiceInstance\MSFT_SPServiceInstance.psm1")
        Import-Module $module
    }    

    $serviceInstances = Get-SPServiceInstance | Where{$_.Server.Name -eq $Server} | Sort-Object -Property TypeName

    if($params -eq $null)
    {
        $params = Get-DSCFakeParameters -FilePath $module
    }

    foreach($serviceInstance in $serviceInstances)
    {
        $params.Name = $serviceInstance.Name
        if($serviceInstance.TypeName -eq "Distributed Cache")
        {
            $Script:dscConfigContent += "        SPDistributedCacheService " + $serviceInstance.TypeName.Replace(" ", "") + "Instance`r`n"
            $Script:dscConfigContent += "        {`r`n"
            $results = Get-TargetResource @params
            $Script:dscConfigContent += Get-DSCBlock -Params $results -ModulePath $module
            $Script:dscConfigContent += "        }`r`n"
        }
        elseif($serviceInstance.TypeName -eq "User Profile Synchronization Service")
        {
            $Script:dscConfigContent += "        SPUserProfileSyncService " + $serviceInstance.TypeName.Replace(" ", "") + "Instance`r`n"
            $Script:dscConfigContent += "        {`r`n"
            $results = Get-TargetResource @params
            $Script:dscConfigContent += Get-DSCBlock -Params $results -ModulePath $module
            $Script:dscConfigContent += "        }`r`n"
        }
        else
        {
            $Script:dscConfigContent += "        SPServiceInstance " + $serviceInstance.TypeName.Replace(" ", "") + "Instance`r`n"
            $Script:dscConfigContent += "        {`r`n"
            $results = Get-TargetResource @params
            $Script:dscConfigContent += Get-DSCBlock -Params $results -ModulePath $module
            $Script:dscConfigContent += "        }`r`n"
        }
    }
}

<## This function retrieves all settings related to Diagnostic Logging (ULS logs) on the SharePoint farm. #>
function Read-DiagnosticLoggingSettings ($modulePath, $params){
    if($modulePath -ne $null)
    {
        $module = Resolve-Path $modulePath
    }
    else {
        $module = Resolve-Path ($Script:SPDSCPath + "\DSCResources\MSFT_SPDiagnosticLoggingSettings\MSFT_SPDiagnosticLoggingSettings.psm1")
        Import-Module $module
    }
   
    if($params -eq $null)
    {
        $params = Get-DSCFakeParameters -FilePath $module
    }
    $diagConfig = Get-SPDiagnosticConfig    

    $Script:dscConfigContent += "        SPDiagnosticLoggingSettings ApplyDiagnosticLogSettings`r`n"
    $Script:dscConfigContent += "        {`r`n"
    $results = Get-TargetResource @params
    $Script:dscConfigContent += Get-DSCBlock -Params $results -ModulePath $module
    $Script:dscConfigContent += "        }`r`n"
}

<## This function retrieves all settings related to the SharePoint Usage Service Application, assuming it exists. #>
function Read-UsageServiceApplication ($modulePath, $params){
    if($modulePath -ne $null)
    {
        $module = Resolve-Path $modulePath
    }
    else {
        $module = Resolve-Path ($Script:SPDSCPath + "\DSCResources\MSFT_SPUsageApplication\MSFT_SPUsageApplication.psm1")
        Import-Module $module
    }
    if($params -eq $null)
    {
        $params = Get-DSCFakeParameters -FilePath $module
    }

    $usageApplication = Get-SPUsageApplication
    if($usageApplication.Length -gt 0)
    {
        $Script:dscConfigContent += "        SPUsageApplication " + $usageApplication.TypeName.Replace(" ", "") + "`r`n"
        $Script:dscConfigContent += "        {`r`n"
        $results = Get-TargetResource @params
        $Script:dscConfigContent += Get-DSCBlock -Params $results -ModulePath $module
        $Script:dscConfigContent += "        }`r`n"
    }
}

<## This function retrieves settings associated with the State Service Application, assuming it exists. #>
function Read-StateServiceApplication ($modulePath, $params){
    if($modulePath -ne $null)
    {
        $module = Resolve-Path $modulePath
    }
    else {
        $module = Resolve-Path ($Script:SPDSCPath + "\DSCResources\MSFT_SPStateServiceApp\MSFT_SPStateServiceApp.psm1")
        Import-Module $module
    }
    
    if($params -eq $null)
    {
        $params = Get-DSCFakeParameters -FilePath $module
    }

    $stateApplications = Get-SPStateServiceApplication
    foreach($stateApp in $stateApplications)
    {
        if($stateApp -ne $null)
        {
            $params.Name = $stateApp.DisplayName
            $Script:dscConfigContent += "        SPStateServiceApp " + $stateApp.DisplayName.Replace(" ", "") + "`r`n"
            $Script:dscConfigContent += "        {`r`n"
            $results = Get-TargetResource @params
            $Script:dscConfigContent += Get-DSCBlock -Params $results -ModulePath $module
            $Script:dscConfigContent += "        }`r`n"
        }
    }
}

<## This function retrieves information about all the "Super" accounts (Super Reader & Super User) used for caching. #>
function Read-CacheAccounts ($modulePath, $params){
    if($modulePath -ne $null)
    {
        $module = Resolve-Path $modulePath
    }
    else {
        $module = Resolve-Path ($Script:SPDSCPath + "\DSCResources\MSFT_SPCacheAccounts\MSFT_SPCacheAccounts.psm1")
        Import-Module $module
    }
    
    if($params -eq $null)
    {
        $params = Get-DSCFakeParameters -FilePath $module
    }

    $webApps = Get-SPWebApplication

    foreach($webApp in $webApps)
    {
        $params.WebAppUrl = $webApp.Url
        $results = Get-TargetResource @params

        $accountsMissing = 0
        if($results.SuperReaderAlias -ne "" -and $results.SuperUserAlias -ne "")
        {
            $Script:dscConfigContent += "        SPCacheAccounts " + $webApp.DisplayName.Replace(" ", "") + "CacheAccounts`r`n"
            $Script:dscConfigContent += "        {`r`n"        
            $Script:dscConfigContent += Get-DSCBlock -Params $results -ModulePath $module
            $Script:dscConfigContent += "        }`r`n"
        }
    }
}

<## This function retrieves settings related to the User Profile Service Application. #>
function Read-UserProfileServiceapplication ($modulePath, $params){
    if($modulePath -ne $null)
    {
        $module = Resolve-Path $modulePath
    }
    else {
        $module = Resolve-Path ($Script:SPDSCPath + "\DSCResources\MSFT_SPUserProfileServiceApp\MSFT_SPUserProfileServiceApp.psm1")
        Import-Module $module
    }
    
    if($params -eq $null)
    {
        $params = Get-DSCFakeParameters -FilePath $module
    }

    $ups = Get-SPServiceApplication | Where{$_.TypeName -eq "User Profile Service Application"}

    $sites = Get-SPSite
    if($sites.Length -gt 0)
    {
        $context = Get-SPServiceContext $sites[0]
        try
        {
            $pm = new-object Microsoft.Office.Server.UserProfiles.UserProfileManager($context)
        }
        catch{
            $Script:dscConfigContent += "        <# WARNING: It appears the farm account doesn't have Full Control to the User Profile Service Aplication. This is currently preventing the script from determining the exact path for the MySite Host (if configured). Please ensure the Farm account is granted Full Control on the User Profile Service Application. #>`r`n"
            Write-Host "WARNING - Farm Account does not have Full Control on the User Profile Service Application." -BackgroundColor Yellow -ForegroundColor Black
        }

        if($ups -ne $null)
        {
            $params.Name = $ups.DisplayName
            $Script:dscConfigContent += "        SPUserProfileServiceApp UserProfileServiceApp`r`n"
            $Script:dscConfigContent += "        {`r`n"
            $results = Get-TargetResource @params
            $Script:dscConfigContent += Get-DSCBlock -Params $results -ModulePath $module
            $Script:dscConfigContent += "        }`r`n"
        }
    }
}

<## This function retrieves all settings related to the Secure Store Service Application. Currently this function makes a direct call to the Secure Store database on the farm's SQL server to retrieve information about the logging details. There are currently no publicly available hooks in the SharePoint/Office Server Object Model that allow us to do it. This forces the user executing this reverse DSC script to have to install the SQL Server Client components on the server on which they execute the script, which is not a "best practice". #>
<# TODO: Change the logic to extract information about the logging from being a direct SQL call to something that uses the Object Model. #>
function Read-SecureStoreServiceApplication ($modulePath, $params){
    if($modulePath -ne $null)
    {
        $module = Resolve-Path $modulePath
    }
    else {
        $module = Resolve-Path ($Script:SPDSCPath + "\DSCResources\MSFT_SPSecureStoreServiceApp\MSFT_SPSecureStoreServiceApp.psm1")
        Import-Module $module
    }
    
    if($params -eq $null)
    {
        $params = Get-DSCFakeParameters -FilePath $module
    }

    $ssa = Get-SPServiceApplication | Where{$_.TypeName -eq "Secure Store Service Application"}
    for($i = 0; $i -lt $ssa.Length; $i++)
    {
        $params.Name = $ssa.DisplayName
        $Script:dscConfigContent += "        SPSecureStoreServiceApp " + $ssa[$i].Name.Replace(" ", "") + "`r`n"
        $Script:dscConfigContent += "        {`r`n"
        $results = Get-TargetResource @params

        # HACK: Can't dynamically retrieve value from the Secure Store at the moment #>
        $results.Add("AuditingEnabled", $true)

        $Script:dscConfigContent += Get-DSCBlock -Params $results -ModulePath $module
        $Script:dscConfigContent += "        }`r`n"        
    }
}

<## This function retrieves settings related to the Managed Metadata Service Application. #>
function Read-ManagedMetadataServiceApplication ($modulePath, $params){
    if($modulePath -ne $null)
    {
        $module = Resolve-Path $modulePath
    }
    else {
        $module = Resolve-Path ($Script:SPDSCPath + "\DSCResources\MSFT_SPManagedMetadataServiceApp\MSFT_SPManagedMetadataServiceApp.psm1")
        Import-Module $module
    }
    
    if($params -eq $null)
    {
        $params = Get-DSCFakeParameters -FilePath $module
    }

    $mms = Get-SPServiceApplication | Where{$_.TypeName -eq "Managed Metadata Service"}
    if (Get-Command "Get-SPMetadataServiceApplication" -errorAction SilentlyContinue)
    {
        foreach($mmsInstance in $mms)
        {
            if($mmsInstance -ne $null)
            {
                $params.Name = $mmsInstance.Name
                $Script:dscConfigContent += "        SPManagedMetaDataServiceApp " + $mmsInstance.Name.Replace(" ", "") + "`r`n"
                $Script:dscConfigContent += "        {`r`n"
                $results = Get-TargetResource @params
                $Script:dscConfigContent += Get-DSCBlock -Params $results -ModulePath $module
                $Script:dscConfigContent += "        }`r`n"
            }
        }
    }
}

<## This function retrieves settings related to the Business Connectivity Service Application. #>
function Read-BCSServiceApplication ($modulePath, $params){
    if($modulePath -ne $null)
    {
        $module = Resolve-Path $modulePath
    }
    else {
        $module = Resolve-Path ($Script:SPDSCPath + "\DSCResources\MSFT_SPBCSServiceApp\MSFT_SPBCSServiceApp.psm1")
        Import-Module $module
    }
    
    if($params -eq $null)
    {
        $params = Get-DSCFakeParameters -FilePath $module
    }

    $bcsa = Get-SPServiceApplication | Where{$_.TypeName -eq "Business Data Connectivity Service Application"}
    
    foreach($bcsaInstance in $bcsa)
    {
        if($bcsaInstance -ne $null)
        {
            $Script:dscConfigContent += "        SPBCSServiceApp " + $bcsaInstance.Name.Replace(" ", "") + "`r`n"
            $Script:dscConfigContent += "        {`r`n"
            $params.Name = $bcsa.DisplayName
            $results = Get-TargetResource @params
            $Script:dscConfigContent += Get-DSCBlock -Params $results -ModulePath $module
            $Script:dscConfigContent += "        }`r`n"        
        }
    }
}

<## This function retrieves settings related to the Search Service Application. #>
function Read-SearchServiceApplication ($modulePath, $params){
    if($modulePath -ne $null)
    {
        $module = Resolve-Path $modulePath
    }
    else {
        $module = Resolve-Path ($Script:SPDSCPath + "\DSCResources\MSFT_SPSearchServiceApp\MSFT_SPSearchServiceApp.psm1")
        Import-Module $module
    }    
    
    if($params -eq $null)
    {
        $params = Get-DSCFakeParameters -FilePath $module
    }

    $searchSA = Get-SPServiceApplication | Where{$_.TypeName -eq "Search Service Application"}
    
    foreach($searchSAInstance in $searchSA)
    {
        if($searchSAInstance -ne $null)
        {
            $Script:dscConfigContent += "        SPSearchServiceApp " + $searchSAInstance.Name.Replace(" ", "") + "`r`n"
            $Script:dscConfigContent += "        {`r`n"
            $params.Name = $searchSAInstance.Name
            $results = Get-TargetResource @params
            $Script:dscConfigContent += Get-DSCBlock -Params $results -ModulePath $module
            $Script:dscConfigContent += "        }`r`n"  
        }
    }
}

<## This function sets the settings for the Local Configuration Manager (LCM) component on the server we will be configuring using our resulting DSC Configuration script. The LCM component is the one responsible for orchestrating all DSC configuration related activities and processes on a server. This method specifies settings telling the LCM to not hesitate rebooting the server we are configurating automatically if it requires a reboot (i.e. During the SharePoint Prerequisites installation). Setting this value helps reduce the amount of manual interaction that is required to automate the configuration of our SharePoint farm using our resulting DSC Configuration script. #>
function Set-LCM
{
    $Script:dscConfigContent += "        LocalConfigurationManager"  + "`r`n"
    $Script:dscConfigContent += "        {`r`n"
    $Script:dscConfigContent += "            RebootNodeIfNeeded = `$True`r`n"
    $Script:dscConfigContent += "        }`r`n"
}

function Invoke-SQL {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Server,
        [Parameter(Mandatory=$true)]
        [string]$dbName,
        [Parameter(Mandatory=$true)]
        [string]$sqlQuery
    )
 
    $ConnectString="Data Source=${Server}; Integrated Security=SSPI; Initial Catalog=${dbName}"
 
    $Conn= New-Object System.Data.SqlClient.SQLConnection($ConnectString)
    $Command = New-Object System.Data.SqlClient.SqlCommand($sqlQuery,$Conn)
    $Conn.Open()
 
    $Adapter = New-Object System.Data.SqlClient.SqlDataAdapter $Command
    $DataSet = New-Object System.Data.DataSet
    $Adapter.Fill($DataSet) | Out-Null
 
    $Conn.Close()
    $DataSet.Tables
}


<## This method is used to determine if a specific PowerShell cmdlet is available in the current Powershell Session. It is currently used to determine wheter or not the user has access to call the Invoke-SqlCmd cmdlet or if he needs to install the SQL Client coponent first. It simply returns $true if the cmdlet is available to the user, or $false if it is not. #>
function Test-CommandExists
{
    param ($command)

    $errorActionPreference = "stop"
    try {
        if(Get-Command $command)
        {
            return $true
        }
    }
    catch
    {
        return $false
    }
}

function Get-SPReverseDSC()
{
    <## Call into our main function that is responsible for extracting all the information about our SharePoint farm. #>
    Orchestrator

    <## Prompts the user to specify the FOLDER path where the resulting PowerShell DSC Configuration Script will be saved. #>
    $OutputDSCPath = Read-Host "Output Folder for DSC Configuration"

    <## Ensures the path we specify ends with a Slash, in order to make sure the resulting file path is properly structured. #>
    if(!$OutputDSCPath.EndsWith("\") -and !$OutputDSCPath.EndsWith("/"))
    {
        $OutputDSCPath += "\"
    }

    <## Save the content of the resulting DSC Configuration file into a file at the specified path. #>
    $OutputDSCPath += "SP-Farm.DSC.ps1"
    $Script:dscConfigContent | Out-File $OutputDSCPath
}

Add-PSSnapin Microsoft.SharePoint.PowerShell -EA SilentlyContinue
Get-SPReverseDSC