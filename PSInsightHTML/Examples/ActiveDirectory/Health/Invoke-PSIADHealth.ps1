[CmdletBinding()]
param(
    [switch] $UseSampleData,
    [string] $Domain,
    [pscustomobject] $Snapshot,
    [hashtable] $CommandAdapter,
    [ValidateRange(1,168)][int] $EventWindowHours=72,
    [object[]] $BackupInput=@(),
    [hashtable] $ThresholdOverrides=@{},
    [object[]] $Exceptions=@(),
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
$HealthEvidence=New-PSIADHealthEvidenceModel -Snapshot $Snapshot
$Sample=$Snapshot.Source -eq 'Fictional sample'
if ($Sample) { $null=Add-PSIADHealthFictionalObservations -Snapshot $Snapshot -Evidence $HealthEvidence }
$Health=Test-PSIADHealth -Snapshot $Snapshot -HealthEvidence $HealthEvidence -ThresholdOverrides $ThresholdOverrides -Exceptions $Exceptions
$Assessment=$Health.Assessment; $Model=$Health.Model; $Counts=$Assessment.ScoreExplanation.Counts
$Status=if ($Health.HealthVerdict -eq 'Review') { 'Warning' } elseif ($Health.HealthVerdict -eq 'Incomplete') { 'NotChecked' } else { $Health.HealthVerdict }
$Report=New-PSIReport -Title 'Active Directory Health' -Subtitle $(if ($Sample) { 'Fictional operational scenario | No live environment queried' } else { "Read-only observations | $($HealthEvidence.Domain)" }) -Theme $Theme -Layout Application
$null=$Report | Set-PSIApplicationModel -Model $Model | Set-PSIApplicationAssessment -Assessment $Assessment
$Report | Add-Member -NotePropertyName PrintDisplay -NotePropertyValue @{ ReportIdentity=@{ Kicker='PSInsightHTML / Active Directory Health' }; Scope=$HealthEvidence.Domain; Profile="Health rule pack $($Health.RulePack.Version)"; CoveragePercent=$HealthEvidence.CollectionCoverage.OverallPercent; Tables=@('health-controller-register','health-check-register','health-finding-register','health-coverage-register'); Resources=@{ Columns=@(@{Property='Name';Label='Resource'},@{Property='Type';Label='Type'},@{Property='Site';Label='Site'},@{Property='Status';Label='Health';Format='Status'}) } }
$Critical=@($Model.Findings | Where-Object { $_.Severity -eq 'Critical' -and $_.Status -eq 'Open' })
$Review=@($Model.Findings | Where-Object { $_.Severity -eq 'Warning' -and $_.Status -eq 'Open' })
$ControllerRows=@($Health.DCStates | ForEach-Object { $State=$_; $DC=@($Snapshot.DomainControllers | Where-Object Name -eq $State.DC)[0]; [pscustomobject]@{ DC=$State.DC; Site=$State.Site; Domain=$State.Domain; Status=$State.Status; Critical=$State.Critical; Review=$State.Review; NotTested=$State.NotTested; OS=$DC.OS; GC=$DC.GlobalCatalog; PDC=($DC.Name -eq $Snapshot.Domains[0].PDCEmulator); CPU=$DC.CPU; MemoryUsedPercent=$DC.MemoryUsedPercent; DiskFreeGB=$DC.DiskFreeGB; UptimeDays=$DC.UptimeDays; TimeSource=$DC.TimeSource } })
$CheckRows=@($Assessment.Checks | ForEach-Object { [pscustomobject]@{ Check=$_.Name; Category=$_.CategoryId; Status=$_.Status; Severity=$_.Severity; Observed=$_.ObservedState; Expected=$_.ExpectedState; Evidence=@($_.EvidenceIds) -join ', '; Rule=$_.Metadata.RuleId } })
$FindingRows=@($Model.Findings | ForEach-Object { [pscustomobject]@{ Finding=$_.Title; Category=$_.Category; Severity=$_.Severity; Status=$_.Status; Observed=$_.Summary; Expected=$_.ReadinessImpact; Action=$_.Recommendation.Action } })
$CoverageRows=@($HealthEvidence.CollectionCoverage.Collectors | ForEach-Object { [pscustomobject]@{ Collector=$_.Collector; State=$_.Status; Expected=$_.Expected; Collected=$_.Collected; CoveragePercent=$_.CoveragePercent; Reason=$_.Reason } })
$CategoryRows=@($Assessment.Categories | ForEach-Object { $C=$_; [pscustomobject]@{ Category=$C.Name; Status=$C.Status; Score=$C.Score; Healthy=@($Assessment.Checks | Where-Object { $_.CategoryId -eq $C.Id -and $_.Status -eq 'Ready' }).Count; Review=@($Assessment.Checks | Where-Object { $_.CategoryId -eq $C.Id -and $_.Status -eq 'Review' }).Count; Critical=@($Assessment.Checks | Where-Object { $_.CategoryId -eq $C.Id -and $_.Status -eq 'Blocked' }).Count; NotTested=@($Assessment.Checks | Where-Object { $_.CategoryId -eq $C.Id -and $_.Status -eq 'NotTested' }).Count } })
$StatusFilter=Add-PSIFilter -Property Status -Values @('Healthy','Warning','Critical','NotChecked') -Label 'Health status'
$SiteValues=@($ControllerRows | ForEach-Object Site | Where-Object { $_ } | Sort-Object -Unique)
$SiteFilter=if ($SiteValues.Count) { @(Add-PSIFilter -Property Site -Values $SiteValues -Label 'Site') } else { @() }
$CategoryDetailProperties=@('HealthDirectory','HealthReplication','HealthSysvol','HealthDns','HealthTime','HealthServices','HealthCapacity','HealthTopology','HealthEvents','HealthBackup','HealthConnectivity')
$SiteRows=@($Health.DCStates | Group-Object Site | ForEach-Object { $Group=@($_.Group); [pscustomobject]@{ Site=$_.Name; Controllers=$Group.Count; Healthy=@($Group | Where-Object Status -eq Healthy).Count; Review=@($Group | Where-Object Status -eq Warning).Count; Critical=@($Group | Where-Object Status -eq Critical).Count; NotTested=@($Group | Where-Object Status -eq NotChecked).Count } })
$null=$Report |
    Add-PSIView -Id overview -Title 'Overview' -Subtitle 'Operational verdict, score and evidence coverage' -Icon NavigationHome -Initial |
    Add-PSISection -Title 'Executive Health summary' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Text $(if ($Sample) { 'Fictional data for design and rule validation. Thresholds are provider defaults, not an organizational policy. No remediation is performed.' } else { 'Read-only Health interpretation of a single normalized snapshot. Confirm material findings with the source system before change planning.' }) -Size Small |
    Add-PSIRow -Columns 12 |
    Add-PSIKPI -Title 'Overall Health' -Value $Health.HealthVerdict -Subtitle 'Critical conditions override score' -Status $Status -Icon SeveritySuccess -Span 3 |
    Add-PSIKPI -Title 'Health score' -Value "$($Assessment.Score)%" -Subtitle 'Weighted evaluated checks' -Status Informational -VisualTone Informational -Icon Document -Span 3 |
    Add-PSIKPI -Title 'Evidence coverage' -Value "$($HealthEvidence.CollectionCoverage.OverallPercent)%" -Subtitle 'Collection, not a Health score' -Status Informational -VisualTone Informational -Icon Document -Span 3 |
    Add-PSIKPI -Title 'Domain controllers' -Value $Health.DCStates.Count -Subtitle $HealthEvidence.Domain -Status Informational -VisualTone Informational -Icon ResourceServer -Span 3 |
    Add-PSIRow -Columns 12 |
    Add-PSIKPI -Title 'Healthy checks' -Value $Counts.Ready -Subtitle 'Observed expected state' -Status Healthy -Icon SeveritySuccess -Span 3 |
    Add-PSIKPI -Title 'Review checks' -Value $Counts.Review -Subtitle 'Operational follow-up' -Status Warning -Icon SeverityWarning -Span 3 |
    Add-PSIKPI -Title 'Critical checks' -Value $Counts.Blocked -Subtitle 'Blocking observed conditions' -Status Critical -Icon SeverityCritical -Span 3 |
    Add-PSIKPI -Title 'Not Tested checks' -Value $Counts.NotTested -Subtitle 'Evidence unavailable' -Status NotChecked -Icon Document -Span 3 |
    Add-PSIRow -Columns 12 |
    Add-PSIAssessmentOverview -CheckViewId checks -FindingViewId findings |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id health-category-posture -Title 'Category posture' -Data $CategoryRows -Columns @('Category','Status','Score','Healthy','Review','Critical','NotTested') -PageSize 12
foreach ($Finding in @($Critical | Select-Object -First 2)) { $null=$Report | Add-PSIRow -Columns 12 | Add-PSIAlert -Status Critical -Title $Finding.Title -Message $Finding.Summary -Action $Finding.Recommendation.Action }
$null=$Report | Add-PSIView -Id posture -Title 'Health Posture' -Subtitle 'Reviewable thresholds and weighted categories' -Icon SeveritySuccess | Add-PSISection -Title 'Rule interpretation' | Add-PSIRow -Columns 12 | Add-PSIText -Text 'Ready = 100 points; Review = 50; Blocked, Not Tested and Unknown = 0; Not Applicable is excluded. Category weights combine category scores. Critical conditions override the percentage. Coverage measures collection separately.' | Add-PSIRow -Columns 12 | Add-PSITable -Id health-thresholds -Title 'Provider threshold configuration' -Data @($Health.Thresholds.Keys | Where-Object { $_ -notin @('Version','Source') } | Sort-Object | ForEach-Object { [pscustomobject]@{ Threshold=$_; Value=$Health.Thresholds[$_]; Source=$Health.Thresholds.Source } }) -Columns @('Threshold','Value','Source') -PageSize 20
$null=$Report | Add-PSIView -Id controllers -Title 'Domain Controllers' -Subtitle 'Per-controller Health and operational observations' -Icon ResourceServer | Add-PSISection -Title 'Assessed controllers' | Add-PSIRow -Columns 12 | Add-PSITable -Id health-controller-register -Title 'DC Health register' -Data $ControllerRows -Columns @('DC','Site','Status','Critical','Review','NotTested','OS','GC','PDC','CPU','MemoryUsedPercent','DiskFreeGB','UptimeDays','TimeSource') -Filters (@($StatusFilter)+@($SiteFilter)) -PageSize 10 | Add-PSIRow -Columns 12 | Add-PSIExplorer -Id health-controller-resources -Title 'Select a controller for linked findings and evidence' -Data @($Model.Resources | Where-Object Type -eq 'Domain Controller') -TitleProperty Name -SubtitleProperty Type -StatusProperty Status -DetailProperties (@('Site','Domain','OS','GlobalCatalog','FSMORoles','PDC','CPU','MemoryUsedPercent','DiskFreeGB','UptimeDays','TimeSource','CriticalFindings','ReviewFindings','NotTestedChecks')+$CategoryDetailProperties) -EntityType Resource -FilterProperties @('Status')
foreach ($Definition in @($Health.RulePack.Categories)) {
    $CategoryChecks=@($CheckRows | Where-Object Category -eq $Definition.Id)
    if (-not $CategoryChecks.Count) { continue }
    $ViewId="category-$($Definition.Id)"
    $null=$Report | Add-PSIView -Id $ViewId -Title $Definition.Name -Subtitle "Operational checks and evidence for $($Definition.Name)" -Icon $Definition.Icon | Add-PSISection -Title $Definition.Name | Add-PSIRow -Columns 12 | Add-PSITable -Id "health-$($Definition.Id)-checks" -Title "$($Definition.Name) checks" -Data $CategoryChecks -Columns @('Check','Status','Observed','Expected','Evidence') -PageSize 12
}
$null=$Report | Add-PSIView -Id topology -Title 'Topology' -Subtitle 'Site context and observed replication links' -Icon Relationship | Add-PSISection -Title 'Health topology' | Add-PSIRow -Columns 12 | Add-PSIText -Text 'Select a server or replication link for details. Use Health status, site and node type filters. External endpoints are evidence only. The graph has a 100-node safety limit and a mobile relationship list.' -Size Small | Add-PSIRow -Columns 12 | Add-PSITopology -Id health-topology -Title 'Domain controller replication' -Nodes $Health.TopologyNodes -Relationships $Health.TopologyEdges -DetailProperties (@('Site','Domain','OS','GlobalCatalog','FSMORoles','PDC','CPU','MemoryUsedPercent','DiskFreeGB','UptimeDays','TimeSource','CriticalFindings','ReviewFindings','NotTestedChecks')+$CategoryDetailProperties) -FilterProperties @('Site') -MaxNodes 100 -LinkViews @{ Resource='resources'; Finding='findings'; Evidence='evidence'; Check='checks'; Replication='category-replication' } | Add-PSIRow -Columns 12 | Add-PSITree -Id health-tree -Title 'Site and controller hierarchy' -Nodes $Health.TreeNodes -Relationships $Model.Relationships -DetailProperties @('Site','OS','Status') | Add-PSIRow -Columns 12 | Add-PSITable -Id health-site-summary -Title 'Site Health context (no site score)' -Data $SiteRows -Columns @('Site','Controllers','Healthy','Review','Critical','NotTested')
$null=$Report | Add-PSIView -Id checks -Title 'Checks' -Subtitle 'Every evaluated or untested rule instance' -Icon Document -Group Investigation | Add-PSISection -Title 'Check register' | Add-PSIRow -Columns 12 | Add-PSITable -Id health-check-register -Title 'Health checks' -Data $CheckRows -Columns @('Check','Category','Status','Severity','Observed','Expected','Rule','Evidence') -PageSize 20 | Add-PSIRow -Columns 12 | Add-PSIExplorer -Id health-check-explorer -Title 'Check details and linked evidence' -Data @($Assessment.Checks) -TitleProperty Name -SubtitleProperty CategoryId -StatusProperty Status -EntityType Check -FilterProperties @('CategoryId','Status')
$null=$Report | Add-PSIView -Id findings -Title 'Findings' -Subtitle 'Actionable and unverified conditions' -Icon SeverityWarning -Group Investigation | Add-PSISection -Title 'Finding register' | Add-PSIRow -Columns 12 | Add-PSITable -Id health-finding-register -Title 'Findings' -Data $FindingRows -Columns @('Finding','Category','Severity','Status','Observed','Expected','Action') -PageSize 20 | Add-PSIRow -Columns 12 | Add-PSIExplorer -Id health-finding-explorer -Title 'Finding detail, resources and evidence' -Data @($Model.Findings) -TitleProperty Title -SubtitleProperty Category -StatusProperty Severity -EntityType Finding -FilterProperties @('Category','Severity','Status')
$null=$Report | Add-PSIView -Id resources -Title 'Resources' -Subtitle 'DCs, sites and directory scope' -Icon ResourceServer -Group Investigation | Add-PSISection -Title 'Resource explorer' | Add-PSIRow -Columns 12 | Add-PSIExplorer -Id health-resource-explorer -Title 'Related Health resources' -Data @($Model.Resources) -TitleProperty Name -SubtitleProperty Type -StatusProperty Status -DetailProperties (@('Site','Domain','OS','GlobalCatalog','FSMORoles','PDC','CPU','MemoryUsedPercent','DiskFreeGB','UptimeDays','TimeSource','CriticalFindings','ReviewFindings','NotTestedChecks')+$CategoryDetailProperties) -EntityType Resource -FilterProperties @('Type','Status')
$null=$Report | Add-PSIView -Id evidence -Title 'Evidence' -Subtitle 'Observation provenance and explicit gaps' -Icon Document -Group Investigation | Add-PSISection -Title 'Evidence explorer' | Add-PSIRow -Columns 12 | Add-PSIExplorer -Id health-evidence-explorer -Title 'Collection and Health observations' -Data @($Model.Evidence) -TitleProperty Title -SubtitleProperty Source -EntityType Evidence -FilterProperties @('Type')
$null=$Report | Add-PSIView -Id coverage -Title 'Collection Coverage' -Subtitle 'Availability of facts, separate from Health' -Icon Document -Group Investigation | Add-PSISection -Title 'Collector coverage' | Add-PSIRow -Columns 12 | Add-PSITable -Id health-coverage-register -Title 'Collector states' -Data $CoverageRows -Columns @('Collector','State','Expected','Collected','CoveragePercent','Reason') -PageSize 20
if (@($Assessment.Exceptions).Count) { $null=$Report | Add-PSIView -Id exceptions -Title 'Exceptions' -Subtitle 'Recorded decisions do not erase observations' -Icon Document -Group Investigation | Add-PSISection -Title 'Exception register' | Add-PSIRow -Columns 12 | Add-PSIExplorer -Id health-exceptions -Title 'Health exceptions' -Data @($Assessment.Exceptions) -TitleProperty Title -SubtitleProperty Reason -StatusProperty Status -EntityType Exception }
if (-not $OutputPath) { $OutputPath=Join-Path $ModuleRoot 'Reports/Health' }
$null=New-Item -Path $OutputPath -ItemType Directory -Force
$HtmlPath=Join-Path $OutputPath $(if ($Sample) { 'ADHealth-Sample.html' } else { 'ADHealth-Mocked.html' })
$null=Export-PSIReport -Report $Report -Path $HtmlPath
if (-not $NoBrowser) { try { if ($env:OS -eq 'Windows_NT') { Start-Process $HtmlPath } elseif (Get-Command open -ErrorAction SilentlyContinue) { & open $HtmlPath } } catch { Write-Warning "Report generated but browser opening failed: $($_.Exception.Message)" } }
if ($PassThru) { [pscustomobject]@{ Snapshot=$Snapshot; Evidence=$HealthEvidence; Health=$Health; Report=$Report; HtmlPath=$HtmlPath } } else { $HtmlPath }
