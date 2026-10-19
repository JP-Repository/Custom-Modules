[CmdletBinding()]
param(
    [switch] $UseSampleData,
    [string] $Domain,
    [pscustomobject] $Snapshot,
    [hashtable] $CommandAdapter,
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
    $Raw=Collect-PSIADSnapshot -UseSampleData:$UseSampleData -Domain $Domain -Profile Security -CommandAdapter $CommandAdapter
    $Snapshot=ConvertTo-PSIADDCReadinessModel $Raw
}
$Evidence=New-PSIADSecurityEvidenceModel -Snapshot $Snapshot
$Sample=$Snapshot.Source -eq 'Fictional sample'
if ($Sample) { $null=Add-PSIADSecurityFictionalObservations -Snapshot $Snapshot -Evidence $Evidence }
$Security=Test-PSIADSecurity -Snapshot $Snapshot -SecurityEvidence $Evidence -ThresholdOverrides $ThresholdOverrides -Exceptions $Exceptions
$Assessment=$Security.Assessment; $Model=$Security.Model; $Counts=$Assessment.ScoreExplanation.Counts
$Status=if ($Security.SecurityVerdict -eq 'Secure') { 'Healthy' } elseif ($Security.SecurityVerdict -eq 'Review') { 'Warning' } elseif ($Security.SecurityVerdict -eq 'Incomplete') { 'NotChecked' } else { $Security.SecurityVerdict }
$Report=New-PSIReport -Title 'Active Directory Security' -Subtitle $(if ($Sample) { 'Fictional security scenario | No live environment queried' } else { "Read-only security observations | $($Evidence.Domain)" }) -Theme $Theme -Layout Application
$null=$Report | Set-PSIApplicationModel -Model $Model | Set-PSIApplicationAssessment -Assessment $Assessment
$Report | Add-Member -NotePropertyName PrintDisplay -NotePropertyValue @{ ReportIdentity=@{ Kicker='PSInsightHTML / Active Directory Security' }; Scope=$Evidence.Domain; Profile="Security rule pack $($Security.RulePack.Version)"; CoveragePercent=$Evidence.EvidenceCompleteness.Percent; Tables=@('security-controller-register','security-check-register','security-finding-register','security-coverage-register'); Resources=@{ Columns=@(@{Property='Name';Label='Resource'},@{Property='Type';Label='Type'},@{Property='Site';Label='Site'},@{Property='Status';Label='Security';Format='Status'}) } }
$Critical=@($Model.Findings | Where-Object { $_.Severity -eq 'Critical' -and $_.Status -eq 'Open' })
$Review=@($Model.Findings | Where-Object { $_.Severity -eq 'Warning' -and $_.Status -eq 'Open' })
function ConvertTo-PSISecurityDisplayStatus {
    param([string] $Outcome)
    switch ($Outcome) {
        { $_ -in @('Ready','Secure') } { 'Healthy'; break }
        { $_ -in @('Review','ReadyWithReview','ReviewRequired') } { 'Warning'; break }
        { $_ -in @('Blocked','NotReady') } { 'Critical'; break }
        { $_ -in @('NotTested','Incomplete','Unknown') } { 'NotChecked'; break }
        default { 'Neutral' }
    }
}
$ControllerRows=@($Security.DCStates | ForEach-Object { $State=$_; $DC=@($Snapshot.DomainControllers | Where-Object Name -eq $State.DC)[0]; [pscustomobject]@{ DC=$State.DC; Site=$State.Site; Domain=$State.Domain; Status=$State.Status; Critical=$State.Critical; Review=$State.Review; NotTested=$State.NotTested; OS=$DC.OS; GC=$DC.GlobalCatalog; PDC=($DC.Name -eq $Snapshot.Domains[0].PDCEmulator) } })
$CheckRows=@($Assessment.Checks | ForEach-Object { [pscustomobject]@{ Check=$_.Name; Category=$_.CategoryId; Status=(ConvertTo-PSISecurityDisplayStatus $_.Status); Outcome=$_.Status; Severity=$_.Severity; Observed=$_.ObservedState; Expected=$_.ExpectedState; Evidence=@($_.EvidenceIds) -join ', '; Rule=$_.Metadata.RuleId } })
$FindingRows=@($Model.Findings | ForEach-Object { [pscustomobject]@{ Finding=$_.Title; Category=$_.Category; Severity=$_.Severity; Status=$_.Status; Observed=$_.Summary; Expected=$_.ReadinessImpact; Action=$_.Recommendation.Action } })
$CoverageRows=@($Evidence.CollectionCoverage.Collectors | ForEach-Object { [pscustomobject]@{ Collector=$_.Collector; State=$_.Status; Expected=$_.Expected; Collected=$_.Collected; CoveragePercent=$_.CoveragePercent; Reason=$_.Reason } })
$CategoryRows=@($Assessment.Categories | ForEach-Object { $C=$_; [pscustomobject]@{ Category=$C.Name; Status=(ConvertTo-PSISecurityDisplayStatus $C.Status); Outcome=$C.Status; Score=$C.Score; Secure=@($Assessment.Checks | Where-Object { $_.CategoryId -eq $C.Id -and $_.Status -eq 'Ready' }).Count; Review=@($Assessment.Checks | Where-Object { $_.CategoryId -eq $C.Id -and $_.Status -eq 'Review' }).Count; Critical=@($Assessment.Checks | Where-Object { $_.CategoryId -eq $C.Id -and $_.Status -eq 'Blocked' }).Count; NotTested=@($Assessment.Checks | Where-Object { $_.CategoryId -eq $C.Id -and $_.Status -eq 'NotTested' }).Count } })
$PrivilegedRows=@(if ($Evidence.PrivilegedAccess) { $Evidence.PrivilegedAccess.Members | ForEach-Object { $M=$_.Metadata; [pscustomobject]@{ Principal=$_.Principal; Group=$_.Group; Membership=if ($_.Direct) { 'Direct' } else { 'Nested' }; Path=@($_.NestedPath) -join ' > '; Type=$_.PrincipalType; Enabled=if ($M) { $M.Enabled } else { $null }; PasswordAgeDays=if ($M -and $M.PasswordLastSet) { [math]::Floor(([datetime]$Snapshot.CollectedAt-[datetime]$M.PasswordLastSet).TotalDays) } else { $null }; LastLogon=if ($M) { $M.LastLogonDate } else { $null }; PasswordNeverExpires=if ($M) { $M.PasswordNeverExpires } else { $null }; Resolution=$_.ResolutionState; Scope=$_.Scope } } })
$TelemetryRows=@($Evidence.AuthenticationTelemetry | ForEach-Object { [pscustomobject]@{ DC=$_.DC; Time=$_.Timestamp; Protocol=$_.Kind; Version=$_.Version; Account=$_.Account; Client=$_.Client; Service=$_.Service; Event=$_.SourceEvent; WindowHours=$_.CollectionWindowHours } })
$SourceRows=@($Evidence.Observations | Where-Object { $_.SourceType -ne 'None' } | ForEach-Object { [pscustomobject]@{ DC=$_.DC; Rule=$_.RuleId; State=$_.CollectionState; Source=$_.SourceType; Confidence=$_.Confidence; Value=$_.Value; Error=$_.ErrorClass } })
$GpoRows=@($Evidence.GpoIntent | ForEach-Object { [pscustomobject]@{ Container=$_.Container; State=$_.CollectionState; Links=$_.GpLink; InheritanceFlag=$_.GpOptions; Confidence=$_.Confidence; Effective='Not established' } })
$StatusFilter=Add-PSIFilter -Property Status -Values @('Healthy','Warning','Critical','NotChecked') -Label 'Security state'
$SiteValues=@($ControllerRows | ForEach-Object Site | Where-Object { $_ } | Sort-Object -Unique)
$SiteFilter=if ($SiteValues.Count) { @(Add-PSIFilter -Property Site -Values $SiteValues -Label 'Site') } else { @() }
$CategoryDetailProperties=@('SecurityAuthentication','SecurityKerberos','SecurityNtlm','SecurityLdap','SecuritySmb','SecurityTls','SecurityPrivileged','SecurityHardening','SecurityAudit','SecurityProtocol','SecurityCredential','SecurityIdentity')
$null=$Report |
    Add-PSIView -Id overview -Title 'Overview' -Subtitle 'Security verdict, score and evidence coverage' -Icon NavigationHome -Initial |
    Add-PSISection -Title 'Executive Security summary' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Text $(if ($Sample) { 'Fictional sample facts exercise the rules. Provider recommendations are not an organizational baseline or compliance certification. No remediation is performed.' } else { 'Security interpretation of a shared normalized snapshot. Verify effective policy, traffic evidence and dependencies before changing controls.' }) -Size Small |
    Add-PSIRow -Columns 12 |
    Add-PSIKPI -Title 'Security verdict' -Value $Security.SecurityVerdict -Subtitle 'Critical exposure overrides score' -Status $Status -Icon SeverityCritical -Span 3 |
    Add-PSIKPI -Title 'Security score' -Value "$($Assessment.Score)%" -Subtitle 'Weighted assessed checks' -Status Informational -VisualTone Informational -Icon Document -Span 3 |
    Add-PSIKPI -Title 'Evidence coverage' -Value "$($Evidence.EvidenceCompleteness.Percent)%" -Subtitle 'Complete security facts; not a score' -Status Informational -VisualTone Informational -Icon Document -Span 3 |
    Add-PSIKPI -Title 'Domain controllers' -Value $Security.DCStates.Count -Subtitle $Evidence.Domain -Status Informational -VisualTone Informational -Icon ResourceServer -Span 3 |
    Add-PSIRow -Columns 12 |
    Add-PSIKPI -Title 'Secure checks' -Value $Counts.Ready -Subtitle 'Observed expected state' -Status Healthy -Icon SeveritySuccess -Span 3 |
    Add-PSIKPI -Title 'Review checks' -Value $Counts.Review -Subtitle 'Validate exposure and dependencies' -Status Warning -Icon SeverityWarning -Span 3 |
    Add-PSIKPI -Title 'Critical checks' -Value $Counts.Blocked -Subtitle 'Observed high-risk condition' -Status Critical -Icon SeverityCritical -Span 3 |
    Add-PSIKPI -Title 'Not Tested checks' -Value $Counts.NotTested -Subtitle 'Evidence unavailable or incomplete' -Status NotChecked -Icon Document -Span 3 |
    Add-PSIRow -Columns 12 |
    Add-PSIAssessmentOverview -CheckViewId checks -FindingViewId findings |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id security-category-posture -Title 'Category posture' -Data $CategoryRows -Columns @('Category','Status','Outcome','Score','Secure','Review','Critical','NotTested') -PageSize 12
foreach ($Finding in @($Critical | Select-Object -First 2)) { $null=$Report | Add-PSIRow -Columns 12 | Add-PSIAlert -Status Critical -Title $Finding.Title -Message $Finding.Summary -Action $Finding.Recommendation.Action }
$null=$Report | Add-PSIView -Id posture -Title 'Security Posture' -Subtitle 'Rule scope, thresholds and weighted categories' -Icon SeveritySuccess | Add-PSISection -Title 'Assessment method' | Add-PSIRow -Columns 12 | Add-PSIText -Text 'Ready = 100 points; Review = 50; Blocked, Not Tested and Unknown = 0; Not Applicable is excluded. Critical conditions override score. Registry-only values can indicate risk but cannot prove effective policy. Evidence coverage is separate.' | Add-PSIRow -Columns 12 | Add-PSITable -Id security-thresholds -Title 'Provider threshold configuration' -Data @($Security.Thresholds.Keys | Where-Object { $_ -notin @('Version','Source') } | Sort-Object | ForEach-Object { [pscustomobject]@{ Threshold=$_; Value=$Security.Thresholds[$_]; Source=$Security.Thresholds.Source } }) -Columns @('Threshold','Value','Source') -PageSize 20
if ($GpoRows.Count) { $null=$Report | Add-PSIRow -Columns 12 | Add-PSITable -Id security-gpo-intent -Title 'DC container GPO link intent' -Data $GpoRows -Columns @('Container','State','Links','InheritanceFlag','Confidence','Effective') -PageSize 10 }
$null=$Report | Add-PSIView -Id controllers -Title 'Domain Controllers' -Subtitle 'Per-controller Security and evidence gaps' -Icon ResourceServer | Add-PSISection -Title 'Assessed controllers' | Add-PSIRow -Columns 12 | Add-PSITable -Id security-controller-register -Title 'DC Security register' -Data $ControllerRows -Columns @('DC','Site','Status','Critical','Review','NotTested','OS','GC','PDC') -Filters (@($StatusFilter)+@($SiteFilter)) -PageSize 10 | Add-PSIRow -Columns 12 | Add-PSIExplorer -Id security-controller-resources -Title 'Select a controller for linked findings and evidence' -Data @($Model.Resources | Where-Object Type -eq 'Domain Controller') -TitleProperty Name -SubtitleProperty Type -StatusProperty Status -DetailProperties (@('Site','Domain','OS','GlobalCatalog','FSMORoles','CriticalFindings','ReviewFindings','NotTestedChecks')+$CategoryDetailProperties) -EntityType Resource -FilterProperties @('Status')
foreach ($Definition in @($Security.RulePack.Categories)) {
    $CategoryChecks=@($CheckRows | Where-Object Category -eq $Definition.Id)
    if (-not $CategoryChecks.Count) { continue }
    $null=$Report | Add-PSIView -Id "category-$($Definition.Id)" -Title $Definition.Name -Subtitle "Security checks and evidence for $($Definition.Name)" -Icon $Definition.Icon | Add-PSISection -Title $Definition.Name | Add-PSIRow -Columns 12 | Add-PSITable -Id "security-$($Definition.Id)-checks" -Title "$($Definition.Name) checks" -Data $CategoryChecks -Columns @('Check','Status','Outcome','Observed','Expected','Evidence') -PageSize 12
    if ($Definition.Id -eq 'privileged' -and $PrivilegedRows.Count) { $null=$Report | Add-PSIRow -Columns 12 | Add-PSITable -Id security-privileged-members -Title 'Privileged membership facts' -Data $PrivilegedRows -Columns @('Principal','Group','Membership','Path','Type','Enabled','PasswordAgeDays','LastLogon','PasswordNeverExpires','Resolution','Scope') -PageSize 12 }
    if ($Definition.Id -in @('ntlm','kerberos')) {
        $Kind=if ($Definition.Id -eq 'ntlm') { 'NTLM' } else { 'Kerberos' }
        $Rows=@($TelemetryRows | Where-Object Protocol -eq $Kind)
        if ($Rows.Count) { $null=$Report | Add-PSIRow -Columns 12 | Add-PSITable -Id "security-$($Definition.Id)-telemetry" -Title "$Kind observations (bounded window)" -Data $Rows -Columns @('DC','Time','Version','Account','Client','Service','Event','WindowHours') -PageSize 10 }
    }
    if ($Definition.Id -in @('ldap','smb','tls','credential','audit','hardening','protocol')) {
        $Rules=@($Security.RulePack.Rules | Where-Object Category -eq $Definition.Id | ForEach-Object Id)
        $Rows=@($SourceRows | Where-Object { $_.Rule -in $Rules })
        if ($Rows.Count) { $null=$Report | Add-PSIRow -Columns 12 | Add-PSITable -Id "security-$($Definition.Id)-sources" -Title 'Attributable evidence sources' -Data $Rows -Columns @('DC','Rule','State','Source','Confidence','Value','Error') -PageSize 12 }
    }
}
$null=$Report | Add-PSIView -Id topology -Title 'Topology' -Subtitle 'DC Security state in factual site and replication context' -Icon Relationship | Add-PSISection -Title 'Security topology' | Add-PSIRow -Columns 12 | Add-PSIText -Text 'Select a DC for its Security checks and findings. Replication links are neutral operational context and are not assigned a Security verdict. External endpoints remain evidence only.' -Size Small | Add-PSIRow -Columns 12 | Add-PSITopology -Id security-topology -Title 'Domain controller Security context' -Nodes $Security.TopologyNodes -Relationships $Security.TopologyEdges -DetailProperties (@('Site','Domain','OS','GlobalCatalog','FSMORoles','CriticalFindings','ReviewFindings','NotTestedChecks')+$CategoryDetailProperties) -FilterProperties @('Site') -MaxNodes 100 -LinkViews @{ Resource='resources'; Finding='findings'; Evidence='evidence'; Check='checks' } | Add-PSIRow -Columns 12 | Add-PSITree -Id security-tree -Title 'Site and controller hierarchy' -Nodes $Security.TreeNodes -Relationships $Model.Relationships -DetailProperties @('Site','OS','Status')
$null=$Report | Add-PSIView -Id checks -Title 'Checks' -Subtitle 'Every evaluated or unverified rule instance' -Icon Document -Group Investigation | Add-PSISection -Title 'Check register' | Add-PSIRow -Columns 12 | Add-PSITable -Id security-check-register -Title 'Security checks' -Data $CheckRows -Columns @('Check','Category','Status','Outcome','Severity','Observed','Expected','Rule','Evidence') -PageSize 20 | Add-PSIRow -Columns 12 | Add-PSIExplorer -Id security-check-explorer -Title 'Checks and linked evidence' -Data @($Assessment.Checks) -TitleProperty Name -SubtitleProperty CategoryId -StatusProperty Status -EntityType Check -FilterProperties @('CategoryId','Status')
$null=$Report | Add-PSIView -Id findings -Title 'Findings' -Subtitle 'Observed exposure and unverified controls' -Icon SeverityWarning -Group Investigation | Add-PSISection -Title 'Finding register' | Add-PSIRow -Columns 12 | Add-PSITable -Id security-finding-register -Title 'Security findings' -Data $FindingRows -Columns @('Finding','Category','Severity','Status','Observed','Expected','Action') -PageSize 20 | Add-PSIRow -Columns 12 | Add-PSIExplorer -Id security-finding-explorer -Title 'Finding detail and attributable evidence' -Data @($Model.Findings) -TitleProperty Title -SubtitleProperty Category -StatusProperty Severity -EntityType Finding -FilterProperties @('Category','Severity','Status')
$null=$Report | Add-PSIView -Id resources -Title 'Resources' -Subtitle 'DCs, sites and directory scope' -Icon ResourceServer -Group Investigation | Add-PSISection -Title 'Resource explorer' | Add-PSIRow -Columns 12 | Add-PSIExplorer -Id security-resource-explorer -Title 'Related Security resources' -Data @($Model.Resources) -TitleProperty Name -SubtitleProperty Type -StatusProperty Status -DetailProperties (@('Site','Domain','OS','GlobalCatalog','FSMORoles','CriticalFindings','ReviewFindings','NotTestedChecks')+$CategoryDetailProperties) -EntityType Resource -FilterProperties @('Type','Status')
$null=$Report | Add-PSIView -Id evidence -Title 'Evidence' -Subtitle 'Observation provenance and explicit gaps' -Icon Document -Group Investigation | Add-PSISection -Title 'Evidence explorer' | Add-PSIRow -Columns 12 | Add-PSIExplorer -Id security-evidence-explorer -Title 'Security observations' -Data @($Model.Evidence) -TitleProperty Title -SubtitleProperty Source -EntityType Evidence -FilterProperties @('Type')
$null=$Report | Add-PSIView -Id coverage -Title 'Collection Coverage' -Subtitle 'Security evidence availability and shared collector coverage' -Icon Document -Group Investigation | Add-PSISection -Title 'Evidence and collector coverage' | Add-PSIRow -Columns 12 | Add-PSIText -Text "Complete Security facts: $($Evidence.EvidenceCompleteness.Collected) of $($Evidence.EvidenceCompleteness.Total) ($($Evidence.EvidenceCompleteness.Percent)%). Partial registry indications appear in evidence but do not count as complete facts. Shared snapshot collector coverage: $($Evidence.CollectionCoverage.OverallPercent)%. These measures and the Security score answer different questions." | Add-PSIRow -Columns 12 | Add-PSITable -Id security-coverage-register -Title 'Shared collector states' -Data $CoverageRows -Columns @('Collector','State','Expected','Collected','CoveragePercent','Reason') -PageSize 20
if (@($Assessment.Exceptions).Count) { $null=$Report | Add-PSIView -Id exceptions -Title 'Exceptions' -Subtitle 'Approved decisions do not erase observations' -Icon Document -Group Investigation | Add-PSISection -Title 'Exception register' | Add-PSIRow -Columns 12 | Add-PSIExplorer -Id security-exceptions -Title 'Security exceptions' -Data @($Assessment.Exceptions) -TitleProperty Title -SubtitleProperty Reason -StatusProperty Status -EntityType Exception }
if (-not $OutputPath) { $OutputPath=Join-Path $ModuleRoot 'Reports/Security' }
$null=New-Item -Path $OutputPath -ItemType Directory -Force
$HtmlPath=Join-Path $OutputPath $(if ($Sample) { 'ADSecurity-Sample.html' } else { 'ADSecurity-Mocked.html' })
$null=Export-PSIReport -Report $Report -Path $HtmlPath
if (-not $NoBrowser) { try { if ($env:OS -eq 'Windows_NT') { Start-Process $HtmlPath } elseif (Get-Command open -ErrorAction SilentlyContinue) { & open $HtmlPath } } catch { Write-Warning "Report generated but browser opening failed: $($_.Exception.Message)" } }
if ($PassThru) { [pscustomobject]@{ Snapshot=$Snapshot; Evidence=$Evidence; Security=$Security; Report=$Report; HtmlPath=$HtmlPath } } else { $HtmlPath }
