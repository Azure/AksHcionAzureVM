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

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fyagmurs%2FAzureStackHCIonAzure%2Ftest%2Fazuredeploy.json)

[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Fyagmurs%2FAzureStackHCIonAzure%2Ftest%2Fazuredeploy.json)

### High level deployment process and features

Deploy the ARM template (above buttons) by providing all the parameters required. Find details of **Aks Hci Scenario** options below. Most of the parameters have default values and sufficient for demostrate Aks Hci features and deployment procedures.
During the ARM template deployment Azure VM DSC will create Windows Admin Center VM than Chocolatey which means will be updated once released in Chocolatey repository. All installed extensions are getting updated daily in the background.

Note that all VMs deployed within the Azure VM use **same password** that has been specified in the ARM template.

* Azure VM will be configured as Domain Controller, DHCP, DNS and Hyper-v host.
* All Local accounts are named as **Administrator**.
* The **Domain Administrator** username is the **Username specified in the ARM template**.

### Deployment Scenarios

#### **Aks Hci on Azure VM**

This is one of scenario if you are willing to understand how to deploy Aks Hci and evaluate options.

![ARM-akshcionAzureVM](https://github.com/Azure/AksHcionAzureVM/raw/master/.images/ARM-akshcionAzureVM.png)

**Note**: Once **'onAzureVMDirectly'** option selected for **'Aks Hci Scenario'** the following two option will be disregarded in the DSC configuration. As a result on WAC (Windows Admin Center) VM will be deployed.

#### **Aks Hci on Azure Stack HCI cluster**

This is one of scenario if you are willing to understand how to deploy Aks Hci on Azure Stack HCI and evaluate options. This is also useful scenarion to test Azure Stack HCI only without deploying Aks Hci on top of Azure Stack Hci Cluster.

![ARM-akshcionAzureStackHCICluster](https://github.com/Azure/AksHcionAzureVM/raw/master/.images/ARM-akshcionAzureStackHCICluster.png)

**Note**: Once **'onNestedAzureStackHciClusteronAzureVM'** option selected for **'Aks Hci Scenario'** Make sure the correlation between the deployment VM size and Azure Stack HCI host counts and Memory sizes are compatible. As a result a number of Azure Stack HCI VMs (specified in 'AzS Hci Host Count' with 'AzS Hci Host Memory') and WAC (Windows Admin Center) VM will be deployed on Azure VM.

## Wait for VM to finalize DSC configuration

Once VM deployed successfully. VM will be accessible via RDP.

Open hyper-v manager on the VM to validate if all VMs are located in the console.

## How to run PoC using scripts

There are couple of shortcuts available on the desktop. Desktop shortcuts can be utilized to demostrate or learning purposes to understand process and options

* Proof of concepts guide (**PoC guide**) on the desktop (this guide)
* Step by step script PoC script (**lab Script**) on the desktop, the script includes following options
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

## How to run PoC using Windows Admin Center

Since Windows Admin Center and Azure Stack HCI hosts (based on the scenario selected) have already been deployed and configured on Azure VM, the following guides can be utilized without setting up any additional resources.

Double click on **'Windows Admin Center'** shorcut on the desktop to access Windows Admin Center or Open a new browser (Edge is preinstalled on the computer) and type [wac](https://wac)

### Install Azure Stack HCI using WAC

[Create an Azure Stack HCI cluster using Windows Admin Center](https://docs.microsoft.com/en-us/azure-stack/hci/deploy/create-cluster#step-1-get-started)

### Install Aks Hci using WAC

Aks Hci can be deployed on Azure Stack HCI or directly on Azure VM. The following guide can be utilized to deploy Aks Hci for either scenarios.
[Set up Azure Kubernetes Service using Windows Admin Center](https://docs.microsoft.com/en-us/azure-stack/aks-hci/setup#installing-the-azure-kubernetes-service-extension)
