<#
.SYNOPSIS
    Generate a domain-scoped overview from one read-only AD snapshot.
.DESCRIPTION
    Collects once, then reuses the normalized snapshot for DC inventory and both
    Windows Server readiness targets. Supply -UseSampleData for a fictional demo,
    -Snapshot for a previously normalized snapshot, or -Domain for live collection.
    Live collection is read-only; the report writes HTML only to OutputPath.
#>
[CmdletBinding()]
param(
    [switch] $UseSampleData,
    [string] $Domain,
    [pscustomobject] $Snapshot,
    [hashtable] $CommandAdapter,
    [ValidateSet('Core','Operational','Health','Security','Dependencies','Full')]
    [string] $CollectionProfile = 'Core',
    [ValidateSet('2022','2025')][string] $TargetOS = '2025',
    [string] $OutputPath,
    [ValidateSet('Light','Dark','Auto')][string] $Theme = 'Auto',
    [switch] $NoBrowser,
    [switch] $PassThru
)
$ErrorActionPreference = 'Stop'
$ModuleRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
Import-Module (Join-Path $ModuleRoot 'PSInsightHTML.psd1') -Force -ErrorAction Stop
. (Join-Path $ModuleRoot 'Providers/ActiveDirectory/Shared/Import-PSIADProvider.ps1')

if ($UseSampleData -and ($null -ne $Snapshot -or -not [string]::IsNullOrWhiteSpace($Domain))) {
    throw 'UseSampleData cannot be combined with Snapshot or Domain.'
}
if ($null -ne $Snapshot -and -not [string]::IsNullOrWhiteSpace($Domain)) {
    throw 'Snapshot and Domain are mutually exclusive.'
}
if (-not $UseSampleData -and $null -eq $Snapshot -and [string]::IsNullOrWhiteSpace($Domain)) {
    throw 'Specify -UseSampleData, a normalized -Snapshot, or an explicit -Domain for read-only live collection.'
}

if ($null -eq $Snapshot) {
    $Raw = Collect-PSIADSnapshot -UseSampleData:$UseSampleData -Domain $Domain -Profile $CollectionProfile -CommandAdapter $CommandAdapter
    $Snapshot = ConvertTo-PSIADDCReadinessModel -InputObject $Raw
}
$Inventory = New-PSIADDCInventoryModel -Snapshot $Snapshot
$Presentation = New-PSIADDCInventoryPresentation -Snapshot $Snapshot -Inventory $Inventory
$Readiness2022 = Test-PSIADDCReadiness -Inventory $Snapshot -TargetOS 2022
$Readiness2025 = Test-PSIADDCReadiness -Inventory $Snapshot -TargetOS 2025
$Selected = if ($TargetOS -eq '2022') { $Readiness2022 } else { $Readiness2025 }
$Sample = $Snapshot.Source -eq 'Fictional sample'
$SourceLabel = if ($Sample) { 'Fictional sample - no directory query' } else { 'Read-only domain-scoped observations' }
$Report = New-PSIReport -Title $(if ($Sample) { 'AD Domain Overview | Fictional Sample' } else { "AD Domain Overview | $($Inventory.Summary.Domain)" }) -Subtitle $SourceLabel -Theme $Theme -Layout Application
$null = $Report | Set-PSIApplicationModel -Model $Presentation.Model
$Report | Add-Member -NotePropertyName PrintDisplay -NotePropertyValue @{
    ReportIdentity = @{ Kicker = 'PSInsightHTML / domain overview' }
    Scope = $Inventory.Summary.Domain
    Profile = [string] $Snapshot.CollectionProfile
    CoveragePercent = $Inventory.CollectionCoverage.OverallPercent
    Tables = @('domain-context','domain-controllers','domain-sites','domain-subnets','domain-roles','domain-replication','domain-dc-placement','domain-gpo-intent','domain-readiness','domain-checks','domain-coverage')
}

$Controllers = @($Inventory.DomainControllers | ForEach-Object {
    [pscustomobject]@{ Name=$_.Name; Domain=$_.Domain; Site=$_.Site; IPv4=$_.IPv4; OS=$_.OS; GlobalCatalog=$_.GlobalCatalog; RODC=$_.RODC; FSMORoles=($_.FSMORoles -join ', '); CollectionState=$_.CollectionState }
})
$Sites = @($Inventory.Sites | ForEach-Object {
    [pscustomobject]@{ Site=$_.Name; Controllers=@($_.DomainControllers).Count; Subnets=@($_.Subnets).Count }
})
$OS = @($Inventory.DomainControllers | Group-Object OS | Sort-Object Name | ForEach-Object {
    [pscustomobject]@{ OS=if ([string]::IsNullOrWhiteSpace($_.Name)) { 'Not observed' } else { $_.Name }; Count=$_.Count }
})
$Readiness = @($Readiness2022, $Readiness2025 | ForEach-Object {
    [pscustomobject]@{ TargetOS=$_.TargetOS; Decision=$_.Assessment.Decision; Score=$_.Assessment.Score; Blockers=$_.Assessment.ScoreExplanation.Counts.Blockers; Review=$_.Assessment.ScoreExplanation.Counts.Review; NotTested=$_.Assessment.ScoreExplanation.Counts.NotTested }
})
$Checks = @($Selected.Assessment.Checks | ForEach-Object {
    [pscustomobject]@{ Id=$_.Id; Check=$_.Name; Category=$_.CategoryId; Status=$_.Status; Observed=$_.ObservedState; Expected=$_.ExpectedState }
})
$DCPlacement = @($Snapshot.DomainControllers | ForEach-Object {
    [pscustomobject]@{ DC=$_.Name; ComputerObjectDN=$_.ComputerObjectDN; Site=$_.Site; CollectionState=if ($Sample) { 'FictionalSample' } elseif ($_.ComputerObjectDN) { 'Collected' } else { 'NotTested' } }
})
$GpoIntent = @($Snapshot.GpoIntent | ForEach-Object {
    [pscustomobject]@{ Container=$_.Container; GpLink=$_.GpLink; GpOptions=$_.GpOptions; CollectionState=$_.CollectionState; SourceType=$_.SourceType; EffectivePolicyEstablished=$_.EffectivePolicyEstablished }
})
$Coverage = @($Inventory.CollectionCoverage.Collectors | ForEach-Object {
    [pscustomobject]@{ Collector=$_.Collector; CollectionState=$_.Status; Expected=$_.Expected; Collected=$_.Collected; CoveragePercent=$_.CoveragePercent; Failures=$_.Failures; NotTested=$_.NotTested }
})

$null = $Report |
    Add-PSIView -Id overview -Title 'Overview' -Subtitle 'Scope and collection context' -Icon NavigationHome -Initial |
    Add-PSISection -Title 'Domain at a glance' |
    Add-PSIRow |
    Add-PSIStatus -Status Informational -Label $SourceLabel -Message 'Inventory counts are observations; readiness decisions are target-specific and shown separately.' |
    Add-PSIRow |
    Add-PSIKPI -Title 'Domain controllers' -Value $Inventory.Summary.DCCount -Subtitle $Inventory.Summary.Domain -Status Informational -Icon ResourceServer -Filter @{ Table='domain-controllers'; Property='Domain'; Value=$Inventory.Summary.Domain } |
    Add-PSIKPI -Title 'Sites' -Value $Inventory.Summary.SiteCount -Subtitle 'Observed DC sites' -Status Informational -Icon Relationship |
    Add-PSIKPI -Title 'Subnets' -Value $Inventory.Summary.SubnetCount -Subtitle 'Mapped to observed sites' -Status Informational -Icon Relationship |
    Add-PSIKPI -Title 'Global Catalogs' -Value $Inventory.Summary.GCCount -Subtitle 'Observed DC flags' -Status Informational -Icon ResourceServer |
    Add-PSIRow |
    Add-PSITable -Id domain-context -Title 'Domain and forest context' -Data @($Inventory.Summary) -Columns @('Domain','Forest','DomainFunctionalLevel','ForestFunctionalLevel','Profile','CollectedAt') |
    Add-PSIRow |
    Add-PSIChart -Title 'Observed DC operating systems' -ChartType Bar -Data $OS -CategoryProperty OS -ValueProperty Count -FilterMetadata @{ Table='domain-controllers'; Property='OS' }

$null = $Report |
    Add-PSIView -Id controllers -Title 'Controllers' -Subtitle 'Domain-scoped DC inventory' -Icon ResourceServer -Badge $Inventory.Summary.DCCount |
    Add-PSISection -Title 'Controller register' |
    Add-PSIRow |
    Add-PSITable -Id domain-controllers -Title 'Domain controllers' -Data $Controllers -Columns @('Name','Domain','Site','IPv4','OS','GlobalCatalog','RODC','FSMORoles','CollectionState') -PageSize 10

$null = $Report |
    Add-PSIView -Id topology -Title 'Topology' -Subtitle 'Observed sites, roles and replication' -Icon Relationship |
    Add-PSISection -Title 'Directory topology' |
    Add-PSIRow |
    Add-PSITable -Id domain-sites -Title 'Sites with observed DCs' -Data $Sites -Columns @('Site','Controllers','Subnets') |
    Add-PSIRow |
    Add-PSITable -Id domain-subnets -Title 'Mapped subnets' -Data @($Inventory.Subnets) -Columns @('Name','Site') |
    Add-PSIRow |
    Add-PSITable -Id domain-roles -Title 'FSMO role holders' -Data @($Inventory.FSMORoles) -Columns @('Role','Scope','Holder') |
    Add-PSIRow |
    Add-PSITable -Id domain-replication -Title 'Observed replication relationships' -Data @($Inventory.Replication) -Columns @('Source','Destination','NamingContext','LastSuccess','CurrentFailures','EvidenceOnly') -EmptyMessage 'No replication relationships were returned by the requested collection.'

$null = $Report |
    Add-PSIView -Id policy -Title 'Policy & OU' -Subtitle 'DC object placement and GPO link intent' -Icon Document |
    Add-PSISection -Title 'Directory placement and policy links' |
    Add-PSIRow |
    Add-PSIText -Text 'Computer object distinguished names and gPLink values are directory observations. They do not establish GPO application, security filtering, WMI filtering, precedence or effective policy. Empty results can mean collection was not requested.' -Size Small |
    Add-PSIRow |
    Add-PSITable -Id domain-dc-placement -Title 'DC computer object placement' -Data $DCPlacement -Columns @('DC','ComputerObjectDN','Site','CollectionState') |
    Add-PSIRow |
    Add-PSITable -Id domain-gpo-intent -Title 'DC container GPO link intent' -Data $GpoIntent -Columns @('Container','GpLink','GpOptions','CollectionState','SourceType','EffectivePolicyEstablished') -EmptyMessage 'No DC container GPO link observations were supplied by this collection profile.'

$null = $Report |
    Add-PSIView -Id readiness -Title 'DC Readiness' -Subtitle 'Target-specific planning, not overall domain health' -Icon Rules |
    Add-PSISection -Title 'Windows Server target comparison' |
    Add-PSIRow |
    Add-PSIText -Text 'Readiness scores depend on the selected target rule pack and evidence coverage. Not Tested does not mean Healthy. No directory changes are performed.' -Size Small |
    Add-PSIRow |
    Add-PSITable -Id domain-readiness -Title 'Same snapshot, two target assessments' -Data $Readiness -Columns @('TargetOS','Decision','Score','Blockers','Review','NotTested') -PageSize 2 |
    Add-PSIRow |
    Add-PSITable -Id domain-checks -Title "Windows Server $TargetOS checks" -Data $Checks -Columns @('Id','Check','Category','Status','Observed','Expected') -PageSize 10

$null = $Report |
    Add-PSIView -Id coverage -Title 'Collection Coverage' -Subtitle 'Completeness and collector outcomes' -Icon Document |
    Add-PSISection -Title 'Evidence provenance' |
    Add-PSIRow |
    Add-PSIKPI -Title 'Requested evidence collected' -Value "$($Inventory.CollectionCoverage.OverallPercent)%" -Subtitle 'Completeness only; not a health score' -Status Informational -Icon Document -Span 4 |
    Add-PSIRow |
    Add-PSITable -Id domain-coverage -Title 'Collector coverage' -Data $Coverage -Columns @('Collector','CollectionState','Expected','Collected','CoveragePercent','Failures','NotTested') |
    Add-PSIRow |
    Add-PSIText -Text 'NotRequested is excluded from coverage. Failed, NotSupported and NotTested observations are shown explicitly and must not be read as healthy results.' -Size Small

if (-not $OutputPath) { $OutputPath = Join-Path $ModuleRoot 'Reports/DomainOverview' }
if (-not $Sample) { $OutputPath = Join-Path $OutputPath (Get-Date -Format 'yyyyMMdd-HHmmss') }
$null = New-Item -Path $OutputPath -ItemType Directory -Force
$HtmlPath = Join-Path $OutputPath 'ADDomainOverview.html'
$null = Export-PSIReport -Report $Report -Path $HtmlPath -Renderer Fluent
if (-not $NoBrowser) {
    try {
        if ($env:OS -eq 'Windows_NT') { Start-Process $HtmlPath }
        elseif (Get-Command open -ErrorAction SilentlyContinue) { & open $HtmlPath }
    }
    catch { Write-Warning "Report generated, but browser opening failed: $($_.Exception.Message)" }
}
if ($PassThru) { [pscustomobject]@{ Snapshot=$Snapshot; Inventory=$Inventory; Readiness2022=$Readiness2022; Readiness2025=$Readiness2025; Report=$Report; HtmlPath=$HtmlPath } }
else { $HtmlPath }
