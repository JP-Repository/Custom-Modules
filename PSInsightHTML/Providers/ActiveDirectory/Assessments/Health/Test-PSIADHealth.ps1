function Test-PSIADHealth {
    <# .SYNOPSIS Assess one normalized snapshot and its existing Health evidence, without collection. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject] $Snapshot,
        [Parameter(Mandatory)][pscustomobject] $HealthEvidence,
        [hashtable] $ThresholdOverrides=@{},
        [object[]] $Exceptions=@()
    )
    if ($HealthEvidence.Kind -ne 'ActiveDirectory.HealthEvidence' -or @($Snapshot.Domains).Count -ne 1 -or $HealthEvidence.Domain -ne $Snapshot.Domains[0].Name) { throw 'Health assessment requires matching normalized snapshot and Health evidence.' }
    $RulesRoot=Join-Path $PSScriptRoot '../../Rules/Health'
    $Pack=Import-PowerShellDataFile (Join-Path $RulesRoot 'HealthRules.psd1')
    $Thresholds=Import-PowerShellDataFile (Join-Path $RulesRoot 'Thresholds.psd1')
    foreach ($Key in $ThresholdOverrides.Keys) {
        if (-not $Thresholds.ContainsKey($Key) -or $Key -in @('Version','Source')) { throw "Unknown or read-only Health threshold '$Key'." }
        if ($ThresholdOverrides[$Key] -isnot [ValueType] -or [double]$ThresholdOverrides[$Key] -le 0) { throw "Health threshold '$Key' must be a positive number." }
        $Thresholds[$Key]=[double]$ThresholdOverrides[$Key]
    }
    if ([double]$Thresholds.DiskCriticalFreeGB -ge [double]$Thresholds.DiskReviewFreeGB -or [double]$Thresholds.BackupHealthyDays -ge [double]$Thresholds.BackupCriticalDays -or [double]$Thresholds.ReviewScoreMinimum -gt [double]$Thresholds.ReadyScoreMinimum) { throw 'Health threshold ordering is invalid.' }
    $Inventory=New-PSIADDCInventoryModel -Snapshot $Snapshot
    $Presentation=New-PSIADDCInventoryPresentation -Snapshot $Snapshot -Inventory $Inventory
    $Resources=@($Presentation.Model.Resources)
    $ResourceByName=@{}; $ResourceById=@{}
    foreach ($Resource in $Resources) { $ResourceById[$Resource.Id]=$Resource; if ($Resource.Type -eq 'Domain Controller') { $ResourceByName[$Resource.Name]=$Resource } }
    $Evidence=[System.Collections.Generic.List[object]]::new()
    foreach ($InventoryEvidence in @($Presentation.Model.Evidence)) { $Evidence.Add($InventoryEvidence) }
    $EvidenceByObservation=[System.Collections.Generic.Dictionary[object,string]]::new()
    $Index=0
    foreach ($Observation in @($HealthEvidence.Observations)) {
        $Index++; $Id="health-observation-$Index"
        $ResourceId=if ($ResourceByName.ContainsKey([string]$Observation.DC)) { $ResourceByName[[string]$Observation.DC].Id } else { 'domain' }
        $ValueText=if ($null -eq $Observation.Value) { 'No value' } elseif ($Observation.Value -is [array]) { "$(@($Observation.Value).Count) values" } elseif ($Observation.Value -is [ValueType] -or $Observation.Value -is [string]) { [string]$Observation.Value } else { 'Structured observation' }
        $Record=New-PSIEvidenceRecord -Definition @{ Id=$Id; Title="$($Observation.Type) / $($Observation.DC)"; Type=[string]$Observation.Type; Source=[string]$Observation.CollectionMethod; CollectedAt=[datetime]$Observation.Timestamp; Summary="$($Observation.CollectionState): $ValueText"; Data=@{ CollectionState=$Observation.CollectionState; Collector=$Observation.Collector; Confidence=$Observation.Confidence; ErrorClass=$Observation.ErrorClass; Value=$Observation.Value }; ResourceIds=@($ResourceId); Metadata=@{ CollectionState=$Observation.CollectionState; Scope=$Observation.DC; Confidence=$Observation.Confidence } }
        $Evidence.Add($Record); $EvidenceByObservation.Add($Observation,$Id)
        $ResourceById[$ResourceId].EvidenceIds=@($ResourceById[$ResourceId].EvidenceIds)+@($Id)
    }
    $Findings=[System.Collections.Generic.List[object]]::new(); $Checks=[System.Collections.Generic.List[object]]::new()
    $RuleDefinitions=[System.Collections.Generic.List[object]]::new()
    $RuleIndex=0
    foreach ($Rule in @($Pack.Rules)) {
        $RuleIndex++
        $Definition=[ordered]@{ Id=$Rule.Id; Title=$Rule.Title; Category=$Rule.Category; Description="Operational interpretation of $($Rule.Title.ToLowerInvariant()) evidence."; Applicability=$Rule.Scope; EvidenceRequirements=@($Rule.EvidenceRequirements); Evaluation=$Rule.Evaluation; Outcome=@('Ready','Review','Blocked','NotTested','NotApplicable'); Severity=if ($Rule.Critical) { 'Critical on threshold breach' } else { 'Warning on threshold breach' }; Weight=[double]$Rule.Weight; RequiredForDC=($Rule.RequiredForDC -ne $false); Recommendation=$Rule.Recommendation; Validation=$Rule.Validation; Source=$Pack.SourceCategory; Version=$Pack.Version; Tags=@('ActiveDirectory','Health',$Rule.Category) }
        $RuleDefinitions.Add([pscustomobject]$Definition)
        $Targets=if ($Rule.Scope -eq 'Domain') { @($null) } else { @($Snapshot.DomainControllers) }
        foreach ($DC in $Targets) {
            $Suffix=if ($null -eq $DC) { 'domain' } else { [string]$ResourceByName[[string]$DC.Name].Id }
            $CheckId="health-check-$($Rule.Id)-$Suffix"; $FindingId="health-finding-$($Rule.Id)-$Suffix"
            $ResourceId=if ($null -eq $DC) { 'domain' } else { $ResourceByName[[string]$DC.Name].Id }
            $Outcome=Get-PSIADHealthRuleOutcome -Rule $Rule -Observations @($HealthEvidence.Observations) -Thresholds $Thresholds -AsOf $Snapshot.CollectedAt -DC $DC
            $EvidenceIds=@($Outcome.Observations | ForEach-Object { $EvidenceByObservation[$_] } | Where-Object { $_ } | Sort-Object -Unique)
            $HasFinding=$Outcome.Status -in @('Review','Blocked','NotTested')
            $Severity=if ($Outcome.Status -eq 'Blocked') { 'Critical' } elseif ($Outcome.Status -eq 'Review') { 'Warning' } elseif ($Outcome.Status -eq 'NotTested') { 'Info' } else { 'Healthy' }
            $Name="$($Rule.Title) / $(if ($DC) { $DC.Name } else { $HealthEvidence.Domain })"
            if ($HasFinding) {
                $Finding=New-PSIApplicationFinding -Definition @{ Id=$FindingId; Title=$Name; Summary=$Outcome.Observed; Severity=$Severity; Status=if ($Outcome.Status -eq 'NotTested') { 'NotTested' } else { 'Open' }; Category=$Rule.Category; ReadinessImpact=$Outcome.Expected; AffectedResourceIds=@($ResourceId); EvidenceIds=$EvidenceIds; Recommendation=@{ Action=$Rule.Recommendation; ExpectedState=$Outcome.Expected; AutomationHint='Guidance only; no change executed' }; Validation=@{ Method=$Rule.Validation; ExpectedResult=$Outcome.Expected; Status='NotTested' }; Frameworks=@($Pack.SourceCategory); Tags=@('Health',$Rule.Category); Metadata=@{ RuleId=$Rule.Id; Version=$Pack.Version; Source=$Pack.SourceCategory; CheckId=$CheckId } }
                $Findings.Add($Finding)
                $ResourceById[$ResourceId].FindingIds=@($ResourceById[$ResourceId].FindingIds)+@($FindingId)
                foreach ($EvidenceRecord in @($Evidence | Where-Object { $_.Id -in $EvidenceIds })) { $EvidenceRecord.FindingIds=@($EvidenceRecord.FindingIds)+@($FindingId) }
            }
            $Checks.Add((New-PSIAssessmentCheck -Definition @{ Id=$CheckId; Name=$Name; Description=$Definition.Description; CategoryId=$Rule.Category; Status=$Outcome.Status; Severity=$Severity; Weight=[double]$Rule.Weight; IsBlocking=($Outcome.Status -eq 'Blocked'); ObservedState=$Outcome.Observed; ExpectedState=$Outcome.Expected; FindingIds=if ($HasFinding) { @($FindingId) } else { @() }; ResourceIds=@($ResourceId); EvidenceIds=$EvidenceIds; Recommendation=@{ Action=$Rule.Recommendation; ExpectedState=$Outcome.Expected; AutomationHint='Read-only guidance' }; Validation=@{ Method=$Rule.Validation; ExpectedResult=$Outcome.Expected; Status='NotTested' }; Frameworks=@($Pack.SourceCategory); Tags=@('Health',$Rule.Category); Metadata=@{ RuleId=$Rule.Id; RuleVersion=$Pack.Version; Source=$Pack.SourceCategory; EvidenceRequirements=@($Rule.EvidenceRequirements); Scope=$Rule.Scope; RequiredForDC=($Rule.RequiredForDC -ne $false) } }))
        }
    }
    $DCStates=[System.Collections.Generic.List[object]]::new()
    foreach ($DC in @($Snapshot.DomainControllers)) {
        $Resource=$ResourceByName[[string]$DC.Name]
        $Member=@($Checks | Where-Object { $Resource.Id -in $_.ResourceIds })
        $Required=@($Member | Where-Object { $_.Metadata.RequiredForDC -eq $true })
        $Status=if (@($Member | Where-Object Status -eq Blocked).Count) { 'Critical' } elseif (@($Member | Where-Object Status -eq Review).Count) { 'Warning' } elseif (@($Required | Where-Object Status -eq NotTested).Count) { 'NotChecked' } elseif (@($Required | Where-Object Status -eq Ready).Count) { 'Healthy' } else { 'Unknown' }
        $Resource.Status=$Status
        $Resource.Properties.Domain=$DC.Domain; $Resource.Properties.PDC=($DC.Name -eq $Snapshot.Domains[0].PDCEmulator); $Resource.Properties.RODC=($DC.Writable -eq $false)
        $Resource.Properties.CPU=$DC.CPU; $Resource.Properties.MemoryUsedPercent=$DC.MemoryUsedPercent; $Resource.Properties.DiskFreeGB=$DC.DiskFreeGB; $Resource.Properties.UptimeDays=$DC.UptimeDays
        $Resource.Properties.HealthChecks=$Member.Count; $Resource.Properties.CriticalFindings=@($Member | Where-Object Status -eq Blocked).Count; $Resource.Properties.ReviewFindings=@($Member | Where-Object Status -eq Review).Count; $Resource.Properties.NotTestedChecks=@($Member | Where-Object Status -eq NotTested).Count
        foreach ($CategoryDefinition in @($Pack.Categories)) {
            $CategoryChecks=@($Member | Where-Object CategoryId -eq $CategoryDefinition.Id)
            $CategoryStatus=if (@($CategoryChecks | Where-Object Status -eq Blocked).Count) { 'Critical' }
                elseif (@($CategoryChecks | Where-Object Status -eq Review).Count) { 'Review' }
                elseif (@($CategoryChecks | Where-Object Status -eq NotTested).Count) { 'Not Tested' }
                elseif (@($CategoryChecks | Where-Object Status -eq Ready).Count) { 'Healthy' }
                else { 'Not Applicable' }
            $PropertyName='Health'+$CategoryDefinition.Id.Substring(0,1).ToUpperInvariant()+$CategoryDefinition.Id.Substring(1)
            $Resource.Properties[$PropertyName]=$CategoryStatus
        }
        $DCStates.Add([pscustomobject]@{ DC=$DC.Name; Site=$DC.Site; Domain=$DC.Domain; Status=$Status; Critical=$Resource.Properties.CriticalFindings; Review=$Resource.Properties.ReviewFindings; NotTested=$Resource.Properties.NotTestedChecks; ResourceId=$Resource.Id })
    }
    $Categories=@(foreach ($Definition in @($Pack.Categories)) {
        $Members=@($Checks | Where-Object CategoryId -eq $Definition.Id)
        New-PSIAssessmentCategory -Definition @{ Id=$Definition.Id; Name=$Definition.Name; Icon=$Definition.Icon; Weight=[double]$Definition.Weight; Description="Observed $($Definition.Name) operational condition"; CheckIds=@($Members | ForEach-Object Id); FindingIds=@($Members | ForEach-Object { $_.FindingIds } | Where-Object { $_ } | Sort-Object -Unique); ResourceIds=@($Members | ForEach-Object { $_.ResourceIds } | Where-Object { $_ } | Sort-Object -Unique) }
    })
    $TopologyNodes=@(foreach ($Node in @($Presentation.TopologyNodes)) {
        if ($Node.ResourceId -and $ResourceById.ContainsKey([string]$Node.ResourceId)) {
            $Resource=$ResourceById[[string]$Node.ResourceId]
            @{ NodeId=$Node.NodeId; ResourceId=$Node.ResourceId; Icon='ResourceServer'; Description="Site: $($Resource.Properties.Site); $($Resource.Status)" }
        } else { $Node }
    })
    $TopologyEdges=@(foreach ($Edge in @($Presentation.TopologyEdges)) {
        $Copy=@{}; foreach ($Key in $Edge.Keys) { $Copy[$Key]=$Edge[$Key] }
        $Number=[int]([string]$Edge.Id -replace '^replication-','')-1
        $Link=@($Snapshot.Replication)[$Number]
        $Query=@($HealthEvidence.Observations | Where-Object { $_.Type -eq 'ReplicationQuery' -and $_.DC -eq $Link.Destination -and $_.CollectionState -eq 'Collected' })
        $Obs=@($HealthEvidence.Observations | Where-Object { $_.Type -eq 'Replication' -and $_.Value.Source -eq $Link.Source -and $_.Value.Destination -eq $Link.Destination -and $_.Value.NamingContext -eq $Link.NamingContext })
        $ObservedLink=if ($Obs.Count) { $Obs[0].Value } else { $null }
        $Copy.Status='Unknown'
        if ($Query.Count -ge 2 -and @($Obs | Where-Object CollectionState -eq Collected).Count) {
            $Copy.Status='Healthy'
            if ([int]$ObservedLink.CurrentFailures -gt 0 -or [int]$ObservedLink.ConsecutiveFailures -gt 0) { $Copy.Status='Warning' }
            if ([int]$ObservedLink.ConsecutiveFailures -ge [int]$Thresholds.ReplicationCriticalConsecutiveFailures -or ($ObservedLink.LastSuccess -and $Snapshot.CollectedAt.Subtract([datetime]$ObservedLink.LastSuccess).TotalMinutes -gt [double]$Thresholds.ReplicationCriticalStaleMinutes)) { $Copy.Status='Critical' }
        }
        $Copy.Description="Naming context: $($Link.NamingContext); last success: $($ObservedLink.LastSuccess); consecutive failures: $($ObservedLink.ConsecutiveFailures); error: $($ObservedLink.LastError)"
        $Copy.EvidenceIds=@($Obs | ForEach-Object { $EvidenceByObservation[$_] } | Where-Object { $_ })
        $Copy
    })
    $Model=New-PSIApplicationModel -Resources $Resources -Evidence $Evidence.ToArray() -Findings $Findings.ToArray() -Relationships @($Presentation.Model.Relationships)
    $Assessment=New-PSIApplicationAssessment -Definition @{ Id='ad-operational-health'; Name='Active Directory Health'; Description='Provider-owned interpretation of one normalized snapshot and explicit Health observations.'; AssessmentType='Health'; Target=$HealthEvidence.Domain; Profile="Health rule pack $($Pack.Version)"; Scope="$($HealthEvidence.Domain); $(@($Snapshot.DomainControllers).Count) DCs"; GeneratedAt=$Snapshot.CollectedAt; Categories=$Categories; Checks=$Checks.ToArray(); FindingIds=@($Findings | ForEach-Object Id); ResourceIds=@($Resources | ForEach-Object Id); EvidenceIds=@($Evidence | ForEach-Object Id); Recommendations=@('Prioritize critical observed conditions; validate untested evidence before concluding health.'); Exceptions=$Exceptions; Metadata=@{ RulePackVersion=$Pack.Version; Thresholds=$Thresholds; EvidenceCoveragePercent=$HealthEvidence.CollectionCoverage.OverallPercent; Source=$Snapshot.Source; Print=@{ MethodologyText='One normalized snapshot, explicit collection states, provider-owned versioned thresholds. Missing evidence remains Not Tested; a score cannot override a critical condition.' }; PrintDisplay=@{ ReportIdentity=@{ Kicker='PSInsightHTML / Active Directory Health' }; Scope=$HealthEvidence.Domain; Profile="Health rule pack $($Pack.Version)"; CoveragePercent=$HealthEvidence.CollectionCoverage.OverallPercent; Resources=@{ Columns=@(@{Property='Name';Label='Resource'},@{Property='Type';Label='Type'},@{Property='Site';Label='Site'},@{Property='Status';Label='Health';Format='Status'}) } } }; ReadyScoreMinimum=[double]$Thresholds.ReadyScoreMinimum; ReviewScoreMinimum=[double]$Thresholds.ReviewScoreMinimum }
    $Validation=New-PSIReport -Title 'Health contract validation' -Layout Application
    $null=$Validation | Set-PSIApplicationModel -Model $Model | Set-PSIApplicationAssessment -Assessment $Assessment
    $Decision=$Validation.ApplicationAssessment.Decision
    $Verdict=switch ($Decision) { Ready { 'Healthy' } ReadyWithReview { 'Review' } ReviewRequired { 'Review' } NotReady { 'Critical' } default { 'Incomplete' } }
    [pscustomobject]@{ Snapshot=$Snapshot; HealthEvidence=$HealthEvidence; Inventory=$Inventory; RulePack=$Pack; RuleDefinitions=$RuleDefinitions.ToArray(); Thresholds=$Thresholds; Model=$Model; Assessment=$Validation.ApplicationAssessment; HealthVerdict=$Verdict; DCStates=$DCStates.ToArray(); TreeNodes=$Presentation.TreeNodes; TopologyNodes=$TopologyNodes; TopologyEdges=$TopologyEdges }
}
