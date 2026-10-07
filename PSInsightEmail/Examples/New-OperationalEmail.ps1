[CmdletBinding()]
param(
    [Parameter()][ValidateNotNullOrEmpty()][string] $OutputPath,
    [Parameter()][switch] $Open
)

$ErrorActionPreference = 'Stop'
$ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path $ModuleRoot 'PSInsightEmail.psd1') -Force

$Results = @(
    [pscustomobject]@{ Step = 'Validate configuration'; Result = 'Completed'; Duration = '00:00:18' }
    [pscustomobject]@{ Step = 'Apply sample changes'; Result = 'Completed'; Duration = '00:01:42' }
    [pscustomobject]@{ Step = 'Verify services'; Result = 'Completed'; Duration = '00:00:31' }
)

$Email = New-PSIEmail -Title 'Operational Execution Summary' `
    -Subtitle 'Fictional directory maintenance workflow' `
    -Preheader 'The sample operation completed successfully with no failed steps.' `
    -Template Operational -BrandName 'Example Automation' `
    -EnvironmentLabel 'Example Production' -EnvironmentStatus Healthy `
    -SourceLabel 'Sample maintenance workflow' `
    -FooterNote 'Execution note: this message summarizes a fictional automation run.'

$Email |
    Add-PSIEmailSection -Title 'Execution Result' -Description 'Compact outcome and execution metadata.' |
    Add-PSIEmailRow |
    Add-PSIEmailBanner -Status Healthy -Title 'Changes applied successfully' `
        -Message 'All fictional workflow steps completed and verification checks passed.' |
    Add-PSIEmailRow -Columns 4 |
    Add-PSIEmailKPI -Title 'Steps' -Value 3 -Subtitle 'Executed' -Status Informational |
    Add-PSIEmailKPI -Title 'Succeeded' -Value 3 -Subtitle 'Completed' -Status Healthy |
    Add-PSIEmailKPI -Title 'Warnings' -Value 0 -Subtitle 'None observed' -Status Neutral |
    Add-PSIEmailKPI -Title 'Failed' -Value 0 -Subtitle 'No failures' -Status Healthy |
    Add-PSIEmailRow -Columns 2 |
    Add-PSIEmailKeyValue -Title 'Execution Metadata' -Data ([ordered]@{
        'Run type' = 'Scheduled sample'
        'Target' = 'example.invalid'
        'Change window' = 'Fictional maintenance window'
    }) |
    Add-PSIEmailKeyValue -Title 'Outcome' -Data ([ordered]@{
        'Result' = 'Completed'
        'Validation' = 'Passed'
        'Rollback required' = 'No'
    }) |
    Add-PSIEmailRow |
    Add-PSIEmailTable -Title 'Step Results' -Data $Results -Columns @('Step', 'Result', 'Duration') -MaxRows 10 |
    Out-Null

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path (Join-Path $PSScriptRoot 'Preview') 'PSInsightEmail-Operational.html'
}
Export-PSIEmailPreview -Email $Email -Path $OutputPath -Open:$Open
