$ModuleRoot=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
Describe 'AD provider Health assessment' {
    BeforeAll {
        $script:ModuleRoot=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
        Import-Module (Join-Path $ModuleRoot 'PSInsightHTML.psd1') -Force
        . (Join-Path $ModuleRoot 'Providers/ActiveDirectory/Shared/Import-PSIADProvider.ps1')
        . (Join-Path $ModuleRoot 'Providers/ActiveDirectory/Fixtures/New-PSIADLiveFixtureAdapter.ps1')
        $script:Snapshot=ConvertTo-PSIADDCReadinessModel (Collect-PSIADSnapshot -UseSampleData -Profile Health)
        $script:Evidence=New-PSIADHealthEvidenceModel $Snapshot
        $script:Scenario=New-PSIADHealthEvidenceModel $Snapshot
        $null=Add-PSIADHealthFictionalObservations $Snapshot $Scenario
        $script:Health=Test-PSIADHealth $Snapshot $Scenario
    }
    It 'loads provider-owned versioned rules with source and evidence requirements' {
        $Health.RulePack.Version | Should -Be '1.0'
        $Health.RuleDefinitions.Count | Should -BeGreaterThan 25
        foreach ($Rule in $Health.RuleDefinitions) {
            $Rule.Source | Should -Be 'Provider-defined operational threshold'
            $Rule.EvidenceRequirements.Count | Should -BeGreaterThan 0
            $Rule.Validation | Should -Not -BeNullOrEmpty
        }
    }
    It 'does not export AD Health as a generic core module command' {
        Get-Command Test-PSIADHealth -Module PSInsightHTML -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        (Get-Command Add-PSITopology).Parameters.ContainsKey('FilterProperties') | Should -BeTrue
    }
    It 'maps the critical override through the existing assessment engine' {
        $Health.HealthVerdict | Should -Be Critical
        $Health.Assessment.Decision | Should -Be NotReady
        $Health.Assessment.Score | Should -BeLessThan 100
        $Health.Assessment.ScoreExplanation.Counts.Blocked | Should -BeGreaterThan 0
    }
    It 'separates Health score from collection coverage and readiness' {
        $Health.Assessment.Score | Should -Not -Be $Health.HealthEvidence.CollectionCoverage.OverallPercent
        $Health.Assessment.AssessmentType | Should -Be Health
    }
    It 'keeps all four controller presentation states without promoting required gaps to Healthy' {
        @($Health.DCStates | ForEach-Object Status | Sort-Object -Unique) | Should -Be @('Critical','Healthy','NotChecked','Warning')
        (@($Health.DCStates | Where-Object DC -eq 'dc-04.corp.example')[0]).Status | Should -Be NotChecked
        (@($Health.DCStates | Where-Object DC -eq 'dc-02.corp.example')[0]).Status | Should -Be Healthy
    }
    It 'marks unavailable DFSR folder evidence NotTested and RODC scope NotApplicable' {
        (@($Health.Assessment.Checks | Where-Object Id -eq 'health-check-dfsr-folder-dc-2')[0]).Status | Should -Be NotTested
        (@($Health.Assessment.Checks | Where-Object Id -eq 'health-check-dfsr-folder-dc-7')[0]).Status | Should -Be NotApplicable
    }
    It 'uses configured disk thresholds and a critical finding linked to the affected DC' {
        $Check=@($Health.Assessment.Checks | Where-Object Id -eq 'health-check-disk-dc-6')[0]
        $Check.Status | Should -Be Blocked
        $Finding=@($Health.Model.Findings | Where-Object Id -eq 'health-finding-disk-dc-6')[0]
        $Finding.AffectedResourceIds | Should -Contain 'dc-6'
        $Finding.EvidenceIds.Count | Should -BeGreaterThan 0
        $Changed=Test-PSIADHealth $Snapshot $Scenario @{ DiskCriticalFreeGB=5; DiskReviewFreeGB=15 }
        (@($Changed.Assessment.Checks | Where-Object Id -eq 'health-check-disk-dc-6')[0]).Status | Should -Be Review
    }
    It 'rejects invalid threshold overrides' {
        { Test-PSIADHealth $Snapshot $Scenario @{ DiskCriticalFreeGB=20; DiskReviewFreeGB=15 } } | Should -Throw '*ordering*'
        { Test-PSIADHealth $Snapshot $Scenario @{ ArbitraryThreshold=3 } } | Should -Throw '*Unknown*'
    }
    It 'keeps NotSupported and Failed DNS evidence unassessed in the mocked live adapter' {
        $Adapter=New-PSIADLiveFixtureAdapter
        $MockSnapshot=ConvertTo-PSIADDCReadinessModel (Collect-PSIADSnapshot -Domain root.example.test -Profile Health -CommandAdapter $Adapter)
        $MockEvidence=New-PSIADHealthEvidenceModel $MockSnapshot
        $Mock=Test-PSIADHealth $MockSnapshot $MockEvidence
        @($Mock.Assessment.Checks | Where-Object { $_.CategoryId -eq 'dns' -and $_.Status -eq 'NotTested' }).Count | Should -BeGreaterThan 0
        $Mock.HealthVerdict | Should -BeIn @('Critical','Incomplete','Review')
    }
    It 'links checks, findings, evidence, DC resources and replication edges' {
        $Health.Model.Evidence.Count | Should -BeGreaterThan 100
        (@($Health.Model.Resources | Where-Object Id -eq 'dc-6')[0]).FindingIds | Should -Contain 'health-finding-disk-dc-6'
        @($Health.TopologyNodes | Where-Object ResourceId -eq 'dc-6').Count | Should -Be 1
        @($Health.TopologyEdges | Where-Object Status -eq Critical).Count | Should -BeGreaterThan 0
        $Health.TopologyEdges[0].Description | Should -Match 'Naming context:'
        (@($Health.Model.Resources | Where-Object Id -eq 'dc-6')[0]).Properties.HealthReplication | Should -Be Critical
    }
    It 'does not mutate normalized inventory Health when building assessment' {
        $Inventory=New-PSIADDCInventoryModel $Snapshot
        @($Inventory.DomainControllers | Where-Object Name -eq 'dc-06.corp.example')[0].PSObject.Properties['Status'] | Should -BeNullOrEmpty
    }
    It 'supports one snapshot feeding inventory, both readiness profiles and Health' {
        $Inventory=New-PSIADDCInventoryModel $Snapshot
        $Ready2022=Test-PSIADDCReadiness -Inventory $Snapshot -TargetOS 2022
        $Ready2025=Test-PSIADDCReadiness -Inventory $Snapshot -TargetOS 2025
        $Inventory.Summary.DCCount | Should -Be 8
        $Ready2022.Assessment.AssessmentType | Should -Be Readiness
        $Ready2025.Assessment.AssessmentType | Should -Be Readiness
        $Health.Assessment.AssessmentType | Should -Be Health
    }
    It 'renders a standalone Health application with all main views and no external assets' {
        $Out=Join-Path $TestDrive 'health'
        $Result=& (Join-Path $ModuleRoot 'Examples/ActiveDirectory/Health/Invoke-PSIADHealth.ps1') -Snapshot $Snapshot -OutputPath $Out -NoBrowser -PassThru
        Test-Path $Result.HtmlPath | Should -BeTrue
        $Html=Get-Content $Result.HtmlPath -Raw
        $Html | Should -Match 'health-topology'
        $Html | Should -Match 'data-psi-rel-filter-detail="Site"'
        $Html | Should -Match 'health-site-summary'
        $Html | Should -Match 'health-controller-register'
        $Html | Should -Match 'health-check-explorer'
        $Html | Should -Match 'psi-print-document'
        $Html | Should -Not -Match '<script[^>]+src='
        $Html | Should -Not -Match '<link[^>]+href='
    }
}
