[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path $ModuleRoot 'PSInsightEmail.psd1') -Force

$OutputRoot = Join-Path (Join-Path $PSScriptRoot 'Preview') 'GraphExample'
if (-not (Test-Path -LiteralPath $OutputRoot -PathType Container)) {
    [void] (New-Item -Path $OutputRoot -ItemType Directory -Force)
}

$Results = @(
    [pscustomobject]@{ System = 'server01.example.invalid'; Result = 'Healthy' }
    [pscustomobject]@{ System = 'server02.example.invalid'; Result = 'Warning' }
)
$CsvPath = Join-Path $OutputRoot 'example-graph-results.csv'
$Results | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8

$LogoPath = Join-Path $OutputRoot 'example-graph-logo.png'
$TinyPng = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='
[System.IO.File]::WriteAllBytes($LogoPath, [Convert]::FromBase64String($TinyPng))

$LogoContentId = 'example-graph-logo@psinsightemail'
$Email = New-PSIEmail -Title 'Example Graph Report' `
    -Subtitle 'Fictional Microsoft Graph transport demonstration' `
    -Preheader 'This safe example validates a Graph request without submitting it.' `
    -Template Operational -BrandName 'Example Automation' `
    -EnvironmentLabel 'Example Lab' -EnvironmentStatus Warning `
    -SourceLabel 'Synthetic Graph example' -LogoContentId $LogoContentId `
    -FooterNote 'This example always invokes Graph with WhatIf and sends no email.'

$Email |
    Add-PSIEmailAttachment -Path $CsvPath -Name 'graph-results.csv' |
    Add-PSIEmailInlineResource -Path $LogoPath -ContentId $LogoContentId |
    Out-Null

$Email |
    Add-PSIEmailSection -Title 'Operational Summary' |
    Add-PSIEmailRow |
    Add-PSIEmailBanner -Status Warning -Title 'Review one fictional result' `
        -Message 'The complete synthetic result set is registered as a CSV attachment.' |
    Add-PSIEmailRow -Columns 2 |
    Add-PSIEmailKPI -Title 'Systems Checked' -Value 2 -Status Informational |
    Add-PSIEmailKPI -Title 'Warnings' -Value 1 -Status Warning |
    Out-Null

# Placeholder only. PSInsightEmail does not acquire OAuth tokens, and WhatIf
# ensures this example constructs the request without contacting Microsoft Graph.
$AccessToken = '<ACCESS-TOKEN>'
Send-PSIEmailGraph `
    -Email $Email `
    -AccessToken $AccessToken `
    -To 'recipient@example.invalid' `
    -Subject 'Example Graph Report' `
    -WhatIf
