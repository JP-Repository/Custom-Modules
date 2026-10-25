$ProjectRoot = Split-Path $PSScriptRoot -Parent
$Example = Join-Path $ProjectRoot 'Examples/ActiveDirectory/DomainOverview/Invoke-PSIADDomainOverview.ps1'

Describe 'AD Domain Overview example' {
    BeforeAll {
        $script:Example = Join-Path (Split-Path $PSScriptRoot -Parent) 'Examples/ActiveDirectory/DomainOverview/Invoke-PSIADDomainOverview.ps1'
        . (Join-Path (Split-Path $PSScriptRoot -Parent) 'Providers/ActiveDirectory/Fixtures/New-PSIADLiveFixtureAdapter.ps1')
        $script:Result = & $script:Example -UseSampleData -OutputPath (Join-Path $TestDrive 'sample') -NoBrowser -PassThru
        $script:Html = [System.IO.File]::ReadAllText($script:Result.HtmlPath)
        $Payload = [regex]::Match($script:Html, '(?s)<script type="application/json" id="pf-data">(.*?)</script>')
        if (-not $Payload.Success) { throw 'Fluent data payload was not embedded in the report.' }
        $script:Model = $Payload.Groups[1].Value | ConvertFrom-Json
    }

    It 'builds an overview from the fictional snapshot without a directory query' {
        $script:Result.Snapshot.Source | Should -Be 'Fictional sample'
        $script:Result.Inventory.Summary.DCCount | Should -Be 8
        $script:Result.Inventory.Summary.SiteCount | Should -Be 4
        $script:Result.Readiness2022.TargetOS | Should -Be '2022'
        $script:Result.Readiness2025.TargetOS | Should -Be '2025'
        $script:Html | Should -Match 'Fictional sample - no directory query'
    }

    It 'reuses a supplied normalized snapshot for both readiness targets' {
        $Reused = & $script:Example -Snapshot $script:Result.Snapshot -TargetOS 2022 -OutputPath (Join-Path $TestDrive 'reused') -NoBrowser -PassThru
        [object]::ReferenceEquals($Reused.Snapshot, $script:Result.Snapshot) | Should -BeTrue
        $Reused.Inventory.Summary.DCCount | Should -Be $script:Result.Inventory.Summary.DCCount
        $Reused.Readiness2022.Assessment.Checks.Count | Should -BeGreaterThan 0
        $Reused.Readiness2025.Assessment.Checks.Count | Should -BeGreaterThan 0
        ([System.IO.File]::ReadAllText($Reused.HtmlPath)) | Should -Match 'Windows Server 2022 checks'
    }

    It 'renders the Fluent views, inventory and coverage in standalone HTML' {
        @($script:Model.pages | ForEach-Object { $_.id }) | Should -Be @('overview','controllers','topology','policy','readiness','coverage')
        @('domain-controllers','domain-dc-placement','domain-gpo-intent','domain-readiness','domain-coverage') | ForEach-Object {
            ($script:Html.Contains('"id":"' + $_ + '"')) | Should -BeTrue
        }
        ($script:Html -match '(?is)^\s*<!doctype html>.*<html\b.*<head\b.*</head>.*<body\b.*</body>.*</html>\s*$') | Should -BeTrue
        ($script:Html -match '<script\s+[^>]*src\s*=|<link\s+[^>]*href\s*=|\bfetch\s*\(') | Should -BeFalse
    }

    It 'runs the domain-scoped live path through a fictional command adapter' {
        $Mocked = & $script:Example -Domain root.example.test -CommandAdapter (New-PSIADLiveFixtureAdapter) -CollectionProfile Core -OutputPath (Join-Path $TestDrive 'mocked-live') -NoBrowser -PassThru
        $Mocked.Inventory.Summary.Domain | Should -Be 'root.example.test'
        $Mocked.Inventory.Summary.DCCount | Should -Be 3
        @($Mocked.Inventory.DomainControllers | Where-Object { $_.Domain -ne 'root.example.test' }).Count | Should -Be 0
        $Mocked.Snapshot.Source | Should -Not -Be 'Fictional sample'
        (Test-Path -LiteralPath $Mocked.HtmlPath) | Should -BeTrue
    }

    It 'requires an explicit source before any live collection can start' {
        { & $script:Example -OutputPath (Join-Path $TestDrive 'missing') -NoBrowser } | Should -Throw '*Specify -UseSampleData*'
        { & $script:Example -UseSampleData -Domain 'example.test' -OutputPath (Join-Path $TestDrive 'mixed') -NoBrowser } | Should -Throw '*cannot be combined*'
        { & $script:Example -Snapshot $script:Result.Snapshot -Domain 'example.test' -OutputPath (Join-Path $TestDrive 'mixed') -NoBrowser } | Should -Throw '*mutually exclusive*'
    }

    It 'keeps live collection and provider logic outside the generic module' {
        $Source = [System.IO.File]::ReadAllText($script:Example)
        $Source | Should -Match 'Collect-PSIADSnapshot'
        $Source | Should -Match 'New-PSIADDCInventoryModel'
        $Source | Should -Match 'Test-PSIADDCReadiness'
        $Source | Should -Match 'Export-PSIReport'
    }
}
