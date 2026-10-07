$script:GpoProjectRoot = Split-Path $PSScriptRoot -Parent

Describe 'PSInsightHTML fictional Group Policy provider' {
    BeforeAll {
        $script:GpoProjectRoot = (Get-Location).Path
        . (Join-Path $script:GpoProjectRoot 'Providers/ActiveDirectory/GroupPolicy/Private/PSIADGroupPolicy.Provider.ps1')
        $script:GpoSample = New-PSIADGroupPolicySampleData -GpoCount 180 -AsOfDate ([datetime]::new(2026, 9, 27))
    }

    It 'generates a reproducible, demo-safe GPO inventory without a directory connection' {
        $script:GpoSample.Gpos.Count | Should -Be 180
        $script:GpoSample.Source | Should -Match 'fictional.*no live directory'
        @($script:GpoSample.Gpos.GpoId | Select-Object -Unique).Count | Should -Be 180
        $script:GpoSample.Gpos[0].GpoName | Should -Be 'GPO-North-Workstation-Baseline-001'
        [guid]::Parse($script:GpoSample.Gpos[0].GpoId) | Should -Not -BeNullOrEmpty
        $script:GpoSample.Links.Target | Should -Match 'example,DC=invalid'
        foreach ($Gpo in $script:GpoSample.Gpos) {
            ([datetime] $Gpo.Created) | Should -BeLessOrEqual ([datetime] $Gpo.Modified)
            ([datetime] $Gpo.Modified) | Should -BeLessOrEqual $script:GpoSample.AsOfDate
        }
        { New-PSIADGroupPolicySampleData -GpoCount 99 } | Should -Throw
    }

    It 'models GPO-to-target links as distinct rows with consistent counts and target order' {
        $script:GpoSample.Links.Count | Should -Be 327
        @($script:GpoSample.Gpos | Where-Object LinkCount -eq 0).Count | Should -BeGreaterThan 0
        @($script:GpoSample.Gpos | Where-Object LinkCount -gt 1).Count | Should -BeGreaterThan 0
        @($script:GpoSample.Links | Where-Object LinkEnabled -eq 'No').Count | Should -BeGreaterThan 0
        @($script:GpoSample.Links | Where-Object Enforced -eq 'Yes').Count | Should -BeGreaterThan 0
        @($script:GpoSample.Links | Where-Object TargetType -eq 'OU').Count | Should -BeGreaterThan 0
        @($script:GpoSample.Links | Where-Object TargetType -eq 'Domain').Count | Should -BeGreaterThan 0
        @($script:GpoSample.Links | Where-Object TargetType -eq 'Site').Count | Should -BeGreaterThan 0
        foreach ($Gpo in $script:GpoSample.Gpos) {
            @($script:GpoSample.Links | Where-Object GpoName -eq $Gpo.GpoName).Count | Should -Be $Gpo.LinkCount
            @($script:GpoSample.Links | Where-Object { $_.GpoName -eq $Gpo.GpoName -and $_.LinkEnabled -eq 'No' }).Count | Should -Be $Gpo.DisabledLinkCount
        }
        @($script:GpoSample.Links | Group-Object Target, LinkOrder | Where-Object Count -gt 1).Count | Should -Be 0
    }

    It 'represents configuration, empty settings, security filtering, delegation, and WMI independently' {
        @($script:GpoSample.Gpos | Where-Object ConfigurationState -eq 'Both disabled').Count | Should -BeGreaterThan 0
        @($script:GpoSample.Gpos | Where-Object UserConfiguration -eq 'Disabled').Count | Should -BeGreaterThan 0
        @($script:GpoSample.Gpos | Where-Object ComputerConfiguration -eq 'Disabled').Count | Should -BeGreaterThan 0
        @($script:GpoSample.Gpos | Where-Object SettingsState -eq 'Empty').Count | Should -BeGreaterThan 0
        @($script:GpoSample.Gpos | Where-Object { $_.SettingsState -eq 'Empty' -and ($_.UserVersion -ne 0 -or $_.ComputerVersion -ne 0) }).Count | Should -Be 0
        $Healthy = @($script:GpoSample.Gpos | Where-Object DemoAssessment -eq 'Healthy')
        $Healthy.Count | Should -BeGreaterThan 0
        @($Healthy | Where-Object { $_.LinkCount -eq 0 -or $_.DisabledLinkCount -gt 0 -or $_.SettingsState -eq 'Empty' -or $_.ConfigurationState -eq 'Both disabled' }).Count | Should -Be 0
        @($script:GpoSample.Gpos | Where-Object { $_.DemoAssessment -notin @('Healthy', 'Info') }).Count | Should -Be 0
        @($script:GpoSample.SecurityFilters.FilterType | Select-Object -Unique).Count | Should -Be 4
        @($script:GpoSample.SecurityFilters | Where-Object Principal -eq 'Authenticated Users').Count | Should -BeGreaterThan 0
        @($script:GpoSample.SecurityFilters | Where-Object Principal -eq 'EXAMPLE\Domain Computers').Count | Should -BeGreaterThan 0
        @($script:GpoSample.SecurityFilters | Where-Object ApplyState -eq 'No').Count | Should -BeGreaterThan 0
        $script:GpoSample.Delegations.Count | Should -Be 240
        @($script:GpoSample.Delegations | Where-Object Source -eq 'Inherited').Count | Should -BeGreaterThan 0
        $script:GpoSample.WmiAssignments.Count | Should -Be 30
        @($script:GpoSample.Gpos | Where-Object WmiUsage -eq 'Has filter').Count | Should -Be 30
    }

    It 'builds small chart aggregates whose counts reconcile to the underlying datasets' {
        $Links = @(Get-PSIADGroupPolicyDistribution -Data $script:GpoSample.Gpos -Property LinkState)
        ($Links | Measure-Object Count -Sum).Sum | Should -Be 180
        $Configuration = @(Get-PSIADGroupPolicyDistribution -Data $script:GpoSample.Gpos -Property ConfigurationState)
        ($Configuration | Measure-Object Count -Sum).Sum | Should -Be 180
        $LinkEnabled = @(Get-PSIADGroupPolicyDistribution -Data $script:GpoSample.Links -Property LinkEnabled)
        ($LinkEnabled | Measure-Object Count -Sum).Sum | Should -Be 327
    }
}

Describe 'PSInsightHTML Group Policy assessment report' {
    BeforeAll {
        $script:GpoProjectRoot = (Get-Location).Path
        $script:GpoReportScript = Join-Path $script:GpoProjectRoot 'Examples/ActiveDirectory/GroupPolicy/New-GPOAssessmentReport.ps1'
        $script:GpoTempReport = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.html')
        & $script:GpoReportScript -OutputPath $script:GpoTempReport -Theme Dark -GpoCount 180 -NoBrowser | Out-Null
        $script:GpoHtml = [System.IO.File]::ReadAllText($script:GpoTempReport)
    }
    AfterAll {
        if ($script:GpoTempReport -and (Test-Path $script:GpoTempReport)) { Remove-Item $script:GpoTempReport -Force }
    }

    It 'generates the requested report sections and clearly declares fictional sample data' {
        foreach ($Title in @(
            'Executive Summary', 'Group Policy Inventory Overview', 'GPO Configuration State',
            'GPO Link Analysis', 'Security Filtering and Delegation', 'WMI Filter Usage',
            'Investigation Insights', 'Group Policy Inventory', 'Findings and Recommendations', 'Method and Data Handling'
        )) { $script:GpoHtml | Should -Match ([regex]::Escape($Title)) }
        $script:GpoHtml | Should -Match 'Fictional sample data only'
        $script:GpoHtml | Should -Match 'Narrow sample baseline check'
        $script:GpoHtml | Should -Match 'no live directory connection'
        $script:GpoHtml | Should -Match 'data-theme="Dark"'
        $script:GpoHtml | Should -Match 'data-psi-theme="Auto"'
    }

    It 'renders separate GPO, link, security filtering, delegation, and WMI datasets once each' {
        $Expected = @{
            'gpo-inventory'=180; 'gpo-links'=327; 'gpo-security-filters'=225
            'gpo-delegation'=240; 'gpo-wmi-assignments'=30
        }
        foreach ($Id in $Expected.Keys) {
            $Markup = [regex]::Match($script:GpoHtml, '<section class="psi-table-card" id="' + $Id + '".*?</section>', [System.Text.RegularExpressions.RegexOptions]::Singleline).Value
            $Markup | Should -Not -BeNullOrEmpty
            ([regex]::Matches($Markup, '<tr data-psi-data-row>')).Count | Should -Be $Expected[$Id]
            ([regex]::Matches($script:GpoHtml, 'id="' + $Id + '"')).Count | Should -Be 1
        }
        $script:GpoHtml | Should -Not -Match 'data-psi-records='
    }

    It 'provides seven reference-only Insights with evidence and export allowlists' {
        ([regex]::Matches($script:GpoHtml, 'data-psi-insight=')).Count | Should -Be 7
        foreach ($Title in @('Unlinked GPOs', 'Empty GPOs', 'Both Sections Disabled', 'GPOs With Disabled Links', 'GPOs Using WMI Filters', 'Disabled Link Records', 'Custom or Mixed Filtering')) {
            $script:GpoHtml | Should -Match ([regex]::Escape($Title))
        }
        $script:GpoHtml | Should -Match '&quot;tableId&quot;:&quot;gpo-inventory&quot;'
        $script:GpoHtml | Should -Match '&quot;tableId&quot;:&quot;gpo-links&quot;'
        $script:GpoHtml | Should -Match '&quot;exportColumns&quot;:'
        $script:GpoHtml | Should -Match 'data-psi-export-scope="evidence"'
    }

    It 'uses the existing chart filter, table filters, search, pagination, and export controls' {
        foreach ($Id in @('gpo-inventory', 'gpo-links', 'gpo-security-filters', 'gpo-delegation', 'gpo-wmi-assignments')) {
            $script:GpoHtml | Should -Match "id=`"$Id`""
        }
        $script:GpoHtml | Should -Match 'data-psi-chart-filter=' 
        $script:GpoHtml | Should -Match 'data-psi-filter-property="LinkState"'
        $script:GpoHtml | Should -Match 'data-psi-filter-property="TargetType"'
        $script:GpoHtml | Should -Match 'data-psi-search'
        $script:GpoHtml | Should -Match 'data-psi-pagination'
        $script:GpoHtml | Should -Match 'data-psi-export-format="csv"'
        $script:GpoHtml | Should -Match 'data-psi-export-format="xlsx"'
        $script:GpoHtml | Should -Match 'data-psi-export-format="print"'
        $script:GpoHtml | Should -Match '@media print'
    }

    It 'enforces explicit GPO export fields and keeps output standalone' {
        $InventoryMarkup = [regex]::Match($script:GpoHtml, '<section class="psi-table-card" id="gpo-inventory".*?</section>', [System.Text.RegularExpressions.RegexOptions]::Singleline).Value
        $ConfigMatch = [regex]::Match($InventoryMarkup, 'data-psi-export-config="([^"]+)"')
        $ConfigMatch.Success | Should -BeTrue
        $Config = [System.Net.WebUtility]::HtmlDecode($ConfigMatch.Groups[1].Value) | ConvertFrom-Json
        @($Config.columns) | Should -Contain 'GpoName'
        @($Config.columns) | Should -Contain 'GpoId'
        @($Config.columns) | Should -Not -Contain 'SecurityFilteringSummary'
        $Config.worksheetName | Should -Be 'GPO Inventory'
        $script:GpoHtml | Should -Not -Match '<script\s+[^>]*src\s*=|<link\s+[^>]*href\s*=|<img\s+[^>]*src\s*=|\bfetch\s*\('
        $script:GpoHtml | Should -Match '<style>'
        $script:GpoHtml | Should -Match '<script>'
    }
}
