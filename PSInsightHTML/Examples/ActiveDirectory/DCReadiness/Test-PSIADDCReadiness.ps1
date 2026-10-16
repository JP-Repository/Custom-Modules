function Test-PSIADDCReadiness {
    <# .SYNOPSIS Evaluate one normalized inventory with target-specific provider rules and PSI contracts. #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][pscustomobject] $Inventory,
          [Parameter(Mandatory = $true)][ValidateSet('2022','2025')][string] $TargetOS)
    $Pack=Import-PowerShellDataFile (Join-Path $PSScriptRoot "Rules/WindowsServer$TargetOS.psd1")
    $SecurityPack=Import-PowerShellDataFile (Join-Path $PSScriptRoot 'Rules/SecurityBaseline.psd1')
    $Sources=(Import-PowerShellDataFile (Join-Path $PSScriptRoot 'Rules/RuleSources.psd1')).Sources
    $CategoryDefinitions=@(
        @{ Id='platform'; Name='Platform and inventory'; Icon='ResourceServer'; Weight=1.2 }
        @{ Id='replication'; Name='Replication and SYSVOL'; Icon='Relationship'; Weight=1.5 }
        @{ Id='dns'; Name='DNS readiness'; Icon='Relationship'; Weight=1.1 }
        @{ Id='health'; Name='Core health'; Icon='SeveritySuccess'; Weight=1.1 }
        @{ Id='compatibility'; Name='Compatibility and dependencies'; Icon='ResourceServer'; Weight=1.5 }
        @{ Id='security'; Name='Security baseline'; Icon='SecurityShield'; Weight=1.1 }
        @{ Id='postbuild'; Name='Post-build validation'; Icon='Document'; Weight=0.5 }
    )
    $PostBuildNames=@('Promotion successful','DNS registration','SYSVOL and NETLOGON shares','Replication converged','Global Catalog state','Site membership','Time source','DNS client settings','Inbound and outbound replication','Event log review','Secure channel and authentication','Backup and monitoring onboarding')
    $PostRules=@(for ($I=0; $I -lt $PostBuildNames.Count; $I++) { @{ Id=('postbuild-{0:d2}' -f ($I+1)); Category='postbuild'; Name=$PostBuildNames[$I]; SourceId='LocalPolicy'; Weight=1; Expected="Validated $($PostBuildNames[$I].ToLowerInvariant())"; Rationale='Test only after a target DC exists.' } })
    $SecurityRules=@(foreach ($R in $SecurityPack.Rules) { $Copy=@{}; foreach ($K in $R.Keys) { $Copy[$K]=$R[$K] }; $Copy.Id="security-$($R.Id)"; $Copy.Category='security'; $Copy.Weight=1; $Copy.Rationale='Provider security review; assess client and application effects before enforcement.'; $Copy })
    $Rules=@($Pack.Rules)+@($SecurityRules)+@($PostRules)

    $Resources=[System.Collections.Generic.List[object]]::new()
    $SourceDescription=if ($Inventory.Source -eq 'Fictional sample') { 'Fictional' } else { 'Read-only observed' }
    $InventoryStatus=if ($Inventory.Source -eq 'Fictional sample') { 'Healthy' } else { 'Unknown' }
    $Resources.Add((New-PSIResource -Definition @{ Id='forest'; Name=$Inventory.Forest.Name; Type='Forest'; Status=$InventoryStatus; Description="$SourceDescription AD forest"; Properties=@{ FunctionalLevel=$Inventory.Forest.FunctionalLevel; SysvolReplication=$Inventory.Forest.SysvolReplication; SchemaMaster=$Inventory.Forest.SchemaMaster; DomainNamingMaster=$Inventory.Forest.DomainNamingMaster } }))
    foreach ($Domain in $Inventory.Domains) { $Resources.Add((New-PSIResource -Definition @{ Id='domain'; Name=$Domain.Name; Type='Domain'; Status=$InventoryStatus; Description="$SourceDescription AD domain"; Properties=@{ FunctionalLevel=$Domain.FunctionalLevel; PDCEmulator=$Domain.PDCEmulator; RIDMaster=$Domain.RIDMaster; InfrastructureMaster=$Domain.InfrastructureMaster } })) }
    for ($I=0; $I -lt $Inventory.Sites.Count; $I++) { $Site=$Inventory.Sites[$I]; $Resources.Add((New-PSIResource -Definition @{ Id="site-$($I+1)"; Name=$Site.Name; Type='Site'; Status=$InventoryStatus; Description="$SourceDescription AD site"; Properties=@{ Subnets=@($Site.Subnets) -join ', ' } })) }
    for ($I=0; $I -lt $Inventory.DomainControllers.Count; $I++) {
        $DC=$Inventory.DomainControllers[$I]
        $Resources.Add((New-PSIResource -Definition @{ Id="dc-$($I+1)"; Name=$DC.Name; Type='Domain Controller'; Status=if ($null -eq $DC.Reachable) { 'Unknown' } elseif ($DC.Reachable) { 'Healthy' } else { 'Warning' }; Description="$SourceDescription $($DC.OS) domain controller"; Properties=@{ Site=$DC.Site; OS=$DC.OS; Build=$DC.Build; Writable=$DC.Writable; GlobalCatalog=$DC.GlobalCatalog; FSMORoles=@($DC.FSMORoles) -join ', '; DNSClient=@($DC.DNSClient) -join ', '; TimeSource=$DC.TimeSource; DiskFreeGB=$DC.DiskFreeGB; UptimeDays=$DC.UptimeDays; PendingReboot=$DC.PendingReboot } }))
    }
    for ($I=0; $I -lt $Inventory.Dependencies.Count; $I++) { $D=$Inventory.Dependencies[$I]; $Resources.Add((New-PSIResource -Definition @{ Id="dependency-$($I+1)"; Name=$D.Name; Type=$D.Type; Status=if ($D.Status -eq 'Ready') { 'Healthy' } elseif ($D.Status -eq 'NotTested') { 'NotChecked' } else { 'Warning' }; Description=$D.Detail; Properties=@{ Version=$D.Version; CU=$D.CU; Confidence=$D.Confidence } })) }
    $Relationships=[System.Collections.Generic.List[object]]::new()
    $Relationships.Add((New-PSIRelationship -Definition @{ Id='rel-domain-forest'; SourceResourceId='domain'; TargetResourceId='forest'; Type='belongs-to'; Status='Healthy' }))
    for ($I=0; $I -lt $Inventory.DomainControllers.Count; $I++) {
        $SiteIndex=[array]::IndexOf(@($Inventory.Sites | ForEach-Object { $_.Name }),$Inventory.DomainControllers[$I].Site)
        $Relationships.Add((New-PSIRelationship -Definition @{ Id="rel-dc-$($I+1)"; SourceResourceId="dc-$($I+1)"; TargetResourceId="site-$($SiteIndex+1)"; Type='located-in'; Status='Healthy' }))
    }
    for ($I=0; $I -lt $Inventory.Dependencies.Count; $I++) { $Relationships.Add((New-PSIRelationship -Definition @{ Id="rel-dependency-$($I+1)"; SourceResourceId="dependency-$($I+1)"; TargetResourceId='domain'; Type='depends-on'; Status='Warning' })) }
    foreach ($Link in $Relationships) { foreach ($Resource in $Resources) { if ($Resource.Id -in @($Link.SourceResourceId,$Link.TargetResourceId)) { $Resource.RelationshipIds=@($Resource.RelationshipIds)+@($Link.Id) } } }

    $Evidence=[System.Collections.Generic.List[object]]::new(); $Findings=[System.Collections.Generic.List[object]]::new(); $Checks=[System.Collections.Generic.List[object]]::new()
    foreach ($Rule in $Rules) {
        $Source=$Sources[[string] $Rule.SourceId]
        if ($null -eq $Source) { throw "Rule '$($Rule.Id)' has no registered source." }
        $Outcome=Get-PSIADDCReadinessOutcome -Inventory $Inventory -Rule $Rule -TargetOS $TargetOS
        $Id=[string] $Rule.Id; $EvidenceId="evidence-$Id"; $FindingId="finding-$Id"
        $ResourceIds=switch ($Rule.Category) {
            'platform' { @('forest','domain') }
            'compatibility' { @('domain')+@($Resources | Where-Object { $_.Type -in @('Exchange','Identity sync','NPS','LDAP/LDAPS','Hard-coded DC') } | ForEach-Object { $_.Id }) }
            'postbuild' { @('domain') }
            default { @($Resources | Where-Object { $_.Type -eq 'Domain Controller' } | ForEach-Object { $_.Id }) }
        }
        $HasFinding=$Outcome.Status -in @('Review','Blocked','NotTested','Unknown')
        $Evidence.Add((New-PSIEvidenceRecord -Definition @{ Id=$EvidenceId; Title="$($Rule.Name) observation"; Type='Provider rule observation'; Source=$Inventory.Source; CollectedAt=$Inventory.CollectedAt; Summary=$Outcome.Observed; Data=@{ RuleId=$Id; TargetOS=$TargetOS; Observed=$Outcome.Observed; Expected=$Outcome.Expected; SourceUrl=$Source.Url; SourceName=$Source.Name }; FindingIds=if ($HasFinding) { @($FindingId) } else { @() }; ResourceIds=$ResourceIds }))
        if ($HasFinding) {
            $Findings.Add((New-PSIApplicationFinding -Definition @{ Id=$FindingId; Title=$Rule.Name; Summary=$Outcome.Observed; Severity=if ($Outcome.Status -eq 'Blocked') { 'Critical' } elseif ($Outcome.Status -eq 'Review') { 'Warning' } else { 'Info' }; Status=if ($Outcome.Status -eq 'NotTested') { 'NotTested' } else { 'Open' }; Category=$Rule.Category; ReadinessImpact=$Outcome.Expected; AffectedResourceIds=$ResourceIds; EvidenceIds=@($EvidenceId); Frameworks=@($Source.Name); Recommendation=@{ Action=$Outcome.Action; Rationale=$Rule.Rationale; ExpectedState=$Outcome.Expected; AutomationHint='Guidance only; no action executed' }; Validation=@{ Method='Review source observation and target design'; ExpectedResult=$Outcome.Expected; Status='NotTested' } }))
        }
        foreach ($Resource in $Resources) { if ($Resource.Id -in $ResourceIds) { $Resource.EvidenceIds=@($Resource.EvidenceIds)+@($EvidenceId); if ($HasFinding) { $Resource.FindingIds=@($Resource.FindingIds)+@($FindingId) } } }
        $Checks.Add((New-PSIAssessmentCheck -Definition @{ Id="check-$Id"; Name=$Rule.Name; Description=$Rule.Rationale; CategoryId=$Rule.Category; Status=$Outcome.Status; Severity=if ($Outcome.Status -eq 'Blocked') { 'Critical' } elseif ($Outcome.Status -eq 'Review') { 'Warning' } else { 'Info' }; Weight=[double] $Rule.Weight; IsBlocking=$Outcome.Status -eq 'Blocked'; ObservedState=$Outcome.Observed; ExpectedState=$Outcome.Expected; FindingIds=if ($HasFinding) { @($FindingId) } else { @() }; ResourceIds=$ResourceIds; EvidenceIds=@($EvidenceId); Recommendation=@{ Action=$Outcome.Action; Rationale=$Rule.Rationale; ExpectedState=$Outcome.Expected; AutomationHint='Guidance only' }; Validation=@{ Method='Confirm observation against target design'; ExpectedResult=$Outcome.Expected; Status='NotTested' }; Frameworks=@($Source.Name); Tags=@($TargetOS,$Rule.Category); Metadata=@{ RuleId=$Id; Version=$Pack.Version; TargetOS=$TargetOS; Source=$Source.Name; SourceUrl=$Source.Url; LastReviewed=$Source.LastReviewed; Category=$Rule.Category; Rationale=$Rule.Rationale } }))
    }
    $ResourceRecords=$Resources.ToArray(); $EvidenceRecords=$Evidence.ToArray(); $FindingRecords=$Findings.ToArray(); $CheckRecords=$Checks.ToArray()
    $Model=New-PSIApplicationModel -Resources $ResourceRecords -Evidence $EvidenceRecords -Findings $FindingRecords -Relationships $Relationships.ToArray()
    $Categories=@(foreach ($Definition in $CategoryDefinitions) {
        $Members=@($CheckRecords | Where-Object { $_.CategoryId -eq $Definition.Id })
        New-PSIAssessmentCategory -Definition @{ Id=$Definition.Id; Name=$Definition.Name; Icon=$Definition.Icon; Weight=$Definition.Weight; Description="Provider-owned $($Definition.Name.ToLowerInvariant()) checks"; CheckIds=@($Members | ForEach-Object { $_.Id }); FindingIds=@($Members | ForEach-Object { $_.FindingIds } | Where-Object { $_ } | Sort-Object -Unique); ResourceIds=@($Members | ForEach-Object { $_.ResourceIds } | Where-Object { $_ } | Sort-Object -Unique) }
    })
    $Exceptions=if ($Inventory.Source -eq 'Fictional sample') { @(@{ Id='sample-exception'; Title='Legacy LDAP client review'; Description='Fictional approved, time-bound exception'; CheckId='check-security-ldap-signing'; FindingId='finding-security-ldap-signing'; ResourceIds=@('domain'); Reason='Client compatibility work in progress'; Owner='Sample identity team'; ApprovedBy='Fictional change board'; ApprovedAt=$Inventory.CollectedAt.Date.AddDays(-5); ExpiresAt=$Inventory.CollectedAt.Date.AddDays(25); Status='Approved' }) } else { @() }
    $Assessment=New-PSIApplicationAssessment -Definition @{ Id="ad-dc-readiness-$TargetOS"; Name="Active Directory DC readiness $TargetOS"; Description="$SourceDescription provider assessment using one normalized inventory."; AssessmentType='Readiness'; Target="Windows Server $TargetOS"; Profile="DC Readiness $TargetOS rule pack v$($Pack.Version)"; Scope="$($Inventory.Domains[0].Name); $($Inventory.DomainControllers.Count) DCs"; GeneratedAt=$Inventory.CollectedAt; Categories=$Categories; Checks=$CheckRecords; FindingIds=@($FindingRecords | ForEach-Object { $_.Id }); ResourceIds=@($ResourceRecords | ForEach-Object { $_.Id }); EvidenceIds=@($EvidenceRecords | ForEach-Object { $_.Id }); Recommendations=@('Build a new server, join the domain, promote it, validate, transition services and roles, then demote a legacy DC.','Review blocking and untested checks before change approval.'); Exceptions=$Exceptions; Metadata=@{ RulePackVersion=$Pack.Version; SourceInventory=$Inventory.Source; SecurityPackVersion=$SecurityPack.Version; EvidenceCoveragePercent=$Inventory.CollectionCoverage.OverallPercent }; ReadyScoreMinimum=[double] $Inventory.Thresholds.ReadyScoreMinimum; ReviewScoreMinimum=[double] $Inventory.Thresholds.ReviewScoreMinimum }
    $ValidationReport=New-PSIReport -Title 'Validation model' -Layout Application
    $null=$ValidationReport | Set-PSIApplicationModel -Model $Model | Set-PSIApplicationAssessment -Assessment $Assessment
    $GPO=@(foreach ($Rule in $SecurityPack.Rules) {
        [pscustomobject]@{ Setting=$Rule.Setting; Recommended=$Rule.Recommended; Current=[string] $Inventory.SecurityValues[$Rule.Id]; Status=[string] $Inventory.Security[$Rule.Id]; SuggestedGPO=if ($Inventory.Source -eq 'Fictional sample') { 'DC Security Review - Sample' } else { 'DC Security Review - Suggested' }; SuggestedScope=$Rule.Scope; ConflictingGPO='Not collected'; Framework=$Sources[[string] $Rule.SourceId].Name; SourceUrl=$Sources[[string] $Rule.SourceId].Url; Rationale='Review with owners before enforcement'; Remediation='Plan a controlled policy review; no changes executed'; Impact=$Rule.Impact; Validation=$Rule.Validation }
    })
    [pscustomobject]@{ TargetOS=$TargetOS; Inventory=$Inventory; RulePack=$Pack; SecurityPack=$SecurityPack; Sources=$Sources; Model=$Model; Assessment=$ValidationReport.ApplicationAssessment; GPO=$GPO; PostBuild=@($CheckRecords | Where-Object { $_.CategoryId -eq 'postbuild' }) }
}
