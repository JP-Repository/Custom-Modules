$ProjectRoot=Split-Path $PSScriptRoot -Parent
Describe 'AD DC readiness read-only live collector' {
    BeforeAll {
        $script:Provider=Join-Path (Split-Path $PSScriptRoot -Parent) 'Examples/ActiveDirectory/DCReadiness'
        Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'PSInsightHTML.psd1') -Force
        foreach ($Path in @('SampleData/New-PSIADDCReadinessSample.ps1','Live/Get-PSIADReadOnlyAdapter.ps1','Live/Invoke-PSIADCollector.ps1','Live/Get-PSIADCollectionCoverage.ps1','Live/New-PSIADLiveSnapshot.ps1','Live/Get-PSIADRuleCoverage.ps1','Collect-PSIADDCReadiness.ps1','ConvertTo-PSIADDCReadinessModel.ps1','Get-PSIADDCReadinessOutcome.ps1','Test-PSIADDCReadiness.ps1')) { . (Join-Path $Provider $Path) }
        function New-MockedADAdapter {
            $Adapter=@{
                Domain = { param($Name) [pscustomobject]@{ DNSRoot=if ($Name) { $Name } else { 'child.example.test' }; Forest='example.test'; DomainMode='Windows2016Domain'; NetBIOSName='CHILD'; DomainSID='S-1-5-21-123'; PDCEmulator='dc-child.child.example.test'; RIDMaster='dc-child.child.example.test'; InfrastructureMaster='dc-child.child.example.test' } }
                Forest = { param($Name) [pscustomobject]@{ Name=$Name; ForestMode='Windows2016Forest'; SchemaMaster='dc-child.child.example.test'; DomainNamingMaster='dc-child.child.example.test' } }
                DCs = { param($Name) if ($Name -ne 'child.example.test') { throw 'Unexpected domain scope' }; @([pscustomobject]@{ HostName='dc-child.child.example.test'; Domain='child.example.test'; Site='ChildSite'; IPv4Address='192.0.2.10'; OperatingSystem='Windows Server 2019'; OperatingSystemVersion='17763'; IsReadOnly=$false; IsGlobalCatalog=$true },[pscustomobject]@{ HostName='dc-root.example.test'; Domain='example.test'; Site='RootSite'; OperatingSystem='Windows Server 2019'; OperatingSystemVersion='17763'; IsReadOnly=$false; IsGlobalCatalog=$true }) }
                Sites = { param($Name) @([pscustomobject]@{ Name='ChildSite' }) }
                Subnets = { param($Name) @([pscustomobject]@{ Name='192.0.2.0/24'; Site='ChildSite' }) }
                SiteLinks = { param($Name) @() }
                Partners = { param($HostName) @([pscustomobject]@{ Partner=$HostName; Partition='DC=child,DC=example,DC=test'; ConsecutiveReplicationFailures=0; LastReplicationSuccess=(Get-Date).AddMinutes(-10); LastReplicationResult=0 }) }
                Failures = { param($HostName) @() }
                Remote = { param($HostName) [pscustomobject]@{ OS=[pscustomobject]@{ LastBootUpTime=(Get-Date).AddDays(-5) }; Disk=[pscustomobject]@{ FreeSpace=20GB; Size=100GB }; Services=@{ NTDS='Running'; Netlogon='Running'; DNS='Running'; DFSR='Running'; KDC='Running'; W32Time='Running' }; NICs=@([pscustomobject]@{ DNSServerSearchOrder=@('192.0.2.10','192.0.2.11') }) } }
                Shares = { param($HostName) @('SYSVOL','NETLOGON') }
                Time = { param($HostName) 'time.example.test' }
                DNS = { param($HostName) [pscustomobject]@{ Forwarders=@('192.0.2.53'); Zones=@([pscustomobject]@{ Name='child.example.test'; IsDsIntegrated=$true }); Conditional=@() } }
                Port = { param($HostName,$Port) $true }
                Dependencies = { param($Name) [pscustomobject]@{ Exchange=@([pscustomobject]@{ Name='EX-01'; AdminDisplayVersion='15.2.1234.5' }); PKI=@([pscustomobject]@{ Name='CA-01' }) } }
            }
            [pscustomobject]@{ Adapter=$Adapter }
        }
    }
    It 'scopes DC enumeration to the selected child domain and excludes root-domain DCs' {
        $Mock=New-MockedADAdapter
        $Snapshot=Collect-PSIADDCReadiness -Domain child.example.test -CommandAdapter $Mock.Adapter
        $Snapshot.DomainControllers.Count | Should -Be 1
        $Snapshot.DomainControllers[0].Domain | Should -Be 'child.example.test'
        $Snapshot.Domains.Count | Should -Be 1
        $Snapshot.Forest.Name | Should -Be 'example.test'
    }
    It 'resolves current domain when omitted and isolates an explicitly selected root domain' {
        $Child=Collect-PSIADDCReadiness -CommandAdapter (New-MockedADAdapter).Adapter
        $Child.Domains[0].Name | Should -Be 'child.example.test'
        $Mock=New-MockedADAdapter
        $Mock.Adapter.DCs={ param($Name) if ($Name -ne 'example.test') { throw 'Unexpected root scope' }; @([pscustomobject]@{ HostName='dc-root.example.test'; Domain='example.test'; Site='RootSite'; IPv4Address='192.0.2.20'; OperatingSystem='Windows Server 2019'; OperatingSystemVersion='17763'; IsReadOnly=$false; IsGlobalCatalog=$true }) }
        $Root=Collect-PSIADDCReadiness -Domain example.test -CommandAdapter $Mock.Adapter
        $Root.Domains[0].Name | Should -Be 'example.test'
        $Root.DomainControllers[0].Name | Should -Be 'dc-root.example.test'
        $Mock.Adapter.Domain={ param($Name) [pscustomobject]@{ DNSRoot='example.test'; Forest='example.test' } }
        { Collect-PSIADDCReadiness -Domain other.example.test -CommandAdapter $Mock.Adapter } | Should -Throw '*does not match requested domain*'
    }
    It 'uses the same normalized shape and evaluator as sample mode' {
        $Sample=ConvertTo-PSIADDCReadinessModel (Collect-PSIADDCReadiness -UseSampleData)
        $Live=ConvertTo-PSIADDCReadinessModel (Collect-PSIADDCReadiness -Domain child.example.test -CommandAdapter (New-MockedADAdapter).Adapter)
        @($Live.PSObject.Properties.Name | Where-Object { $_ -notin $Sample.PSObject.Properties.Name }).Count | Should -Be 0
        $Live.SchemaVersion | Should -Be '1.1'
        $Live.Replication[0].LastSuccess | Should -BeOfType [datetime]
        (Test-PSIADDCReadiness -Inventory $Live -TargetOS 2025).Assessment.Checks.Count | Should -Be 45
    }
    It 'records requested and omitted optional collectors without guessing health' {
        $Live=ConvertTo-PSIADDCReadinessModel (Collect-PSIADDCReadiness -Domain child.example.test -CommandAdapter (New-MockedADAdapter).Adapter)
        @($Live.CollectionResults | Where-Object { $_.CollectorId -eq 'Remote' -and $_.Status -eq 'NotRequested' }).Count | Should -Be 1
        @($Live.CollectionResults | Where-Object { $_.CollectorId -eq 'Security' -and $_.Status -eq 'NotRequested' }).Count | Should -Be 1
        $Assessment=Test-PSIADDCReadiness -Inventory $Live -TargetOS 2025
        (@($Assessment.Assessment.Checks | Where-Object Id -eq 'check-disk')[0]).Status | Should -Be 'NotTested'
        (@($Assessment.Assessment.Checks | Where-Object Id -eq 'check-dns-forwarders')[0]).Status | Should -Be 'NotTested'
        $Live.CollectionCoverage.OverallPercent | Should -BeGreaterThan 0
        $Live.CollectionCoverage.OverallPercent | Should -BeLessThan 100
        $Live.CollectionCoverage.OverallPercent | Should -Not -Be $Assessment.Assessment.Score
    }
    It 'continues after a failed replication query and distinguishes that from no failures' {
        $Mock=New-MockedADAdapter
        $Mock.Adapter.Failures={ param($HostName) throw 'Access denied' }
        $Live=ConvertTo-PSIADDCReadinessModel (Collect-PSIADDCReadiness -Domain child.example.test -CommandAdapter $Mock.Adapter)
        @($Live.CollectionResults | Where-Object { $_.CollectorId -eq 'Failures' -and $_.Status -eq 'Failed' }).Count | Should -Be 1
        $Live.Replication.Count | Should -Be 0
        (@((Test-PSIADDCReadiness -Inventory $Live -TargetOS 2025).Assessment.Checks | Where-Object Id -eq 'check-replication')[0]).Status | Should -Be 'NotTested'
        $Live.CollectionLogs.Count | Should -BeGreaterThan 0
    }
    It 'distinguishes a successful empty partner query from a failed partner query' {
        $Mock=New-MockedADAdapter
        $Mock.Adapter.Partners={ param($HostName) @() }
        $Empty=Collect-PSIADDCReadiness -Domain child.example.test -CommandAdapter $Mock.Adapter
        @($Empty.CollectionResults | Where-Object { $_.CollectorId -eq 'Partners' -and $_.Status -eq 'Partial' -and $_.Notes -match 'no partner metadata' }).Count | Should -Be 1
        $Mock.Adapter.Partners={ param($HostName) throw 'Query failure' }
        $Failed=Collect-PSIADDCReadiness -Domain child.example.test -CommandAdapter $Mock.Adapter
        @($Failed.CollectionResults | Where-Object { $_.CollectorId -eq 'Partners' -and $_.Status -eq 'Failed' }).Count | Should -Be 1
    }
    It 'contains partial remote failures and unavailable DNS without calling live systems' {
        $Mock=New-MockedADAdapter
        $Mock.Adapter.Remote={ param($HostName) throw 'Remote management blocked' }
        $Mock.Adapter.DNS={ param($HostName) throw [System.NotSupportedException]::new('DnsServer module unavailable') }
        $Live=ConvertTo-PSIADDCReadinessModel (Collect-PSIADDCReadiness -Domain child.example.test -CommandAdapter $Mock.Adapter -IncludeRemoteChecks)
        @($Live.CollectionResults | Where-Object { $_.CollectorId -eq 'Remote' -and $_.Status -eq 'Failed' }).Count | Should -Be 1
        @($Live.CollectionResults | Where-Object { $_.CollectorId -eq 'DNS' -and $_.Status -eq 'NotSupported' }).Count | Should -Be 1
        $Live.DomainControllers[0].DiskFreeGB | Should -BeNullOrEmpty
        (@((Test-PSIADDCReadiness -Inventory $Live -TargetOS 2025).Assessment.Checks | Where-Object Id -eq 'check-services')[0]).Status | Should -Be 'NotTested'
    }
    It 'collects optional remote, network and low-confidence directory dependencies when requested' {
        $Live=ConvertTo-PSIADDCReadinessModel (Collect-PSIADDCReadiness -Domain child.example.test -CommandAdapter (New-MockedADAdapter).Adapter -IncludeRemoteChecks -IncludePortChecks -IncludeDependencyDiscovery)
        $Live.DomainControllers[0].DiskFreeGB | Should -Be 20
        $Live.Ports.Count | Should -Be 10
        @($Live.Dependencies | Where-Object Type -eq 'Exchange')[0].Confidence | Should -Be 'Low'
        @($Live.Dependencies | Where-Object Type -eq 'PKI').Count | Should -Be 1
        (@((Test-PSIADDCReadiness -Inventory $Live -TargetOS 2025).Assessment.Checks | Where-Object Id -eq 'check-exchange')[0]).Status | Should -Be 'Review'
    }
    It 'handles a failed time query without guessing the PDC source' {
        $Mock=New-MockedADAdapter
        $Mock.Adapter.Time={ param($HostName) throw 'w32tm unavailable' }
        $Live=ConvertTo-PSIADDCReadinessModel (Collect-PSIADDCReadiness -Domain child.example.test -CommandAdapter $Mock.Adapter -IncludeRemoteChecks)
        @($Live.CollectionResults | Where-Object { $_.CollectorId -eq 'Time' -and $_.Status -eq 'Failed' }).Count | Should -Be 1
        (@((Test-PSIADDCReadiness -Inventory $Live -TargetOS 2025).Assessment.Checks | Where-Object Id -eq 'check-time')[0]).Status | Should -Be 'NotTested'
    }
    It 'does not treat missing disk data as zero free space' {
        $Mock=New-MockedADAdapter
        $Mock.Adapter.Remote={ param($HostName) [pscustomobject]@{ OS=[pscustomobject]@{ LastBootUpTime=(Get-Date).AddDays(-1) }; Disk=$null; Services=@{ NTDS='Running'; Netlogon='Running'; DFSR='Running'; KDC='Running'; W32Time='Running' }; NICs=@() } }
        $Live=ConvertTo-PSIADDCReadinessModel (Collect-PSIADDCReadiness -Domain child.example.test -CommandAdapter $Mock.Adapter -IncludeRemoteChecks)
        (@((Test-PSIADDCReadiness -Inventory $Live -TargetOS 2025).Assessment.Checks | Where-Object Id -eq 'check-disk')[0]).Status | Should -Be 'NotTested'
    }
    It 'evaluates collected live disk and service values despite unknown reachability' {
        $Mock=New-MockedADAdapter
        $Mock.Adapter.Remote={ param($HostName) [pscustomobject]@{ OS=[pscustomobject]@{ LastBootUpTime=(Get-Date).AddDays(-1) }; Disk=[pscustomobject]@{ FreeSpace=8GB; Size=100GB }; Services=@{ NTDS='Running'; Netlogon='Stopped'; DNS='Running'; DFSR='Running'; KDC='Running'; W32Time='Running' }; NICs=@([pscustomobject]@{ DNSServerSearchOrder=@('192.0.2.10') }) } }
        $Live=ConvertTo-PSIADDCReadinessModel (Collect-PSIADDCReadiness -Domain child.example.test -CommandAdapter $Mock.Adapter -IncludeRemoteChecks)
        $Live.DomainControllers[0].Reachable | Should -BeNullOrEmpty
        $Checks=(Test-PSIADDCReadiness -Inventory $Live -TargetOS 2025).Assessment.Checks
        (@($Checks | Where-Object Id -eq 'check-disk')[0]).Status | Should -Be 'Review'
        (@($Checks | Where-Object Id -eq 'check-services')[0]).Status | Should -Be 'Review'
    }
    It 'treats optional security observations as partial evidence, not an effective-policy verdict' {
        $Mock=New-MockedADAdapter
        $Mock.Adapter.Security={ param($HostName) @{ 'ldap-signing'='Observed registry DWORD: 2' } }
        $Live=ConvertTo-PSIADDCReadinessModel (Collect-PSIADDCReadiness -Domain child.example.test -CommandAdapter $Mock.Adapter -IncludeSecurityChecks)
        @($Live.CollectionResults | Where-Object { $_.CollectorId -eq 'Security' -and $_.Status -eq 'Partial' }).Count | Should -Be 1
        (@((Test-PSIADDCReadiness -Inventory $Live -TargetOS 2025).Assessment.Checks | Where-Object Id -eq 'check-security-ldap-signing')[0]).Status | Should -Be 'NotTested'
    }
    It 'renders a standalone mocked live report with coverage and sidecars' {
        $Temp=Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
        try {
            $Run=& (Join-Path $Provider 'Invoke-PSIADDCReadiness.ps1') -TargetOS 2025 -Domain child.example.test -CommandAdapter (New-MockedADAdapter).Adapter -OutputPath $Temp -NoBrowser -PassThru
            $Html=[System.IO.File]::ReadAllText($Run.HtmlPath)
            $Html | Should -Match 'data-psi-app-view="coverage"'
            $Html | Should -Match 'Evidence coverage'
            $Html | Should -Match '(?is)^\s*<!doctype html>.*<html\b.*<head\b.*</head>.*<body\b.*</body>.*</html>\s*$'
            $Html | Should -Not -Match '<script\s+[^>]*src\s*=|<link\s+[^>]*href\s*=|\bfetch\s*\('
            (Test-Path (Join-Path (Split-Path $Run.HtmlPath -Parent) 'NormalizedData.json')) | Should -BeTrue
            (Test-Path (Join-Path (Split-Path $Run.HtmlPath -Parent) 'Assessment.json')) | Should -BeTrue
            (Test-Path (Join-Path (Split-Path $Run.HtmlPath -Parent) 'Checks.csv')) | Should -BeTrue
            (Test-Path (Join-Path (Split-Path $Run.HtmlPath -Parent) 'CollectionCoverage.json')) | Should -BeTrue
            (Test-Path (Join-Path (Split-Path $Run.HtmlPath -Parent) 'CollectionCoverage.csv')) | Should -BeTrue
            (Test-Path (Join-Path (Split-Path $Run.HtmlPath -Parent) 'Logs/DCReadiness.log')) | Should -BeTrue
        }
        finally { if (Test-Path $Temp) { Remove-Item -LiteralPath $Temp -Recurse -Force } }
    }
    It 'has no executable modification cmdlets in the live collector' {
        $Files=@(Get-ChildItem (Join-Path $Provider 'Live') -Filter '*.ps1')
        foreach ($File in $Files) { (Get-Content $File.FullName -Raw) | Should -Not -Match '(?im)^\s*(Set-AD\w*|New-AD\w*|Remove-AD\w*|Add-AD\w*|Set-DnsServer\w*|Set-GP\w*|Restart-Service|Stop-Service|Start-Service|Restart-Computer)\b' }
    }
}
