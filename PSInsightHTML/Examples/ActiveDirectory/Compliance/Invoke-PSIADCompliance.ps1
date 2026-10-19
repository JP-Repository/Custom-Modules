[CmdletBinding()]
param(
    [switch] $UseSampleData,
    [string] $Domain,
    [pscustomobject] $Snapshot,
    [hashtable] $CommandAdapter,
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
    $Raw=Collect-PSIADSnapshot -UseSampleData:$UseSampleData -Domain $Domain -Profile Full -CommandAdapter $CommandAdapter
    $Snapshot=ConvertTo-PSIADDCReadinessModel $Raw
}
$Sample=$Snapshot.Source -eq 'Fictional sample'
$SecurityEvidence=New-PSIADSecurityEvidenceModel $Snapshot
$HealthEvidence=New-PSIADHealthEvidenceModel $Snapshot
if ($Sample) {
    $null=Add-PSIADSecurityFictionalObservations $Snapshot $SecurityEvidence
    $null=Add-PSIADHealthFictionalObservations $Snapshot $HealthEvidence
}
$Security=Test-PSIADSecurity $Snapshot $SecurityEvidence
$Health=Test-PSIADHealth $Snapshot $HealthEvidence
$Watch=[System.Diagnostics.Stopwatch]::StartNew()
$FrameworkResults=@(foreach ($Pack in @(Get-PSIADControlMappings -All)) { Test-PSIADCompliance $Snapshot $Security $Health $Pack })
$AllControls=@($FrameworkResults | ForEach-Object { $_.Controls })
$AllResources=@($FrameworkResults | ForEach-Object { $_.ResourceResults })
$CompleteChecks=0; $TotalChecks=0
foreach ($Projection in $FrameworkResults) { $CompleteChecks+=$Projection.EvidenceCompleteness.Complete; $TotalChecks+=$Projection.EvidenceCompleteness.Total }
$Compliance=[pscustomobject]@{
    Framework='Microsoft and NIST selected mappings'; FrameworkVersion='Microsoft 2025 DC / NIST Rev. 5.1'; ScopeNote='Two independently versioned, selected mapping packs. Microsoft 2025 is future-target context for older DCs; NIST organizational selection is unverified.'
    Disclaimer='Not a certification or a complete framework assessment. Context-only mappings do not establish failures. Organizational adoption of NIST controls is not verified.'
    Controls=$AllControls; ResourceResults=$AllResources; Mappings=@($FrameworkResults | ForEach-Object { $_.Mappings })
    EvidenceCompleteness=[pscustomobject]@{ Complete=$CompleteChecks; Total=$TotalChecks; Percent=if ($TotalChecks) { [math]::Round(100*$CompleteChecks/$TotalChecks,1) } else { 0 } }
    Counts=[pscustomobject]@{ Mapped=$AllControls.Count; Applicable=@($AllControls | Where-Object Applicability -eq Applicable).Count; ContextOnly=@($AllControls | Where-Object Applicability -eq ContextOnly).Count; Pass=@($AllControls | Where-Object Status -eq Pass).Count; Review=@($AllControls | Where-Object Status -eq Review).Count; Fail=@($AllControls | Where-Object Status -eq Fail).Count; NotTested=@($AllControls | Where-Object Status -eq NotTested).Count; PartiallyAssessed=@($AllControls | Where-Object Status -eq PartiallyAssessed).Count }
}
$Watch.Stop()
$Count=$Compliance.Counts
$ScopeText=if ($Sample) { 'Fictional sample | no live environment queried' } else { 'Provider snapshot projection | no additional collection' }
$Report=New-PSIReport -Title 'Selected AD Control Mapping' -Subtitle "$ScopeText | $($Compliance.FrameworkVersion)" -Layout Application -Theme $Theme
$Report | Add-Member -NotePropertyName PrintDisplay -NotePropertyValue @{
    ReportIdentity=@{ Kicker='PSInsightHTML / Selected control mapping' }; Scope=$Compliance.ScopeNote
    Profile=$Compliance.FrameworkVersion; CoveragePercent=$Compliance.EvidenceCompleteness.Percent
    TableSectionTitle='Control registers'; CoverFoot='Selected control mapping | Not a certification'
    Tables=@('framework-comparison','control-summary','control-register','resource-control-register','failed-controls','context-controls','control-evidence','mapping-register','crosswalk-register','coverage-register','method-register')
}
$Rows=@($Compliance.Controls | ForEach-Object { [pscustomobject]@{
    ControlId=$_.ControlId; Title=$_.Title; Framework=$_.Framework; Version=$_.FrameworkVersion; Mode=$_.EvaluationMode
    Status=([string]$_.Status -replace '^ContextOnly$','Context only'); Applicability=([string]$_.Applicability -replace '^ContextOnly$','Context only'); Reason=$_.ApplicabilityReason; MappingType=$_.MappingType; EvidencePercent=$_.EvidenceCompletenessPercent
    RuleIds=@($_.SourceRuleIds) -join ', '; Findings=$_.FindingIds.Count; Resources=$_.ResourceIds.Count
} })
$MappingRows=@(foreach ($Projection in $FrameworkResults) { foreach ($Mapping in $Projection.Mappings) { [pscustomobject]@{
    Framework=$Projection.Framework; Version=$Projection.FrameworkVersion; ControlId=$Mapping.ControlId; MappingId=if ($Mapping.MappingId) { $Mapping.MappingId } else { $Mapping.ControlId }
    Title=$Mapping.ControlTitle; MappingType=$Mapping.MappingType; Rules=@($Mapping.SourceRuleIds) -join ', '
    Confidence=$Mapping.MappingConfidence; Evidence=@($Mapping.EvidenceRequirements) -join ', '; Reference=$Mapping.Reference
} } })
$ComparisonRows=@($FrameworkResults | ForEach-Object { [pscustomobject]@{
    Framework=$_.Framework; Version=$_.FrameworkVersion; Mode=$_.EvaluationMode; Applicability=([string]$_.FrameworkApplicability -replace '^ContextOnly$','Context only')
    Selected=$_.Counts.Mapped; Applicable=$_.Counts.Applicable; ContextOnly=$_.Counts.ContextOnly; Pass=$_.Counts.Pass; Review=$_.Counts.Review; Fail=$_.Counts.Fail
    Partial=$_.Counts.PartiallyAssessed; NotTested=$_.Counts.NotTested; EvidencePercent=$_.EvidenceCompleteness.Percent
} })
$CrosswalkRows=@(foreach ($RuleId in @($MappingRows | ForEach-Object { $_.Rules -split ', ' } | Sort-Object -Unique)) {
    $Related=@($MappingRows | Where-Object { $RuleId -in @($_.Rules -split ', ') })
    if (@($Related.Framework | Sort-Object -Unique).Count -gt 1) { [pscustomobject]@{ PSIRule=$RuleId; MicrosoftControls=@($Related | Where-Object Framework -like 'Microsoft*' | ForEach-Object ControlId) -join ', '; NISTControls=@($Related | Where-Object Framework -like 'NIST*' | ForEach-Object ControlId) -join ', '; Note='Shared PSI observation; controls are not asserted equivalent' } }
})
$ResourceRows=@($Compliance.ResourceResults | ForEach-Object { [pscustomobject]@{
    Framework=$_.Framework; ControlId=$_.ControlId; Title=$_.Title; ResourceId=$_.ResourceId; OSVersion=$_.OSVersion; Status=([string]$_.Status -replace '^ContextOnly$','Context only'); Applicability=([string]$_.Applicability -replace '^ContextOnly$','Context only'); Reason=$_.ApplicabilityReason
    MappingType=$_.MappingType; EvidencePercent=$_.EvidenceCompletenessPercent; CheckIds=@($_.CheckIds) -join ', '
} })
$EvidenceRows=@(foreach ($Control in $Compliance.Controls) {
    foreach ($Id in $Control.EvidenceIds) {
        $Item=@($Security.Model.Evidence)+@($Health.Model.Evidence) | Where-Object Id -eq $Id | Select-Object -First 1
        if ($Item) { [pscustomobject]@{ Framework=$Control.Framework; ControlId=$Control.ControlId; EvidenceId=$Id; Title=$Item.Title; Source=$Item.Source; State=$Item.Data.CollectionState; ResourceIds=@($Item.ResourceIds) -join ', ' } }
    }
})
$CoverageRows=@($Compliance.Controls | ForEach-Object { [pscustomobject]@{
    Framework=$_.Framework; ControlId=$_.ControlId; Status=([string]$_.Status -replace '^ContextOnly$','Context only'); Applicability=([string]$_.Applicability -replace '^ContextOnly$','Context only'); Complete=$_.CompleteChecks; Applicable=$_.ApplicableChecks
    EvidencePercent=$_.EvidenceCompletenessPercent; Missing=$_.MissingChecks; MappingType=$_.MappingType
} })
$MethodRows=@(
    [pscustomobject]@{ Topic='Scope'; Explanation=$Compliance.ScopeNote },
    [pscustomobject]@{ Topic='Disclaimer'; Explanation=$Compliance.Disclaimer },
    [pscustomobject]@{ Topic='Framework coverage'; Explanation='Full catalog denominator is unavailable; no framework coverage percentage is claimed.' },
    [pscustomobject]@{ Topic='Evidence completeness'; Explanation='Complete mapped check outcomes divided by applicable mapped check outcomes. This is not an assessment score.' },
    [pscustomobject]@{ Topic='Applicability'; Explanation='OS and DC role are checked before evidence aggregation. Older DCs are context only for the Microsoft 2025 future target. Unknown facts remain NotTested; verified nonmatching scope is NotApplicable.' },
    [pscustomobject]@{ Topic='Aggregation'; Explanation='Applicable resources only: Fail, Review, PartiallyAssessed, NotTested, Pass. Partial mappings never Pass. Supporting mappings never determine result. Context-only resources cannot create Fail.' },
    [pscustomobject]@{ Topic='Exceptions'; Explanation='Exceptions are displayed as context and never change control status.' }
)
$Filter=Add-PSIFilter -Property Status -Values @('Pass','Review','Fail','NotTested','PartiallyAssessed','Context only','NotApplicable') -Label 'Control result'
$FrameworkFilter=Add-PSIFilter -Property Framework -Values @($FrameworkResults | ForEach-Object Framework) -Label 'Framework'
$ApplicabilityFilter=Add-PSIFilter -Property Applicability -Values @('Applicable','Context only','Unknown','NotApplicable') -Label 'Applicability'
$MappingFilter=Add-PSIFilter -Property MappingType -Values @('Direct','Partial','Supporting') -Label 'Mapping type'
$ResourceFilter=Add-PSIFilter -Property ResourceId -Values @($ResourceRows | ForEach-Object ResourceId | Sort-Object -Unique) -Label 'Resource'
$ControlFilter=Add-PSIFilter -Property ControlId -Values @($Rows | ForEach-Object ControlId | Sort-Object -Unique) -Label 'Control ID'
$StatusConditions=@(
    New-PSICondition -Property Status -Operator Equals -Value Pass -Status Healthy
    New-PSICondition -Property Status -Operator Equals -Value Review -Status Warning
    New-PSICondition -Property Status -Operator Equals -Value Fail -Status Critical
    New-PSICondition -Property Status -Operator Equals -Value NotTested -Status NotChecked
    New-PSICondition -Property Status -Operator Equals -Value PartiallyAssessed -Status Informational
    New-PSICondition -Property Status -Operator Equals -Value NotApplicable -Status Neutral
    New-PSICondition -Property Status -Operator Equals -Value 'Context only' -Status Informational
)
$null=$Report | Add-PSIView -Id overview -Title 'Overview' -Subtitle 'Selected control mapping, not certification' -Icon NavigationHome -Initial | Add-PSISection -Title 'Control mapping at a glance' | Add-PSIRow -Columns 12 | Add-PSIText -Text $Compliance.Disclaimer | Add-PSIRow -Columns 12 | Add-PSIKPI -Title 'Mapped controls' -Value $Count.Mapped -Subtitle 'Selected settings only' -Status Informational -Icon Document -Span 3 | Add-PSIKPI -Title 'Failed controls' -Value $Count.Fail -Subtitle 'Observed blocked mapped rule' -Status Critical -Icon SeverityError -Span 3 | Add-PSIKPI -Title 'Needs review' -Value $Count.Review -Subtitle 'Mapped rule requires review' -Status Warning -Icon SeverityWarning -Span 3 | Add-PSIKPI -Title 'Evidence complete' -Value "$($Compliance.EvidenceCompleteness.Percent)%" -Subtitle 'Mapped applicable checks; separate from score' -Status Informational -Icon Document -Span 3 | Add-PSIRow -Columns 12 | Add-PSITable -Id control-summary -Title 'Selected control outcomes' -Data $Rows -Columns @('ControlId','Title','Status','MappingType','EvidencePercent') -Filters @($Filter) -Conditions $StatusConditions -PageSize 10
$null=$Report | Add-PSIRow -Columns 12 | Add-PSIKPI -Title 'Applicable selected controls' -Value $Count.Applicable -Subtitle 'Technical scope matches' -Status Informational -Icon Document -Span 3 | Add-PSIKPI -Title 'Context only' -Value $Count.ContextOnly -Subtitle 'Future-target 2025 mappings' -Status Informational -Icon Document -Span 3 | Add-PSIKPI -Title 'Partly assessed' -Value $Count.PartiallyAssessed -Subtitle 'Partial mapping or evidence' -Status Informational -Icon Document -Span 3 | Add-PSIKPI -Title 'Not tested' -Value $Count.NotTested -Subtitle 'Unknown applicability or evidence' -Status NotChecked -Icon Document -Span 3
$null=$Report | Add-PSIRow -Columns 12 | Add-PSITable -Id overview-frameworks -Title 'Selected framework versions and evaluation modes' -Data $ComparisonRows -Columns @('Framework','Version','Mode','Applicability','Selected','Applicable','ContextOnly','Pass','Review','Fail','Partial','NotTested','EvidencePercent') -ColumnLabels @{ ContextOnly='Context only'; NotTested='Not tested'; EvidencePercent='Evidence %' } -PageSize 10
$null=$Report | Add-PSIView -Id frameworks -Title 'Frameworks' -Subtitle "$($Compliance.Framework) | $($Compliance.FrameworkVersion)" -Icon Document | Add-PSISection -Title 'Reference and scope' | Add-PSIRow -Columns 12 | Add-PSIText -Text "$($Compliance.Framework) - $($Compliance.FrameworkVersion). $($Compliance.ScopeNote) $($Compliance.Disclaimer)" | Add-PSIRow -Columns 12 | Add-PSITable -Id method-register -Title 'Scope, method and limitations' -Data $MethodRows -Columns @('Topic','Explanation') -PageSize 10
$null=$Report | Add-PSIView -Id framework-comparison -Title 'Framework Comparison' -Subtitle 'Selected control slices have different breadth and target versions' -Icon Document | Add-PSISection -Title 'Framework selection and applicability' | Add-PSIRow -Columns 12 | Add-PSIText -Text 'Microsoft 2025 is a future target for this fictional 2016/2019 estate. NIST controls are technical cross-references, not an organizational certification claim.' | Add-PSIRow -Columns 12 | Add-PSITable -Id framework-comparison -Title 'Version-pinned selected mappings' -Data $ComparisonRows -Columns @('Framework','Version','Mode','Applicability','Selected','Applicable','ContextOnly','Pass','Review','Fail','Partial','NotTested','EvidencePercent') -ColumnLabels @{ ContextOnly='Context only'; NotTested='Not tested'; EvidencePercent='Evidence %' } -PageSize 10
$null=$Report | Add-PSIView -Id controls -Title 'Controls' -Subtitle 'Search, sort and filter the selected controls' -Icon Rules | Add-PSISection -Title 'Control register' | Add-PSIRow -Columns 12 | Add-PSITable -Id control-register -Title 'Selected control register' -Data $Rows -Columns @('Framework','Version','ControlId','Title','Status','Applicability','MappingType','EvidencePercent','RuleIds','Findings','Resources') -Filters @($FrameworkFilter,$Filter,$ApplicabilityFilter,$MappingFilter,$ControlFilter) -Conditions $StatusConditions -PageSize 10
$null=$Report | Add-PSIRow -Columns 12 | Add-PSITable -Id resource-control-register -Title 'Per-resource mapped outcomes' -Data $ResourceRows -Columns @('Framework','ControlId','ResourceId','OSVersion','Status','Applicability','Reason','MappingType','EvidencePercent','CheckIds') -Filters @($FrameworkFilter,$Filter,$ApplicabilityFilter,$MappingFilter,$ResourceFilter,$ControlFilter) -Conditions $StatusConditions -PageSize 15
if ($Count.ContextOnly) { $null=$Report | Add-PSIView -Id context-only -Title 'Context Only' -Subtitle 'Future-target mappings are not current failures' -Icon Document -Group Investigation | Add-PSISection -Title '2025 future-state control context' | Add-PSIRow -Columns 12 | Add-PSITable -Id context-controls -Title 'Context-only selected controls' -Data @($Rows | Where-Object Applicability -eq 'Context only') -Columns @('Framework','ControlId','Title','Status','Applicability','Reason','RuleIds') -Filters @($FrameworkFilter,$ControlFilter) -Conditions $StatusConditions -PageSize 10 }
if ($Count.Fail) { $null=$Report | Add-PSIView -Id failed-controls -Title 'Failed Controls' -Subtitle 'Observed blocked PSI rules' -Icon SeverityError -Group Investigation | Add-PSISection -Title 'Control gaps' | Add-PSIRow -Columns 12 | Add-PSITable -Id failed-controls -Title 'Failed selected controls' -Data @($Rows | Where-Object Status -eq Fail) -Columns @('ControlId','Title','Status','RuleIds','Findings','Resources') -Conditions $StatusConditions -PageSize 10 }
if ($Count.Review) { $null=$Report | Add-PSIView -Id review-controls -Title 'Review Controls' -Subtitle 'Mapped observations requiring review' -Icon SeverityWarning -Group Investigation | Add-PSISection -Title 'Review register' | Add-PSIRow -Columns 12 | Add-PSITable -Id review-controls -Title 'Review selected controls' -Data @($Rows | Where-Object Status -eq Review) -Columns @('ControlId','Title','Status','RuleIds') -Conditions $StatusConditions -PageSize 10 }
if ($Count.NotTested -or $Count.PartiallyAssessed) { $null=$Report | Add-PSIView -Id unassessed-controls -Title 'Unassessed Controls' -Subtitle 'Missing evidence and partial mapping coverage' -Icon Document -Group Investigation | Add-PSISection -Title 'Evidence gaps' | Add-PSIRow -Columns 12 | Add-PSITable -Id unassessed-controls -Title 'Not tested or partly assessed' -Data @($Rows | Where-Object { $_.Status -in @('NotTested','PartiallyAssessed') }) -Columns @('ControlId','Title','Status','EvidencePercent','RuleIds') -Conditions $StatusConditions -PageSize 10 }
$null=$Report | Add-PSIView -Id mapped-rules -Title 'Mapped Rules' -Subtitle 'Provider rule IDs and published references' -Icon Rules -Group Investigation | Add-PSISection -Title 'Mapping register' | Add-PSIRow -Columns 12 | Add-PSITable -Id mapping-register -Title 'Rule to control mappings' -Data $MappingRows -Columns @('Framework','Version','ControlId','MappingId','Title','MappingType','Rules','Confidence','Evidence','Reference') -Filters @($FrameworkFilter,$MappingFilter,$ControlFilter) -PageSize 10
$null=$Report | Add-PSIView -Id crosswalk -Title 'Crosswalk' -Subtitle 'Shared PSI rules, not equivalent external controls' -Icon Rules -Group Investigation | Add-PSISection -Title 'Cross-framework rule reuse' | Add-PSIRow -Columns 12 | Add-PSITable -Id crosswalk-register -Title 'Shared rule references' -Data $CrosswalkRows -Columns @('PSIRule','MicrosoftControls','NISTControls','Note') -PageSize 10
$null=$Report | Add-PSIView -Id evidence -Title 'Evidence' -Subtitle 'Linked IDs refer to the existing Security and Health evidence models' -Icon Document -Group Investigation | Add-PSISection -Title 'Linked evidence' | Add-PSIRow -Columns 12 | Add-PSITable -Id control-evidence -Title 'Control evidence links' -Data $EvidenceRows -Columns @('ControlId','EvidenceId','Title','Source','State','ResourceIds') -PageSize 15
$null=$Report | Add-PSIView -Id coverage -Title 'Coverage' -Subtitle 'Mapped controls and evidence completeness are separate measures' -Icon Document -Group Investigation | Add-PSISection -Title 'Coverage method' | Add-PSIRow -Columns 12 | Add-PSIText -Text "Selected mapped controls: $($Count.Mapped). Full framework catalog coverage: not measured. Mapped check evidence complete: $($Compliance.EvidenceCompleteness.Complete)/$($Compliance.EvidenceCompleteness.Total) ($($Compliance.EvidenceCompleteness.Percent)%). Security score and Health score are separate assessments." | Add-PSIRow -Columns 12 | Add-PSITable -Id coverage-register -Title 'Mapped check completeness' -Data $CoverageRows -Columns @('ControlId','Status','Complete','Applicable','EvidencePercent','Missing','MappingType') -Conditions $StatusConditions -PageSize 10
foreach ($Control in $Compliance.Controls) {
    $ViewId=$Control.Id
    $Detail=@([pscustomobject]@{ Field='Framework'; Value="$($Control.Framework) $($Control.FrameworkVersion)" },[pscustomobject]@{ Field='Evaluation mode'; Value=$Control.EvaluationMode },[pscustomobject]@{ Field='Control'; Value="$($Control.ControlId) - $($Control.Title)" },[pscustomobject]@{ Field='Description'; Value=$Control.Description },[pscustomobject]@{ Field='Result'; Value=$Control.Status },[pscustomobject]@{ Field='Applicability'; Value=$Control.Applicability },[pscustomobject]@{ Field='Applicability reason'; Value=$Control.ApplicabilityReason },[pscustomobject]@{ Field='Evidence completeness'; Value="$($Control.EvidenceCompletenessPercent)%" },[pscustomobject]@{ Field='Mapping'; Value="$($Control.MappingType) / $($Control.MappingConfidence)" },[pscustomobject]@{ Field='Rules'; Value=@($Control.SourceRuleIds) -join ', ' },[pscustomobject]@{ Field='Evidence IDs'; Value=@($Control.EvidenceIds) -join ', ' },[pscustomobject]@{ Field='Finding IDs'; Value=@($Control.FindingIds) -join ', ' },[pscustomobject]@{ Field='Resource IDs'; Value=@($Control.ResourceIds) -join ', ' },[pscustomobject]@{ Field='Exceptions'; Value=@($Control.Exceptions | ForEach-Object Id) -join ', ' },[pscustomobject]@{ Field='Reference'; Value=$Control.Reference },[pscustomobject]@{ Field='Limit'; Value=$Control.Notes })
    foreach ($DetailRow in $Detail) {
        if ($DetailRow.Field -in @('Result','Applicability')) { $DetailRow.Value=([string]$DetailRow.Value -replace '^ContextOnly$','Context only') }
        if ($DetailRow.Field -eq 'Evidence completeness' -and $DetailRow.Value -eq '%') { $DetailRow.Value='Unavailable: no applicable checks' }
    }
    $LinkChecks=@(@($Security.Assessment.Checks)+@($Health.Assessment.Checks) | Where-Object { $_.Id -in $Control.CheckIds } | ForEach-Object { [pscustomobject]@{ CheckId=$_.Id; RuleId=$_.Metadata.RuleId; Status=$_.Status; Observed=$_.ObservedState; ResourceIds=@($_.ResourceIds) -join ', '; EvidenceIds=@($_.EvidenceIds) -join ', ' } })
    $LinkFindings=@(@($Security.Model.Findings)+@($Health.Model.Findings) | Where-Object { $_.Id -in $Control.FindingIds } | ForEach-Object { [pscustomobject]@{ FindingId=$_.Id; Title=$_.Title; Severity=$_.Severity; Summary=$_.Summary; EvidenceIds=@($_.EvidenceIds) -join ', ' } })
    $LinkEvidence=@(@($Security.Model.Evidence)+@($Health.Model.Evidence) | Where-Object { $_.Id -in $Control.EvidenceIds } | ForEach-Object { [pscustomobject]@{ EvidenceId=$_.Id; Title=$_.Title; Source=$_.Source; CollectionState=$_.Data.CollectionState; Summary=$_.Summary } })
    $LinkResources=@(@($Security.Model.Resources)+@($Health.Model.Resources) | Where-Object { $_.Id -in $Control.ResourceIds } | Sort-Object Id -Unique | ForEach-Object { [pscustomobject]@{ ResourceId=$_.Id; Name=$_.Name; Type=$_.Type; Status=$_.Status } })
    $Commands=@(@{ Label='Open evidence register'; Icon='Document'; TargetView='evidence' },@{ Label='Open control register'; Icon='Rules'; TargetView='controls' })
    $ControlResourceRows=@($ResourceRows | Where-Object { $_.Framework -eq $Control.Framework -and $_.ControlId -eq $Control.ControlId })
    $null=$Report | Add-PSIView -Id $ViewId -Title "$($Control.ControlId) - $($Control.Title)" -Subtitle "$($Control.Framework) | Mapped rules: $(@($Control.SourceRuleIds) -join ', ')" -Icon Document -Group Controls -Commands $Commands | Add-PSISection -Title 'Control detail' | Add-PSIRow -Columns 12 | Add-PSITable -Id "$ViewId-detail" -Title 'Mapping, result and references' -Data $Detail -Columns @('Field','Value') -PageSize 20 | Add-PSIRow -Columns 12 | Add-PSITable -Id "$ViewId-applicability" -Title 'Resource applicability and result' -Data $ControlResourceRows -Columns @('ResourceId','OSVersion','Applicability','Reason','Status','EvidencePercent') -Conditions $StatusConditions -PageSize 12 | Add-PSIRow -Columns 12 | Add-PSITable -Id "$ViewId-checks" -Title 'Linked PSI checks' -Data $LinkChecks -Columns @('CheckId','RuleId','Status','Observed','ResourceIds','EvidenceIds') -PageSize 12 | Add-PSIRow -Columns 12 | Add-PSITable -Id "$ViewId-findings" -Title 'Linked findings' -Data $LinkFindings -Columns @('FindingId','Title','Severity','Summary','EvidenceIds') -PageSize 10 | Add-PSIRow -Columns 12 | Add-PSITable -Id "$ViewId-evidence" -Title 'Linked evidence references' -Data $LinkEvidence -Columns @('EvidenceId','Title','Source','CollectionState','Summary') -PageSize 12 | Add-PSIRow -Columns 12 | Add-PSITable -Id "$ViewId-resources" -Title 'Affected resources' -Data $LinkResources -Columns @('ResourceId','Name','Type','Status') -PageSize 12
}
if (@($Compliance.Controls | ForEach-Object { $_.Exceptions }).Count) {
    $ExceptionRows=@($Compliance.Controls | ForEach-Object { $Id=$_.ControlId; $_.Exceptions | ForEach-Object { [pscustomobject]@{ ControlId=$Id; ExceptionId=$_.Id; Title=$_.Title; Status=$_.Status; Reason=$_.Reason } } })
    $null=$Report | Add-PSIView -Id exceptions -Title 'Exceptions' -Subtitle 'Decision context does not erase observed failures' -Icon Document -Group Investigation | Add-PSISection -Title 'Linked exceptions' | Add-PSIRow -Columns 12 | Add-PSITable -Id control-exceptions -Title 'Exception context' -Data $ExceptionRows -Columns @('ControlId','ExceptionId','Title','Status','Reason') -PageSize 10
}
if (-not $OutputPath) { $OutputPath=Join-Path $ModuleRoot 'Reports/Compliance' }
$null=New-Item -Path $OutputPath -ItemType Directory -Force
$HtmlPath=Join-Path $OutputPath $(if ($Sample) { 'ADCompliance-Sample.html' } else { 'ADCompliance-Mocked.html' })
$null=Export-PSIReport -Report $Report -Path $HtmlPath
if (-not $NoBrowser) { try { if ($env:OS -eq 'Windows_NT') { Start-Process $HtmlPath } elseif (Get-Command open -ErrorAction SilentlyContinue) { & open $HtmlPath } } catch { Write-Warning "Report generated but browser opening failed: $($_.Exception.Message)" } }
if ($PassThru) { [pscustomobject]@{ Snapshot=$Snapshot; Security=$Security; Health=$Health; Compliance=$Compliance; FrameworkResults=$FrameworkResults; Report=$Report; HtmlPath=$HtmlPath; EvaluationMilliseconds=$Watch.ElapsedMilliseconds } } else { $HtmlPath }
