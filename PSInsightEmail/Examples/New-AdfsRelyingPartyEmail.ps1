<#
.SYNOPSIS
    Generate a fictional AD FS relying party trust email preview.
.DESCRIPTION
    Demonstrates PSInsightEmail composition only. Does not query AD FS or send email.
#>
[CmdletBinding()]
param(
    [Parameter()][ValidateNotNullOrEmpty()][string] $OutputPath,
    [Parameter()][switch] $Open
)

$ErrorActionPreference = 'Stop'
$ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path $ModuleRoot 'PSInsightEmail.psd1') -Force -ErrorAction Stop

$Trusts = @(
    [pscustomobject]@{ Name = 'Expense Portal'; Protocol = 'SAML'; Enabled = 'Yes'; MetadataUpdates = 'Enabled'; Review = 'Routine' }
    [pscustomobject]@{ Name = 'Partner Gateway'; Protocol = 'WS-Federation'; Enabled = 'Yes'; MetadataUpdates = 'Disabled'; Review = 'Owner review' }
    [pscustomobject]@{ Name = 'HR Archive'; Protocol = 'SAML'; Enabled = 'No'; MetadataUpdates = 'Not applicable'; Review = 'Confirm purpose' }
)

$SelectedTrust = @(
    [pscustomobject]@{ Setting = 'Identifier'; Value = 'urn:example:partner-gateway' }
    [pscustomobject]@{ Setting = 'WS-Federation endpoint'; Value = 'https://partner.example.invalid/signin' }
    [pscustomobject]@{ Setting = 'Metadata URL'; Value = 'https://partner.example.invalid/federationmetadata/2007-06/federationmetadata.xml' }
    [pscustomobject]@{ Setting = 'Issuance transform rules'; Value = 'Present; behavior not evaluated in this sample' }
)

$Email = New-PSIEmail -Title 'AD FS Relying Party Trust Review' `
    -Subtitle 'Fictional federation configuration digest' `
    -Preheader 'Three sample trusts; one metadata setting requires owner review.' `
    -Template Operational -BrandName 'Example Identity Operations' `
    -EnvironmentLabel 'Example Federation' -EnvironmentStatus Warning `
    -SourceLabel 'Fictional trust inventory' `
    -FooterNote 'Sample only. Configuration observations do not establish sign-in, claims, or certificate health.'

$Email |
    Add-PSIEmailSection -Title 'Federation Summary' `
        -Description 'A compact review of fictional relying party trust configuration.' |
    Add-PSIEmailRow |
    Add-PSIEmailBanner -Status Warning -Title 'Owner review requested' `
        -Message 'Metadata auto-update is disabled for Partner Gateway. Confirm whether this setting is intentional.' |
    Add-PSIEmailRow -Columns 3 |
    Add-PSIEmailKPI -Title 'Trusts in scope' -Value 3 -Subtitle 'Sample inventory' -Status Informational |
    Add-PSIEmailKPI -Title 'Enabled trusts' -Value 2 -Subtitle 'Configuration state' -Status Informational |
    Add-PSIEmailKPI -Title 'Owner reviews' -Value 1 -Subtitle 'Metadata setting' -Status Warning |
    Add-PSIEmailRow |
    Add-PSIEmailText -Text 'Enabled and disabled are configuration states, not health conclusions. The owner review is illustrative and does not prescribe a change.' -Size Small |
    Add-PSIEmailSection -Title 'Relying Party Inventory' `
        -Description 'Selected fields suitable for a concise operational email.' |
    Add-PSIEmailRow |
    Add-PSIEmailTable -Title 'Sample trusts' -Data $Trusts `
        -Columns @('Name', 'Protocol', 'Enabled', 'MetadataUpdates', 'Review') `
        -ColumnLabels @{ MetadataUpdates = 'Metadata updates'; Review = 'Review state' } -MaxRows 10 |
    Add-PSIEmailSection -Title 'Selected Trust Detail' `
        -Description 'Partner Gateway is shown to demonstrate how a trust can be summarized without exposing raw rules.' |
    Add-PSIEmailRow |
    Add-PSIEmailTable -Title 'Partner Gateway configuration' -Data $SelectedTrust `
        -Columns @('Setting', 'Value') -MaxRows 10 |
    Add-PSIEmailRow |
    Add-PSIEmailAlert -Status Warning -Title 'Confirm metadata management' `
        -Message 'Ask the application owner how federation metadata and configuration changes are reviewed. Do not change the trust based on this sample email.' |
    Out-Null

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path (Join-Path $PSScriptRoot 'Preview') 'PSInsightEmail-AdfsRelyingParty.html'
}
$Preview = Export-PSIEmailPreview -Email $Email -Path $OutputPath -Open:$Open
Write-Host "Generated fictional AD FS email preview: $($Preview.FullName)"
$Preview
