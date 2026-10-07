[CmdletBinding()]
param(
    [Parameter()][ValidateNotNullOrEmpty()][string] $OutputPath,
    [Parameter()][switch] $Open
)

$ErrorActionPreference = 'Stop'
$ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path $ModuleRoot 'PSInsightEmail.psd1') -Force

$PreviewRoot = Join-Path $PSScriptRoot 'Preview'
$ResourceRoot = Join-Path $PreviewRoot 'AttachmentDemo'
if (-not (Test-Path -LiteralPath $ResourceRoot -PathType Container)) {
    [void] (New-Item -Path $ResourceRoot -ItemType Directory -Force)
}

$Results = @(
    [pscustomobject]@{ System = 'server01.example.invalid'; Result = 'Healthy'; DurationSeconds = 18 }
    [pscustomobject]@{ System = 'server02.example.invalid'; Result = 'Warning'; DurationSeconds = 31 }
)
$CsvPath = Join-Path $ResourceRoot 'fictional-system-results.csv'
$Results | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8

$LogoPath = Join-Path $ResourceRoot 'example-automation-logo.png'
$TinyPng = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='
[System.IO.File]::WriteAllBytes($LogoPath, [Convert]::FromBase64String($TinyPng))

$LogoContentId = 'example-automation-logo@psinsightemail'
$Email = New-PSIEmail -Title 'Operational Results with Resources' `
    -Subtitle 'Fictional attachment and inline-resource example' `
    -Preheader 'Two fictional systems were checked; a CSV result file is registered.' `
    -Template Operational -BrandName 'Example Automation' `
    -EnvironmentLabel 'Example Lab' -EnvironmentStatus Warning `
    -SourceLabel 'Synthetic resource demo' -LogoContentId $LogoContentId `
    -FooterNote 'Registration prepares metadata for a transport adapter; this preview does not send email.'

$Email |
    Add-PSIEmailAttachment -Path $CsvPath -Name 'system-results.csv' |
    Add-PSIEmailInlineResource -Path $LogoPath -ContentId $LogoContentId -Name 'automation-logo.png' |
    Out-Null

$Email |
    Add-PSIEmailSection -Title 'Execution Summary' -Description 'Static fictional data with transport-neutral resources.' |
    Add-PSIEmailRow |
    Add-PSIEmailBanner -Status Warning -Title 'Review one sample result' `
        -Message 'The complete fictional result set is registered as a CSV attachment.' |
    Add-PSIEmailRow -Columns 3 |
    Add-PSIEmailKPI -Title 'Systems Checked' -Value 2 -Status Informational |
    Add-PSIEmailKPI -Title 'Healthy' -Value 1 -Status Healthy |
    Add-PSIEmailKPI -Title 'Warnings' -Value 1 -Status Warning |
    Add-PSIEmailRow |
    Add-PSIEmailTable -Title 'Result Preview' -Data $Results `
        -Columns @('System', 'Result', 'DurationSeconds') `
        -ColumnLabels @{ DurationSeconds = 'Duration (seconds)' } -MaxRows 10 |
    Out-Null

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $PreviewRoot 'PSInsightEmail-Attachment.html'
}

$Preview = Export-PSIEmailPreview -Email $Email -Path $OutputPath -Open:$Open
Write-Host "Generated attachment preview: $($Preview.FullName)"
Write-Host "Registered attachments: $($Email.Attachments.Count); inline resources: $($Email.InlineResources.Count)"
$Preview
