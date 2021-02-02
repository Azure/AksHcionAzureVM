function Cleanup-VMs
{
    [CmdletBinding(
        DefaultParameterSetName = 'default',
        SupportsShouldProcess,
        ConfirmImpact = 'High'
    )]
    Param
    (
        [Parameter(ParameterSetName = 'default')]
        [Parameter(Mandatory=$false)]
        [Switch]
        $AzureStackHciHostVMs,

        [Parameter(ParameterSetName = 'default')]
        [Parameter(Mandatory=$false)]
        [Switch]
        $WindowsAdminCenterVM,

        [Parameter(ParameterSetName = 'default')]
        [Parameter(Mandatory=$false)]
        [Switch]
        $DoNotRedeploy,

        [Parameter(ParameterSetName = 'default')]
        [Parameter(Mandatory=$false)]
        [Switch]
        $RemoveAllSourceFiles
    )

    Begin
    {
        #initializing variables
        $domainName = (Get-ADDomain).DnsRoot
        $dhcpScopeString = '192.168.0.0'
        $sleep = 300

    }
    Process
    {
        if ($AzureStackHciHostVMs)
        {
            $AzureStackHCIClusterName = 'hci01'
            $AzureStackHCIHosts = Get-VM "hpv*" -ErrorAction SilentlyContinue
            $ouName = $AzureStackHCIClusterName
            $servers = $AzureStackHCIHosts.Name + $AzureStackHCIClusterName
            
            if ($AzureStackHCIHosts)
            {
                if ($PSCmdlet.ShouldProcess($AzureStackHCIHosts,'Turn off and Remove'))
                {
                    Write-Verbose "[Cleanup-VMs]: Removing Azure Stack HCI hosts, cluster and related DHCP, DNS records and computer accounts"
                    #remove Azure Stack HCI hosts
                    $AzureStackHCIHosts | Stop-VM -TurnOff -Passthru | Remove-VM -Force
                    Remove-Item -Path $AzureStackHCIHosts.ConfigurationLocation -Recurse -Force

                    #remove Azure Stack HCI hosts DNS records, DHCP leases and Disable Computer Accounts
                    Write-Verbose "[Cleanup-VMs]: Removing Dns Records for $($AzureStackHCIHosts.Name + "." + "$domainname")"
                    $AzureStackHCIHosts.Name | ForEach-Object {Get-DnsServerResourceRecord -ZoneName $domainName -Name $_ -ErrorAction SilentlyContinue | Remove-DnsServerResourceRecord -ZoneName $domainName -Force}
            
                    Write-Verbose "[Cleanup-VMs]: Removing Dhcp lease for $($AzureStackHCIHosts.Name)"
                    $AzureStackHCIHosts.Name | ForEach-Object {Get-DhcpServerv4Lease -ScopeId $dhcpScopeString -ErrorAction SilentlyContinue | Where-Object hostname -like $_* | Remove-DhcpServerv4Lease}
            
                    Write-Verbose "[Cleanup-VMs]: Removing Dns Records for $($AzureStackHCIClusterName + "." + "$domainname")"
                    $AzureStackHCIClusterName | ForEach-Object {Get-DnsServerResourceRecord -ZoneName $domainName -Name $_ -ErrorAction SilentlyContinue | Remove-DnsServerResourceRecord -ZoneName $domainName -Force}
            
                    Write-Verbose "[Cleanup-VMs]: Removing Dhcp lease for $AzureStackHCIClusterName"
                    $AzureStackHCIClusterName | ForEach-Object {Get-DhcpServerv4Lease -ScopeId $dhcpScopeString -ErrorAction SilentlyContinue | Where-Object hostname -like $_* | Remove-DhcpServerv4Lease}
            
                    Write-Verbose "[Cleanup-VMs]: Removing AD Computer for $servers"
                    $servers | Get-ADComputer -ErrorAction SilentlyContinue | Remove-ADObject -Recursive -Confirm:$false
            
                    Write-Verbose "[Cleanup-VMs]: Removing the OU: $ouName"
                    Get-ADOrganizationalUnit -Filter * | where-object name -eq $ouName | Set-ADOrganizationalUnit -ProtectedFromAccidentalDeletion $false -PassThru | Remove-ADOrganizationalUnit -Recursive -Confirm:$false
                }
            }
        }

        if ($WindowsAdminCenterVM)
        {
            $wac = Get-VM wac -ErrorAction SilentlyContinue
            if ($wac)
            {
                if ($PSCmdlet.ShouldProcess($wac,'Turn off and Remove'))
                {
                    Write-Verbose "[Cleanup-VMs]: Removing Windows Center VM and related DHCP, DNS records and computer account"
                    #remove Windows Admin Center host
                    $wac | Stop-VM -TurnOff -Passthru | Remove-VM -Force
                    Remove-Item -Path $wac.ConfigurationLocation -Recurse -Force
            
                    #remove Windows Admin Center host DNS record, DHCP lease
                    Write-Verbose "[Cleanup-VMs]: Removing Dns Records for $($wac.Name + "." + "$domainname")"
                    Get-DnsServerResourceRecord -ZoneName $domainName -Name $wac.Name -ErrorAction SilentlyContinue | Remove-DnsServerResourceRecord -ZoneName $domainName -Force
                    Write-Verbose "[Cleanup-VMs]: Removing Dhcp lease for $($wac.Name)"
                    Get-DhcpServerv4Lease -ScopeId $dhcpScopeString -ErrorAction SilentlyContinue | Where-Object hostname -like $wac.Name | Remove-DhcpServerv4Lease
                    Write-Verbose "[Cleanup-VMs]: Removing AD Computer for $($wac.Name)"
                    $wac.name | Get-ADComputer | Remove-ADObject -Recursive -Confirm:$false
                }
            }
        }

        if ($RemoveAllSourceFiles) {
            if ($PSCmdlet.ShouldProcess('PoC Source files','Remove'))
            {
                Remove-Item v:\ -Recurse -Force
            }
        }

        if (-not ($DoNotRedeploy))
        {
            if ($PSCmdlet.ShouldProcess('Re-Apply DSC configuration to restore VMs','Apply'))
            {
                
                Write-Verbose "[Cleanup-VMs]: Recalling DSC config to restore default state."
                Start-DscConfiguration -UseExisting -Wait -Force
                Write-Verbose "[Cleanup-VMs]: DSC config re-applied, check for any error!"
                if ($AzureStackHciHostVMs -or $WindowsAdminCenterVM)
                {
                        Write-Verbose "[Cleanup-VMs]: Sleeping for $sleep seconds to make sure Azure Stack HCI hosts are reachable"
                        Start-Sleep -Seconds $sleep
                        Clear-DnsClientCache
                
                }
            }
        }
        
        Write-Verbose "[Prepare AD]: Creating computer accounts in AD if not exist and configuring delegations for Windows Admin Center"
        Prepare-AdforAzsHciDeployment

    }
    End
    {
    }
}

function Prepare-AzsHciPackage
{
    [CmdletBinding()]
    Param
    (
    )

    Begin
    {
        #variables
        $targetDrive = "V:"
        $sourcePath =  "$targetDrive\source"
        $aksSource = "$sourcePath\aksHciSource"
    }
    Process
    {
        #create source folder for AKS bits
        New-Item -Path $aksSource -ItemType Directory -Force

        #Download AKS on Azure Stack HCI tools if no exist
        if (-not (Test-Path -Path "$aksSource\aks-hci-tools.zip" -ErrorAction SilentlyContinue))
        {
            Write-Verbose "[Prepare-AzsHciPackage]: Downloading AKS on Azure Stack HCI tools from https://aka.ms/aks-hci-download"
            Start-BitsTransfer -Source https://aka.ms/aks-hci-download -Destination "$aksSource\aks-hci-tools.zip" -Confirm:$false
        }
        
        #unblock download file
        Unblock-File -Path "$aksSource\aks-hci-tools.zip"

        #Unzip download file if not unzipped
        if (-not (Test-Path -Path "$aksSource\aks-hci-tools" -ErrorAction SilentlyContinue))
        {
            Write-Verbose "[Prepare-AzsHciPackage]: Unzip downloaded file: aks-hci-tools.zip"
            Expand-Archive -Path "$aksSource\aks-hci-tools.zip" -DestinationPath "$aksSource\aks-hci-tools" -Force
        }

        #Unzip Powershell modules if not unzipped
        if (-not (Test-Path -Path "$aksSource\aks-hci-tools\Powershell\Modules" -ErrorAction SilentlyContinue))
        {
            Write-Verbose "[Prepare-AzsHciPackage]: Unzip Aks Hci PowerShell module"
            Expand-Archive -Path "$aksSource\aks-hci-tools\AksHci.Powershell.zip" -DestinationPath "$aksSource\aks-hci-tools\Powershell\Modules" -Force
        }
    }
    End
    {
    }
}

function Prepare-AzureVMforAksHciDeployment
{
    [CmdletBinding()]
    Param
    (
    )

    Begin
    {
                #variables
                $targetDrive = "V:"
                $sourcePath =  "$targetDrive\source"
                $aksSource = "$sourcePath\aksHciSource"
                $aksHCITargetPath = "$targetDrive\AksHciMain"
    }

    Process
    {
        Prepare-AzsHciPackage

        #Copy AksHCI modules to Azure Stack HCI hosts
        $AzureStackHCIHosts.Name | ForEach-Object {Copy-Item "$aksSource\aks-hci-tools\Powershell\Modules" "c:\Program Files\WindowsPowershell\" -Recurse -Force}

        New-Item -Path $aksHCITargetPath -ItemType Directory -Force
    }
    
    End
    {
    }
}

function Prepare-AdforAzsHciDeployment
{
    [CmdletBinding()]
    Param
    (
    
    )

    Begin
    {
        #variables
        $wac = "wac"
        $AzureStackHCIHosts = Get-VM hpv*
        $AzureStackHCIClusterName = "hci01"
        $ouName = "hci01"
    }
    Process
    {
        #New organizational Unit for cluster
        $dn = Get-ADOrganizationalUnit -Filter * | Where-Object name -eq $ouName
        if (-not ($dn))
        {
            $dn = New-ADOrganizationalUnit -Name $ouName -PassThru
        }
        
        #Get Wac Computer Object
        $wacObject = Get-ADComputer -Filter * | Where-Object name -eq wac
        if (-not ($wacObject))
        {
            $wacObject = New-ADComputer -Name $wac -Enabled $false -PassThru
        }

        #Creates Azure Stack HCI hosts if not exist
        if ($AzureStackHCIHosts.Name)
        {
            $AzureStackHCIHosts.Name | ForEach-Object {
                $comp = Get-ADComputer -Filter * | Where-Object name -eq $_
                if (-not ($comp))
                {
                    New-ADComputer -Name $_ -Enabled $false -Path $dn -PrincipalsAllowedToDelegateToAccount $wacObject
                }
                else
                {
                    $comp | Set-ADComputer -PrincipalsAllowedToDelegateToAccount $wacObject
                    $comp | Move-AdObject -TargetPath $dn
                }
            }
        }

        #Creates Azure Stack HCI Cluster CNO if not exist
        $AzureStackHCIClusterObject = Get-ADComputer -Filter * | Where-Object name -eq $AzureStackHCIClusterName
        if (-not ($AzureStackHCIClusterObject))
        {
            $AzureStackHCIClusterObject = New-ADComputer -Name $AzureStackHCIClusterName -Enabled $false -Path $dn -PrincipalsAllowedToDelegateToAccount $wacObject -PassThru
        }
        else
        {
            $AzureStackHCIClusterObject | Set-ADComputer -PrincipalsAllowedToDelegateToAccount $wacObject
            $AzureStackHCIClusterObject | Move-AdObject -TargetPath $dn
        }    

        #read OU DACL
        $acl = Get-Acl -Path "AD:\$dn"

        # Set properties to allow Cluster CNO to Full Control on the new OU
        $principal = New-Object System.Security.Principal.SecurityIdentifier ($AzureStackHCIClusterObject).SID
        $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($principal, [System.DirectoryServices.ActiveDirectoryRights]::GenericAll, [System.Security.AccessControl.AccessControlType]::Allow, [DirectoryServices.ActiveDirectorySecurityInheritance]::All)

        #modify DACL
        $acl.AddAccessRule($ace)

        #Re-apply the modified DACL to the OU
        Set-ACL -ACLObject $acl -Path "AD:\$dn"
    }
    End
    {
    }
}

Function Configure-AzsHciClusterRoles
{
    [CmdletBinding()]

    Param
    (
    )

    begin 
    {
        #initializing variables
        $AzureStackHCIHosts = Get-VM hpv*
        
        #Enable Roles 
        $rolesToEnable = @("File-Services", "FS-FileServer", "FS-Data-Deduplication", "BitLocker", "Data-Center-Bridging", "EnhancedStorage", "Failover-Clustering", "RSAT", "RSAT-Feature-Tools", "RSAT-DataCenterBridging-LLDP-Tools", "RSAT-Clustering", "RSAT-Clustering-PowerShell", "RSAT-Role-Tools", "RSAT-AD-Tools", "RSAT-AD-PowerShell", "RSAT-Hyper-V-Tools", "Hyper-V-PowerShell")
        $rolesToDisable = @("telnet-client")

        #new PsSession to 
        $psSession = New-PSSession -ComputerName $AzureStackHCIHosts.Name
    }

    process
    {
        Write-Verbose "Enabling/Disabling Roles and Features required on Azure Stack HCI Hosts"
        Invoke-Command -Session $psSession -ScriptBlock {
            $VerbosePreference=$using:VerbosePreference
            if ($using:rolesToEnable.Count -gt 0)
            {
                Write-Verbose "Installing following required roles/features to Azure Stack HCI hosts"
                $using:rolesToEnable | Write-Verbose
                Install-WindowsFeature -Name $using:rolesToEnable
            }
    
            if ($using:rolesToDisable.Count -gt 0)
            {
                Write-Verbose "Removing following unnecessary roles/features from Azure Stack HCI hosts"
                $using:rolesToDisable | Write-Verbose
                Remove-WindowsFeature -Name $using:rolesToDisable
            }
        }
            
    }
    
    end
    {
        Remove-PSSession -Session $psSession
        Remove-Variable -Name psSession
    }   
}

Function Configure-AzsHciClusterNetwork
{

    [CmdletBinding(DefaultParameterSetName='Configure', SupportsShouldProcess=$true)]
    param (
    
        [Parameter(ParameterSetName='Configure')]
        [Parameter(Mandatory=$false)]
        [ValidateSet("HighAvailable","SingleAdapter","Dummy")]
        [string]
        $ManagementInterfaceConfig = "HighAvailable",

        [Parameter(ParameterSetName='Configure')]
        [Parameter(Mandatory=$false)]
        [ValidateSet("OneVirtualSwitchforAllTraffic","OneVirtualSwitchforComputeOnly","TwoVirtualSwitches","Dummy")]
        [string]
        $ComputeAndStorageInterfaceConfig = "OneVirtualSwitchforAllTraffic",

        [Parameter(ParameterSetName='Cleanup')]
        [Parameter(Mandatory=$false)]
        [switch]
        $CleanupConfiguration,

        [Parameter(ParameterSetName='Configure')]
        [Parameter(Mandatory=$false)]
        [switch]
        $ForceCleanup
    )

    begin 
    {
        #initializing variables
        $AzureStackHCIHosts = Get-VM hpv*
        $vSwitchNameMgmt = 'Management'
        $vSwitchNameConverged = "Default Switch"
        $vSwitchNameCompute = "Default Switch"
        $vSwitchNameStorage = "StorageSwitch"

        #Enable Roles 
        $rolesToEnable = @("File-Services", "FS-FileServer", "FS-Data-Deduplication", "BitLocker", "Data-Center-Bridging", "EnhancedStorage", "Failover-Clustering", "RSAT", "RSAT-Feature-Tools", "RSAT-DataCenterBridging-LLDP-Tools", "RSAT-Clustering", "RSAT-Clustering-PowerShell", "RSAT-Role-Tools", "RSAT-AD-Tools", "RSAT-AD-PowerShell", "RSAT-Hyper-V-Tools", "Hyper-V-PowerShell")
        $rolesToDisable = @()

        Clear-DnsClientCache

        #Disable DHCP Scope to prevent IP address from DHCP
        Set-DhcpServerv4Scope -ScopeId 192.168.100.0 -State InActive

        #new PsSession to 
        $psSession = New-PSSession -ComputerName $AzureStackHCIHosts.Name
    }

    process
    {
        if ($cleanupConfiguration)
        {
            Write-Verbose "[Cleanup]: Current network configuration"
            Invoke-Command -Session $psSession -ScriptBlock {
            $vSwitch = Get-VMSwitch
            $VerbosePreference=$using:VerbosePreference
            Write-Verbose "[Cleanup]: Following vSwitch/es will be removed from Azure Stack HCI hosts"
            
            if ($vSwitch)
            {
                $vSwitch.Name | Write-Verbose                
            }

            if ($vSwitch.Name -contains $using:vSwitchNameMgmt)
            {
                Write-Warning -Message "[Cleanup]: $env:COMPUTERNAME Network connection will be interupted for couple of minutes, be patient!!"
                    
            }
            $vSwitch | Remove-VMSwitch -Force
        }

            Clear-DnsClientCache

            Write-Verbose "[Cleanup]: Scramble Nic names to prevent name conflict"
            Invoke-Command -Session $psSession -ScriptBlock {
                $i = get-random -Minimum 100000 -max 999999
                Get-NetAdapter | foreach {Rename-NetAdapter -Name $_.Name -NewName $i; $i++}
            }

            Invoke-Command -Session $psSession -ScriptBlock {
                $adapter = Get-NetAdapter | Where-Object status -eq "disabled"
                $VerbosePreference=$using:VerbosePreference
                if ($adapter)
                {
                    Write-Verbose "[Cleanup]: Following adapters will be enabled on Azure Stack HCI hosts"
                    $adapter.Name | Write-Verbose
                    $adapter | Enable-NetAdapter -Confirm:$false -Passthru
                }
            }
        
            Write-Verbose "[Cleanup]: Recalling DSC config to restore default state"
        
            Start-DscConfiguration -UseExisting -Wait -Verbose:$false
        
        }
        else
        {
            $state = Invoke-Command -Session $psSession -ScriptBlock {
                Get-NetAdapter -Name Management*
            }
            if ($ForceCleanup)
            {
                Write-Warning "Current configuration detected! ForceCleanup switch Enabled. Cleaning up"
                Configure-AzsHciClusterNetwork -CleanupConfiguration
            }
            elseif ($state)
            {
                Write-Warning "Current configuration detected! Cleanup required"
                
                Write-Host "Continue cleanup ? Continue without cleanup, recommended though 'n'o!!! Default action is cleanup. : " -Foregroundcolor Yellow -Nonewline
                $continue = Read-Host 
                if ($continue -ne 'n' )
                {
                    Configure-AzsHciClusterNetwork -CleanupConfiguration
                }
                else
                {
                    Write-Warning "Current configuration detected however no Cleanup option is selected. You may face some errors"
                    Write-Warning "Sleep for 10 seconds to make sure it is not accidentialy entered. You can break execution using 'Crtl + C' to cancel configuration"
                    Start-Sleep 10
                }
            }
            
            #Configure Management Network adapters

            switch ($ManagementInterfaceConfig) {
                "HighAvailable" {
                    Write-Verbose "[Configure ManagementInterfaceConfig]: HighAvailable - Configuring Management Interface"
                    Write-Warning -Message "[Configure ManagementInterfaceConfig]: Network connection will be interupted for couple of minutes, be patient!!"
                    Invoke-Command -Session $psSession -ScriptBlock {
                        $ipConfig = (
                            Get-NetAdapter -Physical | Get-NetAdapterBinding | Where-Object {$_.enabled -eq $true -and $_.DisplayName -eq 'Internet Protocol Version 4 (TCP/IPv4)'} | 
                                Get-NetIPConfiguration | Where-Object IPv4DefaultGateway | Sort-Object IPv4Address
                        )
                        $netAdapters = Get-NetAdapter -Name ($ipConfig.InterfaceAlias)
                        $VerbosePreference=$using:VerbosePreference
                        
                        $newAdapterNames = @()
                        for ($i = 1; $i -lt $netAdapters.count + 1; $i++)
                        {
                            $netAdapterName = $netAdapters[$i - 1].Name
                            
                            if ($netAdapterName -ne $($using:vSwitchNameMgmt + " $i"))
                            {
                                $newAdapterNames += $($using:vSwitchNameMgmt + " $i")
                                Rename-NetAdapter -Name $netAdapterName -NewName $($using:vSwitchNameMgmt + " $i")
                            }
                        }


                        #try to suppress error message
                        New-VMSwitch -Name $using:vSwitchNameMgmt -AllowManagementOS $true -NetAdapterName $newAdapterNames -EnableEmbeddedTeaming $true
                        Rename-NetAdapter -Name "vEthernet `($using:vSwitchNameMgmt`)" -NewName $using:vSwitchNameMgmt
                    }
                    $mgmtSwitchName = $vSwitchNameMgmt
                }
                "SingleAdapter" {
                    Write-Verbose "[Configure ManagementInterfaceConfig]: SingleAdapter - Configuring Management Interface"
                    Invoke-Command -Session $psSession -ScriptBlock {
                        $ipConfig = (
                            Get-NetAdapter -Physical | Get-NetAdapterBinding | Where-Object {$_.enabled -eq $true -and $_.DisplayName -eq 'Internet Protocol Version 4 (TCP/IPv4)'} | 
                                Get-NetIPConfiguration | Where-Object IPv4DefaultGateway | Sort-Object IPv4Address
                        )
                        $netAdapters = Get-NetAdapter -Name ($ipConfig.InterfaceAlias)
                        $VerbosePreference=$using:VerbosePreference
                        Rename-NetAdapter -Name "$($netAdapters[0].Name)" -NewName $($using:vSwitchNameMgmt + " 1") 
                        Rename-NetAdapter -Name "$($netAdapters[1].Name)" -NewName $($using:vSwitchNameMgmt + " 2") 
                        Disable-NetAdapter -Name $($using:vSwitchNameMgmt + " 2") -Confirm:$false
                    }
                    $mgmtSwitchName = $null
                }
            }

            #Configure Compute And Storage Network adapters

            switch ($ComputeAndStorageInterfaceConfig) {
                "OneVirtualSwitchforAllTraffic" {
                    Write-Verbose "[Configure ComputeAndStorageInterfaces]: OneVirtualSwitchforAllTraffic - Configuring ComputeAndStorageInterfaces"
                    Invoke-Command -Session $psSession -ScriptBlock {
                        $ipConfig = (
                            Get-NetAdapter -Physical | Where-Object status -ne disabled | Get-NetAdapterBinding | Where-Object {$_.enabled -eq $true -and $_.DisplayName -eq 'Internet Protocol Version 4 (TCP/IPv4)'} | 
                                Get-NetIPConfiguration | Where-Object {$_.IPv4DefaultGateway -eq $null -and $_.IPv4Address.Ipaddress -like "192.168.25*"} | Sort-Object IPv4Address
                        )
                        $netAdapters = Get-NetAdapter -Name ($ipConfig.InterfaceAlias)
                        $VerbosePreference=$using:VerbosePreference
                        
                        New-VMSwitch -Name $using:vSwitchNameConverged -NetAdapterName $netAdapters.Name -EnableEmbeddedTeaming $true -AllowManagementOS $false
                        
                        for ($i = 1; $i -lt $netAdapters.Count + 1; $i++)
                        {
                            $adapterName = "smb " + $i
                            Add-VMNetworkAdapter -ManagementOS -SwitchName $using:vSwitchNameConverged -Name $adapterName
                            $vNic = Rename-NetAdapter -Name "vEthernet `($adapterName`)" -NewName $adapterName -PassThru
                            $pNic = Rename-NetAdapter -Name $netAdapters[$i - 1].Name -NewName $($using:vSwitchNameConverged + " $i") -PassThru
                            New-NetIPAddress -IPAddress $ipconfig[$i - 1].ipv4Address.Ipaddress -InterfaceAlias $vNic.Name -AddressFamily IPv4 -PrefixLength $ipconfig[$i - 1].ipv4Address.prefixlength | Out-Null
                            $sleep = 5
                            do
                            {
                                Write-Verbose "Waiting for NICs $($vNic.Name) and $($pNic.Name) to come 'up' for $sleep seconds"
                                Start-Sleep -Seconds $sleep
                            }
                            
                            until ((Get-NetAdapter -Name $vNic.Name | Where-Object status -eq "up") -and (Get-NetAdapter -Name $pNic.Name | Where-Object status -eq "up"))
                            Write-Verbose "Setting up $($vNic.Name) and $($pNic.Name) for VMNetworkAdapterTeamMapping"
                            Set-VMNetworkAdapterTeamMapping -ManagementOS -VMNetworkAdapterName $vnic.Name -PhysicalNetAdapterName $pNic.Name
                            
                        } 
                    }
                    $computeSwitchName = $vSwitchNameConverged
                }
                "OneVirtualSwitchforComputeOnly" {
                    Write-Verbose "[Configure ComputeAndStorageInterfaces]: OneVirtualSwitchforComputeOnly - Configuring ComputeAndStorageInterfaces"
                    Invoke-Command -Session $psSession -ScriptBlock {
                        
                        $ipConfigCompute = (
                            Get-NetAdapter -Physical | Where-Object status -ne disabled | Get-NetAdapterBinding | ? {$_.enabled -eq $true -and $_.DisplayName -eq 'Internet Protocol Version 4 (TCP/IPv4)'} | 
                                Get-NetIPConfiguration | Where-Object {($_.IPv4DefaultGateway -eq $null) -and ($_.IPv4Address.Ipaddress -like "192.168.251.*" -or $_.IPv4Address.Ipaddress -like "192.168.252.*")} | 
                                Sort-Object IPv4Address
                        )
                        $netAdaptersCompute = Get-NetAdapter -Name ($ipConfigCompute.InterfaceAlias)
                        
                        $ipConfigStorage = (
                            Get-NetAdapter -Physical | Where-Object status -ne disabled | Get-NetAdapterBinding | ? {$_.enabled -eq $true -and $_.DisplayName -eq 'Internet Protocol Version 4 (TCP/IPv4)'} | 
                            Get-NetIPConfiguration | Where-Object {($_.IPv4DefaultGateway -eq $null) -and ($_.IPv4Address.Ipaddress -like "192.168.253.*" -or $_.IPv4Address.Ipaddress -like "192.168.254.*")} | 
                            Sort-Object IPv4Address
                        )                        
                        #$ipConfigStorage = (Get-NetAdapter -Physical | Where-Object status -ne disabled | Get-NetIPConfiguration | Where-Object {($_.IPv4DefaultGateway -eq $null) -and ($_.IPv4Address.Ipaddress -like "192.168.253.*" -or $_.IPv4Address.Ipaddress -like "192.168.254.*")})
                        $netAdaptersStorage = Get-NetAdapter -Name ($ipConfigStorage.InterfaceAlias)
                        
                        $VerbosePreference=$using:VerbosePreference
                        
                        Write-Verbose "[New SET switch]: $($using:vSwitchNameCompute) with following members"
                        Write-Verbose "$($netAdaptersCompute.Name)"

                        New-VMSwitch -Name $using:vSwitchNameCompute -NetAdapterName $netAdaptersCompute.Name -EnableEmbeddedTeaming $true -AllowManagementOS $false
                        
                        for ($i = 1; $i -lt $netAdaptersCompute.Count + 1; $i++){
                            Write-Verbose "[Rename NIC]: $($netAdaptersCompute[$i - 1].Name) to $($using:vSwitchNameCompute + " $i")"
                            $pNic = Rename-NetAdapter -Name $netAdaptersCompute[$i - 1].Name -NewName $($using:vSwitchNameCompute + " $i") -PassThru
                            
                        }

                        for ($i = 1; $i -lt $netAdaptersStorage.Count + 1; $i++)
                        { 
                            $adapterName = "smb " + $i
                            Write-Verbose "[Rename NIC]: $($netAdaptersStorage[$i - 1].Name) to $adapterName"
                            $pNic = Rename-NetAdapter -Name $netAdaptersStorage[$i - 1].Name -NewName $adapterName -PassThru
                            
                        }
                    }
                    $computeSwitchName = $vSwitchNameCompute
                }
                "TwoVirtualSwitches" {
                    Write-Verbose "[Configure ComputeAndStorageInterfaces]: TwoVirtualSwitches - Configuring ComputeAndStorageInterfaces"
                    Invoke-Command -Session $psSession -ScriptBlock {
                        
                        $ipConfigCompute = (
                            Get-NetAdapter -Physical | Where-Object status -ne disabled | Get-NetAdapterBinding | Where-Object {$_.enabled -eq $true -and $_.DisplayName -eq 'Internet Protocol Version 4 (TCP/IPv4)'} | 
                                Get-NetIPConfiguration | Where-Object {($_.IPv4DefaultGateway -eq $null) -and ($_.IPv4Address.Ipaddress -like "192.168.251.*" -or $_.IPv4Address.Ipaddress -like "192.168.252.*")} | 
                                Sort-Object IPv4Address
                        )
                        $netAdaptersCompute = Get-NetAdapter -Name ($ipConfigCompute.InterfaceAlias)
                        
                        $ipConfigStorage = (
                            Get-NetAdapter -Physical | Where-Object status -ne disabled | Get-NetAdapterBinding | ? {$_.enabled -eq $true -and $_.DisplayName -eq 'Internet Protocol Version 4 (TCP/IPv4)'} | 
                            Get-NetIPConfiguration | Where-Object {($_.IPv4DefaultGateway -eq $null) -and ($_.IPv4Address.Ipaddress -like "192.168.253.*" -or $_.IPv4Address.Ipaddress -like "192.168.254.*")} | 
                            Sort-Object IPv4Address
                        )
                        $netAdaptersStorage = Get-NetAdapter -Name ($ipConfigStorage.InterfaceAlias)
                        
                        $VerbosePreference=$using:VerbosePreference
                        
                        Write-Verbose "[New SET switch]: $($using:vSwitchNameCompute) with following members"
                        
                        New-VMSwitch -Name $using:vSwitchNameCompute -NetAdapterName $netAdaptersCompute.Name -EnableEmbeddedTeaming $true -AllowManagementOS $false
                        
                        for ($i = 1; $i -lt $netAdaptersCompute.Count + 1; $i++)
                        {
                            Write-Verbose "[Rename NIC]: $($netAdaptersCompute[$i - 1].Name) to $adapterName"
                            $pNic = Rename-NetAdapter -Name $netAdaptersCompute[$i - 1].Name -NewName $($using:vSwitchNameCompute + " $i") -PassThru
                        }
                        
                        Write-Verbose "[New SET switch]: $($using:vSwitchNameStorage) with following members"
                        
                        New-VMSwitch -Name $using:vSwitchNameStorage -NetAdapterName $netAdaptersStorage.Name -EnableEmbeddedTeaming $true -AllowManagementOS $false
                        
                        for ($i = 1; $i -lt $netAdaptersStorage.Count + 1; $i++)
                        { 
                            $adapterName = "smb " + $i
                            Add-VMNetworkAdapter -ManagementOS -SwitchName $using:vSwitchNameStorage -Name $adapterName
                            #Start-Sleep 4
                            
                            Write-Verbose "[Rename NIC]: $($netAdaptersStorage[$i - 1].Name) to $adapterName"

                            $vNic = Rename-NetAdapter -Name "vEthernet `($adapterName`)" -NewName $adapterName -PassThru
                            $pNic = Rename-NetAdapter -Name $netAdaptersStorage[$i - 1].Name -NewName $($using:vSwitchNameStorage + " $i") -PassThru
                            New-NetIPAddress -IPAddress $ipConfigStorage[$i - 1].ipv4Address.Ipaddress -InterfaceAlias $vNic.Name -AddressFamily IPv4 -PrefixLength $ipConfigStorage[$i - 1].ipv4Address.prefixlength | Out-Null
                            $sleep = 5
                            do
                            {
                                Write-Verbose "Waiting for NICs $($vNic.Name) and $($pNic.Name) to come 'up' for $sleep seconds"
                                Start-Sleep -Seconds $sleep
                            }
                            until ((Get-NetAdapter -Name $vNic.Name | Where-Object status -eq "up") -and (Get-NetAdapter -Name $pNic.Name | Where-Object status -eq "up"))
                            Write-Verbose "Setting up vNIC: $($vNic.Name) and pNIC: $($pNic.Name) for VMNetworkAdapterTeamMapping"
                            Set-VMNetworkAdapterTeamMapping -ManagementOS -VMNetworkAdapterName $vnic.Name -PhysicalNetAdapterName $pNic.Name
                            
                        }
                    }
                    $computeSwitchName = $vSwitchNameCompute
                }
            }
            
        }
    }
    end
    {
        #Re-Enable DHCP Scope

        Set-DhcpServerv4Scope -ScopeId 192.168.100.0 -State Active
        Remove-PSSession -Session $psSession
        Remove-Variable -Name psSession
        @{
            ManagementSwitch = $mgmtSwitchName
            ComputeSwitch = $computeSwitchName
        }
    }
}

function Erase-AzsHciClusterDisks
{
    [CmdletBinding()]

    Param
    (
    )

    Begin
    {
        #initializing variables
        $AzureStackHCIHosts = Get-VM hpv*

        $psSession = New-PSSession -ComputerName $AzureStackHCIHosts.Name
    }

    Process
    {
        Write-Verbose "Cleaning up previously configured S2D Disks"
        Invoke-Command -Session $psSession -ScriptBlock {
            Update-StorageProviderCache
            Get-StoragePool | Where-Object IsPrimordial -eq $false | Set-StoragePool -IsReadOnly:$false -ErrorAction SilentlyContinue
            Get-StoragePool | Where-Object IsPrimordial -eq $false | Get-VirtualDisk | Remove-VirtualDisk -Confirm:$false -ErrorAction SilentlyContinue
            Get-StoragePool | Where-Object IsPrimordial -eq $false | Remove-StoragePool -Confirm:$false -ErrorAction SilentlyContinue
            Get-PhysicalDisk | Reset-PhysicalDisk -ErrorAction SilentlyContinue
            Get-Disk | Where-Object Number -ne $null | Where-Object IsBoot -ne $true | Where-Object IsSystem -ne $true | Where-Object PartitionStyle -ne RAW | Foreach-Object {
                $_ | Set-Disk -isoffline:$false
                $_ | Set-Disk -isreadonly:$false
                $_ | Clear-Disk -RemoveData -RemoveOEM -Confirm:$false
                $_ | Set-Disk -isreadonly:$true
                $_ | Set-Disk -isoffline:$true
            }
            Get-Disk | Where-Object Number -Ne $Null | Where-Object IsBoot -Ne $True | Where-Object IsSystem -Ne $True | Where-Object PartitionStyle -Eq RAW | Group -NoElement -Property FriendlyName
        } | Sort-Object -Property PsComputerName, Count
    }

    End
    {
        Remove-PSSession -Session $psSession
        Remove-Variable -Name psSession
    }
}

function Configure-AzsHciCluster
{
    [CmdletBinding()]
    Param
    (
        # Param1 help description
        [Parameter(Mandatory=$true)]
        $ClusterName
    )

    Begin
    {
        #initializing variables
        $AzureStackHCIHosts = Get-VM hpv*

        $cimSession = New-CimSession -ComputerName $AzureStackHCIHosts[0].Name
       
    }

    Process
    {
        Write-Verbose "Enabling Cluster: $ClusterName"
        New-Cluster -Name $ClusterName -Node $AzureStackHCIHosts.Name -NoStorage -Force
        Write-Verbose "Enabling Storage Spaces Direct on Cluster: $ClusterName"
        Enable-ClusterStorageSpacesDirect -PoolFriendlyName "Cluster Storage Pool" -CimSession $cimSession -Confirm:$false -SkipEligibilityChecks -ErrorAction SilentlyContinue
    }

    End
    {
        #clean up variables
        Remove-CimSession -CimSession $cimSession
        Remove-Variable -Name cimSession
    }
}

function Prepare-AzsHciClusterforAksHciDeployment
{
    [CmdletBinding()]
    Param
    (
    )

    Begin
    {
        #variables
        $targetDrive = "V:"
        $sourcePath =  "$targetDrive\source"
        $aksSource = "$sourcePath\aksHciSource"
        $AzureStackHCIHosts = Get-VM hpv*
        $AzureStackHCIClusterName = 'Hci01'
        $azSHCICSV = "AksHCIMain"
        $azSHCICSVPath = "c:\ClusterStorage\$azSHCICSV"
    }
    Process
    {
        Prepare-AzsHciPackage

        #Update NuGet Package provider on AzsHci Host
        Invoke-Command -ComputerName $AzureStackHCIHosts.Name -ScriptBlock {
            Install-PackageProvider -Name NuGet -Force 
            Install-Module -Name PowershellGet -Force -Confirm:$false -SkipPublisherCheck
        }

        #Copy AksHCI modules to Azure Stack HCI hosts
        $AzureStackHCIHosts.Name | ForEach-Object {Copy-Item "$aksSource\aks-hci-tools\Powershell\Modules" "\\$_\c$\Program Files\WindowsPowershell\" -Recurse -Force}

        #create Cluster Shared Volume for AksHCI and Enable Deduplication
        #New-Volume -CimSession "$($AzureStackHCIHosts[0].Name)" -FriendlyName $azSHCICSV -FileSystem CSVFS_ReFS -StoragePoolFriendlyName S2D* -Size 1.3TB
        New-Volume -CimSession $AzureStackHCIClusterName -FriendlyName $azSHCICSV -FileSystem CSVFS_ReFS -StoragePoolFriendlyName cluster* -Size 1.3TB
        Enable-DedupVolume -CimSession $AzureStackHCIClusterName -Volume $azSHCICSVPath
        Enable-DedupVolume -CimSession $AzureStackHCIClusterName -Volume $azSHCICSVPath -UsageType HyperV -DataAccess
        
    }
    End
    {
    }
}

function Start-AksHciPoC
{
    param (
    )

    begin
    {

        #Initialize variables
        $AzureStackHCIHosts = Get-VM -Name hpv*
        $sleep = 20

    }

    process
    {
        
        $CleanupVMsSelection = Show-Menu -Items @(
            'Do NOT Cleanup ( !!Default selection!! )',
            'Yes, Cleanup Azure Stack HCI host VMs and Wac VMs',
            'Yes, Cleanup Windows Admin Center VM Only!',
            'Yes, Cleanup Azure Stack HCI host VMs Only!',
            'Yes, Cleanup All VMs for both HCI host VMs, Aks Hci VMs!'
        ) -Title 'Cleanup VMs option to start from scratch?' -Description 'This option will destroy All VMs or selected VMs.'

        $RolesConfigurationProfileSelection = Show-Menu -Items @(
            'Do NOT install any Roles ( !!Default selection!! )',
            'Install required roles to Azure Stack HCI Hosts'
        ) -Title 'Azure Stack HCI Roles and Features Installation optionssndklajsdkljasdjasjdljasd' -Description 'Roles are installed by default. (Optional)'
                    
        $NetworkConfigurationProfileSelection = Show-Menu -Items @(
            'High-available Management & One Virtual Switch for All Traffic ( !!Default selection!! )',
            'High-available networks for Management & One Virtual Switch for Compute Only',
            'High-available networks for Managament & Two Virtual Switches',
            'Single Network Adapter for Management & One Virtual Switch for All Traffic',
            'Single Network Adapter for Management & One Virtual Switch for Compute Only',
            'Single Network Adapter for Management & Two Virtual Switches for Compute and Storage',
            'High-available networks for Management & One Virtual Switch for All Traffic ( !!Also reset network config!! )',
            'Single Network Adapter for Management & One Virtual Switch for Compute Only ( !!Also reset network config!! )',
            'High-available networks for Managament & Two Virtual Switches ( !!Also reset network config!! )',
            'Do NOT configure networks'
        ) -Title 'Azure Stack HCI Network Adapter Configuration options (SET Switch)' -Description ""

        $DisksConfigurationProfileSelection = Show-Menu -Items @(
            'Do NOT erase and cleanup ( !!Default selection!! )',
            'Erase all drives'
        ) -Title 'Azure Stack HCI Disks cleanup options' -Description 'Please do so, if this is NOT first installation on top of clean environment. (Optional)'

        $ClusterConfigurationProfileSelection = Show-Menu -Items @(
            'Enable Cluster using default Name (Cluster Name: hci01) ( !!Default selection!! )',
            'Do NOT Create Cluster yet.'
        ) -Title 'Azure Stack HCI Cluster options' -Description 'Install cluster using default name to prevent any misconfigurations'
        
        $AksHciConfigurationProfileSelection = Show-Menu -Items @(
            'Prepare for Aks Hci Deployment ( !!Default selection!! )',
            'Do NOT Prepare for Aks Hci Deployment yet.'
        ) -Title 'Azure Stack HCI Cluster Aks Hci preparation options' -Description 'Prepare Azure Stack HCI Cluster with Aks Hci pre-requisites'

        switch ($CleanupVMsSelection)
        {
            1 {Cleanup-VMs -AzureStackHciHostVMs -WindowsAdminCenterVM -Verbose; Prepare-AdforAzsHciDeployment}
            2 {Cleanup-VMs -WindowsAdminCenterVM -Verbose}
            3 {Cleanup-VMs -AzureStackHciHostVMs -Verbose; Prepare-AdforAzsHciDeployment}
            4 {if ((Get-Vm * | Where-Object name -ne 'wac').count -gt 0){Uninstall-AksHci}; Cleanup-VMs -AzureStackHciHostVMs -Verbose; Prepare-AdforAzsHciDeployment}
            Default {Write-Warning "[Cleanup-VMs]: No Cleanup selected."} 
        }

        $cimSession = New-CimSession -ComputerName $AzureStackHCIHosts.name

        do
        {
            Clear-DnsClientCache
            Write-Verbose "Waiting for Azure Stack HCI hosts to finish initial DSC configuration for $sleep seconds" -Verbose
            Start-Sleep -Seconds $sleep    
        }
        while (((Get-DscLocalConfigurationManager -CimSession $cimSession -ErrorAction SilentlyContinue | Select-Object -ExpandProperty lcmstate) -contains "busy" -or (Get-DscLocalConfigurationManager -CimSession $cimSession -ErrorAction SilentlyContinue | Select-Object -ExpandProperty lcmstate) -contains "PendingConfiguration"))

        switch ($RolesConfigurationProfileSelection)
        {
            1 {Configure-AzsHciClusterRoles -Verbose}
            Default {Write-Warning "[Configure-AzsHciClusterRoles]: Not installing Roles and  Features, assuming All Roles and Features required are already installed. Subsequent process may rely on Roles and Features Installation."} 
        }
  
        switch ($NetworkConfigurationProfileSelection)
        {
            1 {Configure-AzsHciClusterNetwork -ManagementInterfaceConfig HighAvailable -Verbose -ComputeAndStorageInterfaceConfig OneVirtualSwitchforComputeOnly}
            2 {Configure-AzsHciClusterNetwork -ManagementInterfaceConfig HighAvailable -Verbose -ComputeAndStorageInterfaceConfig TwoVirtualSwitches}
            3 {Configure-AzsHciClusterNetwork -ManagementInterfaceConfig SingleAdapter -Verbose -ComputeAndStorageInterfaceConfig OneVirtualSwitchforAllTraffic}
            4 {Configure-AzsHciClusterNetwork -ManagementInterfaceConfig SingleAdapter -Verbose -ComputeAndStorageInterfaceConfig OneVirtualSwitchforComputeOnly}
            5 {Configure-AzsHciClusterNetwork -ManagementInterfaceConfig SingleAdapter -Verbose -ComputeAndStorageInterfaceConfig TwoVirtualSwitches}
            6 {Configure-AzsHciClusterNetwork -ManagementInterfaceConfig HighAvailable -Verbose -ComputeAndStorageInterfaceConfig OneVirtualSwitchforAllTraffic -ForceCleanup}
            7 {Configure-AzsHciClusterNetwork -ManagementInterfaceConfig SingleAdapter -Verbose -ComputeAndStorageInterfaceConfig OneVirtualSwitchforComputeOnly -ForceCleanup}
            8 {Configure-AzsHciClusterNetwork -ManagementInterfaceConfig HighAvailable -Verbose -ComputeAndStorageInterfaceConfig TwoVirtualSwitches -ForceCleanup}
            9 {Write-Warning "[Configure-AzsHciClusterNetwork]: Assuming Networks are already configured!"}
            Default {Configure-AzsHciClusterNetwork -ManagementInterfaceConfig HighAvailable -Verbose -ComputeAndStorageInterfaceConfig OneVirtualSwitchforAllTraffic}
        }

        switch ($DisksConfigurationProfileSelection)
        {
            1 {Erase-AzsHciClusterDisks -Verbose}
            default {Write-Warning "[Erase-AzsHciClusterDisks]: Assuming this is first installation on top of clean environment. Otherwise subsequent process may fail."} 
        }

        switch ($ClusterConfigurationProfileSelection)
        {
            1 {Write-Warning "You may need to configure cluster manually!"}
            Default {Configure-AzsHciCluster -ClusterName hci01 -Verbose} 
        }

        switch ($AksHciConfigurationProfileSelection)
        {
            1 {Write-Warning "You may need to prepare Azure Stack HCI cluster for Aks Hci pre-requisites manually!"}
            Default {Prepare-AzsHciClusterforAksHciDeployment -Verbose} 
        }
    }

    end
    {

        Remove-CimSession $cimSession
        Remove-variable cimsession

    }    
}

function Show-Menu
{
    [CmdletBinding()]
    [OutputType([string])]
    Param
    (
        [parameter(Mandatory=$true)]
        [string[]]
        $Items,

        [parameter(Mandatory=$true)]
        [string]
        $Title,

        [string]
        $Description,

        [int]
        [ValidateRange(4,10)]
        $MenuIndent = 4,

        [System.ConsoleColor]
        $ColorTitle = 'Green',

        [System.ConsoleColor]
        $ColorDescription = 'Yellow'
    )

    Begin
    {
        $titleLength = [math]::Round($Title.Length / 2)
        $longest = [math]::Round(($items | ForEach-Object {$_.length} | Sort-Object -Descending | Select-Object -First 1) / 2)
        if ($longest -lt $titleLength)
        {
            $longest = $titleLength
        }
        
    }
    Process
    {
        Clear-Host
        Write-Host $('=' * $(($longest + $MenuIndent) - $titleLength) + " " + "$Title" + " " + '=' * $(($longest + $MenuIndent) - $titleLength) ) -ForegroundColor Green
        Write-Host ""
        
        if ($Description)
        {
            Write-Host $(" " * $($MenuIndent - 2) + $Description) -ForegroundColor Yellow
            Write-Host ""
        }

        for ($i = 0; $i -lt $items.count; $i++)
        { 
            Write-Host "$(" " * $MenuIndent + "$i" + '. ' + $items[$i])"
        }
        
        Write-Host ""
        Write-Host "Selection: " -ForegroundColor Green -NoNewline
        
        $selection = Read-Host
        
        if ([string]::IsNullOrEmpty($selection))
        {
            $selection = 0
        }
        return $selection
    }
    End
    {

    }
}
