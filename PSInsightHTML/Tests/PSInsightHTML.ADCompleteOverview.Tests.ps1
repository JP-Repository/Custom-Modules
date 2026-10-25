Describe 'AD complete overview and live inventory examples' {
    BeforeAll {
        $script:Root = Split-Path $PSScriptRoot -Parent
        $script:Runner = Join-Path $script:Root 'Examples/ActiveDirectory/LiveInventory/Invoke-PSIADInventoryReport.ps1'
        $script:Overview = Join-Path $script:Root 'Examples/ActiveDirectory/Invoke-PSIADCompleteOverview.ps1'
        . (Join-Path $script:Root 'Providers/ActiveDirectory/Fixtures/New-PSIADLiveFixtureAdapter.ps1')
        $script:Sample = & $script:Overview -UseSampleData -OutputPath (Join-Path $TestDrive 'complete') -NoBrowser -PassThru
    }

    It 'exports a discoverable complete overview command after module import' {
        Import-Module (Join-Path $script:Root 'PSInsightHTML.psd1') -Force
        (Get-Command Invoke-PSIADCompleteOverview -Module PSInsightHTML) | Should -Not -BeNullOrEmpty
        $Entry = @(Get-PSIReportCatalog | Where-Object Command -eq 'Invoke-PSIADCompleteOverview')[0]
        $Entry.SupportsSampleData | Should -BeTrue
        $Entry.SupportsLiveCollection | Should -BeTrue
        $Run = Invoke-PSIADCompleteOverview -UseSampleData -Only DomainOverview -OutputPath (Join-Path $TestDrive 'public-command') -NoBrowser -PassThru
        $Run.FailedCount | Should -Be 0
        (Test-Path -LiteralPath $Run.IndexPath -PathType Leaf) | Should -BeTrue
    }

    It 'restores the caller renderer setting after generating Fluent reports' {
        $Previous = $env:PSINSIGHTHTML_RENDERER
        try {
            $env:PSINSIGHTHTML_RENDERER = 'Classic'
            $Run = Invoke-PSIADCompleteOverview -UseSampleData -Only Groups -OutputPath (Join-Path $TestDrive 'renderer-restore') -NoBrowser -PassThru
            $Run.FailedCount | Should -Be 0
            $env:PSINSIGHTHTML_RENDERER | Should -Be 'Classic'
            ([System.IO.File]::ReadAllText($Run.Results[0].HtmlPath)).Contains('id="pf-data"') | Should -BeTrue
        }
        finally { $env:PSINSIGHTHTML_RENDERER = $Previous }
    }

    It 'generates all sixteen linked fictional reports from one overview command' {
        $script:Sample.Results.Count | Should -Be 16
        $script:Sample.FailedCount | Should -Be 0
        foreach ($Item in $script:Sample.Results) {
            $Item.Status | Should -Be 'Generated'
            (Test-Path -LiteralPath $Item.HtmlPath -PathType Leaf) | Should -BeTrue
            ([System.IO.File]::ReadAllText($Item.HtmlPath)).Contains('id="pf-data"') | Should -BeTrue
        }
        $Index = [System.IO.File]::ReadAllText($script:Sample.IndexPath)
        $Index | Should -Match 'Complete Domain Overview'
        $Index | Should -Match 'GroupPolicy'
        $Index | Should -Match 'OUs'
        $Index | Should -Match 'Fictional sample. No directory or network query was made.'
    }

    It 'includes DC, topology, GPO and OU context without claiming effective policy' {
        $Result = @($script:Sample.Results | Where-Object Name -eq 'DomainOverview')[0]
        $Html = [System.IO.File]::ReadAllText($Result.HtmlPath)
        $Html | Should -Match 'domain-dc-placement'
        $Html | Should -Match 'domain-gpo-intent'
        $Html | Should -Match 'EffectivePolicyEstablished'
        $Html | Should -Match 'They do not establish GPO application'
    }

    It 'supports each dedicated inventory wrapper with the fictional fixture' {
        foreach ($Name in @('Groups','GroupPolicy','Users','Computers','OUs','DNS','Replication','SitesSubnets')) {
            $Path = Join-Path $script:Root "Examples/ActiveDirectory/LiveInventory/Invoke-PSIAD$Name.ps1"
            (Test-Path -LiteralPath $Path -PathType Leaf) | Should -BeTrue
            $Result = & $Path -UseSampleData -OutputPath (Join-Path $TestDrive "wrapper-$Name") -NoBrowser -PassThru
            $Result.ReportType | Should -Be $Name
            (Test-Path -LiteralPath $Result.HtmlPath -PathType Leaf) | Should -BeTrue
        }
    }

    It 'enforces explicit domain scope and an honest displayed-row limit in the mocked live path' {
        $Adapter = @{
            Domain = { param($Name) [pscustomobject]@{ DNSRoot='root.example.test' } }
            Groups = { param($Name,$Limit) @([pscustomobject]@{ Name='Fictional A'; SamAccountName='a'; GroupScope='Global'; GroupCategory='Security'; Description='A' },[pscustomobject]@{ Name='Fictional B'; SamAccountName='b'; GroupScope='Universal'; GroupCategory='Security'; Description='B' }) }
        }
        { & $script:Runner -ReportType Groups -Domain other.example.test -CommandAdapter $Adapter -OutputPath (Join-Path $TestDrive 'wrong') -NoBrowser } | Should -Throw '*does not match requested domain*'
        $Result = & $script:Runner -ReportType Groups -Domain root.example.test -CommandAdapter $Adapter -MaxObjects 1 -OutputPath (Join-Path $TestDrive 'mocked') -NoBrowser -PassThru
        $Result.Records.Count | Should -Be 1
        $Result.Truncated | Should -BeTrue
        ([System.IO.File]::ReadAllText($Result.HtmlPath)) | Should -Match 'More than displayed'
    }

    It 'projects every direct inventory type through a fictional live command adapter' {
        $Adapter = @{
            Domain = { param($Name) [pscustomobject]@{ DNSRoot='root.example.test' } }
            Groups = { param($Name,$Limit) [pscustomobject]@{ Name='Example Group'; SamAccountName='example-group'; GroupScope='Global'; GroupCategory='Security'; Description='Fictional' } }
            GroupPolicy = { param($Name,$Limit) [pscustomobject]@{ DisplayName='Example Policy'; Id=[guid]::Empty; GpoStatus='AllSettingsEnabled'; CreationTime=(Get-Date).AddDays(-10); ModificationTime=(Get-Date); Owner='EXAMPLE\\Admins' } }
            Users = { param($Name,$Limit) [pscustomobject]@{ Name='Example User'; SamAccountName='example.user'; Enabled=$true; Department='Operations'; EmployeeType='Employee'; Country='US'; LastLogonDate=(Get-Date).AddDays(-2); PasswordLastSet=(Get-Date).AddDays(-30); AccountExpirationDate=$null; PasswordNeverExpires=$false } }
            Computers = { param($Name,$Limit) [pscustomobject]@{ Name='EXAMPLE-PC'; DNSHostName='example-pc.root.example.test'; Enabled=$true; OperatingSystem='Windows 11'; OperatingSystemVersion='10.0'; LastLogonDate=(Get-Date).AddDays(-1); Location='North' } }
            OUs = { param($Name,$Limit) [pscustomobject]@{ Name='Domain Controllers'; DistinguishedName='OU=Domain Controllers,DC=root,DC=example,DC=test'; ProtectedFromAccidentalDeletion=$true; gPLink=''; gPOptions=0 } }
        }
        foreach ($Type in @('Groups','GroupPolicy','Users','Computers','OUs')) {
            $Result = & $script:Runner -ReportType $Type -Domain root.example.test -CommandAdapter $Adapter -OutputPath (Join-Path $TestDrive "direct-$Type") -NoBrowser -PassThru
            $Result.Domain | Should -Be 'root.example.test'
            $Result.Records.Count | Should -Be 1
            $Result.Truncated | Should -BeFalse
            (Test-Path -LiteralPath $Result.HtmlPath -PathType Leaf) | Should -BeTrue
        }
    }

    It 'uses only read-only directory command families in the live inventory adapter' {
        $Source = [System.IO.File]::ReadAllText((Join-Path $script:Root 'Examples/ActiveDirectory/LiveInventory/Get-PSIADInventoryAdapter.ps1'))
        $Source | Should -Match 'Get-ADGroup'
        $Source | Should -Match 'Get-GPO'
        $Source | Should -Not -Match '\b(?:Set|New|Remove|Enable|Disable|Move)-(?:AD|GPO|DnsServer)[A-Za-z]*\b'
    }

    It 'reuses a normalized snapshot for replication inventory without a live query' {
        $Result = & $script:Runner -ReportType Replication -Snapshot $script:Sample.Snapshot -OutputPath (Join-Path $TestDrive 'snapshot') -NoBrowser -PassThru
        [object]::ReferenceEquals($Result.Snapshot, $script:Sample.Snapshot) | Should -BeTrue
        $Result.Records.Count | Should -BeGreaterThan 0
        $Result.Domain | Should -Be 'corp.example'
    }

    It 'uses the fictional command adapter for the one-snapshot overview path' {
        $Adapter = New-PSIADLiveFixtureAdapter
        $Result = & $script:Overview -Domain root.example.test -CommandAdapter $Adapter -CollectionProfile Core -Only DomainOverview,DCInventory,DCReadiness2025,DNS,Replication,SitesSubnets -OutputPath (Join-Path $TestDrive 'mocked-overview') -NoBrowser -PassThru
        $Result.FailedCount | Should -Be 0
        $Result.Domain | Should -Be 'root.example.test'
        $Result.Snapshot.Source | Should -Be 'Live read-only AD collection'
        $Result.Results.Count | Should -Be 6
    }

    It 'reports a scoped inventory query and record count with Verbose' {
        $Adapter = @{
            Domain = { param($Name) [pscustomobject]@{ DNSRoot = 'root.example.test' } }
            Groups = { param($Name,$Limit) [pscustomobject]@{ Name = 'Fictional Group'; SamAccountName = 'fictional-group'; GroupScope = 'Global'; GroupCategory = 'Security' } }
        }
        $Output = @(& $script:Runner -ReportType Groups -Domain root.example.test -CommandAdapter $Adapter -OutputPath (Join-Path $TestDrive 'verbose-groups') -NoBrowser -PassThru -Verbose 4>&1)
        $Messages = @($Output | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object Message)
        $Messages | Should -Contain 'Querying Groups in root.example.test (display limit 2000)'
        $Messages | Should -Contain 'Groups inventory: 1 records displayed; truncated: False'
    }

    It 'reports each requested collector and outcome with Verbose' {
        . (Join-Path $script:Root 'Providers/ActiveDirectory/Shared/Import-PSIADProvider.ps1')
        $CollectionResults = [System.Collections.Generic.List[object]]::new()
        $CollectionLogs = [System.Collections.Generic.List[object]]::new()
        $Output = @(Invoke-PSIADCollector -Adapter @{ Probe = { 'fictional observation' } } -Id Probe -Category Test -Scope fictional-dc -Arguments @() -Results $CollectionResults -Logs $CollectionLogs -Verbose 4>&1)
        $Messages = @($Output | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object Message)
        $Messages | Should -Contain 'Checking Probe on fictional-dc'
        ($Messages -join ' ') | Should -Match 'Collector Probe on fictional-dc: Collected \([0-9.]+ ms\)'
        $CollectionResults[0].Status | Should -Be 'Collected'
    }

    It 'keeps generated HTML offline and visibly labels its export control' {
        $Html = [System.IO.File]::ReadAllText((@($script:Sample.Results | Where-Object Name -eq 'Groups')[0]).HtmlPath)
        $Html | Should -Not -Match '<script\s+[^>]*src\s*=|<link\s+[^>]*href\s*=|\bfetch\s*\('
        $Html | Should -Match 'pf-export-menu'
        $Html | Should -Match 'Export filtered rows'
        $Payload = [regex]::Match($Html,'(?s)<script type="application/json" id="pf-data">(.*?)</script>')
        $Payload.Success | Should -BeTrue
        $Model = $Payload.Groups[1].Value | ConvertFrom-Json
        $Table = @($Model.sections.rows.items | Where-Object { $_.t -eq 'Table' -and $_.id -eq 'ad-inventory' })[0]
        @($Table.export.formats) | Should -Be @('Csv','Xlsx','Print')
    }
}
