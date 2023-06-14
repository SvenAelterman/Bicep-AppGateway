[CmdLetBinding()]
Param()

[string]$Location = 'usgovvirginia'
[string]$TargetSubscription = 'subscription ID'
[string]$TemplateParameterFile = 'main.parameters-sample.jsonc'

.\deploy.ps1 -Location $Location -TargetSubscription $TargetSubscription `
    -TemplateParameterFile $TemplateParameterFile
