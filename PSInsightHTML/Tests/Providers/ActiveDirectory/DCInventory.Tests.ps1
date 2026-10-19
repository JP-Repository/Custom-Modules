$ModuleRoot=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
Describe 'AD DC inventory on the shared normalized snapshot' {
    BeforeAll {
        $script:ModuleRoot=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
        Import-Module (Join-Path $script:ModuleRoot 'PSInsightHTML.psd1') -Force
        . (Join-Path $script:ModuleRoot 'Providers/ActiveDirectory/Shared/Import-PSIADProvider.ps1')
        . (Join-Path $script:ModuleRoot 'Providers/ActiveDirectory/Fixtures/New-PSIADLiveFixtureAdapter.ps1')
        $script:Snapshot=ConvertTo-PSIADDCReadinessModel (Collect-PSIADSnapshot -UseSampleData -Profile Operational)
        $script:Inventory=New-PSIADDCInventoryModel -Snapshot $script:Snapshot
        $script:Presentation=New-PSIADDCInventoryPresentation -Snapshot $script:Snapshot -Inventory $script:Inventory
    }
    It 'projects domain and forest context without a score or decision' {
        $Inventory.Summary.Domain | Should -Be 'corp.example'
        $Inventory.Summary.Forest | Should -Be 'corp.example'
        $Inventory.Summary.DCCount | Should -Be 8
        $Inventory.Summary.GCCount | Should -Be 7
        $Inventory.Summary.SiteCount | Should -Be 4
        $Inventory.Summary.SubnetCount | Should -Be 4
        $Inventory.Summary.Profile | Should -Be 'Operational'
        $Inventory.PSObject.Properties['Score'] | Should -BeNullOrEmpty
    }
    It 'projects DC, DNS, time, system, services and shares only from observed fields' {
        $Inventory.DomainControllers[0].Name | Should -Be 'dc-01.corp.example'
        $Inventory.DomainControllers[0].OS | Should -Be 'Windows Server 2016'
        $Inventory.DNSClients[0].PrimaryDNS | Should -Be '10.40.1.11'
        @($Inventory.DNSForwarders | Where-Object { $_.DC -eq 'dc-01.corp.example' }).Count | Should -Be 2
        @($Inventory.Time | Where-Object PDC).Count | Should -Be 1
        $Inventory.System[0].UptimeDays | Should -Be 14
        $Inventory.System[0].CPU | Should -Be 20
        $Inventory.System[0].MemoryGB | Should -Be 32
        $Inventory.System[0].SystemDrive | Should -Be 'C:'
        $Inventory.DomainControllers[0].IPv4 | Should -Be '10.40.1.11'
        $Inventory.System[0].NICSubnets | Should -Be '255.255.255.0'
        @($Inventory.Services | Where-Object Service -eq 'NTDS').Count | Should -Be 8
        @($Inventory.Shares | Where-Object Share -eq 'SYSVOL').Count | Should -Be 7
    }
    It 'keeps forest FSMO distinct from domain FSMO and retains site/subnet/replication facts' {
        @($Inventory.FSMORoles | Where-Object Scope -eq Forest).Count | Should -Be 2
        @($Inventory.FSMORoles | Where-Object Scope -eq 'corp.example').Count | Should -Be 3
        $Inventory.Subnets.Count | Should -Be 4
        $Inventory.Replication.Count | Should -Be 5
        @($Inventory.Replication | Where-Object { $_.External -and $_.EvidenceOnly }).Count | Should -Be 1
    }
    It 'preserves overlapping raw DC facts without a second inventory collector' {
        foreach ($SourceDC in $Snapshot.DomainControllers) {
            $Projected=@($Inventory.DomainControllers | Where-Object Name -eq $SourceDC.Name)[0]
            $Projected.Site | Should -Be $SourceDC.Site
            $Projected.OS | Should -Be $SourceDC.OS
            $Projected.Build | Should -Be $SourceDC.Build
            $Projected.GlobalCatalog | Should -Be $SourceDC.GlobalCatalog
            $Projected.IPv4 | Should -Be $SourceDC.IPv4Address
            $Projected.PrimaryDNS | Should -Be $SourceDC.DNSClient[0]
            $Projected.DNSForwarders.Count | Should -Be $SourceDC.DNSForwarders.Count
            $Projected.TimeSource | Should -Be $SourceDC.TimeSource
            $Projected.Shares.Count | Should -Be ([int]$SourceDC.SysvolShare + [int]$SourceDC.NetlogonShare)
        }
    }
    It 'creates neutral resources, hierarchy, topology and collection evidence' {
        $Presentation.Model.Findings.Count | Should -Be 0
        @($Presentation.Model.Resources | Where-Object { $_.Status -notin @('Unknown','NotChecked') }).Count | Should -Be 0
        @($Presentation.Model.Relationships | Where-Object { $_.Status -notin @('Unknown','NotChecked') }).Count | Should -Be 0
        $Presentation.TreeNodes.Count | Should -Be 14
        $Presentation.TopologyEdges.Count | Should -Be 5
        @($Presentation.Model.Relationships | Where-Object Type -eq 'replicates-with').Count | Should -Be 4
        $Presentation.Model.Evidence.Count | Should -BeGreaterThan 0
        @($Presentation.Model.Resources | Where-Object { $_.EvidenceIds.Count -gt 0 }).Count | Should -BeGreaterThan 0
    }
    It 'reuses one snapshot for inventory and two readiness versions without mutation' {
        $Before=ConvertTo-Json -InputObject $Snapshot -Depth 20 -Compress
        $null=New-PSIADDCInventoryModel -Snapshot $Snapshot
        (Test-PSIADDCReadiness -Inventory $Snapshot -TargetOS 2022).Assessment.Decision | Should -Be Incomplete
        (Test-PSIADDCReadiness -Inventory $Snapshot -TargetOS 2025).Assessment.Decision | Should -Be NotReady
        (ConvertTo-Json -InputObject $Snapshot -Depth 20 -Compress) | Should -Be $Before
    }
    It 'keeps explicit target domain scope with child-domain replication as evidence only' {
        $PreviousHostDomain=$env:USERDNSDOMAIN
        try {
            $env:USERDNSDOMAIN='child.example.test'
            $Raw=Collect-PSIADSnapshot -Domain root.example.test -CommandAdapter (New-PSIADLiveFixtureAdapter) -Profile Operational
        } finally { $env:USERDNSDOMAIN=$PreviousHostDomain }
        $Mock=ConvertTo-PSIADDCReadinessModel $Raw
        $Projected=New-PSIADDCInventoryModel -Snapshot $Mock
        $Projected.Summary.Domain | Should -Be 'root.example.test'
        $Projected.Summary.Forest | Should -Be 'example.test'
        $Projected.DomainControllers.Count | Should -Be 3
        @($Projected.DomainControllers | Where-Object { $_.Name -like '*child*' }).Count | Should -Be 0
        @($Projected.Replication | Where-Object { $_.External -and $_.EvidenceOnly }).Count | Should -BeGreaterThan 0
        @($Projected.DNSForwarders | Where-Object CollectionState -eq NotSupported).Count | Should -Be 3
        $Projected.System[0].MemoryGB | Should -Be 32
        $Projected.System[0].SystemDrive | Should -Be 'C:'
        $Projected.System[0].NICSubnets | Should -Be '255.255.255.128'
        $Projected.System[2].MemoryGB | Should -BeNullOrEmpty
        $Projected.CollectionCoverage.OverallPercent | Should -BeLessThan 100
        $MockPresentation=New-PSIADDCInventoryPresentation -Snapshot $Mock -Inventory $Projected
        @($MockPresentation.Model.Resources | Where-Object { $_.Type -eq 'Domain Controller' -and $_.EvidenceIds.Count -gt 0 }).Count | Should -Be 3
    }
    It 'generates a standalone report with inventory views, print tables and safe HTML' {
        $Folder=Join-Path ([System.IO.Path]::GetTempPath()) ('psi-ad-inventory-' + [guid]::NewGuid().ToString('N'))
        try {
            $Result=& (Join-Path $ModuleRoot 'Examples/ActiveDirectory/DCInventory/Invoke-PSIADDCInventory.ps1') -Snapshot $Snapshot -OutputPath $Folder -NoBrowser -PassThru
            $Html=[System.IO.File]::ReadAllText($Result.HtmlPath)
            $Html | Should -Match 'inventory-controllers|inventory-dns-forwarders|inventory-tree|inventory-topology'
            $Html | Should -Match 'psi-print-inventory-tables'
            $Html | Should -Match 'Collection Coverage'
            $Html | Should -Not -Match '<script\s+[^>]*src\s*=|<link\s+[^>]*href\s*=|<img\s+[^>]*src\s*='
            $Result.Report.ApplicationAssessment | Should -BeNullOrEmpty
            $Result.Presentation.Model.Findings.Count | Should -Be 0
        } finally { if (Test-Path $Folder) { Remove-Item $Folder -Recurse -Force } }
    }
    It 'uses PowerShell 5.1 compatible syntax and does not add a module public command' {
        (Get-Command New-PSIADDCInventoryModel -Module PSInsightHTML -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
        foreach ($File in @('Models/New-PSIADDCInventoryModel.ps1','Models/New-PSIADDCInventoryPresentation.ps1')) {
            $Path=Join-Path $ModuleRoot ('Providers/ActiveDirectory/' + $File)
            $Errors=$null
            [System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$null,[ref]$Errors) | Out-Null
            @($Errors).Count | Should -Be 0
            (Get-Content $Path -Raw) | Should -Not -Match '\?\?|\?\.|\s-Parallel\b'
        }
    }
}
