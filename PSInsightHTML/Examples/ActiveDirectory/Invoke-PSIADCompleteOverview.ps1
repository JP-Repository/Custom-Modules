<#
.SYNOPSIS
    Generate a linked, domain-scoped AD report set from one DC snapshot plus scoped directory inventories.
.DESCRIPTION
    Read-only example entry point. Individual failures remain visible in index.html.
    No live collection occurs with UseSampleData or a supplied normalized Snapshot.
#>
[CmdletBinding()]
param(
    [switch] $UseSampleData,
    [string] $Domain,
    [pscustomobject] $Snapshot,
    [hashtable] $CommandAdapter,
    [ValidateSet('Core','Operational','Health','Security','Dependencies','Full')][string] $CollectionProfile = 'Full',
    [ValidateRange(1,50000)][int] $MaxObjects = 2000,
    [ValidateRange(5,300)][int] $EventQueryTimeoutSeconds = 30,
    [ValidateSet('Light','Dark','Auto')][string] $Theme = 'Auto',
    [string] $OutputPath,
    [ValidateSet('DomainOverview','DCInventory','DCReadiness2022','DCReadiness2025','HealthEvidence','Health','Security','Compliance','DNS','Replication','SitesSubnets','GroupPolicy','OUs','Groups','Users','Computers')]
    [string[]] $Only = @(),
    [switch] $NoBrowser,
    [switch] $PassThru
)
$ErrorActionPreference = 'Stop'
$ModuleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
# The public command already runs inside this module. Avoid a second forced import,
# which repeats bundle validation and can emit the same warning twice.
$LoadedModule = @(Get-Module -Name PSInsightHTML | Where-Object { $_.ModuleBase -eq $ModuleRoot })
if ($LoadedModule.Count -eq 0) {
    Import-Module (Join-Path $ModuleRoot 'PSInsightHTML.psd1') -Force -ErrorAction Stop -Verbose:$false
}
. (Join-Path $ModuleRoot 'Providers/ActiveDirectory/Shared/Import-PSIADProvider.ps1')
if ($UseSampleData -and ($null -ne $Snapshot -or -not [string]::IsNullOrWhiteSpace($Domain))) { throw 'UseSampleData cannot be combined with Snapshot or Domain.' }
if ($null -ne $Snapshot -and -not [string]::IsNullOrWhiteSpace($Domain) -and [string]$Snapshot.Domains[0].Name -ne $Domain) { throw 'Snapshot domain does not match the explicitly requested Domain.' }
if (-not $UseSampleData -and $null -eq $Snapshot -and [string]::IsNullOrWhiteSpace($Domain)) { throw 'Specify -UseSampleData, a normalized -Snapshot, or an explicit -Domain.' }
if ($null -eq $Snapshot) {
    Write-Progress -Id 30 -Activity 'AD Complete Overview' -Status ("Collecting {0} snapshot" -f $CollectionProfile)
    try {
        $Raw = Collect-PSIADSnapshot -UseSampleData:$UseSampleData -Domain $Domain -Profile $CollectionProfile -EventQueryTimeoutSeconds $EventQueryTimeoutSeconds -CommandAdapter $CommandAdapter -Verbose:([bool]$PSBoundParameters['Verbose'])
        $Snapshot = ConvertTo-PSIADDCReadinessModel -InputObject $Raw
    }
    finally { Write-Progress -Id 30 -Activity 'AD Complete Overview' -Completed }
}
if (@($Snapshot.Domains).Count -ne 1) { throw 'Complete Overview requires one normalized, domain-scoped snapshot.' }
$DomainName = [string] $Snapshot.Domains[0].Name
$Sample = $Snapshot.Source -eq 'Fictional sample'
if (-not $Sample -and [string]::IsNullOrWhiteSpace($Domain) -and $Only.Count -eq 0) {
    throw 'A supplied live Snapshot needs -Domain to collect Groups, GPOs, Users, Computers and OUs, or use -Only for snapshot-backed reports.'
}
if (-not $OutputPath) { $OutputPath = Join-Path $ModuleRoot 'Reports/ADCompleteOverview' }
if (-not $Sample) { $OutputPath = Join-Path $OutputPath (Get-Date -Format 'yyyyMMdd-HHmmss') }
$null = New-Item -Path $OutputPath -ItemType Directory -Force
$RootPath = (Resolve-Path -LiteralPath $OutputPath).Path
$All = @('DomainOverview','DCInventory','DCReadiness2022','DCReadiness2025','HealthEvidence','Health','Security','Compliance','DNS','Replication','SitesSubnets','GroupPolicy','OUs','Groups','Users','Computers')
$Selected = if ($Only.Count) { @($All | Where-Object { $_ -in $Only }) } else { $All }
$Results = [System.Collections.Generic.List[object]]::new()
$PreviousRenderer = $env:PSINSIGHTHTML_RENDERER
try {
    $env:PSINSIGHTHTML_RENDERER = 'Fluent'
    $JobIndex = 0
foreach ($Name in $Selected) {
    $JobIndex++
    Write-Progress -Id 30 -Activity 'AD Complete Overview' -Status ("Building {0} ({1}/{2})" -f $Name,$JobIndex,$Selected.Count) -PercentComplete ([int](100 * ($JobIndex - 1) / $Selected.Count))
    $Folder = Join-Path $RootPath $Name
    $ErrorText = ''
    $HtmlPath = ''
    try {
        switch ($Name) {
            'DomainOverview' { $Script = Join-Path $PSScriptRoot 'DomainOverview/Invoke-PSIADDomainOverview.ps1'; $Parameters = @{ Snapshot=$Snapshot; OutputPath=$Folder; Theme=$Theme; NoBrowser=$true; PassThru=$true } }
            'DCInventory' { $Script = Join-Path $PSScriptRoot 'DCInventory/Invoke-PSIADDCInventory.ps1'; $Parameters = @{ Snapshot=$Snapshot; OutputPath=$Folder; Theme=$Theme; NoBrowser=$true; PassThru=$true } }
            { $_ -in @('DCReadiness2022','DCReadiness2025') } { $Script = Join-Path $PSScriptRoot 'DCReadiness/Invoke-PSIADDCReadiness.ps1'; $Parameters = @{ NormalizedSnapshot=$Snapshot; TargetOS=$Name.Substring(11); OutputPath=$Folder; Theme=$Theme; NoBrowser=$true; PassThru=$true } }
            'HealthEvidence' { $Script = Join-Path $PSScriptRoot 'HealthEvidence/Invoke-PSIADHealthEvidence.ps1'; $Parameters = @{ Snapshot=$Snapshot; OutputPath=$Folder; Theme=$Theme; NoBrowser=$true; PassThru=$true } }
            'Health' { $Script = Join-Path $PSScriptRoot 'Health/Invoke-PSIADHealth.ps1'; $Parameters = @{ Snapshot=$Snapshot; OutputPath=$Folder; Theme=$Theme; NoBrowser=$true; PassThru=$true } }
            'Security' { $Script = Join-Path $PSScriptRoot 'Security/Invoke-PSIADSecurity.ps1'; $Parameters = @{ Snapshot=$Snapshot; OutputPath=$Folder; Theme=$Theme; NoBrowser=$true; PassThru=$true } }
            'Compliance' { $Script = Join-Path $PSScriptRoot 'Compliance/Invoke-PSIADCompliance.ps1'; $Parameters = @{ Snapshot=$Snapshot; OutputPath=$Folder; Theme=$Theme; NoBrowser=$true; PassThru=$true } }
            default {
                $Script = Join-Path $PSScriptRoot 'LiveInventory/Invoke-PSIADInventoryReport.ps1'
                $Parameters = @{ ReportType=$Name; OutputPath=$Folder; Theme=$Theme; NoBrowser=$true; PassThru=$true; MaxObjects=$MaxObjects }
                if ($Name -in @('DNS','Replication','SitesSubnets')) { $Parameters.Snapshot = $Snapshot }
                elseif ($Sample) { $Parameters.UseSampleData = $true }
                else {
                    if ([string]::IsNullOrWhiteSpace($Domain)) { throw "An explicit -Domain is required for $Name live inventory." }
                    $Parameters.Domain = $Domain
                    if ($null -ne $CommandAdapter) { $Parameters.CommandAdapter = $CommandAdapter }
                }
            }
        }
        Write-Verbose ("Rendering {0} ({1}/{2})" -f $Name,$JobIndex,$Selected.Count)
        $Parameters.Verbose = ([bool]$PSBoundParameters['Verbose']) -and ($Name -in @('GroupPolicy','OUs','Groups','Users','Computers'))
        $Run = & $Script @Parameters 6>$null
        if ($null -eq $Run -or [string]::IsNullOrWhiteSpace([string]$Run.HtmlPath) -or -not (Test-Path -LiteralPath $Run.HtmlPath -PathType Leaf)) { throw 'Report script did not produce an HTML file.' }
        $HtmlPath = [string] $Run.HtmlPath
    }
    catch { $ErrorText = $_.Exception.Message }
    $Status = if ($ErrorText) { 'Failed' } else { 'Generated' }
    $Results.Add([pscustomobject]@{ Name=$Name; Status=$Status; HtmlPath=$HtmlPath; Error=$ErrorText })
    Write-Host ("[{0}/{1}] {2}: {3}" -f $JobIndex,$Selected.Count,$Name,$Status)
}
}
finally {
    Write-Progress -Id 30 -Activity 'AD Complete Overview' -Completed
    $env:PSINSIGHTHTML_RENDERER = $PreviousRenderer
}
$Encode = { param($Value) [System.Net.WebUtility]::HtmlEncode([string]$Value) }
$Cards = @($Results | ForEach-Object {
    $Title = & $Encode $_.Name
    if ($_.Status -eq 'Generated') {
        $Relative = $_.HtmlPath.Substring($RootPath.Length).TrimStart([char[]]@('\','/')) -replace '\\','/'
        $Href = & $Encode $Relative
        "<a class='card' href='$Href'><span class='tag good'>Generated</span><strong>$Title</strong><span>Open report &rarr;</span></a>"
    }
    else {
        $Message = & $Encode $_.Error
        "<div class='card failed'><span class='tag bad'>Failed</span><strong>$Title</strong><span>$Message</span></div>"
    }
}) -join "`n"
$SafeDomain = & $Encode $DomainName
$SafeProfile = & $Encode $Snapshot.CollectionProfile
$SafeTheme = & $Encode $Theme
$Generated = (Get-Date).ToString('yyyy-MM-dd HH:mm')
$SampleText = if ($Sample) { 'Fictional sample. No directory or network query was made.' } else { 'Read-only, domain-scoped observations. Review collection coverage and failures before acting.' }
$SafeSampleText = & $Encode $SampleText
$IndexPath = Join-Path $RootPath 'index.html'
@"
<!DOCTYPE html><html lang='en' data-theme='$SafeTheme'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>AD Complete Overview | $SafeDomain</title><style>
:root{font:14px/1.5 'Segoe UI Variable Text','Segoe UI',system-ui,sans-serif;color-scheme:light;--canvas:#e9eef4;--surface:#f8fafc;--text:#1b2b3b;--muted:#40556d;--stroke:#cdd8e4;--brand:#0f6cbd;--good:#0e7a0d;--bad:#b10e1c}
:root[data-theme=Dark]{color-scheme:dark;--canvas:#1b1b1b;--surface:#262626;--text:#fff;--muted:#c7c7c7;--stroke:#3d3d3d;--brand:#479ef5;--good:#54b054;--bad:#ee8f95}
@media(prefers-color-scheme:dark){:root[data-theme=Auto]{color-scheme:dark;--canvas:#1b1b1b;--surface:#262626;--text:#fff;--muted:#c7c7c7;--stroke:#3d3d3d;--brand:#479ef5;--good:#54b054;--bad:#ee8f95}}
*{box-sizing:border-box}body{margin:0;background:var(--canvas);color:var(--text)}main{max-width:1180px;margin:auto;padding:32px 24px}header{margin-bottom:24px}small{color:var(--muted)}h1{font-size:28px;line-height:1.2;margin:8px 0}p{color:var(--muted)}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:12px}.card{background:var(--surface);border:1px solid var(--stroke);border-radius:8px;padding:18px;display:flex;flex-direction:column;gap:9px;min-height:132px;min-width:0;color:var(--text);text-decoration:none;overflow-wrap:anywhere}.card:hover,.card:focus-visible{border-color:var(--brand);outline:2px solid var(--brand);outline-offset:1px}.card.failed{border-color:var(--bad)}.card strong{font-size:16px}.card>span:last-child{color:var(--muted)}.tag{font-size:12px;font-weight:600}.good{color:var(--good)}.bad{color:var(--bad)}footer{margin-top:24px;color:var(--muted)}
</style></head><body><main><header><small>PSInsightHTML / Active Directory report set</small><h1>Complete Domain Overview</h1><p>$SafeDomain &middot; $SafeProfile collection &middot; $Generated</p><p>$SafeSampleText</p></header><section class='grid' aria-label='Generated reports'>$Cards</section><footer>Each report is standalone and works offline. Missing evidence does not mean healthy.</footer></main></body></html>
"@ | Set-Content -LiteralPath $IndexPath -Encoding UTF8
$Failed = @($Results | Where-Object Status -eq 'Failed')
if ($Failed.Count) { Write-Warning "$($Failed.Count) of $($Results.Count) reports failed. See index.html for details." }
if (-not $NoBrowser) {
    try {
        if ($env:OS -eq 'Windows_NT') { Start-Process $IndexPath }
        elseif (Get-Command open -ErrorAction SilentlyContinue) { & open $IndexPath }
    } catch { Write-Warning "Index generated, but browser opening failed: $($_.Exception.Message)" }
}
if ($PassThru) { [pscustomobject]@{ Domain=$DomainName; Snapshot=$Snapshot; Results=$Results.ToArray(); IndexPath=$IndexPath; FailedCount=$Failed.Count } }
else { $IndexPath }
