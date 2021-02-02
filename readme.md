# Aks Hci on Azure VM project

This repository is designed to simplify Aks Hci demos in mind for people who are developers without domain knowledge or IT-Pros without Virtualization knowledge. It consist of an ARM template to deploy VM with DSC extentions to provide ready to utilize PoC environment.

There are two scenarios to utilize the ARM template as follows.

## Aks Hci on Azure VM

Only Windows Admin Center VM will be created once ARM template successfully deployed. Windows Admin center or PowerShell scripts (available to the desktop) may be utilized for completing Aks Hci deployment on top of Azure VM in couple of minutes.

### **Architecture of the deployment** (Aks Hci on Azure VM)

Following drawing shows the end result comes from ARM template once **'onAzureVMDirectly'** option in 'Aks Hci Scenario' parameter selected.

![AksHciOnAzureStackHci](https://github.com/Azure/AksHcionAzureVM/raw/master/.images/AksHcionAzureVM.png)

## Aks Hci on Azure Stack HCI cluster

Following drawing shows the end result comes from ARM template once **'onNestedAzureStackHciClusteronAzureVM'** option in 'Aks Hci Scenario' parameter selected.

Azure Stack HCI host and Windows Admin Center VMs will be created once ARM template successfully deployed. Windows Admin center or PowerShell scripts (available to the desktop) may be utilized for completing Azure Stack HCI deployment in couple of minutes. Afterwards Aks Hci may be deployed on top of Azure Stack HCI clusters using provided scripts (available to the desktop).

**Note**: Due to nature of multiple layers of Nested virtualization, there are performance implications. However this is implemented to practice bits and pieces of the whole deployment to experience Aks Hci on top of Azure Stack HCI.

### **Architecture of the deployment** (Aks Hci on Azure Stack HCI cluster)

![AksHciOnAzureStackHci](https://github.com/Azure/AksHcionAzureVM/raw/master/.images/AksHciOnAzureStackHci.png)

## Using ARM template to deploy Azure VM

Click the button below to deploy via Azure portal:

**Do not use 192.168.0.0/24 , 192.168.100.0/24 , 192.168.251.0/24, 192.168.252.0/24, 192.168.253.0/24 , 192.168.254.0/24 networks as address space for Vnet since those network are getting utilized in the Nested environment.**

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fyagmurs%2FAzureStackHCIonAzure%2Ftest%2Fazuredeploy.json)

[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Fyagmurs%2FAzureStackHCIonAzure%2Ftest%2Fazuredeploy.json)

### High level deployment process and features

Deploy the ARM template (above buttons) by providing all the parameters required. Find details of **Aks Hci Scenario** options below. Most of the parameters have default values and sufficient for demostrate Aks Hci features and deployment procedures.
During the ARM template deployment Azure VM DSC extension will create Windows Admin Center VM (WAC) than installs latest version of Windows Admin Center bits available on Chocolatey repository. Once Windows Admin Center installed, all extensions are getting updated daily in the background via DSC running in WAC VM.

Note that all VMs deployed within the Azure VM use **same password** that has been specified in the ARM template.

* Azure VM will be configured as Domain Controller, DHCP, DNS and Hyper-v host.
* All Local accounts are named as **Administrator**.
* The **Domain Administrator** username for the environment is the **Username specified in the ARM template**.

### Deployment Scenarios

There are two scenarios available at the moment which are consist as follows.

#### **Aks Hci on Azure VM**

This is first scenario if you are evaluating how to deploy Aks Hci to understand capabilities.

![ARM-akshcionAzureVM](https://github.com/Azure/AksHcionAzureVM/raw/master/.images/ARM-akshcionAzureVM.png)

**Note**: Once **'onAzureVMDirectly'** option selected for **'Aks Hci Scenario'** the following two option will be disregarded in the DSC configuration. As a result only WAC (Windows Admin Center) VM will be deployed.

* AzS HCI Host Count
* AzS HCI Host Memory

#### **Aks Hci on Azure Stack HCI cluster**

This is the second scenario if you are evaluating how to deploy Aks Hci on Azure Stack HCI to understand capabilities. This is also useful scenarion to test Azure Stack HCI only without deploying Aks Hci on top of Azure Stack Hci Cluster.

![ARM-akshcionAzureStackHCICluster](https://github.com/Azure/AksHcionAzureVM/raw/master/.images/ARM-akshcionAzureStackHCICluster.png)

**Note**: Once **'onNestedAzureStackHciClusteronAzureVM'** option selected for **'Aks Hci Scenario'** Make sure the correlation between the deployment VM size and Azure Stack HCI host counts and Memory sizes are compatible. As a result a number of Azure Stack HCI VMs (specified in 'AzS Hci Host Count' with 'AzS Hci Host Memory') and WAC (Windows Admin Center) VM will be deployed on Azure VM.

## Wait for VM to finalize DSC configuration

Once VM deployed successfully. (Takes approximately about 30 minutes) VM will be accessible via RDP.

Open Hyper-v manager on the VM to validate if all VMs are located in the console.

## How to run Proof of concepts using PowerShell scripts

There are couple of shortcuts available on the desktop. Desktop shortcuts can be utilized to demostrate or learning purposes to understand process and options

* Proof of concepts guide (**PoC guide**) on the desktop ([this guide](https://azure.github.io/AksHcionAzureVM/))
* Step by step script PoC script (**lab script**) on the desktop, the script includes following options
  * Deployment of Azure Stack HCI cluster through a wizard. (Depends on the scenario selected)
  * Tools and prerequisites installations
  * Management and Target Aks clusters deployment
  * Azure Arc onboarding process
  * Enable Azure Arc montioring
  * Deploy demo application to Kubernetes cluster onboarded to Azure Arc
  * Scale up kubernetes cluster
  * Deployment of an older version of Kubernetes cluster than updating the cluster to newer version
  * Uninstall onboarding from Azure Arc
  * Destroy kubernetes cluster
  * Remove Aks Hci deployment

## How to run Proof of concepts using Windows Admin Center

Since Windows Admin Center and Azure Stack HCI hosts (based on the scenario selected) have already been deployed and configured on Azure VM, the following guides can be utilized without setting up any additional resources.

Double click on **'Windows Admin Center'** shorcut on the desktop to access Windows Admin Center or Open a new browser (Edge is preinstalled on the computer) and type [wac](https://wac)

### **Install Azure Stack HCI using Windows Admin Center**

[Create an Azure Stack HCI cluster using Windows Admin Center](https://docs.microsoft.com/en-us/azure-stack/hci/deploy/create-cluster#step-1-get-started)

### **Install Aks Hci using Windows Admin Center**

Aks Hci can be deployed on Azure Stack HCI or directly on Azure VM. The following guide can be utilized to deploy Aks Hci for either scenarios.
[Set up Azure Kubernetes Service using Windows Admin Center](https://docs.microsoft.com/en-us/azure-stack/aks-hci/setup#installing-the-azure-kubernetes-service-extension)

## What exactly does ARM template deploy under the hood

* The ARM template utilize the latest Windows Server 2019 Marketplace image and use templatelink to deploy Vnet etc.
* Two disks are added to Azure VM
  * F: drive for Domain Controller (Disk 1)
  * V: drive for Hyper-v and all source files (Disk 2)
* Also DSC extension utilized to install and configure VM with the following components
  * Creates source folder on V: drive to download required files
  * Creates V:\VMs\base folder to place VHDx file
  * Creates V:\VMs folder to host VMs
  * Configures Azure VM as Domain Controller
  * Installs DNS server role
  * Installs DHCP server role and configures with two scopes
  * Couple of virtual adapters with layer 3 connectivity
  * Downloads Azure Stack HCI OS iso file
  * Creates image (VHDx) based on Azure Stack HCI OS iso file as V:\VMs\base\AzSHCI.vhdx
  * Creates Windows Admin Center VM from VHDx using differencing disk
  * Creates multiple instance of Azure Stack HCI host VMs (based on scenario) from VHDx using differencing disk with multiple NICs
  * Assigns static IP addresses to some of the Nics on VMs especially for non-management NICs
  * Joins all VMs to the domain
  * Downloads and extract repository files to Azure VM for further use
  * Install Windows Admin Center and runs extension update on WAC VM (Runs extension update every 24 hours via DSC on the VM)
  * Creates desktop shortcuts based on scenario selected

### VMs in the nested environment messed up / willing to reset and start over?

#### Option 1

Just run the following PowerShell on Azure VM. It will destroy and re-create Azure Stack HCI and Windows Admin Center VMs. Will take about 3-5 mins to complete the task including WAC deployment.

```powershell

Cleanup-VMs -AzureStackHciHostVMs -WindowsAdminCenterVM

```

#### Option 2

Running the following PowerShell on Azure VM will result removing VMs and source files then re-create image (VHDx) and VMs from scratch. Will take about 10-15 mins to complete. Useful if new Azure Stack HCI host image published.

```powershell

Cleanup-VMs -AzureStackHciHostVMs -WindowsAdminCenterVM -RemoveAllSourceFiles

```

#### Option 3

Running the following PowerShell on Azure VM or Azure Stack HCI cluster will result removing all VMs created through Aks Hci deployment

```powershell

Uninstall-AksHci

```

**Note**: Cleanup-VMS will trigger DSC after cleanup process to bring Azure VM to initial state. Use **-DoNotRedeploy** with the command if initial state is not desired.

## Issues and features

### Known issues

### How to file a bug

1. Go to our [issue tracker on GitHub](https://github.com/Azure/AksHcionAzureVM/issues)
1. Search for existing issues using the search field at the top of the page
1. File a new issue including the info listed below

### Requesting a feature

Feel free to file new feature requests as an issue on GitHub, just like a bug.

 > Yagmur Sahin
 >
 > Twitter: [@yagmurs](https://twitter.com/yagmurs)
