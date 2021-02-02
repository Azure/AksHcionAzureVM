$rgPrefix = 'yagmurs-azurestack'
$location = 'germanywestcentral'
$branch = 'test'
$subs = Get-Content .\scripts\ignore\subscription.txt
if (-not (Get-AzAccessToken))
{
    Connect-AzAccount -UseDeviceAuthentication
}

if (-not ($sub))
{
    $subs | Out-GridView -PassThru | ForEach-Object {$sub = $_}
}
Write-Verbose -Message "Subscription: $sub will be used" -Verbose

if ((Get-AzContext | Select-Object -ExpandProperty name) -notlike "$sub*")
{
    Get-AzSubscription | Out-GridView -PassThru | Select-AzSubscription
}

$paramUri = "https://raw.githubusercontent.com/yagmurs/AzureStackHCIonAzure/test/azuredeploy.parameters.json"
$paramFileAsHash = ((Invoke-WebRequest -UseBasicParsing -Uri $paramUri).content | ConvertFrom-Json -AsHashtable)
if (-not ($clearTextPassword))
{
    $clearTextPassword = Read-Host -Prompt "Enter password for the VM" -MaskInput
}

$encryptedPass = $clearTextPassword | ConvertTo-SecureString -AsPlainText -Force
$templateParameterObject = @{}
$paramFileAsHash.parameters.keys | ForEach-Object {$templateParameterObject[$_] = $paramFileAsHash.parameters.$_.value}
$templateParameterObject.add("AdminPassword", $encryptedPass)
$templateParameterObject.location = $location
$templateParameterObject.branch = $branch
#$templateParameterObject.aksHciScenario = 'onNestedAzureStackHciClusteronAzureVM'
#$templateParameterObject

do {
    Write-Host "'N'ew or 'D'SC only deployment?" -Nonewline -ForegroundColor DarkYellow -BackgroundColor Blue
    $dtype = read-host
} until ($dtype -eq "N" -or $dtype -eq "D")

if ($dtype -eq "n")
{
    if ([string]::IsNullOrEmpty($rgPrefix))
    {
        Write-Error "`$rgPrefix is empty" -ErrorAction Stop
    }

    do 
    {
        $r = get-random -Minimum 1 -Maximum 3
    } while (Get-AzResourceGroup -Name "$rgPrefix$r" -ErrorAction SilentlyContinue)

    $rgName = "$rgPrefix$r"

    $rgObject = @($("$rgPrefix" + 0), $("$rgPrefix" + 1), $("$rgPrefix" + 2), $("$rgPrefix" + 3)) | ForEach-Object {Get-AzResourceGroup -Name $_ -ErrorAction SilentlyContinue}
    
    if ($rgObject) 
    {
        Write-Verbose -Message "Resource Group: $($rgObject.ResourceGroupName) will be deleted" -Verbose
        $rgObject | Remove-AzResourceGroup -confirm:$true
        #$rgObject | Remove-AzResourceGroup -Force -AsJob
    }

    $templateParameterObject.dnsPrefix = $templateParameterObject.dnsPrefix.Insert($templateParameterObject.dnsPrefix.Length, $r)

    New-AzResourceGroup -Name $rgName -Location $templateParameterObject.location
    New-AzResourceGroupDeployment -ResourceGroupName $rgName `
    -Name "azshcihost" -TemplateUri "https://raw.githubusercontent.com/yagmurs/AzureStackHCIonAzure/$branch/azuredeploy.json" `
    -TemplateParameterObject $templateParameterObject
}
elseif ($dtype -eq "d")
{
    $rg = (Get-AzResourceGroup -ResourceGroupName $rgPrefix*).ResourceGroupName
    $r = $rg[-1]
    Write-Verbose "Removing DSC Extension for VM on $rg Resource Group" -Verbose
    Get-AzVMExtension -ResourceGroupName $rg -VMName dc01 | Where-Object ExtensionType -eq DSC | Remove-AzVMExtension -Force -Verbose

    $templateParameterObject.dnsPrefix = $templateParameterObject.dnsPrefix.Insert($templateParameterObject.dnsPrefix.Length, $r)
    
    Write-Verbose "Redeploying ARM template for VM on $rg Resource Group" -Verbose
    New-AzResourceGroupDeployment -ResourceGroupName $rg `
    -Name "azshcihost" -TemplateUri "https://raw.githubusercontent.com/yagmurs/AzureStackHCIonAzure/$branch/azuredeploy.json" `
    -TemplateParameterObject $templateParameterObject -Force -Verbose
}