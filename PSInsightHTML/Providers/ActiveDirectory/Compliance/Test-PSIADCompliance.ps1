function Test-PSIADCompliance {
    <# .SYNOPSIS Project existing provider assessments into selected external control mappings. No collection or mutation. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject] $Snapshot,
        [Parameter(Mandatory)][pscustomobject] $Security,
        [pscustomobject] $Health,
        [hashtable] $MappingPack=(Get-PSIADControlMappings)
    )
    if (-not [object]::ReferenceEquals($Snapshot,$Security.Snapshot) -or ($Health -and -not [object]::ReferenceEquals($Snapshot,$Health.Snapshot))) {
        throw 'Compliance requires assessments from the same normalized snapshot.'
    }
    if (-not $MappingPack.Framework -or -not $MappingPack.FrameworkVersion -or -not $MappingPack.Controls) { throw 'Compliance mapping pack requires a framework, version, and controls.' }
    $FrameworkId=if ($MappingPack.FrameworkId) { [string]$MappingPack.FrameworkId } else { [string]$MappingPack.Framework }
    $Mode=if ($MappingPack.EvaluationMode) { [string]$MappingPack.EvaluationMode } else { 'CurrentState' }
    if ($Mode -notin @('CurrentState','FutureTarget','ContextOnly')) { throw 'Invalid compliance evaluation mode.' }
    $MappingIds=@{}
    foreach ($Mapping in @($MappingPack.Controls)) {
        $MappingId=if ($Mapping.MappingId) { [string]$Mapping.MappingId } else { [string]$Mapping.ControlId }
        if (-not $MappingId -or -not $Mapping.ControlId -or -not $Mapping.Reference -or -not @($Mapping.SourceRuleIds).Count -or $Mapping.MappingType -notin @('Direct','Partial','Supporting')) { throw 'Invalid compliance control mapping.' }
        if ($MappingIds.ContainsKey($MappingId)) { throw "Duplicate mapping ID '$MappingId'." }
        $MappingIds[$MappingId]=$true
    }
    $Rules=@{}
    foreach ($Rule in @($Security.RuleDefinitions)+$(if ($Health) { @($Health.RuleDefinitions) } else { @() })) { $Rules[[string]$Rule.Id]=$true }
    $Checks=@($Security.Assessment.Checks)+$(if ($Health) { @($Health.Assessment.Checks) } else { @() })
    function Resolve-ControlState([object[]]$Member,[string]$Type) {
        $Applicable=@($Member | Where-Object Status -ne NotApplicable)
        if (-not $Applicable.Count) { return 'NotApplicable' }
        $Complete=@($Applicable | Where-Object { $_.Status -in @('Ready','Review','Blocked') })
        if ($Type -eq 'Supporting') { if ($Complete.Count) { return 'PartiallyAssessed' }; return 'NotTested' }
        if (@($Applicable | Where-Object Status -eq Blocked).Count) { return 'Fail' }
        if (-not $Complete.Count) { return 'NotTested' }
        if ($Complete.Count -lt $Applicable.Count) { return 'PartiallyAssessed' }
        if (@($Applicable | Where-Object Status -eq Review).Count) { return 'Review' }
        if ($Type -eq 'Partial') { return 'PartiallyAssessed' }
        return 'Pass'
    }
    $Results=[System.Collections.Generic.List[object]]::new()
    $ResourceResults=[System.Collections.Generic.List[object]]::new()
    foreach ($Mapping in @($MappingPack.Controls | Where-Object MappingType -ne Supporting)) {
        $MappingId=if ($Mapping.MappingId) { [string]$Mapping.MappingId } else { [string]$Mapping.ControlId }
        foreach ($RuleId in @($Mapping.SourceRuleIds)) { if (-not $Rules.ContainsKey([string]$RuleId)) { throw "Unknown mapped PSI rule '$RuleId'." } }
        $Supporting=@($MappingPack.Controls | Where-Object { $_.MappingType -eq 'Supporting' -and $_.ControlId -eq $Mapping.ControlId })
        $MappedChecks=@($Checks | Where-Object { $_.Metadata.RuleId -in @($Mapping.SourceRuleIds) })
        $CheckIds=@($MappedChecks | ForEach-Object Id | Sort-Object -Unique)
        $FindingIds=@($MappedChecks | ForEach-Object { $_.FindingIds } | Where-Object { $_ } | Sort-Object -Unique)
        $EvidenceIds=@($MappedChecks | ForEach-Object { $_.EvidenceIds } | Where-Object { $_ } | Sort-Object -Unique)
        $ResourceIds=@($MappedChecks | ForEach-Object { $_.ResourceIds } | Where-Object { $_ } | Sort-Object -Unique)
        $Exceptions=@($Security.Assessment.Exceptions)+$(if ($Health) { @($Health.Assessment.Exceptions) } else { @() })
        $LinkedExceptions=@($Exceptions | Where-Object { $_.CheckId -in $CheckIds -or $_.FindingId -in $FindingIds -or @($_.ResourceIds | Where-Object { $_ -in $ResourceIds }).Count })
        $ControlResources=[System.Collections.Generic.List[object]]::new()
        $EligibleChecks=[System.Collections.Generic.List[object]]::new()
        foreach ($ResourceId in $ResourceIds) {
            $ResourceChecks=@($MappedChecks | Where-Object { $ResourceId -in $_.ResourceIds })
            $Applicability=Resolve-PSIADComplianceApplicability -Snapshot $Snapshot -MappingPack $MappingPack -Mapping $Mapping -ResourceId ([string]$ResourceId)
            if ($Applicability.State -eq 'Applicable') { foreach ($Check in $ResourceChecks) { $EligibleChecks.Add($Check) } }
            $ResourceApplicable=if ($Applicability.State -eq 'Applicable') { @($ResourceChecks | Where-Object Status -ne NotApplicable) } else { @() }
            $ResourceComplete=@($ResourceApplicable | Where-Object { $_.Status -in @('Ready','Review','Blocked') }).Count
            $ResourceState=if ($Applicability.State -eq 'Applicable') { Resolve-ControlState $ResourceChecks ([string]$Mapping.MappingType) } elseif ($Applicability.State -eq 'Unknown') { 'NotTested' } else { $Applicability.State }
            $Entry=[pscustomobject]@{
                Identity="$FrameworkId|$($MappingPack.FrameworkVersion)|$($Mapping.ControlId)|$ResourceId"
                FrameworkId=$FrameworkId; Framework=[string]$MappingPack.Framework; FrameworkVersion=[string]$MappingPack.FrameworkVersion
                ControlId=[string]$Mapping.ControlId; Title=[string]$Mapping.ControlTitle; ResourceId=[string]$ResourceId
                Status=$ResourceState; Applicability=$Applicability.State; ApplicabilityReason=$Applicability.Reason; ApplicabilityConfidence=$Applicability.Confidence
                OSVersion=$Applicability.OSVersion; EvaluationMode=$Mode; MappingType=[string]$Mapping.MappingType
                CheckIds=@($ResourceChecks | ForEach-Object Id); EvidenceIds=@($ResourceChecks | ForEach-Object { $_.EvidenceIds } | Where-Object { $_ } | Sort-Object -Unique)
                EvidenceCompletenessPercent=if ($ResourceApplicable.Count) { [math]::Round(100*$ResourceComplete/$ResourceApplicable.Count,1) } else { $null }
            }
            $ControlResources.Add($Entry); $ResourceResults.Add($Entry)
        }
        $Applicable=@($EligibleChecks.ToArray() | Where-Object Status -ne NotApplicable)
        $Ready=@($Applicable | Where-Object Status -eq Ready).Count
        $Review=@($Applicable | Where-Object Status -eq Review).Count
        $Blocked=@($Applicable | Where-Object Status -eq Blocked).Count
        $Missing=@($Applicable | Where-Object { $_.Status -in @('NotTested','Unknown') }).Count
        $Complete=@($Applicable | Where-Object { $_.Status -in @('Ready','Review','Blocked') }).Count
        $ResourceStates=@($ControlResources.ToArray() | Where-Object Applicability -eq Applicable | ForEach-Object Status)
        $State=if ('Fail' -in $ResourceStates) { 'Fail' } elseif ('Review' -in $ResourceStates) { 'Review' } elseif ('PartiallyAssessed' -in $ResourceStates) { 'PartiallyAssessed' } elseif ('NotTested' -in $ResourceStates) { 'NotTested' } elseif ('Pass' -in $ResourceStates) { 'Pass' } elseif (@($ControlResources | Where-Object Applicability -eq Unknown).Count) { 'NotTested' } elseif (@($ControlResources | Where-Object Applicability -eq ContextOnly).Count) { 'ContextOnly' } else { 'NotApplicable' }
        if ($State -eq 'Pass' -and @($ControlResources | Where-Object Applicability -eq Unknown).Count) { $State='PartiallyAssessed' }
        $ControlApplicability=if (@($ControlResources | Where-Object Applicability -eq Applicable).Count) { 'Applicable' } elseif (@($ControlResources | Where-Object Applicability -eq Unknown).Count) { 'Unknown' } elseif (@($ControlResources | Where-Object Applicability -eq ContextOnly).Count) { 'ContextOnly' } else { 'NotApplicable' }
        $Reasons=@($ControlResources | ForEach-Object ApplicabilityReason | Sort-Object -Unique) -join ' '
        $Results.Add([pscustomobject]@{
            Id=('control-'+($FrameworkId -replace '[^A-Za-z0-9-]','-')+'-'+($Mapping.ControlId -replace '[^A-Za-z0-9-]','-'))
            Identity="$FrameworkId|$($MappingPack.FrameworkVersion)|$($Mapping.ControlId)|$($MappingId)"
            FrameworkId=$FrameworkId; Framework=[string]$MappingPack.Framework; FrameworkVersion=[string]$MappingPack.FrameworkVersion; EvaluationMode=$Mode
            ControlId=[string]$Mapping.ControlId; Title=[string]$Mapping.ControlTitle; Description=[string]$Mapping.ControlDescription
            MappingType=[string]$Mapping.MappingType; MappingConfidence=[string]$Mapping.MappingConfidence; Applicability=$ControlApplicability; ApplicabilityReason=$Reasons
            ApplicableOperatingSystems=@($MappingPack.ApplicableOperatingSystems)+@($Mapping.ApplicableOperatingSystems) | Where-Object { $_ }
            ApplicableVersions=@($MappingPack.ApplicableVersions)+@($Mapping.ApplicableVersions) | Where-Object { $_ }
            ApplicableRoles=@($MappingPack.ApplicableRoles)+@($Mapping.ApplicableRoles) | Where-Object { $_ }
            ApplicabilityConfidence=if (@($ControlResources | Where-Object Applicability -eq Unknown).Count) { 'Low' } else { 'High' }; ContextOnly=($ControlApplicability -eq 'ContextOnly')
            SupportingMappings=@($Supporting | ForEach-Object { [pscustomobject]@{ MappingId=$_.MappingId; SourceRuleIds=@($_.SourceRuleIds); Notes=$_.Notes; Reference=$_.Reference } })
            SourceRuleIds=@($Mapping.SourceRuleIds); EvidenceRequirements=@($Mapping.EvidenceRequirements); Notes=[string]$Mapping.Notes; Reference=[string]$Mapping.Reference
            Status=$State; CheckIds=$CheckIds; FindingIds=$FindingIds; EvidenceIds=$EvidenceIds; ResourceIds=$ResourceIds; Exceptions=$LinkedExceptions
            EvidenceCompletenessPercent=if ($Applicable.Count) { [math]::Round(100*$Complete/$Applicable.Count,1) } else { $null }
            ApplicableChecks=$Applicable.Count; CompleteChecks=$Complete; ReadyChecks=$Ready; ReviewChecks=$Review; BlockedChecks=$Blocked; MissingChecks=$Missing
        })
    }
    $ResultArray=$Results.ToArray(); $AllApplicable=@($ResultArray | Where-Object Applicability -eq Applicable)
    $FrameworkResourceStates=@(for ($Index=0; $Index -lt @($Snapshot.DomainControllers).Count; $Index++) {
        (Resolve-PSIADComplianceApplicability -Snapshot $Snapshot -MappingPack $MappingPack -Mapping @{} -ResourceId "dc-$($Index+1)").State
    })
    $FrameworkState=if ('Applicable' -in $FrameworkResourceStates) { 'Applicable' } elseif ('Unknown' -in $FrameworkResourceStates) { 'Unknown' } elseif ('ContextOnly' -in $FrameworkResourceStates) { 'ContextOnly' } else { 'NotApplicable' }
    $TotalChecks=0; $CompleteChecks=0
    foreach ($Control in $AllApplicable) { $TotalChecks += $Control.ApplicableChecks; $CompleteChecks += $Control.CompleteChecks }
    [pscustomobject]@{
        Kind='ActiveDirectory.SelectedControlMapping'; ContractVersion='1.1'; Snapshot=$Snapshot; Security=$Security; Health=$Health
        FrameworkId=$FrameworkId; Framework=[string]$MappingPack.Framework; FrameworkVersion=[string]$MappingPack.FrameworkVersion; EvaluationMode=$Mode
        FrameworkApplicability=$FrameworkState
        ScopeNote=[string]$MappingPack.ScopeNote
        Mappings=@($MappingPack.Controls); Controls=$ResultArray; ResourceResults=$ResourceResults.ToArray()
        Counts=[pscustomobject]@{ Mapped=$ResultArray.Count; Applicable=@($ResultArray | Where-Object Applicability -eq Applicable).Count; ContextOnly=@($ResultArray | Where-Object Applicability -eq ContextOnly).Count; Unknown=@($ResultArray | Where-Object Applicability -eq Unknown).Count; Pass=@($ResultArray | Where-Object Status -eq Pass).Count; Review=@($ResultArray | Where-Object Status -eq Review).Count; Fail=@($ResultArray | Where-Object Status -eq Fail).Count; NotTested=@($ResultArray | Where-Object Status -eq NotTested).Count; PartiallyAssessed=@($ResultArray | Where-Object Status -eq PartiallyAssessed).Count; NotApplicable=@($ResultArray | Where-Object Status -eq NotApplicable).Count }
        FrameworkCoverage=[pscustomobject]@{ Mapped=$ResultArray.Count; CatalogTotal=$MappingPack.CatalogControlCount; Percent=$null; Label='Selected Control Mapping; full catalog coverage not measured' }
        EvidenceCompleteness=[pscustomobject]@{ Complete=$CompleteChecks; Total=$TotalChecks; Percent=if ($TotalChecks) { [math]::Round(100*$CompleteChecks/$TotalChecks,1) } else { $null } }
        Disclaimer='Not a certification or a complete framework assessment. Unmapped controls are not automatically compliant. Missing evidence remains unknown. Partial and supporting mappings do not prove a full control.'
    }
}
