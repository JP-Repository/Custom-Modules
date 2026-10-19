function Test-PSIADSecurity {
    <# .SYNOPSIS Assess one shared normalized snapshot and its Security evidence without collection. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject] $Snapshot,
        [Parameter(Mandatory)][pscustomobject] $SecurityEvidence,
        [hashtable] $ThresholdOverrides=@{},
        [object[]] $Exceptions=@()
    )
    if ($SecurityEvidence.Kind -ne 'ActiveDirectory.SecurityEvidence' -or @($Snapshot.Domains).Count -ne 1 -or $SecurityEvidence.Domain -ne $Snapshot.Domains[0].Name) { throw 'Security assessment requires matching normalized snapshot and Security evidence.' }
    $RulesRoot=Join-Path $PSScriptRoot '../../Rules/Security'
    $Pack=Import-PowerShellDataFile (Join-Path $RulesRoot 'SecurityRules.psd1')
    $Thresholds=Import-PowerShellDataFile (Join-Path $RulesRoot 'Thresholds.psd1')
    foreach ($Key in $ThresholdOverrides.Keys) {
        if (-not $Thresholds.ContainsKey($Key) -or $Key -in @('Version','Source')) { throw "Unknown or read-only Security threshold '$Key'." }
        if ($ThresholdOverrides[$Key] -isnot [ValueType] -or [double]$ThresholdOverrides[$Key] -le 0) { throw "Security threshold '$Key' must be a positive number." }
        $Thresholds[$Key]=[double]$ThresholdOverrides[$Key]
    }
    if ([double]$Thresholds.ReviewScoreMinimum -gt [double]$Thresholds.ReadyScoreMinimum -or [double]$Thresholds.ReadyScoreMinimum -gt 100) { throw 'Security score threshold ordering is invalid.' }
    $Inventory=New-PSIADDCInventoryModel -Snapshot $Snapshot
    $Presentation=New-PSIADDCInventoryPresentation -Snapshot $Snapshot -Inventory $Inventory
    $Resources=@($Presentation.Model.Resources)
    $ResourceByName=@{}; $ResourceById=@{}
    foreach ($Resource in $Resources) { $ResourceById[$Resource.Id]=$Resource; if ($Resource.Type -eq 'Domain Controller') { $ResourceByName[$Resource.Name]=$Resource } }
    $Evidence=[System.Collections.Generic.List[object]]::new()
    foreach ($Item in @($Presentation.Model.Evidence)) { $Evidence.Add($Item) }
    $EvidenceByObservation=[System.Collections.Generic.Dictionary[object,string]]::new()
    $Index=0
    foreach ($Observation in @($SecurityEvidence.Observations)) {
        $Index++; $Id="security-observation-$Index"
        $ResourceId=if ($ResourceByName.ContainsKey([string]$Observation.DC)) { $ResourceByName[[string]$Observation.DC].Id } else { 'domain' }
        $Summary="$($Observation.CollectionState): $(if ($null -eq $Observation.Value) { 'No attributable value' } else { [string]$Observation.Value })"
        $Record=New-PSIEvidenceRecord -Definition @{ Id=$Id; Title="$($Observation.RuleId) / $($Observation.DC)"; Type=[string]$Observation.EvidenceType; Source=[string]$Observation.CollectionMethod; CollectedAt=[datetime]$Observation.Timestamp; Summary=$Summary; Data=@{ CollectionState=$Observation.CollectionState; Confidence=$Observation.Confidence; Value=$Observation.Value; RuleId=$Observation.RuleId; SourceType=$Observation.SourceType; ErrorClass=$Observation.ErrorClass; QueryWindowHours=$Observation.QueryWindowHours }; ResourceIds=@($ResourceId); Metadata=@{ CollectionState=$Observation.CollectionState; Scope=$Observation.DC; Confidence=$Observation.Confidence; Provenance=$Observation.Source; SourceType=$Observation.SourceType } }
        $Evidence.Add($Record); $EvidenceByObservation.Add($Observation,$Id)
        $ResourceById[$ResourceId].EvidenceIds=@($ResourceById[$ResourceId].EvidenceIds)+@($Id)
    }
    $Findings=[System.Collections.Generic.List[object]]::new(); $Checks=[System.Collections.Generic.List[object]]::new(); $RuleDefinitions=[System.Collections.Generic.List[object]]::new()
    foreach ($Rule in @($Pack.Rules)) {
        $Definition=[ordered]@{ Id=$Rule.Id; Title=$Rule.Title; Category=$Rule.Category; Description="Security interpretation of $($Rule.Title.ToLowerInvariant()) evidence."; Applicability=$Rule.Scope; EvidenceRequirements=@($Rule.Evidence); Evaluation=if ($Rule.Threshold) { 'Threshold' } else { 'Explicit value classification' }; Outcome=@('Ready','Review','Blocked','NotTested','NotApplicable'); Severity='Rule-defined'; Weight=[double]$Rule.Weight; Recommendation=$Rule.Recommendation; Validation=$Rule.Validation; Source=$Pack.SourceCategory; Version=$Pack.Version; Tags=@('ActiveDirectory','Security',$Rule.Category) }
        $RuleDefinitions.Add([pscustomobject]$Definition)
        $Targets=if ($Rule.Scope -eq 'Domain') { @([pscustomobject]@{ Name=$SecurityEvidence.Domain }) } else { @($Snapshot.DomainControllers) }
        foreach ($DC in $Targets) {
            $ResourceId=if ($Rule.Scope -eq 'Domain') { 'domain' } else { [string]$ResourceByName[[string]$DC.Name].Id }
            $CheckId="security-check-$($Rule.Id)-$ResourceId"; $FindingId="security-finding-$($Rule.Id)-$ResourceId"
            $Outcome=Get-PSIADSecurityRuleOutcome -Rule $Rule -Observations @($SecurityEvidence.Observations) -Thresholds $Thresholds -DC $(if ($Rule.Scope -eq 'Domain') { $null } else { $DC }) -Domain $SecurityEvidence.Domain
            $EvidenceIds=@($Outcome.Observations | ForEach-Object { $EvidenceByObservation[$_] } | Where-Object { $_ } | Sort-Object -Unique)
            $HasFinding=$Outcome.Status -in @('Review','Blocked','NotTested')
            $Severity=if ($Outcome.Status -eq 'Blocked') { 'Critical' } elseif ($Outcome.Status -eq 'Review') { 'Warning' } elseif ($Outcome.Status -eq 'NotTested') { 'Info' } else { 'Healthy' }
            $Name="$($Rule.Title) / $($DC.Name)"
            if ($HasFinding) {
                $Finding=New-PSIApplicationFinding -Definition @{ Id=$FindingId; Title=$Name; Summary=$Outcome.Observed; Severity=$Severity; Status=if ($Outcome.Status -eq 'NotTested') { 'NotTested' } else { 'Open' }; Category=$Rule.Category; ReadinessImpact=$Outcome.Expected; AffectedResourceIds=@($ResourceId); EvidenceIds=$EvidenceIds; Recommendation=@{ Action=$Rule.Recommendation; ExpectedState=$Outcome.Expected; AutomationHint='Guidance only; no change executed' }; Validation=@{ Method=$Rule.Validation; ExpectedResult=$Outcome.Expected; Status='NotTested' }; Frameworks=@($Pack.SourceCategory); Tags=@('Security',$Rule.Category); Metadata=@{ RuleId=$Rule.Id; Version=$Pack.Version; Source=$Pack.SourceCategory; CheckId=$CheckId } }
                $Findings.Add($Finding); $ResourceById[$ResourceId].FindingIds=@($ResourceById[$ResourceId].FindingIds)+@($FindingId)
                foreach ($Record in @($Evidence | Where-Object { $_.Id -in $EvidenceIds })) { $Record.FindingIds=@($Record.FindingIds)+@($FindingId) }
            }
            $Checks.Add((New-PSIAssessmentCheck -Definition @{ Id=$CheckId; Name=$Name; Description=$Definition.Description; CategoryId=$Rule.Category; Status=$Outcome.Status; Severity=$Severity; Weight=[double]$Rule.Weight; IsBlocking=($Outcome.Status -eq 'Blocked'); ObservedState=$Outcome.Observed; ExpectedState=$Outcome.Expected; FindingIds=if ($HasFinding) { @($FindingId) } else { @() }; ResourceIds=@($ResourceId); EvidenceIds=$EvidenceIds; Recommendation=@{ Action=$Rule.Recommendation; ExpectedState=$Outcome.Expected; AutomationHint='Read-only guidance' }; Validation=@{ Method=$Rule.Validation; ExpectedResult=$Outcome.Expected; Status='NotTested' }; Frameworks=@($Pack.SourceCategory); Tags=@('Security',$Rule.Category); Metadata=@{ RuleId=$Rule.Id; RuleVersion=$Pack.Version; Source=$Pack.SourceCategory; EvidenceRequirements=@($Rule.Evidence); Scope=$Rule.Scope; RequiredForDC=$true } }))
        }
    }
    $DCStates=[System.Collections.Generic.List[object]]::new()
    foreach ($DC in @($Snapshot.DomainControllers)) {
        $Resource=$ResourceByName[[string]$DC.Name]
        $Member=@($Checks | Where-Object { $Resource.Id -in $_.ResourceIds })
        $Status=if (@($Member | Where-Object Status -eq Blocked).Count) { 'Critical' } elseif (@($Member | Where-Object Status -eq Review).Count) { 'Warning' } elseif (@($Member | Where-Object Status -eq NotTested).Count) { 'NotChecked' } elseif (@($Member | Where-Object Status -eq Ready).Count) { 'Healthy' } else { 'Unknown' }
        $Resource.Status=$Status; $Resource.Properties.Domain=$DC.Domain
        $Resource.Properties.SecurityChecks=$Member.Count; $Resource.Properties.CriticalFindings=@($Member | Where-Object Status -eq Blocked).Count; $Resource.Properties.ReviewFindings=@($Member | Where-Object Status -eq Review).Count; $Resource.Properties.NotTestedChecks=@($Member | Where-Object Status -eq NotTested).Count
        foreach ($Category in @($Pack.Categories)) {
            $CategoryChecks=@($Member | Where-Object CategoryId -eq $Category.Id)
            $CategoryStatus=if (@($CategoryChecks | Where-Object Status -eq Blocked).Count) { 'Critical' } elseif (@($CategoryChecks | Where-Object Status -eq Review).Count) { 'Review' } elseif (@($CategoryChecks | Where-Object Status -eq NotTested).Count) { 'Not Tested' } elseif (@($CategoryChecks | Where-Object Status -eq Ready).Count) { 'Secure' } else { 'Not Applicable' }
            $PropertyName='Security'+$Category.Id.Substring(0,1).ToUpperInvariant()+$Category.Id.Substring(1)
            $Resource.Properties[$PropertyName]=$CategoryStatus
        }
        $DCStates.Add([pscustomobject]@{ DC=$DC.Name; Site=$DC.Site; Domain=$DC.Domain; Status=$Status; Critical=$Resource.Properties.CriticalFindings; Review=$Resource.Properties.ReviewFindings; NotTested=$Resource.Properties.NotTestedChecks; ResourceId=$Resource.Id })
    }
    $Categories=@(foreach ($Category in @($Pack.Categories)) {
        $Members=@($Checks | Where-Object CategoryId -eq $Category.Id)
        New-PSIAssessmentCategory -Definition @{ Id=$Category.Id; Name=$Category.Name; Icon=$Category.Icon; Weight=[double]$Category.Weight; Description="Observed $($Category.Name) security condition"; CheckIds=@($Members | ForEach-Object Id); FindingIds=@($Members | ForEach-Object { $_.FindingIds } | Where-Object { $_ } | Sort-Object -Unique); ResourceIds=@($Members | ForEach-Object { $_.ResourceIds } | Where-Object { $_ } | Sort-Object -Unique) }
    })
    $TopologyNodes=@(foreach ($Node in @($Presentation.TopologyNodes)) { if ($Node.ResourceId -and $ResourceById.ContainsKey([string]$Node.ResourceId)) { $Resource=$ResourceById[[string]$Node.ResourceId]; @{ NodeId=$Node.NodeId; ResourceId=$Node.ResourceId; Icon='ResourceServer'; Description="Site: $($Resource.Properties.Site); Security: $($Resource.Status)" } } else { $Node } })
    $TopologyEdges=@(foreach ($Edge in @($Presentation.TopologyEdges)) { $Copy=@{}; foreach ($Key in $Edge.Keys) { $Copy[$Key]=$Edge[$Key] }; $Copy.Status='Unknown'; $Copy.Description='Replication relationship is operational context, not a Security control assessment.'; $Copy })
    $Model=New-PSIApplicationModel -Resources $Resources -Evidence $Evidence.ToArray() -Findings $Findings.ToArray() -Relationships @($Presentation.Model.Relationships)
    $Assessment=New-PSIApplicationAssessment -Definition @{ Id='ad-security'; Name='Active Directory Security'; Description='Provider-owned interpretation of one shared snapshot and explicit Security observations.'; AssessmentType='Security'; Target=$SecurityEvidence.Domain; Profile="Security rule pack $($Pack.Version)"; Scope="$($SecurityEvidence.Domain); $(@($Snapshot.DomainControllers).Count) DCs"; GeneratedAt=$Snapshot.CollectedAt; Categories=$Categories; Checks=$Checks.ToArray(); FindingIds=@($Findings | ForEach-Object Id); ResourceIds=@($Resources | ForEach-Object Id); EvidenceIds=@($Evidence | ForEach-Object Id); Recommendations=@('Prioritize observed critical exposure; validate incomplete evidence and dependencies before changing policy.'); Exceptions=$Exceptions; Metadata=@{ RulePackVersion=$Pack.Version; Thresholds=$Thresholds; EvidenceCoveragePercent=$SecurityEvidence.EvidenceCompleteness.Percent; SharedCollectionCoveragePercent=$SecurityEvidence.CollectionCoverage.OverallPercent; Source=$Snapshot.Source; Print=@{ MethodologyText='One normalized snapshot, explicit Security evidence states and provider-owned versioned rules. Missing evidence remains Not Tested; a score cannot override a critical condition.' }; PrintDisplay=@{ ReportIdentity=@{ Kicker='PSInsightHTML / Active Directory Security' }; Scope=$SecurityEvidence.Domain; Profile="Security rule pack $($Pack.Version)"; CoveragePercent=$SecurityEvidence.EvidenceCompleteness.Percent; Resources=@{ Columns=@(@{Property='Name';Label='Resource'},@{Property='Type';Label='Type'},@{Property='Site';Label='Site'},@{Property='Status';Label='Security';Format='Status'}) } } }; ReadyScoreMinimum=[double]$Thresholds.ReadyScoreMinimum; ReviewScoreMinimum=[double]$Thresholds.ReviewScoreMinimum }
    $Validation=New-PSIReport -Title 'Security contract validation' -Layout Application
    $null=$Validation | Set-PSIApplicationModel -Model $Model | Set-PSIApplicationAssessment -Assessment $Assessment
    $Decision=$Validation.ApplicationAssessment.Decision
    $Verdict=switch ($Decision) { Ready { 'Secure' } ReadyWithReview { 'Review' } ReviewRequired { 'Review' } NotReady { 'Critical' } default { 'Incomplete' } }
    [pscustomobject]@{ Snapshot=$Snapshot; SecurityEvidence=$SecurityEvidence; Inventory=$Inventory; RulePack=$Pack; RuleDefinitions=$RuleDefinitions.ToArray(); Thresholds=$Thresholds; Model=$Model; Assessment=$Validation.ApplicationAssessment; SecurityVerdict=$Verdict; DCStates=$DCStates.ToArray(); TreeNodes=$Presentation.TreeNodes; TopologyNodes=$TopologyNodes; TopologyEdges=$TopologyEdges }
}
