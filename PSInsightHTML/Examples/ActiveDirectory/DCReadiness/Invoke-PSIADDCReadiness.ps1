[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('2022','2025')][string] $TargetOS,
    [switch] $UseSampleData,
    [string] $Domain,
    [switch] $IncludeRemoteChecks,
    [switch] $IncludePortChecks,
    [switch] $IncludeSecurityChecks,
    [switch] $IncludeDependencyDiscovery,
    [hashtable] $CommandAdapter,
    [string] $OutputPath,
    [ValidateSet('Light','Dark','Auto')][string] $Theme = 'Auto',
    [switch] $NoBrowser,
    [switch] $PassThru
)
$ErrorActionPreference='Stop'
$ModuleRoot=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
Import-Module (Join-Path $ModuleRoot 'PSInsightHTML.psd1') -Force
. (Join-Path $PSScriptRoot 'SampleData/New-PSIADDCReadinessSample.ps1')
. (Join-Path $PSScriptRoot 'Live/Get-PSIADReadOnlyAdapter.ps1')
. (Join-Path $PSScriptRoot 'Live/Invoke-PSIADCollector.ps1')
. (Join-Path $PSScriptRoot 'Live/Get-PSIADCollectionCoverage.ps1')
. (Join-Path $PSScriptRoot 'Live/New-PSIADLiveSnapshot.ps1')
. (Join-Path $PSScriptRoot 'Live/Get-PSIADRuleCoverage.ps1')
. (Join-Path $PSScriptRoot 'Collect-PSIADDCReadiness.ps1')
. (Join-Path $PSScriptRoot 'ConvertTo-PSIADDCReadinessModel.ps1')
. (Join-Path $PSScriptRoot 'Get-PSIADDCReadinessOutcome.ps1')
. (Join-Path $PSScriptRoot 'Test-PSIADDCReadiness.ps1')
if (-not $OutputPath) { if ($UseSampleData) { $OutputPath=Join-Path $ModuleRoot 'Reports/DCReadiness' } elseif ($env:OS -eq 'Windows_NT') { $OutputPath='C:\Temp\Reports\DCReadiness' } else { $OutputPath=Join-Path $ModuleRoot 'Reports/DCReadiness' } }
if (-not $UseSampleData) { $OutputPath=Join-Path $OutputPath (Get-Date -Format 'yyyyMMdd-HHmmss') }

$Snapshot=Collect-PSIADDCReadiness -UseSampleData:$UseSampleData -Domain $Domain -IncludeRemoteChecks:$IncludeRemoteChecks -IncludePortChecks:$IncludePortChecks -IncludeSecurityChecks:$IncludeSecurityChecks -IncludeDependencyDiscovery:$IncludeDependencyDiscovery -CommandAdapter $CommandAdapter
$Inventory=ConvertTo-PSIADDCReadinessModel -InputObject $Snapshot
$Results=@{}
foreach ($Target in @('2022','2025')) { $Results[$Target]=Test-PSIADDCReadiness -Inventory $Inventory -TargetOS $Target }
$Selected=$Results[$TargetOS]
$Comparison=@(
    foreach ($Target in @('2022','2025')) {
        $A=$Results[$Target].Assessment
        [pscustomobject]@{ Target="Windows Server $Target"; Decision=$A.Decision; Score="$($A.Score)%"; Blockers=$A.ScoreExplanation.Counts.Blockers; Review=$A.ScoreExplanation.Counts.Review; Ready=$A.ScoreExplanation.Counts.Ready; NotTested=$A.ScoreExplanation.Counts.NotTested; Exchange=(@($A.Checks | Where-Object { $_.Id -eq 'check-exchange' })[0]).Status }
    }
)
$Assessment=$Selected.Assessment; $Model=$Selected.Model
$IsSample=$Inventory.Source -eq 'Fictional sample'
$Report=New-PSIReport -Title $(if ($IsSample) { "DC Readiness $TargetOS | Fictional Sample" } else { "DC Readiness $TargetOS | $($Inventory.Domains[0].Name)" }) -Subtitle 'Active Directory domain controller modernization assessment' -Theme $Theme -Layout Application
$null=$Report | Set-PSIApplicationModel -Model $Model | Set-PSIApplicationAssessment -Assessment $Assessment

$null=$Report |
    Add-PSIView -Id overview -Title 'Overview' -Subtitle "Windows Server $TargetOS readiness and comparison" -Icon NavigationHome -Initial -Commands @(@{ Label='Review checks'; Icon='Rules'; TargetView='checks' }) |
    Add-PSISection -Title "Windows Server $TargetOS readiness" |
    Add-PSIRow -Columns 12 |
    Add-PSIStatus -Status $(if ($Inventory.CollectionCoverage.OverallPercent -ge 99) { 'Healthy' } else { 'Warning' }) -Label "Evidence coverage $($Inventory.CollectionCoverage.OverallPercent)% | Readiness score $($Assessment.Score)%" -Message 'Coverage and readiness are separate measures. Review Collection Coverage before acting on the decision.' |
    Add-PSIRow -Columns 12 |
    Add-PSIAssessmentOverview |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Text $(if ($IsSample) { 'Fictional sample only. One normalized inventory is evaluated independently against versioned Windows Server 2022 and 2025 rule packs. This report does not query or modify Active Directory.' } else { "Read-only evidence for $($Inventory.Domains[0].Name). Missing or partial collection is Not Tested; no directory changes are performed." }) -Size Small |
    Add-PSIRow -Columns 12 |
    Add-PSIKPI -Title 'Domain controllers' -Value $Inventory.DomainControllers.Count -Subtitle "$($Inventory.Sites.Count) sites in the selected domain" -Status Informational -Icon ResourceServer -Span 3 |
    Add-PSIKPI -Title 'Blocking checks' -Value $Assessment.ScoreExplanation.Counts.Blockers -Subtitle 'Target-specific decision override' -Status $(if ($Assessment.ScoreExplanation.Counts.Blockers) { 'Critical' } else { 'Healthy' }) -Icon SeverityError -Span 3 |
    Add-PSIKPI -Title 'Review' -Value $Assessment.ScoreExplanation.Counts.Review -Subtitle 'Requires owner validation' -Status Warning -Icon SeverityWarning -Span 3 |
    Add-PSIKPI -Title 'Not tested' -Value $Assessment.ScoreExplanation.Counts.NotTested -Subtitle 'Includes post-build checks' -Status NotChecked -Icon SeverityInfo -Span 3 |
    Add-PSIRow -Columns 12 |
    Add-PSIKPI -Title 'Readiness score' -Value "$($Assessment.Score)%" -Subtitle 'Assessment rule score' -Status Informational -Icon Rules -Span 3 |
    Add-PSIKPI -Title 'Evidence coverage' -Value "$($Inventory.CollectionCoverage.OverallPercent)%" -Subtitle 'Requested collection, separate from readiness' -Status $(if ($Inventory.CollectionCoverage.OverallPercent -ge 99) { 'Healthy' } else { 'Warning' }) -VisualTone Informational -Icon Document -Span 3 |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'dc-target-comparison' -Title 'Same inventory, two target assessments' -Data $Comparison -Columns @('Target','Decision','Score','Blockers','Review','Ready','NotTested','Exchange') -PageSize 2 |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Text $(if ($IsSample) { 'The 2025 target is blocked by the fictional Exchange 2019 CU13 dependency: Microsoft introduced Windows Server 2025 AD server support in CU14. The 2022 target is compatible from CU12 but remains incomplete because dependency and post-build validations are not tested. Exchange 2019 is past its October 2025 support end date, so its lifecycle remains a review item.' } else { 'This decision uses only collected evidence. Check Collection Coverage before interpreting any readiness score or compatibility result.' }) -Size Small

$CoverageNames=@{ DCs='Domain controllers'; Domain='Domain metadata'; Forest='Forest metadata'; Sites='AD sites'; Subnets='AD subnets'; SiteLinks='AD site links'; Partners='Replication partners'; Failures='Replication failures'; Remote='Remote OS, disk, services and DNS client'; Shares='SYSVOL and NETLOGON shares'; Time='Time source'; DNS='DNS Server'; Port='Collector-to-DC TCP ports'; Security='Security registry observations'; Dependencies='Dependency discovery'; DFSRMigration='DFSR migration state'; PendingReboot='Pending reboot state'; ResolverReachability='DNS resolver reachability'; ZoneHealth='DNS zone health'; ForwarderReachability='DNS forwarder reachability'; PDCSourceReachability='PDC time source reachability'; ProviderDependencyInput='Application dependency owner input' }
$CoverageRows=@(foreach ($Item in $Inventory.CollectionCoverage.Collectors) { [pscustomobject]@{ Collector=if ($CoverageNames.ContainsKey($Item.Collector)) { $CoverageNames[$Item.Collector] } else { $Item.Collector }; Status=switch ($Item.Status) { Collected { 'Healthy' } Partial { 'Warning' } Failed { 'Critical' } NotSupported { 'Unknown' } default { 'NotChecked' } }; CollectionState=$Item.Status; Expected=$Item.Expected; Collected=$Item.Collected; CoveragePercent=$Item.CoveragePercent; Failures=$Item.Failures; NotTested=$Item.NotTested } })
$FailureRows=@(foreach ($Item in @($Inventory.CollectionResults | Where-Object { $_.Status -in @('Failed','Partial','NotSupported') })) { [pscustomobject]@{ Collector=if ($CoverageNames.ContainsKey($Item.CollectorId)) { $CoverageNames[$Item.CollectorId] } else { $Item.CollectorId }; Scope=$Item.Scope; Status=switch ($Item.Status) { Failed { 'Critical' } Partial { 'Warning' } default { 'Unknown' } }; CollectionState=$Item.Status; ErrorCode=$Item.ErrorCode; Notes=$Item.Notes } })
$null=$Report |
    Add-PSIView -Id coverage -Title 'Collection Coverage' -Subtitle 'Read-only evidence completeness and failures' -Icon Document -Group Investigation |
    Add-PSISection -Title 'Evidence coverage' |
    Add-PSIRow -Columns 12 |
    Add-PSIKPI -Title 'Overall evidence coverage' -Value "$($Inventory.CollectionCoverage.OverallPercent)%" -Subtitle "$($Inventory.CollectionCoverage.Collected) of $($Inventory.CollectionCoverage.Expected) requested observations" -Status $(if ($Inventory.CollectionCoverage.OverallPercent -ge 99) { 'Healthy' } else { 'Warning' }) -VisualTone Informational -Icon Document -Span 4 |
    Add-PSIText -Text 'Evidence coverage measures completed requested collection. It does not change the readiness score or override the assessment decision. Not Requested and Not Supported are shown explicitly.' -Size Small |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'dc-coverage' -Title 'Collector coverage' -Data $CoverageRows -Columns @('Collector','Status','CollectionState','Expected','Collected','CoveragePercent','Failures','NotTested') -ColumnLabels @{ CollectionState='Collection state'; Expected='Expected'; Collected='Collected'; CoveragePercent='Coverage %'; NotTested='Not tested' } -PageSize 12 |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'dc-collection-failures' -Title 'Partial and failed observations' -Data $FailureRows -Columns @('Collector','Scope','Status','CollectionState','ErrorCode','Notes') -ColumnLabels @{ CollectionState='Collection state'; ErrorCode='Error type' } -PageSize 12

$Exchange=@($Inventory.Dependencies | Where-Object { $_.Type -eq 'Exchange' })
$ExchangeCheck=@($Assessment.Checks | Where-Object { $_.Id -eq 'check-exchange' })[0]
$ExchangeDisplayStatus=switch ($ExchangeCheck.Status) { 'Blocked' { 'Critical' } 'Review' { 'Warning' } 'Ready' { 'Healthy' } default { 'NotChecked' } }
$null=$Report |
    Add-PSIView -Id compatibility -Title 'Compatibility' -Subtitle 'Target OS, functional levels and Exchange' -Icon ResourceServer -Badge $TargetOS |
    Add-PSISection -Title 'Compatibility assessment' |
    Add-PSIRow -Columns 12 |
    Add-PSIStatus -Status $ExchangeDisplayStatus -Label "Exchange and AD server compatibility | $TargetOS" -Message $ExchangeCheck.ObservedState |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'dc-compatibility' -Title 'Target compatibility checks' -Data @($Assessment.Checks | Where-Object { $_.CategoryId -eq 'compatibility' -or $_.Id -eq 'check-functional-level' } | Select-Object Name,Status,ObservedState,ExpectedState) -Columns @('Name','Status','ObservedState','ExpectedState') -PageSize 8 |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'dc-exchange' -Title 'Exchange evidence' -Data $Exchange -Columns @('Name','Version','CU','Confidence','Status','Detail') -PageSize 5 |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Text 'For Exchange PrepareAD where a Windows Server 2025 DC holds Schema Master, verify that DC has the November 2025 or later Windows cumulative update. Exact Exchange CU remains a review item unless reliably verified.' -Size Small

$DCHealth=@($Inventory.DomainControllers | Select-Object Name,Site,OS,Build,Writable,GlobalCatalog,Reachable,DiskFreeGB,TimeSource,PendingReboot)
$SysvolState=if ($Inventory.Forest.SysvolReplication) { $Inventory.Forest.SysvolReplication } else { 'Not Tested' }
$DfsrState=if ($Inventory.Forest.DFSRMigrationState) { $Inventory.Forest.DFSRMigrationState } else { 'Not Tested' }
$null=$Report |
    Add-PSIView -Id health -Title 'Health' -Subtitle 'DC inventory, services, time and storage' -Icon SeveritySuccess |
    Add-PSISection -Title 'Core DC health' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'dc-health' -Title 'Controller health evidence' -Data $DCHealth -Columns @('Name','Site','OS','Writable','GlobalCatalog','Reachable','DiskFreeGB','TimeSource','PendingReboot') -PageSize 8 |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Text "Disk review threshold: less than $($Inventory.Thresholds.DiskFreeGBReviewBelow) GB free, supplied by the provider profile. Service-running state is not treated as complete functional health." -Size Small

$null=$Report |
    Add-PSIView -Id replication -Title 'Replication' -Subtitle 'Partners, naming contexts and SYSVOL' -Icon Relationship |
    Add-PSISection -Title 'Replication readiness' |
    Add-PSIRow -Columns 12 |
    Add-PSIStatus -Status $(if ($IsSample) { 'Warning' } else { 'NotChecked' }) -Label $(if ($IsSample) { 'Historical RPC error recovered' } else { 'Replication collection' }) -Message $(if ($IsSample) { 'The sample 1722 event has zero current and consecutive failures, with a recent successful replication. It is a review signal, not an automatic blocker.' } else { 'Partner and failure queries are shown separately in Collection Coverage. A failed query is never interpreted as no failures.' }) |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'dc-replication' -Title 'Observed replication links' -Data $Inventory.Replication -Columns @('Source','Destination','NamingContext','CurrentFailures','ConsecutiveFailures','LastSuccess','LastError','LatencyMinutes') -PageSize 6 |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Text "SYSVOL engine: $SysvolState; DFSR migration: $DfsrState. Current material failures or unsupported SYSVOL replication block readiness when verified." -Size Small

$DnsRows=@(foreach ($DC in $Inventory.DomainControllers) { [pscustomobject]@{ DC=$DC.Name; Site=$DC.Site; PrimaryDNS=@($DC.DNSClient)[0]; SecondaryDNS=@($DC.DNSClient)[1]; DNSRole=$DC.DNSRole; Forwarders=@($DC.DNSForwarders) -join ', '; ForwardZoneHealthy=$DC.ForwardZoneHealthy; ReverseZoneHealthy=$DC.ReverseZoneHealthy; ConditionalForwarders=@($DC.ConditionalForwarders) -join ', ' } })
$null=$Report |
    Add-PSIView -Id dns -Title 'DNS' -Subtitle 'Clients, zones, forwarders and resilience' -Icon Relationship |
    Add-PSISection -Title 'DNS readiness' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'dc-dns' -Title 'DC DNS configuration' -Data $DnsRows -Columns @('DC','Site','PrimaryDNS','SecondaryDNS','DNSRole','Forwarders','ForwardZoneHealthy','ReverseZoneHealthy','ConditionalForwarders') -PageSize 8 |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Text $(if ($IsSample) { 'Self-DNS is reviewed with resolver reachability and site design; it is not automatically invalid. One sample upstream forwarder is unreachable.' } else { 'Self-DNS alone is not unhealthy. Resolver and forwarder reachability are untested unless supported evidence is explicitly collected.' }) -Size Small

$SecurityRows=@($Selected.GPO | Select-Object Setting,Current,Recommended,Status,Framework)
$null=$Report |
    Add-PSIView -Id security -Title 'Security' -Subtitle 'Versioned provider security observations' -Icon SecurityShield |
    Add-PSISection -Title 'Security review' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'dc-security' -Title 'Security baseline observations' -Data $SecurityRows -Columns @('Setting','Current','Recommended','Status','Framework') -PageSize 10 |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Text 'These provider rules and local thresholds are assessment guidance, not a NIST, CIS, or STIG certification. Missing effective policy remains Not Tested.' -Size Small

$null=$Report |
    Add-PSIView -Id gpo -Title 'GPO Build Standard' -Subtitle 'Recommendation-only policy planning' -Icon Rules -Group Investigation |
    Add-PSISection -Title 'Suggested DC GPO standard' |
    Add-PSIRow -Columns 12 |
    Add-PSIStatus -Status Informational -Label 'Planning guidance only' -Message 'No Group Policy object is created or changed by this provider.' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'dc-gpo' -Title 'Recommended settings and validation' -Data $Selected.GPO -Columns @('Setting','Recommended','Current','Status','SuggestedGPO','SuggestedScope','ConflictingGPO','Framework','Rationale','Remediation','Impact','Validation') -PageSize 8

$null=$Report |
    Add-PSIView -Id dependencies -Title 'Dependencies' -Subtitle 'Exchange, identity, PKI and applications' -Icon Relationship -Group Investigation |
    Add-PSISection -Title 'Application dependency review' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'dc-dependencies' -Title 'Known and untested dependencies' -Data $Inventory.Dependencies -Columns @('Name','Type','Version','CU','Confidence','Status','Detail') -PageSize 9 |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'dc-ports' -Title 'Topology-aware port observations' -Data $Inventory.Ports -Columns @('Port','Role','Source','Destination','Result') -PageSize 12

$null=$Report |
    Add-PSIView -Id checks -Title 'Checks' -Subtitle 'Category, status, blocker and evidence investigation' -Icon Rules -Badge $Assessment.Checks.Count |
    Add-PSISection -Title 'Assessment checks' |
    Add-PSIRow -Columns 12 |
    Add-PSIExplorer -Id 'dc-checks' -Title 'Readiness checks' -Data $Assessment.Checks -TitleProperty Name -SubtitleProperty CategoryId -StatusProperty Status -EntityType Check -FilterProperties @('CategoryId','Status') |
    Add-PSIRow -Columns 12 |
    Add-PSIExplorer -Id 'dc-categories' -Title 'Category posture' -Data $Assessment.Categories -TitleProperty Name -SubtitleProperty Description -StatusProperty Status -EntityType Category

$null=$Report |
    Add-PSIView -Id findings -Title 'Findings' -Subtitle 'Observed gaps and guidance' -Icon SeverityWarning -Badge $Model.Findings.Count |
    Add-PSISection -Title 'Finding queue' |
    Add-PSIRow -Columns 12 |
    Add-PSIExplorer -Id 'dc-findings' -Title 'Assessment findings' -Data $Model.Findings -TitleProperty Title -SubtitleProperty Category -StatusProperty Severity -EntityType Finding
$null=$Report |
    Add-PSIView -Id resources -Title 'Resources' -Subtitle 'Forest, domains, sites, DCs and dependencies' -Icon ResourceServer -Badge $Model.Resources.Count |
    Add-PSISection -Title 'Resource inventory' |
    Add-PSIRow -Columns 12 |
    Add-PSIExplorer -Id 'dc-resources' -Title 'Known resources' -Data $Model.Resources -TitleProperty Name -SubtitleProperty Type -StatusProperty Status -EntityType Resource
$null=$Report |
    Add-PSIView -Id evidence -Title 'Evidence' -Subtitle 'Source-referenced observations' -Icon Document -Group Investigation |
    Add-PSISection -Title 'Evidence register' |
    Add-PSIRow -Columns 12 |
    Add-PSIExplorer -Id 'dc-evidence' -Title 'Provider observations' -Data $Model.Evidence -TitleProperty Title -SubtitleProperty Source -EntityType Evidence
$null=$Report |
    Add-PSIView -Id exceptions -Title 'Exceptions' -Subtitle 'Approved exception with ownership and expiry' -Icon SeverityInfo -Group Investigation |
    Add-PSISection -Title 'Exception register' |
    Add-PSIRow -Columns 12 |
    Add-PSIExplorer -Id 'dc-exceptions' -Title 'Documented exceptions' -Data $Assessment.Exceptions -TitleProperty Title -SubtitleProperty Reason -StatusProperty Status -EntityType Exception
$null=$Report |
    Add-PSIView -Id postbuild -Title 'Post-Build Validation' -Subtitle 'Checks to perform after promotion' -Icon Document -Group Investigation |
    Add-PSISection -Title 'Post-build checklist' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Text 'These checks are Not Tested because no new domain controller was deployed. They are definitions for later validation, not executed tasks.' -Size Small |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'dc-postbuild' -Title 'Post-build validation definitions' -Data @($Selected.PostBuild | Select-Object Name,Status,ObservedState,ExpectedState) -Columns @('Name','Status','ObservedState','ExpectedState') -PageSize 12

$null=New-Item -Path $OutputPath -ItemType Directory -Force
$HtmlPath=Join-Path $OutputPath "DCReadiness-$TargetOS.html"
$Html=Export-PSIReport -Report $Report -Path $HtmlPath
$InventoryFile=if ($IsSample) { "NormalizedInventory-$TargetOS.json" } else { 'NormalizedData.json' }
$AssessmentFile=if ($IsSample) { "Assessment-$TargetOS.json" } else { 'Assessment.json' }
$ChecksFile=if ($IsSample) { "Checks-$TargetOS.csv" } else { 'Checks.csv' }
$Inventory | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $OutputPath $InventoryFile) -Encoding UTF8
$Assessment | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $OutputPath $AssessmentFile) -Encoding UTF8
$Assessment.Checks | Select-Object Id,Name,CategoryId,Status,Severity,IsBlocking,ObservedState,ExpectedState | Export-Csv -LiteralPath (Join-Path $OutputPath $ChecksFile) -NoTypeInformation -Encoding UTF8
$Comparison | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputPath "TargetComparison-$TargetOS.json") -Encoding UTF8
$Inventory.CollectionCoverage | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $OutputPath 'CollectionCoverage.json') -Encoding UTF8
$Inventory.CollectionCoverage.Collectors | Export-Csv -LiteralPath (Join-Path $OutputPath 'CollectionCoverage.csv') -NoTypeInformation -Encoding UTF8
if (-not $IsSample) {
    $LogsPath=Join-Path $OutputPath 'Logs'; $null=New-Item -Path $LogsPath -ItemType Directory -Force
    $LogJson=ConvertTo-Json -InputObject @($Inventory.CollectionLogs) -Depth 8
    Set-Content -LiteralPath (Join-Path $LogsPath 'DCReadiness.log') -Value $LogJson -Encoding UTF8
}
Write-Host "Generated DC readiness report: $($Html.FullName) ($($Html.Length) bytes)"
if (-not $NoBrowser) {
    try { if ($IsMacOS) { & open $Html.FullName 2>$null } elseif ($IsWindows -or $env:OS -eq 'Windows_NT') { Start-Process $Html.FullName } else { & xdg-open $Html.FullName 2>$null } }
    catch { Write-Warning "Default browser could not be opened: $($_.Exception.Message)" }
}
if ($PassThru) { [pscustomobject]@{ Report=$Report; Inventory=$Inventory; Selected=$Selected; Comparison=$Comparison; HtmlPath=$Html.FullName } }
