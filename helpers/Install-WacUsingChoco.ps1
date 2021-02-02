configuration WindowsAdminCenter
{
    Import-DscResource -ModuleName 'cChoco'
    Import-DscResource -ModuleName 'ComputerManagementDsc'

    node localhost
    {
        LocalConfigurationManager {
            RebootNodeIfNeeded = $true
            ActionAfterReboot  = 'ContinueConfiguration'
            ConfigurationMode = 'ApplyAndAutoCorrect'
            ConfigurationModeFrequencyMins = 1440
        }

        cChocoInstaller InstallChoco
        {
            InstallDir = "c:\choco"
        }

        cChocoFeature allowGlobalConfirmation 
        {

            FeatureName = "allowGlobalConfirmation"
            Ensure      = 'Present'
            DependsOn   = '[cChocoInstaller]installChoco'
        }

        cChocoFeature useRememberedArgumentsForUpgrades 
        {

            FeatureName = "useRememberedArgumentsForUpgrades"
            Ensure      = 'Present'
            DependsOn   = '[cChocoInstaller]installChoco'
        }

        cChocoPackageInstaller "Install Windows Admin Center on 443"
        {
            Name        = 'windows-admin-center'
            Ensure      = 'Present'
            AutoUpgrade = $true
            DependsOn   = '[cChocoInstaller]installChoco'
            Params      = "'/Port:443'"
        }
        
        PendingReboot "reboot"
        {
            Name = 'reboot'
        }

        Script "Fake reboot"
        {
            TestScript = {
                return (Test-Path HKLM:\SOFTWARE\RebootKey)
            }
            SetScript = {
                New-Item -Path HKLM:\SOFTWARE\RebootKey -Force
                $global:DSCMachineStatus = 1 
            }
            GetScript = {
                return @{result = 'result'}
            }
            DependsOn = "[cChocoPackageInstaller]Install Windows Admin Center on 443"
        }
        
        script "Windows Admin Center updater"
        {
            GetScript = {
                
                # Specify the WAC gateway
                $wac = "https://$env:COMPUTERNAME"
                
                # Add the module to the current session
                $module = "$env:ProgramFiles\Windows Admin Center\PowerShell\Modules\ExtensionTools\ExtensionTools.psm1"

                Import-Module -Name $module -Verbose -Force
                
                # List the WAC extensions
                $extensions = Get-Extension $wac | Where-Object {$_.isLatestVersion -like 'False'}
                
                $result = if ($extensions.count -gt 0) {$false} else {$true}

                return @{
                    Wac = $WAC
                    extensions = $extensions
                    result = $result
                }
            }
            TestScript = {
                # Create and invoke a scriptblock using the $GetScript automatic variable, which contains a string representation of the GetScript.
                $state = [scriptblock]::Create($GetScript).Invoke()
                return $state.Result
            }
            SetScript = {
                $state = [scriptblock]::Create($GetScript).Invoke()

                $date = get-date -f yyyy-MM-dd

                $logFile = Join-Path -Path "C:\Users\Public" -ChildPath $('WACUpdateLog-' + $date + '.log')

                New-Item -Path $logFile -ItemType File -Force
                
                ForEach($extension in $state.extensions)
                {    
                    Update-Extension $state.wac -ExtensionId $extension.Id -Verbose | Out-File -Append -FilePath $logFile -Force
                }

                # Delete log files older than 30 days
                Get-ChildItem -Path "C:\Users\Public\WACUpdateLog*" -Recurse -Include @("*.log") | Where-Object { $_.CreationTime -lt (Get-Date).AddDays(-30)} | Remove-Item
            }
            DependsOn = "[Script]Fake reboot"
        }
    }
}


$date = get-date -f yyyy-MM-dd
$logFile = Join-Path -Path "C:\temp" -ChildPath $('WindowsAdminCenter-Transcipt-' + $date + '.log')
$DscConfigLocation = "c:\temp\WindowsAdminCenter"

Start-Transcript -Path $logFile

Remove-DscConfigurationDocument -Stage Current, Previous, Pending -Force

WindowsAdminCenter -OutputPath $DscConfigLocation 

Set-DscLocalConfigurationManager -Path $DscConfigLocation -Verbose

Start-DscConfiguration -Path $DscConfigLocation -Wait -Verbose

Start-DscConfiguration -UseExisting -Wait -Verbose -Force

Stop-Transcript

Logoff
