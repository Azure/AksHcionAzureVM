
Import-Module AzureStackHCIInstallerHelper

# The following function calls the wizard to setup Azure Stack Hci cluster then prepares hosts for Aks Hci Deployment
Start-AksHciPoC -verbose

#register Azure Stack HCI cluster as Azure Arc resource (pre-requisites to deploy any vm on Azure Stack HCI)
# https://docs.microsoft.com/en-us/azure-stack/hci/deploy/register-with-azure

# variables used in the script, update them accordingly based on your environment before proceed further
$tenant = "xxxxxxxxxxx.onmicrosoft.com"
$subscriptionID = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
$rgName = "new-arc-hci-rg"
$location = "westeurope"
$hciHostName = "hpv01"
$hciClusterName = "hci01"

Install-Module az
Install-Module AzureAD
Install-Module -Name Az.StackHCI
Connect-AzAccount -Tenant $tenant
Select-AzSubscription -Subscription $subscriptionID
$rg = New-AzResourceGroup -Name $rgName -Location $location
Register-AzStackHCI  -SubscriptionId $subscriptionID -ComputerName $hciHostName -ResourceName $hciClusterName -ResourceGroupName $rg.ResourceGroupName -Region $rg.location

break 

#############################################################
#                                                           #
# Run the following code on one of the Azure Stack HCI host #
#                                                           #
#############################################################

#Enable AksHCI on Azure Stack HCI cluster
# variables used in the script, update them accordingly based on your environment before proceed further
$targetDrive = "C:\ClusterStorage"
$AksHciTargetFolder = "AksHCIMain"
$AksHciTargetPath = "$targetDrive\$AksHciTargetFolder"
$sourcePath =  "$AksHciTargetPath\source" 
$targetClusterName = "target-cls1-on-hci" #must be lower case
$tenant = "xxxxxxxxxxx.onmicrosoft.com"
$subscriptionID = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
$rgName = "new-arc-rg"
$location = "westeurope"

break

#region pre-requisites 
# Install Az modules to access Azure and Azure Arc Kubernetes resources
Install-Module az
Install-Module Az.ConnectedKubernetes

# Install Chocolatey if not installed already 
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

# supress choco installation prompt
choco feature enable -n allowGlobalConfirmation

# Install Azure Cli using Chocolatey
choco install azure-cli

# Install latest Helm using Chocolatey
choco install kubernetes-helm

#update environment variable values after Azure Cli and Helm installation
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine")

# Add and update Az Cli k8sconfiguration and connectedk8s extensions
# https://docs.microsoft.com/en-us/azure/azure-arc/kubernetes/connect-cluster
az extension add --name connectedk8s
az extension add --name k8sconfiguration

# check if update available for extensions 
az extension update --name connectedk8s
az extension update --name k8sconfiguration

#endregion pre-requisites

break

#region Enable AksHCI

#Deploy Management Cluster
# https://docs.microsoft.com/en-us/azure-stack/aks-hci/create-kubernetes-cluster-powershell
Import-Module AksHci
Initialize-AksHciNode

$managementClusterParams = @{
    imageDir = "$AksHciTargetPath\Images"
    cloudConfigLocation = "$AksHciTargetPath\Config"
    workingDir = "$AksHciTargetPath\Working"
    vnetName = 'Default Switch'
    controlPlaneVmSize = 'default' # Get-AksHciVmSize
    loadBalancerVmSize = 'default' # Get-AksHciVmSize
}

Set-AksHciConfig @managementClusterParams

Install-AksHci

#Deploy Target Cluster

$targetClusterParams = @{
    clusterName = $targetClusterName
    kubernetesVersion = 'v1.18.8'
    controlPlaneNodeCount = 1
    linuxNodeCount = 1
    windowsNodeCount = 0
    controlPlaneVmSize = 'default' # Get-AksHciVmSize
    loadBalancerVmSize = 'default' # Get-AksHciVmSize
    linuxNodeVmSize = 'default' # Get-AksHciVmSize
    windowsNodeVmSize = 'default' # Get-AksHciVmSize
}

New-AksHciCluster @targetClusterParams

#endregion Enable AksHCI

#region deploy and upgrade kubernetes cluster
# https://docs.microsoft.com/en-us/azure-stack/aks-hci/create-kubernetes-cluster-powershell#step-3-upgrade-kubernetes-version

$demoClusterParams = @{
    clusterName = 'update-demo'
    kubernetesVersion = 'v1.16.10' # v1.16.15, v1.17.11, v1.18.8
    controlPlaneNodeCount = 1
    linuxNodeCount = 1
    windowsNodeCount = 0
    controlPlaneVmSize = 'default' # Get-AksHciSize
    loadBalancerVmSize = 'default' # Get-AksHciSize
    linuxNodeVmSize = 'default' # Get-AksHciSize
    windowsNodeVmSize = 'default' # Get-AksHciSize
}

New-AksHciCluster @demoClusterParams

#List k8s clusters
Get-AksHciCluster -clusterName update-demo

# scale up controller node count
Set-AksHciClusterNodeCount -clusterName update-demo -controlPlaneNodeCount 3

# run update patch (1.16.x --> 1.16.y)
Update-AksHciCluster -clusterName update-demo -patch

# run update without patching (1.16.x --> 1.17.y)
Update-AksHciCluster -clusterName update-demo


#endregion

break

#list Aks Hci cmdlets
Get-Command -Module AksHci

#List k8s clusters
Get-AksHciCluster

#Retreive AksHCI logs for Target Cluster deployment
Get-AksHciCredential -clusterName $targetClusterName

#region onboarding

# login Azure
Connect-AzAccount -Tenant $tenant

# Get current Azure context
Get-AzContext

# list subscriptions 
Get-AzSubscription

# select subscription
Select-AzSubscription -Subscription $subscriptionID

# Verify using correct subscription
Get-AzContext
$context = Get-AzContext

# Create new resource group to onboard Aks Hci to Azure Arc
$rg = New-AzResourceGroup -Name $rgName -Location $location

#https://docs.microsoft.com/en-us/powershell/module/az.resources/new-azadserviceprincipal?view=azps-5.4.0
# Create new Spn on azure and assing them contributor access on the Resource Group
$sp = New-AzADServicePrincipal -Role Contributor -Scope "/subscriptions/$subscriptionID/resourceGroups/$($rg.ResourceGroupName)"
[pscredential]$credObject = New-Object System.Management.Automation.PSCredential ($sp.ApplicationId, $sp.Secret)

#https://docs.microsoft.com/en-us/azure-stack/aks-hci/connect-to-arc
# Onboard Aks Hci to Azure Arc using Powershell
Install-AksHciArcOnboarding -clusterName $targetClusterName -resourcegroup $rg.ResourceGroupName -location $rg.location -subscriptionId $context.Subscription.Id -clientid $sp.ApplicationId -clientsecret $credObject.GetNetworkCredential().Password -tenantid $context.Tenant.Id

# get state of the onboarding process
kubectl get pods -n azure-arc-onboarding

# list error information
kubectl describe pod -n azure-arc-onboarding azure-arc-onboarding-<Name of the pod>
kubectl logs -n azure-arc-onboarding azure-arc-onboarding-<Name of the pod>

#endregion onboarding

#region enable monitoring

# enable monitoring using Powershell
# https://docs.microsoft.com/en-us/azure/azure-monitor/insights/container-insights-enable-arc-enabled-clusters
Invoke-WebRequest https://aka.ms/enable-monitoring-powershell-script -OutFile enable-monitoring.ps1
$azureArcClusterResourceId = "/subscriptions/$subscriptionID/resourceGroups/$($rg.ResourceGroupName)/providers/Microsoft.Kubernetes/connectedClusters/$targetClusterName"
$kubeContext = kubectl.exe config current-context
$logAnalyticsWorkspaceResourceId = "/subscriptions/$subscriptionID/resourceGroups/$($rg.ResourceGroupName)/providers/microsoft.operationalinsights/workspaces/yagmurslog"
.\enable-monitoring.ps1 -clusterResourceId $azureArcClusterResourceId -kubeContext $kubeContext -workspaceResourceId $logAnalyticsWorkspaceResourceId

#endregion enable monitoring

#region deploy application

# the repository can be forked to run advanced scenarios. If you fork the repo please update the repo variable accordingly to be used in the following commands.
$gitRepo = "https://github.com/Azure/arc-k8s-demo"

# deploy demo application from Azure Arc Enabled Kubernetes from Azure portal (UI)
<#
    Go to Azure Portal --> Azure arc target kubernetes cluster --> select gitops and add, provide following information

    Configuration name: cluster-config
    Operator instance name: cluster-config
    Operator namespace: cluster-config
    Repository URL: https://github.com/Azure/arc-k8s-demo.git
    Operator scope: Cluster
    add
#>

# deploy demo application on Azure Arc Enabled Kubernetes using Azure Cli
# https://docs.microsoft.com/en-us/azure/azure-arc/kubernetes/use-gitops-connected-cluster
az login --tenant $tenant
az k8sconfiguration create --name "cluster-config" --cluster-name $targetClusterName --resource-group $rg.ResourceGroupName --operator-instance-name "cluster-config" --operator-namespace 'cluster-config' --repository-url $gitRepo --scope "cluster" --cluster-type "connectedClusters" --operator-params "'--git-poll-interval 3s --git-readonly'"

# list all service config
kubectl.exe get services

# list specific service config for azure vote application
kubectl.exe get services azure-vote-front

#endregion deploy application


#region scale up

# Scale up/down node count
Set-AksHciClusterNodeCount -clusterName $targetClusterName -linuxNodeCount 1 -windowsNodeCount 0

# scale up azure vote application pod count

# scale up with devops from github vote application pod count

# verify scale up

#endregion

#region clean up

# uninstall / remove from Azure Arc
Uninstall-AksHciArcOnboarding -clusterName $targetClusterName

#Retreive AksHCI logs for Target Cluster deployment
Get-AksHciLogs

#List k8s clusters
Get-AksHciCluster

#Remove Target cluster
Remove-AksHciCluster -clusterName $targetClusterName

Uninstall-AksHci

#endregion
