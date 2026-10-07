[CmdletBinding()]
param(
    [Parameter()][ValidateNotNullOrEmpty()][string] $OutputPath,
    [Parameter()][switch] $Open
)

$ErrorActionPreference = 'Stop'
$ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path $ModuleRoot 'PSInsightEmail.psd1') -Force

$Exceptions = @(
    [pscustomobject]@{ Item = 'sample.user001@example.invalid'; Observed = 14; Limit = 10; Variance = '+4' }
    [pscustomobject]@{ Item = 'sample.user002@example.invalid'; Observed = 12; Limit = 10; Variance = '+2' }
    [pscustomobject]@{ Item = 'sample.user003@example.invalid'; Observed = 11; Limit = 10; Variance = '+1' }
)

$Email = New-PSIEmail -Title 'Device Assignment Threshold Review' `
    -Subtitle 'Fictional exception summary' `
    -Preheader 'Three sample identities exceed the configured device threshold.' `
    -Template Threshold -BrandName 'Example Governance' `
    -EnvironmentLabel 'Example Tenant' -EnvironmentStatus Warning `
    -SourceLabel 'Synthetic assignment inventory' `
    -FooterNote 'Threshold note: investigate exceptions before making operational changes.'

$Email |
    Add-PSIEmailSection -Title 'Threshold Summary' -Description 'Static exceptions above the fictional limit of 10 devices.' |
    Add-PSIEmailRow |
    Add-PSIEmailBanner -Status Warning -Title 'Threshold exceptions detected' `
        -Message 'Three fictional identities exceed the configured device assignment limit.' |
    Add-PSIEmailRow -Columns 3 |
    Add-PSIEmailKPI -Title 'Items Evaluated' -Value 250 -Subtitle 'Synthetic inventory' -Status Informational |
    Add-PSIEmailKPI -Title 'Over Limit' -Value 3 -Subtitle 'Review required' -Status Warning |
    Add-PSIEmailKPI -Title 'Highest Count' -Value 14 -Subtitle 'Limit: 10' -Status Critical |
    Add-PSIEmailRow |
    Add-PSIEmailTable -Title 'Items Over Limit' -Data $Exceptions `
        -Columns @('Item', 'Observed', 'Limit', 'Variance') -MaxRows 20 |
    Add-PSIEmailRow |
    Add-PSIEmailText -Text 'This compact exception list is intended for triage and follow-up.' -Size Small |
    Out-Null

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path (Join-Path $PSScriptRoot 'Preview') 'PSInsightEmail-Threshold.html'
}
Export-PSIEmailPreview -Email $Email -Path $OutputPath -Open:$Open
