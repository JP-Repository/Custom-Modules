[CmdletBinding()]
param(
    [Parameter()][ValidateNotNullOrEmpty()][string] $OutputPath,
    [Parameter()][switch] $Open
)

$ErrorActionPreference = 'Stop'
$ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path $ModuleRoot 'PSInsightEmail.psd1') -Force

$ExpiringItems = @(
    [pscustomobject]@{ Identity = 'svc-build@example.invalid'; Type = 'Certificate'; ExpiresIn = '6 days'; Owner = 'Platform Team' }
    [pscustomobject]@{ Identity = 'svc-data@example.invalid'; Type = 'Credential'; ExpiresIn = '14 days'; Owner = 'Data Team' }
    [pscustomobject]@{ Identity = 'svc-web@example.invalid'; Type = 'Certificate'; ExpiresIn = '28 days'; Owner = 'Application Team' }
)

$Email = New-PSIEmail -Title 'Credential and Certificate Health' `
    -Subtitle 'Fictional 30-day expiry outlook' `
    -Preheader 'One sample item expires within seven days.' `
    -Template Health -BrandName 'Example Service Health' `
    -EnvironmentLabel 'Example Estate' -EnvironmentStatus Warning `
    -SourceLabel 'Fictional credential inventory' `
    -FooterNote 'Health note: dates are illustrative and do not represent live credentials.'

$Email |
    Add-PSIEmailSection -Title 'Expiry Health' -Description 'Items approaching their fictional renewal date.' |
    Add-PSIEmailRow |
    Add-PSIEmailBanner -Status Warning -Title 'Renewal attention required' `
        -Message 'One fictional certificate expires within the next seven days.' |
    Add-PSIEmailRow -Columns 4 |
    Add-PSIEmailKPI -Title 'Tracked Items' -Value 48 -Subtitle 'Inventory total' -Status Informational |
    Add-PSIEmailKPI -Title 'Within 30 Days' -Value 3 -Subtitle 'Plan renewal' -Status Warning |
    Add-PSIEmailKPI -Title 'Within 7 Days' -Value 1 -Subtitle 'Prioritize' -Status Critical |
    Add-PSIEmailKPI -Title 'Healthy' -Value 45 -Subtitle 'Beyond 30 days' -Status Healthy |
    Add-PSIEmailRow |
    Add-PSIEmailTable -Title 'Upcoming Expirations' -Data $ExpiringItems `
        -Columns @('Identity', 'Type', 'ExpiresIn', 'Owner') `
        -ColumnLabels @{ ExpiresIn = 'Expires in' } -MaxRows 20 |
    Out-Null

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path (Join-Path $PSScriptRoot 'Preview') 'PSInsightEmail-Health.html'
}
Export-PSIEmailPreview -Email $Email -Path $OutputPath -Open:$Open
