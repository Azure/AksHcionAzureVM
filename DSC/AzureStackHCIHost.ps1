configuration AzureStackHCIHost
{ 
   param 
   ( 
        [Parameter(Mandatory)]
        [String]$DomainName,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Admincreds,

        [Int]$RetryCount=20,

        [Int]$RetryIntervalSec=30,

        [String]$targetDrive = "V:",

        [String]$sourcePath =  "$targetDrive\source",

        [String]$targetVMPath = "$targetDrive\VMs",

        [String]$baseVHDFolderPath = "$targetVMPath\base",

        [String]$azsHCIISOLocalPath = "$sourcePath\AzSHCI.iso",

        [String]$wacLocalPath = "$sourcePath\WACLatest.msi",

        [String]$azsHCIIsoUri = "https://aka.ms/2CNBagfhSZ8BM7jyEV8I",

        [String]$azsHciVhdPath = "$baseVHDFolderPath\AzSHCI.vhdx",

        [String]$ws2019IsoUri = "https://software-download.microsoft.com/download/pr/17763.737.190906-2324.rs5_release_svc_refresh_SERVER_EVAL_x64FRE_en-us_1.iso",

        [String]$ws2019IsoLocalPath = "$sourcePath\ws2019.iso",

        [String]$ws2019VhdPath = "$baseVHDFolderPath\ws2019.vhdx",

        [String]$wacUri = "https://aka.ms/wacdownload",

        [Int]$azsHostCount = 2,

        [Int]$azsHostDataDiskCount = 3,

        [Int64]$dataDiskSize = 500GB,

        [string]$natPrefix = "AzSHCI",

        [string]$vSwitchNameMgmt = "Management",

        [string]$vSwitchNameConverged = "Default Switch",

        [string]$HCIvmPrefix = "hpv",

        [string]$wacVMName = "wac",

        [int]$azsHCIHostMemory,

        [string]$branch = "master",

        [string]$aksHciScenario
    ) 
    
    Import-DscResource -ModuleName 'xActiveDirectory'
    Import-DscResource -ModuleName 'xStorage'
    Import-DscResource -ModuleName 'NetworkingDSC'
    Import-DscResource -ModuleName 'PSDesiredStateConfiguration'
    Import-DscResource -ModuleName 'ComputerManagementDsc'
    Import-DscResource -ModuleName 'xHyper-v'
    Import-DscResource -ModuleName 'cHyper-v'
    Import-DscResource -ModuleName 'xPSDesiredStateConfiguration'
    Import-DscResource -ModuleName 'xDHCpServer'
    Import-DscResource -ModuleName 'cChoco'
    Import-DscResource -ModuleName 'DSCR_Shortcut'
    
    $repoName = "AzureStackHCIonAzure"
    $repoBaseUrl = "https://github.com/yagmurs/$repoName"
    $branchFiles = "$repoBaseUrl/archive/$branch.zip"
    
    if ($aksHciScenario -eq 'onAzureVMDirectly') {
        $labScript = "Deploy-AksHciOnAzureVM.ps1"
    }
    else
    {
        $labScript = "Deploy-AksHciOnNestedAzureAzureStackHCI.ps1"
    }
    
    [System.Management.Automation.PSCredential]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($Admincreds.UserName)", $Admincreds.Password)
    
    $ipConfig = (Get-NetAdapter -Physical | Get-NetIPConfiguration | Where-Object IPv4DefaultGateway)
    $netAdapters = Get-NetAdapter -Name ($ipConfig.InterfaceAlias) | Select-Object -First 1
    $InterfaceAlias=$($netAdapters.Name)

    Node localhost
    {
        LocalConfigurationManager {
            RebootNodeIfNeeded = $true
            ActionAfterReboot  = 'ContinueConfiguration'
            ConfigurationMode = 'ApplyOnly'
        }

        xWaitforDisk Disk1
        {
            DiskID = 1
            RetryIntervalSec =$RetryIntervalSec
            RetryCount = $RetryCount
        }

        xDisk ADDataDisk 
        {
            DiskID = 1
            DriveLetter = "F"
            DependsOn = "[xWaitForDisk]Disk1"
        }

        xWaitforDisk Disk2
        {
            DiskID = 2
            RetryIntervalSec =$RetryIntervalSec
            RetryCount = $RetryCount
        }

        xDisk hpvDataDisk 
        {
            DiskID = 2
            DriveLetter = $targetDrive
            DependsOn = "[xWaitForDisk]Disk2"
        }

        File "source"
        {
            DestinationPath = $sourcePath
            Type = 'Directory'
            Force = $true
            DependsOn = "[xDisk]hpvDataDisk"
        }

        File "folder-vms"
        {
            Type = 'Directory'
            DestinationPath = $targetVMPath
            DependsOn = "[xDisk]hpvDataDisk"
        }

        File "VM-base"
        {
            Type = 'Directory'
            DestinationPath = $baseVHDFolderPath
            DependsOn = "[File]folder-vms"
        } 

        Registry "Disable Internet Explorer ESC for Admin"
        {
            Key = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
            ValueName = "IsInstalled"
            ValueData = "0"
            ValueType = "Dword"
        }

        Registry "Disable Internet Explorer ESC for User"
        {
            Key = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
            ValueName = "IsInstalled"
            ValueData = "0"
            ValueType = "Dword"
        }

        Registry "Add Wac to Intranet zone for SSO"
        {
            Key = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap\EscDomains\wac'
            ValueName = "https"
            ValueData = 1
            ValueType = 'Dword'
        }

        ScheduledTask "Disable Server Manager at Startup"
        {
            TaskName = 'ServerManager'
            Enable = $false
            TaskPath = '\Microsoft\Windows\Server Manager'
        }

        script "Download branch files for $branch"
        {
            GetScript = {
                $result = Test-Path -Path "$using:sourcePath\$using:branch.zip"
                return @{ 'Result' = $result }
            }

            SetScript = {
                Invoke-WebRequest -Uri $using:branchFiles -OutFile "$using:sourcePath\$using:branch.zip"
                #Start-BitsTransfer -Source $using:branchFiles -Destination "$using:sourcePath\$using:branch.zip"        
            }

            TestScript = {
                # Create and invoke a scriptblock using the $GetScript automatic variable, which contains a string representation of the GetScript.
                $state = [scriptblock]::Create($GetScript).Invoke()
                return $state.Result
            }
            DependsOn = "[File]source"
        }

        archive "Extract branch files"
        {
            Ensure = 'Present'
            Path = "$sourcePath\$branch.zip"
            Destination = "$sourcePath\branchData"
            Validate = $true
            Checksum = 'SHA-1'
            DependsOn = "[script]Download branch files for $branch"
        }

        script "Download AzureStack HCI bits"
        {
            GetScript = {
                $result = Test-Path -Path $using:azsHCIISOLocalPath
                return @{ 'Result' = $result }
            }

            SetScript = {
                Start-BitsTransfer -Source $using:azsHCIIsoUri -Destination $using:azsHCIISOLocalPath            
            }

            TestScript = {
                # Create and invoke a scriptblock using the $GetScript automatic variable, which contains a string representation of the GetScript.
                $state = [scriptblock]::Create($GetScript).Invoke()
                return $state.Result
            }
            DependsOn = "[File]source"
        }

        WindowsFeature DNS 
        { 
            Ensure = "Present" 
            Name = "DNS"		
        }

        WindowsFeature "Enable Deduplication" 
        { 
            Ensure = "Present" 
            Name = "FS-Data-Deduplication"		
        }

        Script EnableDNSDiags
	    {
      	    SetScript = { 
		        Set-DnsServerDiagnostics -All $true
                Write-Verbose -Verbose "Enabling DNS client diagnostics" 
            }
            GetScript =  { @{} }
            TestScript = { $false }
	        DependsOn = "[WindowsFeature]DNS"
        }

	    WindowsFeature DnsTools
	    {
	        Ensure = "Present"
            Name = "RSAT-DNS-Server"
            DependsOn = "[WindowsFeature]DNS"
	    }

        DnsServerAddress "DnsServerAddress for $InterfaceAlias"
        { 
            Address        = '127.0.0.1' 
            InterfaceAlias = $InterfaceAlias
            AddressFamily  = 'IPv4'
	        DependsOn = "[WindowsFeature]DNS"
        }

        WindowsFeature ADDSInstall 
        { 
            Ensure = "Present" 
            Name = "AD-Domain-Services"
	        DependsOn="[WindowsFeature]DNS" 
        } 

        WindowsFeature ADDSTools
        {
            Ensure = "Present"
            Name = "RSAT-ADDS-Tools"
            DependsOn = "[WindowsFeature]ADDSInstall"
        }

        WindowsFeature ADAdminCenter
        {
            Ensure = "Present"
            Name = "RSAT-AD-AdminCenter"
            DependsOn = "[WindowsFeature]ADDSInstall"
        }
         
        xADDomain FirstDS 
        {
            DomainName = $DomainName
            DomainAdministratorCredential = $DomainCreds
            SafemodeAdministratorPassword = $DomainCreds
            DatabasePath = "F:\NTDS"
            LogPath = "F:\NTDS"
            SysvolPath = "F:\SYSVOL"
	        DependsOn = @("[xDisk]ADDataDisk", "[WindowsFeature]ADDSInstall")
        }

        WindowsFeature "Install DHCPServer"
        {
           Name = 'DHCP'
           Ensure = 'Present'
        }

        WindowsFeature DHCPTools
	    {
	        Ensure = "Present"
            Name = "RSAT-DHCP"
            DependsOn = "[WindowsFeature]Install DHCPServer"
	    }

        WindowsFeature "Hyper-V" 
        {
            Name   = "Hyper-V"
            Ensure = "Present"
        }

        WindowsFeature "RSAT-Hyper-V-Tools" 
        {
            Name = "RSAT-Hyper-V-Tools"
            Ensure = "Present"
            DependsOn = "[WindowsFeature]Hyper-V" 
        }

        WindowsFeature "RSAT-Clustering" 
        {
            Name = "RSAT-Clustering"
            Ensure = "Present"
        }

        xVMHost "hpvHost"
        {
            IsSingleInstance = 'yes'
            EnableEnhancedSessionMode = $true
            VirtualHardDiskPath = $targetVMPath
            VirtualMachinePath = $targetVMPath
            DependsOn = "[WindowsFeature]Hyper-V"
        }

        xVMSwitch "$vSwitchNameMgmt"
        {
            Name = $vSwitchNameMgmt
            Type = "Internal"
            DependsOn = "[WindowsFeature]Hyper-V"
        }

        xVMSwitch "$vSwitchNameConverged"
        {
            Name = $vSwitchNameConverged
            Type = "Internal"
            DependsOn = "[WindowsFeature]Hyper-V"
        }

        IPAddress "New IP for vEthernet $vSwitchNameMgmt"
        {
            InterfaceAlias = "vEthernet `($vSwitchNameMgmt`)"
            AddressFamily = 'IPv4'
            IPAddress = '192.168.0.1/24'
            DependsOn = "[xVMSwitch]$vSwitchNameMgmt"
        }

        NetIPInterface "Enable IP forwarding on vEthernet $vSwitchNameMgmt"
        {   
            AddressFamily  = 'IPv4'
            InterfaceAlias = "vEthernet `($vSwitchNameMgmt`)"
            Forwarding     = 'Enabled'
            DependsOn      = "[IPAddress]New IP for vEthernet $vSwitchNameMgmt"
        }

        NetAdapterRdma "Enable RDMA on vEthernet $vSwitchNameMgmt"
        {
            Name = "vEthernet `($vSwitchNameMgmt`)"
            Enabled = $true
            DependsOn = "[NetIPInterface]Enable IP forwarding on vEthernet $vSwitchNameMgmt"
        }

        DnsServerAddress "DnsServerAddress for vEthernet $vSwitchNameMgmt" 
        { 
            Address        = '127.0.0.1' 
            InterfaceAlias = "vEthernet `($vSwitchNameMgmt`)"
            AddressFamily  = 'IPv4'
	        DependsOn = "[IPAddress]New IP for vEthernet $vSwitchNameMgmt"
        }

        IPAddress "New IP for vEthernet $vSwitchNameConverged"
        {
            InterfaceAlias = "vEthernet `($vSwitchNameConverged`)"
            AddressFamily = 'IPv4'
            IPAddress = '192.168.100.1/24'
            DependsOn = "[xVMSwitch]$vSwitchNameConverged"
        }

        NetIPInterface "Enable IP forwarding on vEthernet $vSwitchNameConverged"
        {   
            AddressFamily  = 'IPv4'
            InterfaceAlias = "vEthernet `($vSwitchNameConverged`)"
            Forwarding     = 'Enabled'
            DependsOn      = "[IPAddress]New IP for vEthernet $vSwitchNameConverged"
        }

        NetAdapterRdma "Enable RDMA on vEthernet $vSwitchNameConverged"
        {
            Name = "vEthernet `($vSwitchNameConverged`)"
            Enabled = $true
            DependsOn = "[NetIPInterface]Enable IP forwarding on vEthernet $vSwitchNameConverged"
        }

        DnsServerAddress "DnsServerAddress for vEthernet $vSwitchNameConverged" 
        { 
            Address        = '127.0.0.1' 
            InterfaceAlias = "vEthernet `($vSwitchNameConverged`)"
            AddressFamily  = 'IPv4'
	        DependsOn = "[IPAddress]New IP for vEthernet $vSwitchNameConverged"
        }

        xDhcpServerAuthorization "Authorize DHCP"
        {
            Ensure = 'Present'
            DependsOn = @('[WindowsFeature]Install DHCPServer')
            DnsName = [System.Net.Dns]::GetHostByName($env:computerName).hostname
            IPAddress = '192.168.100.1'
        }

        xDhcpServerScope "Scope 192.168.0.0" 
        { 
            Ensure = 'Present'
            IPStartRange = '192.168.0.150' 
            IPEndRange = '192.168.0.240' 
            ScopeId = '192.168.0.0'
            Name = 'Management Address Range for VMs on AzSHCI Cluster' 
            SubnetMask = '255.255.255.0' 
            LeaseDuration = '02.00:00:00' 
            State = 'Active' 
            AddressFamily = 'IPv4'
            DependsOn = @("[WindowsFeature]Install DHCPServer", "[IPAddress]New IP for vEthernet $vSwitchNameMgmt")
        }

        xDhcpServerScope "Scope 192.168.100.0" 
        { 
            Ensure = 'Present'
            IPStartRange = '192.168.100.21' 
            IPEndRange = '192.168.100.254' 
            ScopeId = '192.168.100.0'
            Name = 'Client Address Range for Nested VMs on AzSHCI Cluster' 
            SubnetMask = '255.255.255.0' 
            LeaseDuration = '02.00:00:00' 
            State = 'Active' 
            AddressFamily = 'IPv4'
            DependsOn = @("[WindowsFeature]Install DHCPServer", "[IPAddress]New IP for vEthernet $vSwitchNameConverged")
        }

        xDhcpServerOption "Option 192.168.0.0" 
        { 
            Ensure = 'Present' 
            ScopeID = '192.168.0.0' 
            DnsDomain = $DomainName 
            DnsServerIPAddress = '192.168.0.1' 
            AddressFamily = 'IPv4' 
            Router = '192.168.0.1'
            DependsOn = @("[WindowsFeature]Install DHCPServer", "[IPAddress]New IP for vEthernet $vSwitchNameMgmt")
        }

        xDhcpServerOption "Option 192.168.100.0" 
        { 
            Ensure = 'Present' 
            ScopeID = '192.168.100.0' 
            DnsDomain = $DomainName 
            DnsServerIPAddress = '192.168.100.1' 
            AddressFamily = 'IPv4' 
            Router = '192.168.100.1'
            DependsOn = @("[WindowsFeature]Install DHCPServer", "[IPAddress]New IP for vEthernet $vSwitchNameConverged")
        }

        script "New Nat rule for Management Network"
        {
            GetScript = {
                $nat = $($using:natPrefix + "-Management")
                $result = if (Get-NetNat -Name $nat -ErrorAction SilentlyContinue) {$true} else {$false}
                return @{ 'Result' = $result }
            }

            SetScript = {
                $nat = $($using:natPrefix + "-Management")
                New-NetNat -Name $nat -InternalIPInterfaceAddressPrefix "192.168.0.0/24"          
            }

            TestScript = {
                # Create and invoke a scriptblock using the $GetScript automatic variable, which contains a string representation of the GetScript.
                $state = [scriptblock]::Create($GetScript).Invoke()
                return $state.Result
            }
            DependsOn = "[IPAddress]New IP for vEthernet $vSwitchNameMgmt"
        }

        script "New Nat rule for Nested Network"
        {
            GetScript = {
                $nat = $($using:natPrefix + "-Nested")
                $result = if (Get-NetNat -Name $nat -ErrorAction SilentlyContinue) {$true} else {$false}
                return @{ 'Result' = $result }
            }

            SetScript = {
                $nat = $($using:natPrefix + "-Nested")
                New-NetNat -Name $nat -InternalIPInterfaceAddressPrefix "192.168.100.0/24"          
            }

            TestScript = {
                # Create and invoke a scriptblock using the $GetScript automatic variable, which contains a string representation of the GetScript.
                $state = [scriptblock]::Create($GetScript).Invoke()
                return $state.Result
            }
            DependsOn = "[IPAddress]New IP for vEthernet $vSwitchNameConverged"
        }

        script "prepareVHDX"
        {
            GetScript = {
                $result = Test-Path -Path $using:azsHciVhdPath
                return @{ 'Result' = $result }
            }

            SetScript = {
                #Create Azure Stack HCI Host Image
                Convert-Wim2Vhd -DiskLayout UEFI -SourcePath $using:azsHCIISOLocalPath -Path $using:azsHciVhdPath -Size 100GB -Dynamic -Index 1 -ErrorAction SilentlyContinue
                #Enable Hyper-v role on the Azure Stack HCI Host Image
                Install-WindowsFeature -Vhd $using:azsHciVhdPath -Name Hyper-V
            }

            TestScript = {
                # Create and invoke a scriptblock using the $GetScript automatic variable, which contains a string representation of the GetScript.
                $state = [scriptblock]::Create($GetScript).Invoke()
                return $state.Result
            }
            DependsOn = "[file]VM-Base", "[script]Download AzureStack HCI bits"
        }

        if ($aksHciScenario -eq 'onNestedAzureStackHciClusteronAzureVM')
        {
            for ($i = 1; $i -lt $azsHostCount + 1; $i++)
            {
                $suffix = '{0:D2}' -f $i
                $vmname = $($HCIvmPrefix + $suffix)
                $memory = $azsHCIHostMemory * 1gb

                file "VM-Folder-$vmname"
                {
                    Ensure = 'Present'
                    DestinationPath = "$targetVMPath\$vmname"
                    Type = 'Directory'
                    DependsOn = "[File]folder-vms"
                }
                
                xVhd "NewOSDisk-$vmname"
                {
                    Ensure           = 'Present'
                    Name             = "$vmname-OSDisk.vhdx"
                    Path             = "$targetVMPath\$vmname"
                    Generation       = 'vhdx'
                    ParentPath       = $azsHciVhdPath
                    Type             = 'Differencing'
                    DependsOn = "[xVMSwitch]$vSwitchNameMgmt", "[script]prepareVHDX", "[file]VM-Folder-$vmname"
                }

                xVMHyperV "VM-$vmname"
                {
                    Ensure          = 'Present'
                    Name            = $vmname
                    VhdPath         = "$targetVMPath\$vmname\$vmname-OSDisk.vhdx"
                    Path            = $targetVMPath
                    Generation      = 2
                    StartupMemory   = $memory
                    ProcessorCount  = 4
                    DependsOn       = "[xVhd]NewOSDisk-$vmname"
                }

                xVMProcessor "Enable NestedVirtualization-$vmname"
                {
                    VMName = $vmname
                    ExposeVirtualizationExtensions = $true
                    DependsOn = "[xVMHyperV]VM-$vmname"
                }

                script "remove default Network Adapter on VM-$vmname"
                {
                    GetScript = {
                        $VMNetworkAdapter = Get-VMNetworkAdapter -VMName $using:vmname -Name 'Network Adapter' -ErrorAction SilentlyContinue
                        $result = if ($VMNetworkAdapter) {$false} else {$true}
                        return @{
                            VMName = $VMNetworkAdapter.VMName
                            Name = $VMNetworkAdapter.Name
                            Result = $result
                        }
                    }
        
                    SetScript = {
                        $state = [scriptblock]::Create($GetScript).Invoke()
                        Remove-VMNetworkAdapter -VMName $state.VMName -Name $state.Name                 
                    }
        
                    TestScript = {
                        # Create and invoke a scriptblock using the $GetScript automatic variable, which contains a string representation of the GetScript.
                        $state = [scriptblock]::Create($GetScript).Invoke()
                        return $state.Result
                    }
                    DependsOn = "[xVMHyperV]VM-$vmname"
                }

                for ($k = 1; $k -le 2; $k++)
                {
                    $mgmtNicName = "$vmname-Management$k"
                    xVMNetworkAdapter "New Network Adapter $mgmtNicName $vmname DHCP"
                    {
                        Id = $mgmtNicName
                        Name = $mgmtNicName
                        SwitchName = $vSwitchNameMgmt
                        VMName = $vmname
                        Ensure = 'Present'
                        DependsOn = "[xVMHyperV]VM-$vmname"
                    }

                    cVMNetworkAdapterSettings "Enable $vmname $mgmtNicName Mac address spoofing and Teaming"
                    {
                        Id = $mgmtNicName
                        Name = $mgmtNicName
                        SwitchName = $vSwitchNameMgmt
                        VMName = $vmname
                        AllowTeaming = 'on'
                        MacAddressSpoofing = 'on'
                        DependsOn = "[xVMNetworkAdapter]New Network Adapter $mgmtNicName $vmname DHCP"
                    }
                }

                for ($l = 1; $l -le 4; $l++) 
                {
                    $ipAddress = $('192.168.25' + $l + '.1' + $suffix)
                    $nicName = "$vmname-Converged-Nic$l"

                    xVMNetworkAdapter "New Network Adapter Converged $vmname $nicName $ipAddress"
                    {
                        Id = $nicName
                        Name = $nicName
                        SwitchName = $vSwitchNameConverged
                        VMName = $vmname
                        NetworkSetting = xNetworkSettings {
                            IpAddress = $ipAddress
                            Subnet = "255.255.255.0"
                        }
                        Ensure = 'Present'
                        DependsOn = "[xVMHyperV]VM-$vmname"
                    }
                    
                    cVMNetworkAdapterSettings "Enable $vmname $nicName Mac address spoofing and Teaming"
                    {
                        Id = $nicName
                        Name = $nicName
                        SwitchName = $vSwitchNameConverged
                        VMName = $vmname
                        AllowTeaming = 'on'
                        MacAddressSpoofing = 'on'
                        DependsOn = "[xVMNetworkAdapter]New Network Adapter Converged $vmname $nicName $ipAddress"
                    }
                }    

                for ($j = 1; $j -lt $azsHostDataDiskCount + 1 ; $j++)
                { 
                    xvhd "$vmname-DataDisk$j"
                    {
                        Ensure           = 'Present'
                        Name             = "$vmname-DataDisk$j.vhdx"
                        Path             = "$targetVMPath\$vmname"
                        Generation       = 'vhdx'
                        Type             = 'Dynamic'
                        MaximumSizeBytes = $dataDiskSize
                        DependsOn        = "[xVMHyperV]VM-$vmname"
                    }
                
                    xVMHardDiskDrive "$vmname-DataDisk$j"
                    {
                        VMName = $vmname
                        ControllerType = 'SCSI'
                        ControllerLocation = $j
                        Path = "$targetVMPath\$vmname\$vmname-DataDisk$j.vhdx"
                        Ensure = 'Present'
                        DependsOn = "[xVMHyperV]VM-$vmname"
                    }
                }

                script "UnattendXML for $vmname"
                {
                    GetScript = {
                        $name = $using:VmName
                        $result = Test-Path -Path "$using:targetVMPath\$name\Unattend.xml"
                        return @{ 'Result' = $result }
                    }

                    SetScript = {
                        try 
                        {
                            $name = $using:VmName
                            $mount = Mount-VHD -Path "$using:targetVMPath\$name\$name-OSDisk.vhdx" -Passthru -ErrorAction Stop
                            Start-Sleep -Seconds 2
                            $driveLetter = $mount | Get-Disk | Get-Partition | Get-Volume | Where-Object DriveLetter | Select-Object -ExpandProperty DriveLetter
                            
                            New-Item -Path $("$driveLetter" + ":" + "\Temp") -ItemType Directory -Force -ErrorAction Stop
                            
                            Copy-Item -Path "$using:sourcePath\branchData\$using:repoName-$using:branch\helpers\Install-AzsRolesandFeatures.ps1" -Destination $("$driveLetter" + ":" + "\Temp") -Force -ErrorAction Stop

                            New-BasicUnattendXML -ComputerName $name -LocalAdministratorPassword $($using:Admincreds).Password -Domain $using:DomainName -Username $using:Admincreds.Username `
                                -Password $($using:Admincreds).Password -JoinDomain $using:DomainName -AutoLogonCount 1 -OutputPath "$using:targetVMPath\$name" -Force `
                                -PowerShellScriptFullPath 'c:\temp\Install-AzsRolesandFeatures.ps1' -ErrorAction Stop

                            Copy-Item -Path "$using:targetVMPath\$name\Unattend.xml" -Destination $("$driveLetter" + ":" + "\Windows\system32\SysPrep") -Force -ErrorAction Stop

                            Start-Sleep -Seconds 2
                        }
                        finally 
                        {
                            DisMount-VHD -Path "$using:targetVMPath\$name\$name-OSDisk.vhdx"
                        }
                        
                        Start-VM -Name $name
                    }

                    TestScript = {
                        # Create and invoke a scriptblock using the $GetScript automatic variable, which contains a string representation of the GetScript.
                        $state = [scriptblock]::Create($GetScript).Invoke()
                        return $state.Result
                    }
                    DependsOn = "[xVhd]NewOSDisk-$vmname", "[archive]Extract branch files"
                }
            }
        }
        
        file "VM-Folder-$wacVMName"
        {
            Ensure = 'Present'
            DestinationPath = "$targetVMPath\$wacVMName"
            Type = 'Directory'
            DependsOn = "[File]folder-vms"
        }
        
        xVhd "NewOSDisk-$wacVMName"
        {
            Ensure           = 'Present'
            Name             = "$wacVMName-OSDisk.vhdx"
            Path             = "$targetVMPath\$wacVMName"
            Generation       = 'vhdx'
            ParentPath       = $azsHciVhdPath
            Type             = 'Differencing'
            DependsOn = "[xVMSwitch]$vSwitchNameMgmt", "[script]prepareVHDX", "[file]VM-Folder-$wacVMName"
        }

        xVMHyperV "VM-$wacVMName"
        {
            Ensure          = 'Present'
            Name            = $wacVMName
            VhdPath         = "$targetVMPath\$wacVMName\$wacVMName-OSDisk.vhdx"
            Path            = $targetVMPath
            Generation      = 2
            StartupMemory   = 2GB
            MinimumMemory   = 2GB
            MaximumMemory   = 8GB
            ProcessorCount  = 2
            DependsOn       = "[xVhd]NewOSDisk-$wacVMName"
        }
        
        xVMNetworkAdapter "remove default Network Adapter on VM-$wacVMName"
        {
            Ensure = 'Absent'
            Id = "Network Adapter"
            Name = "Network Adapter"
            SwitchName = $vSwitchNameMgmt
            VMName = $wacVMName
            DependsOn = "[xVMHyperV]VM-$wacVMName"
        }

        xVMNetworkAdapter "New Network Adapter Management for VM-$wacVMName"
        {
            Id = "$wacVMName-Management"
            Name = "$wacVMName-Management"
            SwitchName = $vSwitchNameMgmt
            VMName = $wacVMName
            NetworkSetting = xNetworkSettings {
                IpAddress = "192.168.0.100"
                Subnet = "255.255.255.0"
                DefaultGateway = "192.168.0.1"
                DnsServer = "192.168.0.1"
            }
            Ensure = 'Present'
            DependsOn = "[xVMHyperV]VM-$wacVMName"
        }

        Script "UnattendXML for $wacVMName"
        {
            GetScript = {
                $name = $using:wacVMName
                $result = Test-Path -Path "$using:targetVMPath\$name\Unattend.xml"
                return @{ 'Result' = $result }
            }

            SetScript = {
                try 
                {
                    $name = $using:wacVMName
                    $mount = Mount-VHD "$using:targetVMPath\$name\$name-OSDisk.vhdx" -Passthru -ErrorAction Stop
                    Start-Sleep -Seconds 2
                    $driveLetter = $mount | Get-Disk | Get-Partition | Get-Volume | Where-Object DriveLetter | Select-Object -ExpandProperty DriveLetter
                    
                    New-Item -Path $("$driveLetter" + ":" + "\Temp") -ItemType Directory -Force -ErrorAction Stop
                    Copy-Item -Path "$using:sourcePath\branchData\$using:repoName-$using:branch\helpers\Install-WacUsingChoco.ps1" -Destination $("$driveLetter" + ":" + "\Temp") -Force -ErrorAction Stop

                    New-BasicUnattendXML -ComputerName $name -LocalAdministratorPassword $($using:Admincreds).Password -Domain $using:DomainName -Username $using:Admincreds.Username `
                    -Password $($using:Admincreds).Password -JoinDomain $using:DomainName -AutoLogonCount 1 -OutputPath "$using:targetVMPath\$name" -Force `
                    -IpCidr "192.168.0.100/24" -DnsServer '192.168.0.1' -NicNameForIPandDNSAssignments 'Ethernet' -PowerShellScriptFullPath 'c:\temp\Install-WacUsingChoco.ps1' -ErrorAction Stop
                    
                    Copy-Item -Path "$using:targetVMPath\$name\Unattend.xml" -Destination $("$driveLetter" + ":" + "\Windows\system32\SysPrep") -Force -ErrorAction Stop
                    
                    Copy-Item -Path "C:\Program Files\WindowsPowerShell\Modules\cChoco" -Destination $("$driveLetter" + ":" + "\Program Files\WindowsPowerShell\Modules") -Recurse -Force -ErrorAction Stop
                    Copy-Item -Path "C:\Program Files\WindowsPowerShell\Modules\ComputerManagementDsc" -Destination $("$driveLetter" + ":" + "\Program Files\WindowsPowerShell\Modules") -Recurse -Force -ErrorAction Stop
                    
                    Start-Sleep -Seconds 2
                    
                }
                finally
                {
                    DisMount-VHD "$using:targetVMPath\$name\$name-OSDisk.vhdx"
                }
                
                Start-VM -Name $name
            }

            TestScript = {
                # Create and invoke a scriptblock using the $GetScript automatic variable, which contains a string representation of the GetScript.
                $state = [scriptblock]::Create($GetScript).Invoke()
                return $state.Result
            }
            DependsOn = "[xVhd]NewOSDisk-$wacVMName", "[archive]Extract branch files"
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

        cChocoPackageInstaller "Install Chromium Edge"
        {
            Name        = 'microsoft-edge'
            Ensure      = 'Present'
            AutoUpgrade = $true
            DependsOn   = '[cChocoInstaller]installChoco'
        }

        cShortcut "Wac Shortcut"
        {
            Path      = 'C:\Users\Public\Desktop\Windows Admin Center.lnk'
            Target    = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
            Arguments = 'https://wac'
            Icon      = 'shell32.dll,34'
        }

        cShortcut "Document Shortcut"
        {
            Path      = 'C:\Users\Public\Desktop\Poc Guide.lnk'
            Target    = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
            Arguments = "https://yagmurs.github.io/$repoName"
            Icon      = 'shell32.dll,74'
        }

        cShortcut "Lab Guide Shortcut"
        {
            Path      = 'C:\Users\Public\Desktop\Lab Script.lnk'
            Target    = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell_ise.exe'
            Arguments = "$sourcePath\branchData\$repoName-$branch\scripts\$labScript"
        }
    }
}
