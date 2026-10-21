$Root = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $Root 'PSInsightHTML.psd1') -Force

Describe 'Fluent compact presentation components' {
    BeforeAll {
        $script:Root = Split-Path $PSScriptRoot -Parent
        $script:BenchmarkPath = Join-Path $TestDrive 'CompactBenchmark.html'
        & (Join-Path $Root 'Examples/FluentExplorer/Invoke-FluentExplorerBenchmark.ps1') -OutputPath $script:BenchmarkPath | Out-Null
        $script:Html = [System.IO.File]::ReadAllText($script:BenchmarkPath)
    }

    It 'shows six compact KPI tiles in the summary' {
        $Summary = [regex]::Match($script:Html, '(?s)<section class="psi-app-view" id="psi-view-overview".*?</section>').Value
        ([regex]::Matches($Summary, 'class="psi-kpi-card')).Count | Should -Be 6
        $script:Html | Should -Match 'min-height: 88px; padding: 12px 14px'
        $script:Html | Should -Match 'font-size: clamp\(20px, 2vw, 24px\)'
    }
    It 'uses one resource header with breadcrumb, metadata, status and actions' {
        ([regex]::Matches($script:Html, 'id="psi-resource-header"')).Count | Should -Be 1
        $script:Html | Should -Match 'data-psi-resource-header-breadcrumb'
        $script:Html | Should -Match 'data-psi-resource-header-tags'
        $script:Html | Should -Match 'data-psi-resource-header-actions'
        $script:Html | Should -Match '"Breadcrumb":\["Infrastructure"'
    }
    It 'binds workspace tabs to existing view panels and counts' {
        $script:Html | Should -Match 'role="tablist" aria-label="Workspace views"'
        $script:Html | Should -Match 'data-psi-workspace-tab="overview"[^>]*aria-selected="true"'
        $script:Html | Should -Match 'data-psi-workspace-tab="checks"[^>]*aria-controls="psi-view-checks"'
        $script:Html | Should -Match 'psi-workspace-tab-count">6</span>'
        $script:Html | Should -Match 'id="psi-view-overview"[^>]*role="tabpanel"'
    }
    It 'renders four lightweight inline SVG metrics' {
        ([regex]::Matches($script:Html, '<figure class="psi-sparkline-panel')).Count | Should -Be 4
        $script:Html | Should -Match 'class="psi-sparkline-visual" viewBox="0 0 100 34"'
        $script:Html | Should -Match 'LDAP latency'
    }
    It 'rejects invalid sparkline data without unsafe markup' {
        $Report = New-PSIReport -Title Test
        $Report | Add-PSISection -Title Metrics | Add-PSIRow | Out-Null
        { $Report | Add-PSISparkline -Values @(1, $null, 2) } | Should -Throw
        { $Report | Add-PSISparkline -Values @(1, 'x', 2) } | Should -Throw '*finite numbers*'
        { $Report | Add-PSISparkline -Values @(1) } | Should -Throw '*between 2 and 120*'
        { $Report | Add-PSISparkline -Values @(1,2) -Minimum 4 -Maximum 2 } | Should -Throw '*less than Maximum*'
        { $Report | Add-PSISparkline -Values @(1,2) -Minimum 1.5 } | Should -Throw '*include all Values*'
    }
    It 'uses finite coordinates and HTML encodes sparkline labels' {
        $Report = New-PSIReport -Title Test
        $Report | Add-PSISection -Title Metrics | Add-PSIRow |
            Add-PSISparkline -Values @(2,2,2) -Label '<img src=x>' -CurrentValue '<script>' | Out-Null
        $Path = Join-Path $TestDrive 'Sparkline.html'
        Export-PSIReport -Report $Report -Path $Path | Out-Null
        $Markup = [System.IO.File]::ReadAllText($Path)
        $Markup | Should -Match '&lt;img src=x&gt;'
        $Markup | Should -Match '&lt;script&gt;'
        $Markup | Should -Not -Match 'NaN|Infinity'
        $Markup | Should -Match 'psi-sparkline-visual'
    }
    It 'renders requested semantic badge labels with icons in compact tables' {
        $Statuses = @('Healthy','Ready','Warning','Review','Critical','Blocked','Info','Unknown','NotTested','NotSupported','NA')
        $Rows = @($Statuses | ForEach-Object { [pscustomobject]@{ Name='Sample'; Status=$_ } })
        $Report = New-PSIReport -Title Test -Layout Application -Navigation FluentExplorer -Density Compact
        $Report | Add-PSIView -Id main -Title Main -Initial | Add-PSISection -Title Status | Add-PSIRow |
            Add-PSITable -Title 'Statuses' -Data $Rows -Columns @('Name','Status') | Out-Null
        $Path = Join-Path $TestDrive 'Statuses.html'
        Export-PSIReport -Report $Report -Path $Path | Out-Null
        $Markup = [System.IO.File]::ReadAllText($Path)
        foreach ($Status in $Statuses) { $Markup | Should -Match ('psi-status-badge psi-status-[a-z-]+"><svg[^>]*>.*?</svg>' + $Status + '</span>') }
    }
    It 'keeps compact table behavior and contained scrolling' {
        $script:Html | Should -Match 'data-search-enabled="true" data-sort-enabled="true" data-pagination-enabled="true"'
        $script:Html | Should -Match 'max-width: 100%; overflow-x: auto'
        $script:Html | Should -Match 'height: 34px; max-width: 240px; padding: 6px 9px'
        $script:Html | Should -Match 'psi-table-empty-content'
    }
    It 'renders generic empty states and validates optional actions' {
        $Report = New-PSIReport -Title Test -Layout Application -Navigation FluentExplorer -Density Compact
        $Report | Add-PSIView -Id main -Title Main -Initial | Add-PSISection -Title Empty | Add-PSIRow |
            Add-PSIEmptyState -Title '<Nothing>' -Explanation 'No sample records.' -ActionLabel 'Open main' -TargetView main | Out-Null
        $Path = Join-Path $TestDrive 'Empty.html'
        Export-PSIReport -Report $Report -Path $Path | Out-Null
        $Markup = [System.IO.File]::ReadAllText($Path)
        $Markup | Should -Match '&lt;Nothing&gt;'
        $Markup | Should -Match 'data-psi-empty-target="main"'
        { $Report | Add-PSIEmptyState -Title Empty -Explanation None -ActionLabel Open } | Should -Throw '*together*'
    }
    It 'keeps legacy reports and existing standalone assets intact' {
        $Report = New-PSIReport -Title Legacy
        $Report | Add-PSISection -Title One | Add-PSIRow |
            Add-PSITable -Title T -Data @([pscustomobject]@{ Status='Healthy' }) | Out-Null
        $Path = Join-Path $TestDrive 'Legacy.html'
        Export-PSIReport -Report $Report -Path $Path | Out-Null
        $Markup = [System.IO.File]::ReadAllText($Path)
        $Markup | Should -Not -Match 'psi-workspace-tabs|data-psi-navigation="FluentExplorer"'
        $Markup | Should -Match 'psi-status-badge psi-status-healthy">Healthy</span>'
        $script:Html | Should -Not -Match '<script\s+[^>]*src\s*=|<link\s+[^>]*href\s*=|<img\s+[^>]*src\s*=|\bfetch\s*\('
    }
    It 'keeps unique element IDs and PowerShell 5.1 source syntax' {
        $DocumentMarkup = [regex]::Replace($script:Html, '(?is)<script\b[^>]*>.*?</script>', '')
        $Ids = [regex]::Matches($DocumentMarkup, '(?i)\bid="([^"]+)"') | ForEach-Object { $_.Groups[1].Value.ToLowerInvariant() }
        @($Ids | Sort-Object -Unique).Count | Should -Be $Ids.Count
        foreach ($File in @('Public/Add-PSISparkline.ps1','Public/Add-PSIEmptyState.ps1','Private/Get-PSIStatusPresentation.ps1','Private/ConvertTo-PSIHtml.ps1','Examples/FluentExplorer/Invoke-FluentExplorerBenchmark.ps1')) {
            $Tokens=$null; $Errors=$null
            $Ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:Root $File),[ref]$Tokens,[ref]$Errors)
            @($Errors).Count | Should -Be 0
            $Ast.Extent.Text | Should -Not -Match '\?\?|\?\.'
        }
    }
}
