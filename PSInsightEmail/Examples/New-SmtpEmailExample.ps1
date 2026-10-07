[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path $ModuleRoot 'PSInsightEmail.psd1') -Force

$OutputRoot = Join-Path (Join-Path $PSScriptRoot 'Preview') 'SmtpExample'
if (-not (Test-Path -LiteralPath $OutputRoot -PathType Container)) {
    [void] (New-Item -Path $OutputRoot -ItemType Directory -Force)
}

$Results = @(
    [pscustomobject]@{ System = 'server01.example.invalid'; Result = 'Healthy' }
    [pscustomobject]@{ System = 'server02.example.invalid'; Result = 'Warning' }
)
$CsvPath = Join-Path $OutputRoot 'example-operational-results.csv'
$Results | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8

$LogoPath = Join-Path $OutputRoot 'example-smtp-logo.png'
$TinyPng = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='
[System.IO.File]::WriteAllBytes($LogoPath, [Convert]::FromBase64String($TinyPng))

$LogoContentId = 'example-smtp-logo@psinsightemail'
$Email = New-PSIEmail -Title 'Example Operational Report' `
    -Subtitle 'Fictional SMTP transport demonstration' `
    -Preheader 'This safe example validates an SMTP message without sending it.' `
    -Template Operational -BrandName 'Example Automation' `
    -EnvironmentLabel 'Example Lab' -EnvironmentStatus Warning `
    -SourceLabel 'Synthetic SMTP example' -LogoContentId $LogoContentId `
    -FooterNote 'This example always invokes SMTP with WhatIf and sends no email.'

$Email |
    Add-PSIEmailAttachment -Path $CsvPath -Name 'operational-results.csv' |
    Add-PSIEmailInlineResource -Path $LogoPath -ContentId $LogoContentId |
    Out-Null

$Email |
    Add-PSIEmailSection -Title 'Operational Summary' |
    Add-PSIEmailRow |
    Add-PSIEmailBanner -Status Warning -Title 'Review one fictional result' `
        -Message 'The complete sample result set is registered as a CSV attachment.' |
    Add-PSIEmailRow -Columns 2 |
    Add-PSIEmailKPI -Title 'Systems Checked' -Value 2 -Status Informational |
    Add-PSIEmailKPI -Title 'Warnings' -Value 1 -Status Warning |
    Add-PSIEmailRow |
    Add-PSIEmailTable -Title 'Result Preview' -Data $Results -Columns @('System', 'Result') |
    Out-Null

# Safe by design: WhatIf validates recipients and local resources, constructs
# the MIME message, and disposes it without connecting to the SMTP server.
Send-PSIEmailSmtp `
    -Email $Email `
    -SmtpServer 'smtp.example.invalid' `
    -From 'automation@example.invalid' `
    -To 'recipient@example.invalid' `
    -Subject 'Example Operational Report' `
    -WhatIf
