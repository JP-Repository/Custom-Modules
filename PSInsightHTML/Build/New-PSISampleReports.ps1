<#
.SYNOPSIS
    Regenerates every sample report into Reports/<Label>/ and summarises the run.

.DESCRIPTION
    Runs each example and provider sample with -NoBrowser, records duration, output
    size and any error, and writes index.html plus run.json to the output folder so
    successive labelled runs (Baseline, Phase1, ...) can be compared side by side.
    Only fictional sample data is used; no live environment is queried.

.EXAMPLE
    ./Build/New-PSISampleReports.ps1 -Label Baseline
#>
[CmdletBinding()]
param(
    [Parameter()][ValidatePattern('^[A-Za-z0-9._-]+$')][string] $Label = (Get-Date -Format 'yyyyMMdd-HHmm'),
    [Parameter()][ValidateSet('Light', 'Dark', 'Auto')][string] $Theme = 'Auto',
    [Parameter()][string[]] $Only = @(),
    [Parameter()][ValidateSet('Classic', 'Fluent', 'Auto')][string] $Renderer = 'Fluent'
)

$ErrorActionPreference = 'Stop'
# Export-PSIReport honours this when -Renderer is not passed, so providers need no changes.
$env:PSINSIGHTHTML_RENDERER = $Renderer
$Root = Split-Path -Path $PSScriptRoot -Parent
$OutDir = Join-Path -Path $Root -ChildPath ('Reports/' + $Label)
[void] (New-Item -ItemType Directory -Path $OutDir -Force)
Import-Module (Join-Path $Root 'PSInsightHTML.psd1') -Force

$Ex = Join-Path $Root 'Examples'
$Workbook = Join-Path $Ex 'Data/Active_Directory_Enterprise_User_Inventory_5000.xlsx'
$Jobs = [ordered]@{
    'Framework-Demo'        = { param($o) & "$Ex/New-DemoReport.ps1" -OutputPath $o -NoBrowser }
    'Adaptive-Demo'         = { param($o) & "$Ex/New-AdaptiveDemoReport.ps1" -OutputPath $o -Theme $Theme -NoBrowser }
    'Composed-AD-Portfolio' = { param($o) & "$Ex/New-ComposedADAssessmentDemo.ps1" -OutputPath $o -Theme $Theme -NoBrowser }
    'Fluent-Explorer'       = { param($o) & "$Ex/FluentExplorer/Invoke-FluentExplorerBenchmark.ps1" -OutputPath $o -Theme $Theme }
    'Fluent-Icons'          = { param($o) & "$Ex/New-FluentIconShowcase.ps1" -OutputPath $o }
    'AD-Groups'             = { param($o) New-PSIADGroupAssessment -UseSampleData -Path $o -Theme $Theme -NoBrowser }
    'AD-Users'              = { param($o) if (Test-Path -LiteralPath $Workbook) { New-PSIADUserInventory -WorkbookPath $Workbook -Path $o -Theme $Theme -NoBrowser } else { throw "Sample workbook not found: $Workbook" } }
    'AD-GroupPolicy'        = { param($o) New-PSIADGroupPolicyAssessment -UseSampleData -Path $o -Theme $Theme -NoBrowser }
    'AD-Replication'        = { param($o) New-PSIADReplicationAssessment -UseSampleData -Path $o -Theme $Theme -NoBrowser }
    'AD-DNS'                = { param($o) New-PSIADDNSAssessment -UseSampleData -Path $o -Theme $Theme -NoBrowser }
    'AD-SitesSubnets'       = { param($o) New-PSIADSitesSubnetsAssessment -UseSampleData -Path $o -Theme $Theme -NoBrowser }
    'AD-DCReadiness-2022'   = { param($o) & "$Ex/ActiveDirectory/DCReadiness/Invoke-PSIADDCReadiness.ps1" -TargetOS 2022 -UseSampleData -OutputPath $o -Theme $Theme -NoBrowser }
    'AD-DCReadiness-2025'   = { param($o) & "$Ex/ActiveDirectory/DCReadiness/Invoke-PSIADDCReadiness.ps1" -TargetOS 2025 -UseSampleData -OutputPath $o -Theme $Theme -NoBrowser }
    'AD-DCInventory'        = { param($o) & "$Ex/ActiveDirectory/DCInventory/Invoke-PSIADDCInventory.ps1" -UseSampleData -OutputPath $o -Theme $Theme -NoBrowser }
    'AD-DomainOverview'     = { param($o) & "$Ex/ActiveDirectory/DomainOverview/Invoke-PSIADDomainOverview.ps1" -UseSampleData -OutputPath $o -Theme $Theme -NoBrowser }
    'AD-Health'             = { param($o) & "$Ex/ActiveDirectory/Health/Invoke-PSIADHealth.ps1" -UseSampleData -OutputPath $o -Theme $Theme -NoBrowser }
    'AD-HealthEvidence'     = { param($o) & "$Ex/ActiveDirectory/HealthEvidence/Invoke-PSIADHealthEvidence.ps1" -UseSampleData -OutputPath $o -Theme $Theme -NoBrowser }
    'AD-Security'           = { param($o) & "$Ex/ActiveDirectory/Security/Invoke-PSIADSecurity.ps1" -UseSampleData -OutputPath $o -Theme $Theme -NoBrowser }
    'AD-Compliance'         = { param($o) & "$Ex/ActiveDirectory/Compliance/Invoke-PSIADCompliance.ps1" -UseSampleData -OutputPath $o -Theme $Theme -NoBrowser }
}

# The newer AD example scripts treat -OutputPath as a folder and write the HTML
# plus JSON/CSV artefacts into it; everything else takes a file path.
$FolderJobs = @('AD-DCReadiness-2022', 'AD-DCReadiness-2025', 'AD-DCInventory', 'AD-DomainOverview', 'AD-Health', 'AD-HealthEvidence', 'AD-Security', 'AD-Compliance')

$Results = foreach ($Name in $Jobs.Keys) {
    if ($Only.Count -and $Name -notin $Only) { continue }
    $File = Join-Path $OutDir "$Name.html"
    $Artefacts = Join-Path $OutDir "$Name.files"
    foreach ($Old in @($File, $Artefacts)) { if (Test-Path -LiteralPath $Old) { Remove-Item -LiteralPath $Old -Recurse -Force } }
    $Target = if ($Name -in $FolderJobs) { $Artefacts } else { $File }
    $Watch = [System.Diagnostics.Stopwatch]::StartNew()
    $ErrorText = $null
    try { $null = & $Jobs[$Name] $Target 6>$null }
    catch { $ErrorText = $_.Exception.Message }
    $Watch.Stop()
    if ($Name -in $FolderJobs -and (Test-Path -LiteralPath $Artefacts)) {
        $Html = Get-ChildItem -LiteralPath $Artefacts -Filter *.html -Recurse | Sort-Object Length -Descending | Select-Object -First 1
        if ($Html) { Copy-Item -LiteralPath $Html.FullName -Destination $File }
    }
    $Exists = Test-Path -LiteralPath $File
    $Row = [pscustomobject]@{
        Report  = $Name
        Status  = if ($ErrorText) { 'Failed' } elseif ($Exists) { 'OK' } else { 'NoOutput' }
        Seconds = [math]::Round($Watch.Elapsed.TotalSeconds, 1)
        SizeKB  = if ($Exists) { [math]::Round((Get-Item -LiteralPath $File).Length / 1KB) } else { $null }
        Error   = $ErrorText
    }
    Write-Host ('{0,-24} {1,-8} {2,6}s {3,8} KB {4}' -f $Row.Report, $Row.Status, $Row.Seconds, $Row.SizeKB, $Row.Error)
    $Row
}

# Partial runs (-Only) update their rows and keep the rest of the previous summary.
$RunFile = Join-Path $OutDir 'run.json'
$Results = @($Results)
if ($Only.Count -and (Test-Path -LiteralPath $RunFile)) {
    $Previous = @(Get-Content -LiteralPath $RunFile -Raw | ConvertFrom-Json)
    $Fresh = @{}; foreach ($R in $Results) { $Fresh[$R.Report] = $R }
    $Merged = foreach ($Name in $Jobs.Keys) {
        if ($Fresh.ContainsKey($Name)) { $Fresh[$Name] } else { $Previous | Where-Object Report -eq $Name | Select-Object -First 1 }
    }
    $Results = @($Merged | Where-Object { $_ })
}
ConvertTo-Json -InputObject $Results -Depth 3 | Set-Content -LiteralPath $RunFile -Encoding UTF8
$Rows = ($Results | ForEach-Object {
    $Link = if ($_.Status -eq 'OK') { '<a href="{0}.html">{0}</a>' -f $_.Report } else { $_.Report }
    '<tr><td>{0}</td><td class="{1}">{1}</td><td>{2}</td><td>{3}</td><td>{4}</td></tr>' -f $Link, $_.Status, $_.Seconds, $_.SizeKB, [System.Net.WebUtility]::HtmlEncode([string] $_.Error)
}) -join "`n"
@"
<!DOCTYPE html><html><head><meta charset="utf-8"><title>PSInsightHTML sample run - $Label</title>
<style>body{font:14px 'Segoe UI',sans-serif;margin:32px;color:#242424}table{border-collapse:collapse}td,th{padding:6px 14px;border-bottom:1px solid #e0e0e0;text-align:left}
.OK{color:#0e700e}.Failed,.NoOutput{color:#c50f1f;font-weight:600}</style></head><body>
<h2>PSInsightHTML sample reports - $Label</h2><p>Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm') | theme $Theme | fictional sample data only</p>
<table><tr><th>Report</th><th>Status</th><th>Seconds</th><th>KB</th><th>Error</th></tr>
$Rows
</table></body></html>
"@ | Set-Content -LiteralPath (Join-Path $OutDir 'index.html') -Encoding UTF8
$Results
