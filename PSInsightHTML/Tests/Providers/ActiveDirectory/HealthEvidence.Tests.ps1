$ModuleRoot=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
Describe 'AD health evidence foundation' {
    BeforeAll {
        $script:ModuleRoot=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
        Import-Module (Join-Path $ModuleRoot 'PSInsightHTML.psd1') -Force
        . (Join-Path $ModuleRoot 'Providers/ActiveDirectory/Shared/Import-PSIADProvider.ps1')
        . (Join-Path $ModuleRoot 'Providers/ActiveDirectory/Fixtures/New-PSIADLiveFixtureAdapter.ps1')
        $script:Sample=ConvertTo-PSIADDCReadinessModel (Collect-PSIADSnapshot -UseSampleData -Profile Health)
        $script:Evidence=New-PSIADHealthEvidenceModel -Snapshot $Sample
    }
    It 'keeps the health projection private and verdict-free' {
        $Evidence.Kind | Should -Be 'ActiveDirectory.HealthEvidence'
        $Evidence.NoHealthVerdict | Should -BeTrue
        $Evidence.PSObject.Properties['Score'] | Should -BeNullOrEmpty
        $Evidence.PSObject.Properties['Findings'] | Should -BeNullOrEmpty
        (Get-Command New-PSIADHealthEvidenceModel -Module PSInsightHTML -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
    }
    It 'uses one attributable observation contract and supported collection vocabulary' {
        $Evidence.Observations.Count | Should -BeGreaterThan 100
        foreach ($Item in $Evidence.Observations) {
            $Item.Domain | Should -Be 'corp.example'
            $Item.DC | Should -Not -BeNullOrEmpty
            $Item.Collector | Should -Not -BeNullOrEmpty
            $Item.Timestamp | Should -BeOfType [datetime]
            $Item.CollectionState | Should -BeIn @('Collected','Partial','Failed','NotSupported','NotRequested','NotTested')
            $Item.CollectionMethod | Should -Not -BeNullOrEmpty
        }
        @($Evidence.Observations | Select-Object -ExpandProperty CollectionState -Unique).Count | Should -Be 6
    }
    It 'distinguishes CPU collection from unavailable CPU evidence' {
        (@($Evidence.Observations | Where-Object { $_.Type -eq 'CPU' -and $_.DC -eq 'dc-01.corp.example' })[0]).Value | Should -Be 20
        $Failed=@($Evidence.Observations | Where-Object { $_.Type -eq 'CPU' -and $_.DC -eq 'dc-08.corp.example' })[0]
        $Failed.CollectionState | Should -Be Failed
        $Failed.ErrorClass | Should -Be Timeout
    }
    It 'normalizes memory, disk and uptime without health thresholds' {
        $Memory=@($Evidence.Observations | Where-Object { $_.Type -eq 'Memory' -and $_.DC -eq 'dc-01.corp.example' })[0]
        $Memory.Value.TotalGB | Should -Be 32
        $Memory.Value.AvailableGB | Should -Be 16
        $Memory.Value.UsedPercent | Should -Be 50
        $Disk=@($Evidence.Observations | Where-Object { $_.Type -eq 'Disk' -and $_.DC -eq 'dc-01.corp.example' })[0]
        $Disk.Value.Drive | Should -Be 'C:'
        $Disk.Value.FreePercent | Should -Be 24
        $Evidence.PSObject.Properties['Thresholds'] | Should -BeNullOrEmpty
    }
    It 'keeps Windows features separate from DC role and DNS service observations' {
        $Feature=@($Evidence.Observations | Where-Object { $_.Type -eq 'WindowsFeatures' -and $_.DC -eq 'dc-01.corp.example' })[0]
        $Feature.Value[0].Name | Should -Be 'AD-Domain-Services'
        (@($Evidence.Observations | Where-Object { $_.Type -eq 'WindowsFeatures' -and $_.DC -eq 'dc-07.corp.example' })[0]).CollectionState | Should -Be NotSupported
        @($Evidence.Observations | Where-Object { $_.Type -eq 'Service' -and $_.Value.Name -eq 'DNS' }).Count | Should -Be 8
    }
    It 'separates services, shares and DFSR migration evidence' {
        $Service=@($Evidence.Observations | Where-Object { $_.Type -eq 'Service' -and $_.Value.Name -eq 'NTDS' })[0]
        $Service.Value.DisplayName | Should -Be 'Active Directory Domain Services'
        $Service.Value.StartMode | Should -Be Auto
        @($Evidence.Observations | Where-Object { $_.Type -eq 'Share' -and $_.Value.Name -eq 'SYSVOL' }).Count | Should -Be 8
        @($Evidence.Observations | Where-Object { $_.Type -eq 'Share' -and $_.Value.Name -eq 'NETLOGON' }).Count | Should -Be 8
        (@($Evidence.Observations | Where-Object Type -eq DFSRMigration)[0]).Value | Should -Be Eliminated
    }
    It 'retains replication queries and link fields independently' {
        @($Evidence.Observations | Where-Object Type -eq ReplicationQuery).Count | Should -Be 16
        $Link=@($Evidence.Observations | Where-Object Type -eq Replication)[0]
        $Link.Value.Destination | Should -Not -BeNullOrEmpty
        $Link.Value.NamingContext | Should -Not -BeNullOrEmpty
        $Link.Value.LastSuccess | Should -BeOfType [datetime]
    }
    It 'keeps DNS, time and site-link query states explicit' {
        @($Evidence.Observations | Where-Object Type -eq DNSClient).Count | Should -Be 8
        @($Evidence.Observations | Where-Object Type -eq DNSForwarders).Count | Should -Be 8
        $Time=@($Evidence.Observations | Where-Object { $_.Type -eq 'TimeSource' -and $_.DC -eq 'dc-02.corp.example' })[0]
        $Time.Value.PDC | Should -BeTrue
        $Time.Value.ObservedSource | Should -Be 'ntp-a.example'
        $Sites=@($Evidence.Observations | Where-Object Type -eq SiteLinks)[0]
        $Sites.CollectionState | Should -Be Collected
        $Sites.Value.Count | Should -Be 1
    }
    It 'distinguishes an empty site-link query from a failed query' {
        $Adapter=New-PSIADLiveFixtureAdapter
        $Adapter.SiteLinks={ param($Name) @() }
        $Empty=ConvertTo-PSIADDCReadinessModel (Collect-PSIADSnapshot -Domain root.example.test -CommandAdapter $Adapter)
        $Empty.SiteLinks.Count | Should -Be 0
        $Empty.SiteLinkCollectionState | Should -Be Collected
        $Observation=@((New-PSIADHealthEvidenceModel $Empty).Observations | Where-Object Type -eq SiteLinks)[0]
        $Observation.EmptyResult | Should -BeTrue
        $Adapter.SiteLinks={ param($Name) throw [System.TimeoutException]::new('Fictional site-link timeout') }
        $Failed=ConvertTo-PSIADDCReadinessModel (Collect-PSIADSnapshot -Domain root.example.test -CommandAdapter $Adapter)
        $Failed.SiteLinkCollectionState | Should -Be Failed
        (@((New-PSIADHealthEvidenceModel $Failed).Observations | Where-Object Type -eq SiteLinks)[0]).ErrorClass | Should -Be Timeout
    }
    It 'keeps event content bounded and reports a query window' {
        $Event=@($Evidence.Observations | Where-Object Type -eq Event)[0]
        $Event.Value.EventId | Should -Be 1000
        $Event.Value.MessageSummary | Should -Be 'Fictional startup event'
        $Event.Value.QueryWindowHours | Should -Be 72
        @($Evidence.Observations | Where-Object { $_.Type -eq 'EventQuery' -and $_.CollectionState -eq 'Partial' }).Count | Should -Be 1
    }
    It 'requires typed, scoped, attributed backup provider input' {
        $Backup=[pscustomobject]@{ DC='dc-01.corp.example'; LastSuccessfulSystemStateBackup=(Get-Date).AddDays(-1); Source='Fictional backup console'; Confidence='Medium' }
        $Raw=Collect-PSIADSnapshot -UseSampleData -BackupInput @($Backup)
        $Model=New-PSIADHealthEvidenceModel (ConvertTo-PSIADDCReadinessModel $Raw)
        $Observed=@($Model.Observations | Where-Object { $_.Type -eq 'Backup' -and $_.CollectionState -eq 'Collected' })[0]
        $Observed.Value.LastSuccessfulSystemStateBackup | Should -BeOfType [datetime]
        $Observed.Confidence | Should -Be Medium
        @($Model.Observations | Where-Object { $_.Type -eq 'Backup' -and $_.CollectionState -eq 'NotRequested' }).Count | Should -Be 7
        { [pscustomobject]@{ DC='not-in-scope'; Source='x'; LastSuccessfulSystemStateBackup=(Get-Date) } | ConvertTo-PSIADBackupInput -Domain corp.example -DomainControllers @('dc-01.corp.example') } | Should -Throw '*not in the collected domain*'
        { [pscustomobject]@{ DC='dc-01.corp.example'; Source='x'; LastSuccessfulSystemStateBackup=(Get-Date); EvidenceTimestamp='yesterday' } | ConvertTo-PSIADBackupInput -Domain corp.example -DomainControllers @('dc-01.corp.example') } | Should -Throw '*EvidenceTimestamp*typed DateTime*'
    }
    It 'keeps pending reboot and connectivity evidence separate from verdicts' {
        @($Evidence.Observations | Where-Object Type -eq PendingReboot).Count | Should -Be 8
        $Port=@($Evidence.Observations | Where-Object Type -eq Port)[0]
        $Port.Value.Source | Should -Not -BeNullOrEmpty
        $Port.Value.Destination | Should -Not -BeNullOrEmpty
        $Port.Value.Result | Should -Not -BeNullOrEmpty
    }
    It 'classifies structured collector errors and successful empty queries' {
        $Results=[System.Collections.Generic.List[object]]::new(); $Logs=[System.Collections.Generic.List[object]]::new()
        $null=Invoke-PSIADCollector -Adapter @{ Probe={ @() } } -Id Probe -Category HealthEvidence -Scope dc-a -Arguments @() -Results $Results -Logs $Logs
        $Results[0].Status | Should -Be Collected
        $Results[0].Notes | Should -Match 'no records returned'
        $null=Invoke-PSIADCollector -Adapter @{ Probe={ throw [System.TimeoutException]::new('Timed out') } } -Id Probe -Category HealthEvidence -Scope dc-a -Arguments @() -Results $Results -Logs $Logs
        $Results[1].ErrorClass | Should -Be Timeout
        $null=Invoke-PSIADCollector -Adapter @{} -Id Probe -Category HealthEvidence -Scope dc-a -Arguments @() -Results $Results -Logs $Logs
        $Results[2].Status | Should -Be NotSupported
        $null=Invoke-PSIADCollector -Adapter @{ Probe={ throw [System.UnauthorizedAccessException]::new('Denied') } } -Id Probe -Category HealthEvidence -Scope dc-a -Arguments @() -Results $Results -Logs $Logs
        $Results[3].ErrorClass | Should -Be AccessDenied
    }
    It 'keeps Core remote-free and makes Health an explicit additive scope' {
        (Resolve-PSIADCollectionOptions -Profile Core).IncludeHealthEvidence | Should -BeFalse
        (Resolve-PSIADCollectionOptions -Profile Core).IncludeRemoteChecks | Should -BeFalse
        (Resolve-PSIADCollectionOptions -Profile Health).IncludeHealthEvidence | Should -BeTrue
        (Resolve-PSIADCollectionOptions -Profile Health).IncludeRemoteChecks | Should -BeTrue
        $Core=ConvertTo-PSIADDCReadinessModel (Collect-PSIADSnapshot -Domain root.example.test -CommandAdapter (New-PSIADLiveFixtureAdapter) -Profile Core)
        @($Core.CollectionResults | Where-Object { $_.CollectorId -eq 'Cpu' -and $_.Status -eq 'NotRequested' }).Count | Should -Be 3
    }
    It 'collects mocked-live CPU, memory, features, events and partial collection states' {
        $Raw=Collect-PSIADSnapshot -Domain root.example.test -CommandAdapter (New-PSIADLiveFixtureAdapter) -Profile Health -EventWindowHours 24
        $Live=ConvertTo-PSIADDCReadinessModel $Raw
        $Health=New-PSIADHealthEvidenceModel $Live
        $Live.DomainControllers[0].CPU | Should -Be 30
        $Live.DomainControllers[0].MemoryAvailableGB | Should -Be 16
        $Live.DomainControllers[0].MemoryUsedPercent | Should -Be 50
        $Live.DomainControllers[0].InstalledFeatures.Count | Should -Be 2
        $Live.SiteLinkCollectionState | Should -Be Collected
        $Live.UnmappedSubnets.Count | Should -Be 1
        $Live.UnmappedSubnets[0].Name | Should -Be '198.51.100.0/24'
        $Health.EventWindowHours | Should -Be 24
        (@($Health.Observations | Where-Object { $_.Type -eq 'CPU' -and $_.DC -eq 'dc-a.root.example.test' })[0]).Confidence | Should -Be High
        @($Health.Observations | Where-Object Type -eq Event).Count | Should -Be 3
        @($Live.CollectionResults | Where-Object { $_.CollectorId -eq 'Events' -and $_.Status -eq 'Partial' }).Count | Should -Be 3
        @($Live.CollectionResults | Where-Object { $_.CollectorId -eq 'Features' -and $_.Status -eq 'NotSupported' }).Count | Should -Be 1
        $Live.CollectionCoverage.OverallPercent | Should -BeLessThan 100
    }
    It 'reuses one snapshot across Inventory, both Readiness versions and Health without mutation' {
        $Before=ConvertTo-Json -InputObject $Sample -Depth 20 -Compress
        $Inventory=New-PSIADDCInventoryModel -Snapshot $Sample
        $Inventory.DomainControllers[0].CPU | Should -Be 20
        (Test-PSIADDCReadiness -Inventory $Sample -TargetOS 2022).Assessment.Score | Should -Be 62.3
        (Test-PSIADDCReadiness -Inventory $Sample -TargetOS 2025).Assessment.Score | Should -Be 56.1
        $null=New-PSIADHealthEvidenceModel -Snapshot $Sample
        (ConvertTo-Json -InputObject $Sample -Depth 20 -Compress) | Should -Be $Before
    }
    It 'parses provider files as PowerShell 5.1-compatible read-only source' {
        $Paths=@('Shared/ConvertTo-PSIADBackupInput.ps1','Collectors/Get-PSIADReadOnlyAdapter.ps1','Collectors/New-PSIADLiveSnapshot.ps1','Evidence/New-PSIADHealthEvidenceModel.ps1')
        foreach ($Relative in $Paths) {
            $Path=Join-Path $ModuleRoot ('Providers/ActiveDirectory/' + $Relative)
            $Errors=$null
            [System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$null,[ref]$Errors) | Out-Null
            @($Errors).Count | Should -Be 0
            (Get-Content $Path -Raw) | Should -Not -Match '\?\?|\?\.|\s-Parallel\b'
        }
        $Collectors=Get-ChildItem (Join-Path $ModuleRoot 'Providers/ActiveDirectory/Collectors') -Filter '*.ps1'
        foreach ($File in $Collectors) { (Get-Content $File.FullName -Raw) | Should -Not -Match '(?im)^\s*(Set-AD\w*|New-AD\w*|Remove-AD\w*|Add-AD\w*|Set-DnsServer\w*|Add-DnsServer\w*|Remove-DnsServer\w*|Set-ItemProperty|Restart-Service|Stop-Service|Start-Service|Restart-Computer)\b' }
    }
    It 'generates a standalone multi-view evidence report without a health assessment' {
        $Folder=Join-Path ([System.IO.Path]::GetTempPath()) ('psi-health-evidence-' + [guid]::NewGuid().ToString('N'))
        try {
            $Result=& (Join-Path $ModuleRoot 'Examples/ActiveDirectory/HealthEvidence/Invoke-PSIADHealthEvidence.ps1') -Snapshot $Sample -OutputPath $Folder -NoBrowser -PassThru
            $Html=[System.IO.File]::ReadAllText($Result.HtmlPath)
            $Html | Should -Match 'Evidence Foundation|Evidence foundation'
            $Html | Should -Match 'No Health Verdict'
            $Html | Should -Match 'health-dcs|health-services|health-events|health-coverage|health-register'
            $Html | Should -Not -Match '<script\s+[^>]*src\s*=|<link\s+[^>]*href\s*=|<img\s+[^>]*src\s*='
            $Result.Report.ApplicationAssessment | Should -BeNullOrEmpty
            $Result.Evidence.NoHealthVerdict | Should -BeTrue
        } finally { if (Test-Path $Folder) { Remove-Item $Folder -Recurse -Force } }
    }
}
