$ModuleRoot=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
Describe 'AD provider Security assessment' {
    BeforeAll {
        $script:ModuleRoot=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
        Import-Module (Join-Path $ModuleRoot 'PSInsightHTML.psd1') -Force
        . (Join-Path $ModuleRoot 'Providers/ActiveDirectory/Shared/Import-PSIADProvider.ps1')
        . (Join-Path $ModuleRoot 'Providers/ActiveDirectory/Fixtures/New-PSIADLiveFixtureAdapter.ps1')
        $script:Snapshot=ConvertTo-PSIADDCReadinessModel (Collect-PSIADSnapshot -UseSampleData -Profile Security)
        $script:Evidence=New-PSIADSecurityEvidenceModel $Snapshot
        $null=Add-PSIADSecurityFictionalObservations $Snapshot $Evidence
        $script:Security=Test-PSIADSecurity $Snapshot $Evidence
    }
    It 'loads provider-owned rule metadata without exporting provider commands from core' {
        $Security.RulePack.Version | Should -Be '1.0'
        $Security.RuleDefinitions.Count | Should -Be 29
        Get-Command Test-PSIADSecurity -Module PSInsightHTML -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        foreach ($Rule in $Security.RuleDefinitions) {
            $Rule.Source | Should -Be 'Provider-defined security recommendation'
            $Rule.EvidenceRequirements.Count | Should -BeGreaterThan 0
            $Rule.Validation | Should -Not -BeNullOrEmpty
        }
    }
    It 'classifies each rule with explicit secure, review, critical and missing-state behavior' {
        foreach ($Rule in @($Security.RulePack.Rules)) {
            $DC=if ($Rule.Scope -eq 'Domain') { $null } else { $Snapshot.DomainControllers[0] }
            $Scope=if ($null -eq $DC) { $Snapshot.Domains[0].Name } else { $DC.Name }
            $Missing=Get-PSIADSecurityRuleOutcome $Rule @() $Security.Thresholds $DC $Snapshot.Domains[0].Name
            $Missing.Status | Should -Be NotTested -Because $Rule.Id
            $Good=if ($Rule.Threshold) { if ($Rule.Id -eq 'event-retention') { 2048 } else { 30 } } else { @($Rule.Good)[0] }
            $Fact=[pscustomobject]@{ RuleId=$Rule.Id; DC=$Scope; CollectionState='Collected'; Value=$Good; EvidenceType=$Rule.Evidence }
            (Get-PSIADSecurityRuleOutcome $Rule @($Fact) $Security.Thresholds $DC $Snapshot.Domains[0].Name).Status | Should -Be Ready -Because $Rule.Id
            foreach ($State in @('Partial','Failed','NotSupported','NotRequested','NotTested')) {
                $Fact.CollectionState=$State
                (Get-PSIADSecurityRuleOutcome $Rule @($Fact) $Security.Thresholds $DC $Snapshot.Domains[0].Name).Status | Should -Be NotTested -Because "$($Rule.Id) / $State"
            }
            $Fact.CollectionState='Collected'
            if (@($Rule.Review).Count) {
                $Fact.Value=@($Rule.Review)[0]
                (Get-PSIADSecurityRuleOutcome $Rule @($Fact) $Security.Thresholds $DC $Snapshot.Domains[0].Name).Status | Should -Be Review -Because $Rule.Id
            }
            elseif ($Rule.Threshold) {
                $Fact.Value=if ($Rule.Id -eq 'event-retention') { 100 } else { 500 }
                (Get-PSIADSecurityRuleOutcome $Rule @($Fact) $Security.Thresholds $DC $Snapshot.Domains[0].Name).Status | Should -Be Review -Because $Rule.Id
            }
            if (@($Rule.Bad).Count) {
                $Fact.Value=@($Rule.Bad)[0]
                (Get-PSIADSecurityRuleOutcome $Rule @($Fact) $Security.Thresholds $DC $Snapshot.Domains[0].Name).Status | Should -Be Blocked -Because $Rule.Id
            }
        }
    }
    It 'keeps selected registry values separate from effective policy' {
        $Rule=@($Security.RulePack.Rules | Where-Object Id -eq 'ldap-signing')[0]
        $Fact=[pscustomobject]@{ RuleId='ldap-signing'; DC=$Snapshot.DomainControllers[0].Name; CollectionState='Partial'; Value=2; EvidenceType='SelectedRegistry' }
        (Get-PSIADSecurityRuleOutcome $Rule @($Fact) $Security.Thresholds $Snapshot.DomainControllers[0] $Snapshot.Domains[0].Name).Status | Should -Be NotTested
        $Fact.Value=0
        (Get-PSIADSecurityRuleOutcome $Rule @($Fact) $Security.Thresholds $Snapshot.DomainControllers[0] $Snapshot.Domains[0].Name).Status | Should -Be Review
    }
    It 'makes DNS-only checks NotApplicable on a non-DNS DC' {
        $Rule=@($Security.RulePack.Rules | Where-Object Id -eq 'dns-zone-transfer')[0]
        $DC=@($Snapshot.DomainControllers | Where-Object DNSRole -eq $false)[0]
        (Get-PSIADSecurityRuleOutcome $Rule @() $Security.Thresholds $DC $Snapshot.Domains[0].Name).Status | Should -Be NotApplicable
    }
    It 'uses the generic score and critical override without confusing collection coverage' {
        $Security.SecurityVerdict | Should -Be Critical
        $Security.Assessment.Decision | Should -Be NotReady
        $Security.Assessment.Score | Should -BeLessThan 100
        $Security.Assessment.Score | Should -Not -Be $Security.SecurityEvidence.CollectionCoverage.OverallPercent
        $Security.Assessment.ScoreExplanation.Counts.Blocked | Should -BeGreaterThan 0
    }
    It 'shows secure, review, critical and unverified DCs without promoting missing evidence' {
        @($Security.DCStates | ForEach-Object Status | Sort-Object -Unique) | Should -Be @('Critical','Healthy','NotChecked','Warning')
        (@($Security.DCStates | Where-Object DC -eq 'dc-02.corp.example')[0]).Status | Should -Be Healthy
        (@($Security.DCStates | Where-Object DC -eq 'dc-08.corp.example')[0]).Status | Should -Be NotChecked
        (@($Security.DCStates | Where-Object DC -eq 'dc-05.corp.example')[0]).Status | Should -Be Critical
    }
    It 'links observed NTLMv1 risk to the affected DC and evidence' {
        $Check=@($Security.Assessment.Checks | Where-Object Id -eq 'security-check-ntlmv1-usage-dc-5')[0]
        $Check.Status | Should -Be Blocked
        $Check.EvidenceIds.Count | Should -BeGreaterThan 0
        $Finding=@($Security.Model.Findings | Where-Object Id -eq 'security-finding-ntlmv1-usage-dc-5')[0]
        $Finding.AffectedResourceIds | Should -Contain 'dc-5'
        $Finding.Recommendation.Action | Should -Match 'client'
    }
    It 'preserves domain-scoped privileged and identity checks' {
        @($Security.Assessment.Checks | Where-Object { $_.CategoryId -eq 'privileged' }).Count | Should -Be 2
        @($Security.Assessment.Checks | Where-Object { $_.CategoryId -eq 'identity' }).Count | Should -Be 1
        (@($Security.Assessment.Checks | Where-Object Id -eq 'security-check-privileged-members-domain')[0]).Status | Should -Be Review
    }
    It 'rejects unsupported or invalid threshold overrides' {
        { Test-PSIADSecurity $Snapshot $Evidence @{ Arbitrary=1 } } | Should -Throw '*Unknown*'
        { Test-PSIADSecurity $Snapshot $Evidence @{ ReadyScoreMinimum=101 } } | Should -Throw '*ordering*'
    }
    It 'retains an approved exception alongside the observed critical condition' {
        $Exception=@{ Id='security-exception-one'; Title='Fictional approved risk'; Reason='Dependency review in progress'; Status='Approved'; ApprovedBy='Fictional reviewer'; ApprovedAt=(Get-Date); ResourceIds=@('dc-5') }
        $WithException=Test-PSIADSecurity -Snapshot $Snapshot -SecurityEvidence $Evidence -Exceptions @($Exception)
        $WithException.Assessment.Exceptions.Count | Should -Be 1
        $WithException.SecurityVerdict | Should -Be Critical
        $WithException.Assessment.Score | Should -Be $Security.Assessment.Score
        @($WithException.Model.Findings | Where-Object Id -eq 'security-finding-ntlmv1-usage-dc-5').Count | Should -Be 1
    }
    It 'uses all implemented categories with no empty category views' {
        foreach ($Category in $Security.RulePack.Categories) { @($Security.Assessment.Checks | Where-Object CategoryId -eq $Category.Id).Count | Should -BeGreaterThan 0 -Because $Category.Id }
    }
    It 'runs mocked-live evidence without upgrading registry facts into secure policy' {
        $Adapter=New-PSIADLiveFixtureAdapter
        $MockSnapshot=ConvertTo-PSIADDCReadinessModel (Collect-PSIADSnapshot -Domain root.example.test -Profile Security -CommandAdapter $Adapter)
        $MockEvidence=New-PSIADSecurityEvidenceModel $MockSnapshot
        $Mock=Test-PSIADSecurity $MockSnapshot $MockEvidence
        $Mock.SecurityVerdict | Should -Be Critical
        $MockEvidence.EvidenceCompleteness.Percent | Should -BeGreaterThan 0
        (@($Mock.Assessment.Checks | Where-Object { $_.Status -eq 'Blocked' -and $_.Metadata.RuleId -eq 'ntlmv1-usage' })).Count | Should -Be 1
        @($Mock.Assessment.Checks | Where-Object { $_.Status -eq 'NotTested' }).Count | Should -BeGreaterThan 0
        @($Mock.Model.Resources | Where-Object { $_.Type -eq 'Domain Controller' }).Count | Should -Be 3
        @($Mock.TopologyNodes | Where-Object { $_.ResourceId -eq 'dc-child' }).Count | Should -Be 0
    }
    It 'reuses one snapshot for Inventory, both Readiness profiles, Health and Security without mutation' {
        $Before=$Snapshot | ConvertTo-Json -Depth 30 -Compress
        $Inventory=New-PSIADDCInventoryModel $Snapshot
        $Ready2022=Test-PSIADDCReadiness -Inventory $Snapshot -TargetOS 2022
        $Ready2025=Test-PSIADDCReadiness -Inventory $Snapshot -TargetOS 2025
        $HealthEvidence=New-PSIADHealthEvidenceModel $Snapshot
        $null=Add-PSIADHealthFictionalObservations $Snapshot $HealthEvidence
        $Health=Test-PSIADHealth $Snapshot $HealthEvidence
        $Inventory.Summary.DCCount | Should -Be 8
        $Ready2022.Assessment.Score | Should -Be 62.3
        $Ready2022.Assessment.Decision | Should -Be Incomplete
        $Ready2025.Assessment.Score | Should -Be 56.1
        $Ready2025.Assessment.Decision | Should -Be NotReady
        $Health.HealthVerdict | Should -Be Critical
        $Health.Assessment.Score | Should -Be 61.8
        $Security.Assessment.AssessmentType | Should -Be Security
        ($Snapshot | ConvertTo-Json -Depth 30 -Compress) | Should -BeExactly $Before
        (@($Inventory.DomainControllers | Where-Object Name -eq 'dc-05.corp.example')[0]).PSObject.Properties['Status'] | Should -BeNullOrEmpty
    }
    It 'keeps unassessed replication edges neutral and all DC nodes selectable' {
        @($Security.TopologyNodes | Where-Object ResourceId).Count | Should -Be 8
        @($Security.TopologyEdges | Where-Object Status -ne Unknown).Count | Should -Be 0
    }
    It 'renders a standalone application with Security views and print contract' {
        $Out=Join-Path $TestDrive 'security'
        $Result=& (Join-Path $ModuleRoot 'Examples/ActiveDirectory/Security/Invoke-PSIADSecurity.ps1') -Snapshot $Snapshot -OutputPath $Out -NoBrowser -PassThru
        Test-Path $Result.HtmlPath | Should -BeTrue
        $Html=Get-Content $Result.HtmlPath -Raw
        $Html | Should -Match 'security-topology'
        $Html | Should -Match 'security-controller-register'
        $Html | Should -Match 'security-check-explorer'
        $Html | Should -Match 'psi-print-document'
        $Html | Should -Match '<dt>Security score</dt>'
        $Html | Should -Not -Match 'readiness score'
        $Html | Should -Not -Match '<script[^>]+src='
        $Html | Should -Not -Match '<link[^>]+href='
    }
}
