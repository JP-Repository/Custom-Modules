[CmdletBinding()]
param(
    [switch] $UseSampleData,
    [string] $Domain,
    [pscustomobject] $Snapshot,
    [hashtable] $CommandAdapter,
    [ValidateRange(1,168)][int] $EventWindowHours=72,
    [object[]] $BackupInput=@(),
    [string] $OutputPath,
    [ValidateSet('Light','Dark','Auto')][string] $Theme='Auto',
    [switch] $NoBrowser,
    [switch] $PassThru
)
$ErrorActionPreference='Stop'
$ModuleRoot=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
Import-Module (Join-Path $ModuleRoot 'PSInsightHTML.psd1') -Force
. (Join-Path $ModuleRoot 'Providers/ActiveDirectory/Shared/Import-PSIADProvider.ps1')
if ($null -eq $Snapshot) {
    $Raw=Collect-PSIADSnapshot -UseSampleData:$UseSampleData -Domain $Domain -Profile Health -EventWindowHours $EventWindowHours -BackupInput $BackupInput -CommandAdapter $CommandAdapter
    $Snapshot=ConvertTo-PSIADDCReadinessModel $Raw
}
$Evidence=New-PSIADHealthEvidenceModel -Snapshot $Snapshot
$Inventory=New-PSIADDCInventoryModel -Snapshot $Snapshot
$Presentation=New-PSIADDCInventoryPresentation -Snapshot $Snapshot -Inventory $Inventory
$Sample=$Snapshot.Source -eq 'Fictional sample'
$Report=New-PSIReport -Title 'AD Health Evidence Foundation' -Subtitle $(if ($Sample) { 'Fictional sample | Evidence only | No Health Verdict' } else { "Domain: $($Evidence.Domain) | Evidence only | No Health Verdict" }) -Theme $Theme -Layout Application
$null=$Report | Set-PSIApplicationModel -Model $Presentation.Model
$PrintDisplay=@{
    ReportIdentity=@{ Kicker='PSInsightHTML / Health evidence foundation' }
    Scope=$Evidence.Domain; Profile=[string]$Snapshot.CollectionProfile; CoveragePercent=$Evidence.CollectionCoverage.OverallPercent
    Tables=@('health-dcs','health-services','health-shares','health-replication','health-dns','health-time','health-features','health-events','health-event-queries','health-sites','health-subnets','health-unmapped','health-sitelinks','health-coverage','health-register')
    Resources=@{ Columns=@(@{Property='Name';Label='Resource'},@{Property='Type';Label='Type'},@{Property='Site';Label='Site'}) }
}
$Report | Add-Member -NotePropertyName PrintDisplay -NotePropertyValue $PrintDisplay
$Counts=@($Evidence.Observations | Group-Object CollectionState | Sort-Object Name | ForEach-Object { [pscustomobject]@{ CollectionState=$_.Name; Count=$_.Count } })
$DCData=@($Snapshot.DomainControllers | ForEach-Object { $DC=$_; [pscustomobject]@{ DC=$DC.Name; Domain=$DC.Domain; Site=$DC.Site; CPU=$DC.CPU; MemoryTotalGB=$DC.MemoryGB; MemoryAvailableGB=$DC.MemoryAvailableGB; MemoryUsedPercent=$DC.MemoryUsedPercent; Drive=$DC.SystemDrive; DiskTotalGB=$DC.DiskSizeGB; DiskFreeGB=$DC.DiskFreeGB; DiskFreePercent=$DC.DiskFreePercent; UptimeDays=$DC.UptimeDays } })
$ServiceData=@($Evidence.Observations | Where-Object Type -eq Service | ForEach-Object { [pscustomobject]@{ DC=$_.DC; Service=$_.Value.Name; DisplayName=$_.Value.DisplayName; ObservedState=$_.Value.ObservedState; StartMode=$_.Value.StartMode; CollectionState=$_.CollectionState; CollectionMethod=$_.CollectionMethod } })
$ShareData=@($Evidence.Observations | Where-Object Type -eq Share | ForEach-Object { [pscustomobject]@{ DC=$_.DC; Share=$_.Value.Name; Present=$_.Value.Present; CollectionState=$_.CollectionState } })
$ReplicationData=@($Evidence.Observations | Where-Object Type -eq Replication | ForEach-Object { [pscustomobject]@{ Source=$_.Value.Source; Destination=$_.Value.Destination; NamingContext=$_.Value.NamingContext; CurrentFailures=$_.Value.CurrentFailures; ConsecutiveFailures=$_.Value.ConsecutiveFailures; LastSuccess=$_.Value.LastSuccess; LastError=$_.Value.LastError; CollectionState=$_.CollectionState } })
$DNSData=@($Evidence.Observations | Where-Object Type -eq DNSForwarders | ForEach-Object { [pscustomobject]@{ DC=$_.DC; Forwarders=@($_.Value) -join ', '; CollectionState=$_.CollectionState; EmptyResult=$_.EmptyResult } })
$TimeData=@($Evidence.Observations | Where-Object Type -eq TimeSource | ForEach-Object { [pscustomobject]@{ DC=$_.DC; PDC=$_.Value.PDC; ObservedSource=$_.Value.ObservedSource; ConfiguredSource=$_.Value.ConfiguredSource; SourceReachable=$_.Value.SourceReachable; CollectionState=$_.CollectionState } })
$FeatureData=@($Evidence.Observations | Where-Object Type -eq WindowsFeatures | ForEach-Object { $Observation=$_; if (@($Observation.Value).Count) { foreach ($Feature in @($Observation.Value)) { [pscustomobject]@{ DC=$Observation.DC; Feature=$Feature.Name; Installed=$Feature.Installed; CollectionState=$Observation.CollectionState } } } else { [pscustomobject]@{ DC=$Observation.DC; Feature=''; Installed=$null; CollectionState=$Observation.CollectionState } } })
$EventData=@($Evidence.Observations | Where-Object Type -eq Event | ForEach-Object { [pscustomobject]@{ DC=$_.DC; Log=$_.Value.Log; Provider=$_.Value.Provider; EventId=$_.Value.EventId; Level=$_.Value.Level; Timestamp=$_.Timestamp; Category=$_.Value.EvidenceCategory; Summary=$_.Value.MessageSummary } })
$QueryData=@($Evidence.Observations | Where-Object Type -eq EventQuery | ForEach-Object { [pscustomobject]@{ DC=$_.DC; Log=if ($_.Value) { $_.Value.Log } else { '' }; WindowHours=$Evidence.EventWindowHours; CollectionState=$_.CollectionState; ErrorClass=$_.ErrorClass } })
$CoverageData=@($Evidence.CollectionCoverage.Collectors | ForEach-Object { [pscustomobject]@{ Collector=$_.Collector; CollectionState=$_.Status; Expected=$_.Expected; Collected=$_.Collected; CoveragePercent=$_.CoveragePercent; Reason=$_.Reason } })
$Register=@($Evidence.Observations | ForEach-Object { [pscustomobject]@{ Type=$_.Type; DC=$_.DC; Domain=$_.Domain; Collector=$_.Collector; Timestamp=$_.Timestamp; CollectionState=$_.CollectionState; CollectionMethod=$_.CollectionMethod; Confidence=$_.Confidence; ErrorClass=$_.ErrorClass; EmptyResult=$_.EmptyResult } })
$null=$Report |
    Add-PSIView -Id overview -Title 'Overview' -Subtitle 'Coverage and scope, without a health verdict' -Icon NavigationHome -Initial |
    Add-PSISection -Title 'Evidence foundation' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Text $(if ($Sample) { 'Fictional sample data. No live infrastructure was queried. This is evidence, not a Health assessment.' } else { 'Read-only collection evidence. No health score, findings or operational thresholds have been applied.' }) -Size Small |
    Add-PSIRow -Columns 12 |
    Add-PSIKPI -Title 'Domain controllers' -Value $Snapshot.DomainControllers.Count -Subtitle $Evidence.Domain -Status Informational -Icon ResourceServer -Span 3 |
    Add-PSIKPI -Title 'Evidence observations' -Value $Evidence.Observations.Count -Subtitle 'Attributable records' -Status Informational -Icon Document -Span 3 |
    Add-PSIKPI -Title 'Collected' -Value @($Evidence.Observations | Where-Object CollectionState -eq Collected).Count -Subtitle 'Query or fixture observations' -Status Informational -Icon Document -Span 3 |
    Add-PSIKPI -Title 'Unavailable or incomplete' -Value @($Evidence.Observations | Where-Object CollectionState -in @('Partial','Failed','NotSupported')).Count -Subtitle 'Review collection state, not health' -Status Informational -Icon Document -Span 3 |
    Add-PSIRow -Columns 12 |
    Add-PSIChart -Title 'Evidence collection states' -ChartType Bar -Data $Counts -CategoryProperty CollectionState -ValueProperty Count
$null=$Report |
    Add-PSIView -Id controllers -Title 'DC Evidence' -Subtitle 'System observations by controller' -Icon ResourceServer |
    Add-PSISection -Title 'CPU, memory, disk and uptime' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id health-dcs -Title 'Controller system evidence' -Data $DCData -Columns @('DC','Domain','Site','CPU','MemoryTotalGB','MemoryAvailableGB','MemoryUsedPercent','Drive','DiskTotalGB','DiskFreeGB','DiskFreePercent','UptimeDays') -PageSize 10 |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Text 'Blank measurements mean unavailable evidence. No CPU, memory, disk or uptime threshold has been applied.' -Size Small
$null=$Report |
    Add-PSIView -Id services -Title 'Services & Shares' -Subtitle 'Independent service and share observations' -Icon ResourceServer |
    Add-PSISection -Title 'Service and SYSVOL evidence' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id health-services -Title 'Observed services' -Data $ServiceData -Columns @('DC','Service','DisplayName','ObservedState','StartMode','CollectionState','CollectionMethod') -PageSize 12 |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id health-shares -Title 'SYSVOL and NETLOGON shares' -Data $ShareData -Columns @('DC','Share','Present','CollectionState')
$null=$Report |
    Add-PSIView -Id replication -Title 'Replication' -Subtitle 'Partner metadata and failure observations' -Icon Relationship |
    Add-PSISection -Title 'Inbound replication facts' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id health-replication -Title 'Replication metadata' -Data $ReplicationData -Columns @('Source','Destination','NamingContext','CurrentFailures','ConsecutiveFailures','LastSuccess','LastError','CollectionState')
$null=$Report |
    Add-PSIView -Id dns -Title 'DNS' -Subtitle 'Forwarders and collection states' -Icon Relationship |
    Add-PSISection -Title 'DNS observations' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id health-dns -Title 'Forwarder observations' -Data $DNSData -Columns @('DC','Forwarders','CollectionState','EmptyResult') |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Text 'NotSupported denotes unavailable DNS management tooling. Empty results are meaningful only when the query completed.' -Size Small
$null=$Report |
    Add-PSIView -Id time -Title 'Time' -Subtitle 'Observed and configured sources' -Icon Document |
    Add-PSISection -Title 'Time evidence' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id health-time -Title 'Time source observations' -Data $TimeData -Columns @('DC','PDC','ObservedSource','ConfiguredSource','SourceReachable','CollectionState')
$null=$Report |
    Add-PSIView -Id system -Title 'System' -Subtitle 'Windows feature inventory' -Icon ResourceServer |
    Add-PSISection -Title 'Installed feature evidence' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id health-features -Title 'Windows roles and features' -Data $FeatureData -Columns @('DC','Feature','Installed','CollectionState')
$null=$Report |
    Add-PSIView -Id events -Title 'Events' -Subtitle 'Bounded event summaries and query states' -Icon Document |
    Add-PSISection -Title 'Event evidence' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id health-events -Title 'Observed events' -Data $EventData -Columns @('DC','Log','Provider','EventId','Level','Timestamp','Category','Summary') -EmptyMessage 'No events were returned in the selected window.' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id health-event-queries -Title 'Event query states' -Data $QueryData -Columns @('DC','Log','WindowHours','CollectionState','ErrorClass')
$null=$Report |
    Add-PSIView -Id topology -Title 'Topology / Sites' -Subtitle 'Site and subnet mapping' -Icon Relationship |
    Add-PSISection -Title 'Topology evidence' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id health-sites -Title 'Sites' -Data @($Snapshot.Sites | ForEach-Object { [pscustomobject]@{ Name=$_.Name; DomainControllers=@($_.DomainControllers) -join ', ' } }) -Columns @('Name','DomainControllers') |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id health-subnets -Title 'Subnets' -Data @($Snapshot.Subnets) -Columns @('Name','Site') |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id health-unmapped -Title 'Unmapped subnet observations' -Data @($Snapshot.UnmappedSubnets) -Columns @('Name','Site','CollectionState') -EmptyMessage 'No unmapped subnet observations were returned.' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id health-sitelinks -Title 'Site links' -Data @($Snapshot.SiteLinks | ForEach-Object { [pscustomobject]@{ Name=$_.Name; Sites=@($_.Sites) -join ', '; Cost=$_.Cost; ReplicationIntervalMinutes=$_.ReplicationIntervalMinutes; CollectionState=$Snapshot.SiteLinkCollectionState } }) -Columns @('Name','Sites','Cost','ReplicationIntervalMinutes','CollectionState')
$null=$Report |
    Add-PSIView -Id coverage -Title 'Collection Coverage' -Subtitle 'Evidence availability, not health' -Icon Document -Group Investigation |
    Add-PSISection -Title 'Collection provenance' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id health-coverage -Title 'Collector coverage' -Data $CoverageData -Columns @('Collector','CollectionState','Expected','Collected','CoveragePercent','Reason') -EmptyMessage 'Fictional fixture values are supplied directly.'
$null=$Report |
    Add-PSIView -Id evidence -Title 'Evidence Register' -Subtitle 'Attributable observation contract' -Icon Document -Group Investigation |
    Add-PSISection -Title 'Evidence records' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id health-register -Title 'Observation provenance' -Data $Register -Columns @('Type','DC','Domain','Collector','Timestamp','CollectionState','CollectionMethod','Confidence','ErrorClass','EmptyResult') -PageSize 20
if (-not $OutputPath) { $OutputPath=Join-Path $ModuleRoot 'Reports/HealthEvidence' }
$null=New-Item -Path $OutputPath -ItemType Directory -Force
$HtmlPath=Join-Path $OutputPath $(if ($Sample) { 'HealthEvidence-Sample.html' } else { 'HealthEvidence-Mocked.html' })
$null=Export-PSIReport -Report $Report -Path $HtmlPath
if (-not $NoBrowser) {
    try {
        if ($env:OS -eq 'Windows_NT') { Start-Process $HtmlPath }
        elseif (Get-Command open -ErrorAction SilentlyContinue) { & open $HtmlPath }
    } catch { Write-Warning "Report generated, but browser opening failed: $($_.Exception.Message)" }
}
if ($PassThru) { [pscustomobject]@{ Snapshot=$Snapshot; Evidence=$Evidence; Report=$Report; HtmlPath=$HtmlPath } } else { $HtmlPath }
