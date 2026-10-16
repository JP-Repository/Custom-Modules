$ProjectRoot=Split-Path $PSScriptRoot -Parent
$ProviderRoot=Join-Path $ProjectRoot 'Examples/ActiveDirectory/DCReadiness'
Describe 'AD DC readiness provider sample and rules' {
    BeforeAll {
        $script:ProviderRoot=Join-Path (Split-Path $PSScriptRoot -Parent) 'Examples/ActiveDirectory/DCReadiness'
        Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'PSInsightHTML.psd1') -Force
        . (Join-Path $ProviderRoot 'SampleData/New-PSIADDCReadinessSample.ps1')
        . (Join-Path $ProviderRoot 'Live/Get-PSIADReadOnlyAdapter.ps1')
        . (Join-Path $ProviderRoot 'Live/Invoke-PSIADCollector.ps1')
        . (Join-Path $ProviderRoot 'Live/Get-PSIADCollectionCoverage.ps1')
        . (Join-Path $ProviderRoot 'Live/New-PSIADLiveSnapshot.ps1')
        . (Join-Path $ProviderRoot 'Live/Get-PSIADRuleCoverage.ps1')
        . (Join-Path $ProviderRoot 'Collect-PSIADDCReadiness.ps1')
        . (Join-Path $ProviderRoot 'ConvertTo-PSIADDCReadinessModel.ps1')
        . (Join-Path $ProviderRoot 'Get-PSIADDCReadinessOutcome.ps1')
        . (Join-Path $ProviderRoot 'Test-PSIADDCReadiness.ps1')
        $script:Sample=New-PSIADDCReadinessSample -AsOf ([datetime]'2026-10-16T12:00:00')
        $script:Inventory=ConvertTo-PSIADDCReadinessModel $script:Sample
        $script:Result22=Test-PSIADDCReadiness -Inventory $script:Inventory -TargetOS 2022
        $script:Result25=Test-PSIADDCReadiness -Inventory $script:Inventory -TargetOS 2025
    }
    It 'generates a deterministic, fictional eight-DC snapshot across sites and mixed operating systems' {
        $Sample.DomainControllers.Count | Should -Be 8
        $Sample.Sites.Count | Should -Be 4
        @($Sample.DomainControllers | Select-Object -ExpandProperty OS -Unique).Count | Should -Be 2
        $Sample.Forest.Name | Should -Be 'corp.example'
        $Sample.Forest.FunctionalLevel | Should -Be 2016
        @($Sample.DomainControllers | Where-Object { -not $_.Reachable }).Count | Should -Be 1
    }
    It 'keeps the sample path and rejects absent normalized fields' {
        (Collect-PSIADDCReadiness -UseSampleData).Sample | Should -BeTrue
        $Bad=New-PSIADDCReadinessSample; $Bad.DNS=$null
        { ConvertTo-PSIADDCReadinessModel $Bad } | Should -Throw '*requires DNS*'
    }
    It 'preserves typed dates and one normalized contract for either target' {
        $Inventory.Replication[0].LastSuccess | Should -BeOfType [datetime]
        $Inventory.CollectedAt | Should -BeOfType [datetime]
        [object]::ReferenceEquals($Result22.Inventory,$Inventory) | Should -BeTrue
        [object]::ReferenceEquals($Result25.Inventory,$Inventory) | Should -BeTrue
    }
    It 'uses separate versioned, source-referenced target rule packs' {
        $Result22.RulePack.TargetOS | Should -Be '2022'
        $Result25.RulePack.TargetOS | Should -Be '2025'
        foreach ($Result in @($Result22,$Result25)) {
            $Result.RulePack.Version | Should -Be '1.0.0'
            @($Result.RulePack.Rules | Where-Object { -not $_.SourceId -or -not $Result.Sources[$_.SourceId] }).Count | Should -Be 0
        }
    }
    It 'uses the 2022 interoperability matrix without requiring a 2016 functional level' {
        $Copy=New-PSIADDCReadinessSample; $Copy.Forest.FunctionalLevel='2012R2'; $Copy.Domains[0].FunctionalLevel='2012R2'
        $R=Test-PSIADDCReadiness -Inventory (ConvertTo-PSIADDCReadinessModel $Copy) -TargetOS 2022
        (@($R.Assessment.Checks | Where-Object Id -eq 'check-functional-level')[0]).Status | Should -Be 'Ready'
    }
    It 'blocks the 2025 target below the 2016 functional level' {
        $Copy=New-PSIADDCReadinessSample; $Copy.Forest.FunctionalLevel='2012R2'; $Copy.Domains[0].FunctionalLevel='2012R2'
        $R=Test-PSIADDCReadiness -Inventory (ConvertTo-PSIADDCReadinessModel $Copy) -TargetOS 2025
        (@($R.Assessment.Checks | Where-Object Id -eq 'check-functional-level')[0]).Status | Should -Be 'Blocked'
    }
    It 'differentiates the target decisions and Exchange CU13 interpretation' {
        $Result22.Assessment.Decision | Should -Be 'Incomplete'
        $Result25.Assessment.Decision | Should -Be 'NotReady'
        $Result22.Assessment.Score | Should -BeGreaterThan $Result25.Assessment.Score
        (@($Result22.Assessment.Checks | Where-Object Id -eq 'check-exchange')[0]).Status | Should -Be 'Review'
        (@($Result25.Assessment.Checks | Where-Object Id -eq 'check-exchange')[0]).Status | Should -Be 'Blocked'
        $Result25.Assessment.ScoreExplanation.Counts.Blockers | Should -Be 1
    }
    It 'treats unknown Exchange CU as review and Exchange 2016 as incompatible with 2025' {
        $Copy=New-PSIADDCReadinessSample; $Copy.Dependencies[0].CU=$null
        $R=Test-PSIADDCReadiness -Inventory (ConvertTo-PSIADDCReadinessModel $Copy) -TargetOS 2025
        (@($R.Assessment.Checks | Where-Object Id -eq 'check-exchange')[0]).Status | Should -Be 'Review'
        $Copy.Dependencies[0].Version='2016'; $Copy.Dependencies[0].CU=23
        $R=Test-PSIADDCReadiness -Inventory (ConvertTo-PSIADDCReadinessModel $Copy) -TargetOS 2025
        (@($R.Assessment.Checks | Where-Object Id -eq 'check-exchange')[0]).Status | Should -Be 'Blocked'
    }
    It 'treats recovered RPC history as review and current material failures as a blocker' {
        (@($Result22.Assessment.Checks | Where-Object Id -eq 'check-replication')[0]).Status | Should -Be 'Review'
        $Copy=New-PSIADDCReadinessSample; $Copy.Replication[0].CurrentFailures=3; $Copy.Replication[0].ConsecutiveFailures=3
        $R=Test-PSIADDCReadiness -Inventory (ConvertTo-PSIADDCReadinessModel $Copy) -TargetOS 2022
        (@($R.Assessment.Checks | Where-Object Id -eq 'check-replication')[0]).Status | Should -Be 'Blocked'
        $R.Assessment.Decision | Should -Be 'NotReady'
    }
    It 'blocks FRS SYSVOL but reviews the sample DNS concern without condemning self-DNS' {
        (@($Result22.Assessment.Checks | Where-Object Id -eq 'check-dns-forwarders')[0]).Status | Should -Be 'Review'
        $Copy=New-PSIADDCReadinessSample; $Copy.Forest.SysvolReplication='FRS'
        $R=Test-PSIADDCReadiness -Inventory (ConvertTo-PSIADDCReadinessModel $Copy) -TargetOS 2025
        (@($R.Assessment.Checks | Where-Object Id -eq 'check-sysvol')[0]).Status | Should -Be 'Blocked'
    }
    It 'uses the configured absolute disk threshold' {
        (@($Result22.Assessment.Checks | Where-Object Id -eq 'check-disk')[0]).Status | Should -Be 'Review'
        $Copy=New-PSIADDCReadinessSample; $Copy.DomainControllers[5].DiskFreeGB=10
        $R=Test-PSIADDCReadiness -Inventory (ConvertTo-PSIADDCReadinessModel $Copy) -TargetOS 2022
        (@($R.Assessment.Checks | Where-Object Id -eq 'check-disk')[0]).Status | Should -Be 'Ready'
    }
    It 'reviews approaching source OS support end and blocks an expired Server 2016 source state' {
        (@($Result22.Assessment.Checks | Where-Object Id -eq 'check-dc-inventory')[0]).Status | Should -Be 'Review'
        $Copy=New-PSIADDCReadinessSample -AsOf ([datetime]'2027-02-01')
        $R=Test-PSIADDCReadiness -Inventory (ConvertTo-PSIADDCReadinessModel $Copy) -TargetOS 2022
        (@($R.Assessment.Checks | Where-Object Id -eq 'check-dc-inventory')[0]).Status | Should -Be 'Blocked'
    }
    It 'provides security observations, GPO structure and post-build definitions' {
        $Result25.SecurityPack.Version | Should -Be '1.0.0'
        @($Result25.Assessment.Checks | Where-Object CategoryId -eq 'security').Count | Should -Be 17
        $Result25.GPO.Count | Should -Be 17
        $Result25.GPO[0].PSObject.Properties.Name | Should -Contain 'ConflictingGPO'
        $Result25.GPO[0].PSObject.Properties.Name | Should -Contain 'Validation'
        $Result25.PostBuild.Count | Should -Be 12
        @($Result25.PostBuild | Where-Object Status -eq 'NotTested').Count | Should -Be 12
    }
    It 'maps checks to PSI model resources, evidence, findings and relationships' {
        $Result25.Assessment.Checks.Count | Should -Be 45
        $Result25.Model.Resources.Count | Should -BeGreaterThan 18
        $Result25.Model.Evidence.Count | Should -Be 45
        $Result25.Model.Relationships.Count | Should -BeGreaterThan 10
        $Result25.Assessment.Checks[0].EvidenceIds.Count | Should -Be 1
        $Result25.Assessment.Checks[0].Metadata.SourceUrl | Should -Match '^https://learn.microsoft.com/'
    }
    It 'keeps the approved exception informational and source provenance explicit' {
        $Result25.Assessment.Exceptions.Count | Should -Be 1
        $Result25.Assessment.Decision | Should -Be 'NotReady'
        $Result25.Assessment.Checks[0].Metadata.LastReviewed | Should -Be '2026-10-16'
        $Result25.Sources.Exchange.Url | Should -Match 'learn.microsoft.com'
    }
    It 'retains the legacy provider catalog and does not export this example as core API' {
        @(Get-PSIReportCatalog).Count | Should -Be 6
        (Get-Command -Module PSInsightHTML -CommandType Function | Where-Object Name -eq 'Test-PSIADDCReadiness').Count | Should -Be 0
    }
    It 'generates standalone light and dark application views plus JSON and CSV outputs' {
        foreach ($Theme in @('Light','Dark')) {
            $Temp=Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
            try {
                & (Join-Path $ProviderRoot 'Invoke-PSIADDCReadiness.ps1') -TargetOS 2025 -UseSampleData -OutputPath $Temp -Theme $Theme -NoBrowser | Out-Null
                $Html=[System.IO.File]::ReadAllText((Join-Path $Temp 'DCReadiness-2025.html'))
                $Html | Should -Match ('data-theme="{0}"' -f $Theme)
                foreach ($View in @('overview','compatibility','replication','dns','security','gpo','checks','evidence','postbuild')) { $Html | Should -Match ('data-psi-app-view="{0}"' -f $View) }
                $Html | Should -Match 'NOT READY'
                $Html | Should -Not -Match '<script\s+[^>]*src\s*=|<link\s+[^>]*href\s*=|\bfetch\s*\('
                (Test-Path (Join-Path $Temp 'NormalizedInventory-2025.json')) | Should -BeTrue
                (Test-Path (Join-Path $Temp 'Checks-2025.csv')) | Should -BeTrue
                (Test-Path (Join-Path $Temp 'TargetComparison-2025.json')) | Should -BeTrue
            }
            finally { if (Test-Path $Temp) { Remove-Item -LiteralPath $Temp -Recurse -Force } }
        }
    }
}
