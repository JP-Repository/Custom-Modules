[CmdletBinding()]
param(
    [Parameter()][ValidateNotNullOrEmpty()][string] $OutputPath,
    [Parameter()][switch] $Open
)

$ErrorActionPreference = 'Stop'
$ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path -Path $ModuleRoot -ChildPath 'PSInsightEmail.psd1') -Force

$Systems = @(
    [pscustomobject]@{ Name = 'server01.example.invalid'; Role = 'Application'; Status = 'Healthy' }
    [pscustomobject]@{ Name = 'server02.example.invalid'; Role = 'Database'; Status = 'Warning' }
    [pscustomobject]@{ Name = 'server03.example.invalid'; Role = 'Worker'; Status = 'Healthy' }
)

$Email = New-PSIEmail -Title 'Infrastructure Check Summary' `
    -Subtitle 'Fictional operations snapshot' `
    -Preheader 'Three sample systems checked; one warning requires review.' `
    -Template Operational -BrandName 'Example Operations' `
    -EnvironmentLabel 'Example Production' -EnvironmentStatus Warning `
    -SourceLabel 'Fictional daily check' `
    -FooterNote 'Automated sample run. Review warning items through the normal operational process.'

$Email |
    Add-PSIEmailSection -Title 'Executive Summary' -Description 'Automated check results for the fictional sample environment.' |
    Add-PSIEmailRow |
    Add-PSIEmailBanner -Status Warning -Title 'Review requested' -Message 'One fictional system returned a warning result.' |
    Add-PSIEmailRow -Columns 3 |
    Add-PSIEmailKPI -Title 'Systems Checked' -Value 3 -Status Informational -Subtitle 'Sample inventory' |
    Add-PSIEmailKPI -Title 'Warnings' -Value 1 -Status Warning -Subtitle 'Review requested' |
    Add-PSIEmailKPI -Title 'Critical Findings' -Value 0 -Status Healthy -Subtitle 'No critical results' |
    Add-PSIEmailRow |
    Add-PSIEmailAlert -Status Informational -Title 'Sample data only' `
        -Message 'This preview contains fictional values and does not represent a live environment.' |
    Add-PSIEmailRow |
    Add-PSIEmailKeyValue -Title 'Assessment Scope' -Data ([ordered]@{
        'Environment'     = 'Example Lab'
        'Systems Checked' = 3
        'Assessment Type' = 'Fictional infrastructure check'
    }) |
    Add-PSIEmailRow |
    Add-PSIEmailTable -Title 'System Results' -Data $Systems `
        -Columns @('Name', 'Role', 'Status') -ColumnLabels @{ Name = 'System'; Role = 'Function' } -MaxRows 10 |
    Add-PSIEmailRow |
    Add-PSIEmailDivider |
    Add-PSIEmailRow |
    Add-PSIEmailText -Text 'Review warning items through the appropriate operational process.' -Size Small |
    Out-Null

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Preview') -ChildPath 'PSInsightEmail-Demo.html'
}

$Preview = Export-PSIEmailPreview -Email $Email -Path $OutputPath -Open:$Open
Write-Host "Generated email preview: $($Preview.FullName)"
$Preview
