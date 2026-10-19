$ModuleRoot=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
Describe 'Active Directory shared provider consolidation' {
    BeforeAll {
        $script:ModuleRoot=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
        $script:ProviderRoot=Join-Path $script:ModuleRoot 'Providers/ActiveDirectory'
        Import-Module (Join-Path $script:ModuleRoot 'PSInsightHTML.psd1') -Force
        . (Join-Path $script:ProviderRoot 'Shared/Import-PSIADProvider.ps1')
        . (Join-Path $script:ProviderRoot 'Fixtures/New-PSIADLiveFixtureAdapter.ps1')
        $script:Sample=ConvertTo-PSIADDCReadinessModel (Collect-PSIADSnapshot -UseSampleData)
    }
    It 'keeps provider implementation private and exposes no extra module commands' {
        (Get-Command Collect-PSIADSnapshot -Module PSInsightHTML -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
        (Get-Command Test-PSIADDCReadiness -Module PSInsightHTML -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
    }
    It 'resolves profiles and compatible switches without selecting an assessment' {
        $Core=Resolve-PSIADCollectionOptions
        $Core.IncludeRemoteChecks | Should -BeFalse
        $Core.IncludeDependencyDiscovery | Should -BeFalse
        $Full=Resolve-PSIADCollectionOptions -Profile Full
        @($Full.IncludeRemoteChecks,$Full.IncludePortChecks,$Full.IncludeSecurityChecks,$Full.IncludeDependencyDiscovery | Where-Object { $_ }).Count | Should -Be 4
        (Resolve-PSIADCollectionOptions -Profile Core -IncludeSecurityChecks).IncludeSecurityChecks | Should -BeTrue
    }
    It 'normalizes one reusable snapshot with explicit scope and optional observations' {
        $Sample.CollectionProfile | Should -Be Core
        $Sample.Metadata.ResourceScope | Should -Be 'corp.example'
        $Sample.Subnets.Count | Should -Be 4
        $Sample.Services.Count | Should -Be 8
        $Sample.SecurityObservations.Count | Should -Be 17
        $Sample.Replication[0].LastSuccess | Should -BeOfType [datetime]
        $Sample.CollectionEvents.Count | Should -Be $Sample.CollectionLogs.Count
    }
    It 'does not mutate the snapshot while evaluating both target versions' {
        $Before=ConvertTo-Json -InputObject $Sample -Depth 20 -Compress
        $null=Test-PSIADDCReadiness -Inventory $Sample -TargetOS 2022
        $null=Test-PSIADDCReadiness -Inventory $Sample -TargetOS 2025
        (ConvertTo-Json -InputObject $Sample -Depth 20 -Compress) | Should -Be $Before
    }
    It 'preserves the approved 2022 fictional outcome, counts and model' {
        $Result=Test-PSIADDCReadiness -Inventory $Sample -TargetOS 2022
        $Result.Assessment.Decision | Should -Be Incomplete
        $Result.Assessment.Score | Should -Be 62.3
        $Sample.CollectionCoverage.OverallPercent | Should -Be 100
        $Result.Assessment.Checks.Count | Should -Be 45
        @($Result.Assessment.Checks | Where-Object Status -eq Ready).Count | Should -Be 19
        @($Result.Assessment.Checks | Where-Object Status -eq Review).Count | Should -Be 13
        @($Result.Assessment.Checks | Where-Object Status -eq Blocked).Count | Should -Be 0
        @($Result.Assessment.Checks | Where-Object Status -eq NotTested).Count | Should -Be 13
        $Result.Model.Resources.Count | Should -Be 23
        $Result.Model.Evidence.Count | Should -Be 45
        $Result.Model.Relationships.Count | Should -Be 18
    }
    It 'preserves the approved 2025 fictional outcome, counts and model' {
        $Result=Test-PSIADDCReadiness -Inventory $Sample -TargetOS 2025
        $Result.Assessment.Decision | Should -Be NotReady
        $Result.Assessment.Score | Should -Be 56.1
        $Result.Assessment.Checks.Count | Should -Be 45
        @($Result.Assessment.Checks | Where-Object Status -eq Ready).Count | Should -Be 19
        @($Result.Assessment.Checks | Where-Object Status -eq Review).Count | Should -Be 12
        @($Result.Assessment.Checks | Where-Object Status -eq Blocked).Count | Should -Be 1
        @($Result.Assessment.Checks | Where-Object Status -eq NotTested).Count | Should -Be 13
        $Result.Model.Resources.Count | Should -Be 23
        $Result.Model.Evidence.Count | Should -Be 45
        $Result.Model.Relationships.Count | Should -Be 18
    }
    It 'keeps provider-input dependencies explicit and unassessed at collection time' {
        $Raw=Collect-PSIADSnapshot -UseSampleData -DependencyInput @([pscustomobject]@{ Name='Sample monitoring'; Type='Monitoring'; Owner='Operations'; Criticality='High'; Notes='Owner supplied'; EvidenceSource='Workshop' })
        $Item=@($Raw.Dependencies | Where-Object Name -eq 'Sample monitoring')[0]
        $Item.QueryState | Should -Be ProviderInput
        $Item.Status | Should -Be NotTested
        $Item.Owner | Should -Be Operations
        $Item.EvidenceSource | Should -Be Workshop
        { [pscustomobject]@{ Name='Incomplete' } | ConvertTo-PSIADDependencyInput } | Should -Throw '*Name and Type*'
    }
    It 'keeps resource, relationship and evidence helpers independent of readiness decisions' {
        $Resources=[System.Collections.Generic.List[object]]::new()
        Add-PSIADResources -Inventory $Sample -Resources $Resources
        $Relationships=[System.Collections.Generic.List[object]]::new()
        Add-PSIADRelationships -Inventory $Sample -Resources $Resources -Relationships $Relationships
        $Resources.Count | Should -Be 23
        $Relationships.Count | Should -Be 18
        @($Resources | Where-Object Type -eq 'Domain Controller').Count | Should -Be 8
        $Evidence=New-PSIADRuleEvidence -Inventory $Sample -RuleId probe -RuleName Probe -TargetOS 2025 -Outcome ([pscustomobject]@{Observed='Observed';Expected='Expected'}) -Source ([pscustomobject]@{Url='https://example.test';Name='Example'})
        $Evidence.Type | Should -Be 'Provider rule observation'
        $Evidence.ResourceIds.Count | Should -Be 0
        $Observed=New-PSIADObservationEvidence -Id observation-one -Title 'Collection status' -Snapshot $Sample -CollectionResult ([pscustomobject]@{ CollectorId='DNS'; Status='NotSupported'; Scope='dc-01.corp.example' }) -Summary 'Capability unavailable'
        $Observed.Data.CollectionState | Should -Be NotSupported
        $Observed.Data.Scope | Should -Be 'dc-01.corp.example'
        $Observed.FindingIds.Count | Should -Be 0
    }
    It 'retains external replication evidence without expanding assessed resource scope' {
        $Raw=Collect-PSIADSnapshot -Domain root.example.test -CommandAdapter (New-PSIADLiveFixtureAdapter) -Profile Operational -IncludeSecurityChecks -IncludeDependencyDiscovery
        $Snapshot=ConvertTo-PSIADDCReadinessModel $Raw
        $Snapshot.DomainControllers.Count | Should -Be 3
        $Snapshot.Metadata.ResourceScope | Should -Be 'root.example.test'
        $Snapshot.Metadata.EvidenceScope | Should -Be 'example.test'
        @($Snapshot.Replication | Where-Object { $_.ExternalToAssessmentScope -and $_.EvidenceOnly -and $_.NamingContextKind -in @('Configuration','Schema') }).Count | Should -BeGreaterThan 0
        @($Snapshot.CollectionResults | Where-Object { $_.CollectorId -eq 'DNS' -and $_.Status -eq 'NotSupported' }).Count | Should -Be 3
        @($Snapshot.CollectionResults | Where-Object { $_.CollectorId -eq 'Security' -and $_.Status -eq 'Partial' }).Count | Should -Be 3
        @($Snapshot.CollectionResults | Where-Object { $_.CollectorId -eq 'Dependencies' -and $_.Status -eq 'Partial' }).Count | Should -Be 1
        $Snapshot.Time.PDCSourceReachable | Should -BeNullOrEmpty
        $Result=Test-PSIADDCReadiness -Inventory $Snapshot -TargetOS 2025
        $Result.Model.Resources.Count | Should -Be 13
        $Result.Assessment.Metadata.EvidenceCoveragePercent | Should -Be $Snapshot.CollectionCoverage.OverallPercent
    }
    It 'maps normalized replication observations to presentation without adding resources' {
        $Result=Test-PSIADDCReadiness -Inventory $Sample -TargetOS 2025
        $Presentation=New-PSIADPresentationRelationships -Inventory $Sample -Model $Result.Model
        $Presentation.InfrastructureNodes.Count | Should -Be 23
        $Presentation.ReplicationEdges.Count | Should -Be $Sample.Replication.Count
        @($Presentation.ReplicationNodes | Where-Object { $_.IsExternal -and $_.EvidenceOnly }).Count | Should -Be 1
        $Result.Model.Resources.Count | Should -Be 23
    }
    It 'reports capabilities from collection records without probing infrastructure' {
        $Metadata=Get-PSIADProviderMetadata -Snapshot $Sample
        $Metadata.Name | Should -Be ActiveDirectory
        $Metadata.PowerShellVersion | Should -Be '5.1'
        $Metadata.ReadOnly | Should -BeTrue
        @($Metadata.SupportedCollectors | Where-Object Name -eq DNS).Count | Should -Be 1
    }
    It 'keeps provider collector source free of mutation commands' {
        $Files=Get-ChildItem (Join-Path $ProviderRoot 'Collectors') -Filter '*.ps1'
        foreach ($File in $Files) {
            [System.IO.File]::ReadAllText($File.FullName) | Should -Not -Match '(?im)^\s*(Set-AD\w*|New-AD\w*|Remove-AD\w*|Add-AD\w*|Set-DnsServer\w*|Add-DnsServer\w*|Remove-DnsServer\w*|Set-GP\w*|New-GP\w*|Remove-GP\w*|Set-ItemProperty|New-ItemProperty|Restart-Service|Stop-Service|Start-Service|Restart-Computer)\b'
        }
    }
}
