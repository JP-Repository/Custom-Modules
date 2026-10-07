Describe 'PSInsightHTML provider integration and report catalog' {
    BeforeAll {
        $script:ProviderProjectRoot = (Get-Location).Path
        $script:ProviderManifest = Join-Path $script:ProviderProjectRoot 'PSInsightHTML.psd1'
        Remove-Module PSInsightHTML -ErrorAction SilentlyContinue
        Import-Module -Name $script:ProviderManifest -ErrorAction Stop
    }

    It 'imports without required ActiveDirectory or GroupPolicy modules' {
        (Get-Module PSInsightHTML) | Should -Not -BeNullOrEmpty
        @((Get-Module PSInsightHTML).RequiredModules).Count | Should -Be 0
        (Import-PowerShellDataFile -LiteralPath $script:ProviderManifest).ContainsKey('RequiredModules') | Should -BeFalse
        if (@(Get-Module -ListAvailable ActiveDirectory, GroupPolicy).Count -eq 0) {
            (Get-Command Get-PSIReportCatalog -Module PSInsightHTML) | Should -Not -BeNullOrEmpty
        }
    }

    It 'exports catalog and only the six implemented provider reports' {
        $Commands = @(Get-Command -Module PSInsightHTML -CommandType Function | Select-Object -ExpandProperty Name)
        $Expected = @(
            'Get-PSIReportCatalog','New-PSIADUserInventory','New-PSIADGroupPolicyAssessment',
            'New-PSIADGroupAssessment','New-PSIADReplicationAssessment','New-PSIADDNSAssessment',
            'New-PSIADSitesSubnetsAssessment'
        )
        foreach ($Name in $Expected) { $Commands | Should -Contain $Name }
        $Commands | Should -Not -Contain 'New-PSIADDomainControllerAssessment'
        $Commands | Should -Not -Contain 'New-PSIADReplicationSampleData'
        $Commands | Should -Not -Contain 'Import-PSIADUserInventoryWorkbook'
        $Commands | Should -Not -Contain 'Find-PSIADBestSubnetMatch'
    }

    It 'returns complete catalog objects driven by six report metadata files' {
        $Catalog = @(Get-PSIReportCatalog)
        $Catalog.Count | Should -Be 6
        @(Get-ChildItem -LiteralPath (Join-Path $script:ProviderProjectRoot 'Providers/ActiveDirectory') -Filter Report.psd1 -Recurse -File).Count | Should -Be 6
        foreach ($Entry in $Catalog) {
            $Entry | Should -BeOfType [pscustomobject]
            foreach ($Name in @('Id','Provider','Name','Description','Category','Command','Status','SupportsSampleData','SupportsProvidedData','SupportsLiveCollection','MinimumPowerShellVersion')) {
                $Entry.PSObject.Properties.Name | Should -Contain $Name
            }
            $Entry.Provider | Should -Be 'ActiveDirectory'
            $Entry.SupportsSampleData | Should -BeTrue
            $Entry.SupportsLiveCollection | Should -BeFalse
            $Entry.MinimumPowerShellVersion | Should -Be '5.1'
            (Get-Command -Name $Entry.Command -Module PSInsightHTML -CommandType Function) | Should -Not -BeNullOrEmpty
        }
        @($Catalog | Where-Object SupportsProvidedData).Count | Should -Be 1
        ($Catalog | Where-Object SupportsProvidedData).Command | Should -Be 'New-PSIADUserInventory'
    }

    It 'supports provider, name, and normal pipeline filtering' {
        @(Get-PSIReportCatalog -Provider ActiveDirectory).Count | Should -Be 6
        @(Get-PSIReportCatalog -Provider OtherProvider).Count | Should -Be 0
        @(Get-PSIReportCatalog -Name '*Replication*').Count | Should -Be 1
        @(Get-PSIReportCatalog | Where-Object SupportsSampleData).Count | Should -Be 6
        $Loader = [System.IO.File]::ReadAllText((Join-Path $script:ProviderProjectRoot 'PSInsightHTML.psm1'))
        $CatalogSource = [System.IO.File]::ReadAllText((Join-Path $script:ProviderProjectRoot 'Public/Get-PSIReportCatalog.ps1'))
        $Loader | Should -Not -Match 'ActiveDirectory'
        $CatalogSource | Should -Not -Match 'ActiveDirectory'
    }

    It 'requires an explicit source mode and rejects unsupported live or supplied-data calls' {
        { New-PSIADReplicationAssessment -NoBrowser } | Should -Throw '*UseSampleData*'
        { New-PSIADUserInventory -NoBrowser } | Should -Throw '*UseSampleData or -WorkbookPath*'
        { New-PSIADUserInventory -UseSampleData -WorkbookPath 'sample.xlsx' -NoBrowser } | Should -Throw '*mutually exclusive*'
        (Get-Command New-PSIADUserInventory).Parameters.Keys | Should -Contain 'WorkbookPath'
        (Get-Command New-PSIADReplicationAssessment).Parameters.Keys | Should -Not -Contain 'Live'
    }

    It 'generates a standalone report through <Command>' -ForEach @(
        @{Command='New-PSIADUserInventory'; Title='Active Directory User Inventory'},
        @{Command='New-PSIADGroupPolicyAssessment'; Title='Group Policy'},
        @{Command='New-PSIADGroupAssessment'; Title='Group Assessment'},
        @{Command='New-PSIADReplicationAssessment'; Title='Replication'},
        @{Command='New-PSIADDNSAssessment'; Title='DNS'},
        @{Command='New-PSIADSitesSubnetsAssessment'; Title='Sites &amp; Subnets'}
    ) {
        $TemporaryReport = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.html')
        try {
            & $Command -UseSampleData -Path $TemporaryReport -Theme Dark -NoBrowser | Out-Null
            (Test-Path -LiteralPath $TemporaryReport -PathType Leaf) | Should -BeTrue
            $Html = [System.IO.File]::ReadAllText($TemporaryReport)
            $Html | Should -Match ([regex]::Escape($Title))
            $Html | Should -Match '<style>'
            $Html | Should -Match '<script>'
            $Html | Should -Match 'data-theme="Dark"'
            $Html | Should -Match 'data-psi-insight='
            $Html | Should -Match 'data-psi-export-format="csv"'
            $Html | Should -Match 'data-psi-export-format="xlsx"'
            $Html | Should -Match 'data-psi-export-format="print"'
            $Html | Should -Not -Match '<script\s+[^>]*src\s*=|<link\s+[^>]*href\s*=|<img\s+[^>]*src\s*=|\bfetch\s*\('
        }
        finally {
            if (Test-Path -LiteralPath $TemporaryReport) { Remove-Item -LiteralPath $TemporaryReport -Force }
        }
    }

    It 'keeps provider implementation helpers private after report generation' {
        $Exported = @(Get-Command -Module PSInsightHTML -CommandType Function | Select-Object -ExpandProperty Name)
        $Exported.Count | Should -Be 30
        $Exported | Should -Not -Contain 'New-PSIADReplicationSampleData'
        $Exported | Should -Not -Contain 'Get-PSIADGroupPolicyDistribution'
        $Exported | Should -Not -Contain 'Import-PSIADUserInventoryWorkbook'
        $Exported | Should -Not -Contain 'ConvertTo-PSIADSubnetDefinition'
    }
}
