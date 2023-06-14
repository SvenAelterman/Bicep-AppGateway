# PowerShell script to deploy the main.bicep template with parameter values

#Requires -Modules "Az"
#Requires -PSEdition Core

# Use these parameters to customize the deployment instead of modifying the default parameter values
[CmdletBinding()]
Param(
	[ValidateSet('eastus2', 'eastus', 'usgovvirginia')]
	[Parameter(Mandatory)]
	[string]$Location,
	[Parameter(Mandatory)]
	[string]$TargetSubscription,
	[Parameter(Mandatory)]
	[string]$TemplateParameterFile 
)

Select-AzSubscription $TargetSubscription

# Perform the ARM deployment
$DeploymentResult = New-AzDeployment -Location $Location -Name "AppGW-$(Get-Date -Format 'yyyyMMddThhmmssZ' -AsUTC)" `
	-TemplateFile ".\main.bicep" -TemplateParameterFile $TemplateParameterFile

if ($DeploymentResult.ProvisioningState -eq 'Succeeded') {
	Write-Host "🔥 Azure Resource Manager deployment successful!"

	$AppGwPublicIpAddress = $DeploymentResult.Outputs.appGwPublicIpAddress.Value
	Write-Host "`nFor a quick test, modify your HOSTS file and add the following entry:`n$($AppGwPublicIpAddress)`t<website domain>"
}
else {
	$DeploymentResult
}
