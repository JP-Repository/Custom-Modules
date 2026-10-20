$ProjectRoot = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $ProjectRoot 'PSInsightHTML.psd1') -Force

Describe 'Fluent Explorer application foundation' {
    BeforeAll {
        $script:Root = Split-Path $PSScriptRoot -Parent
        $script:BenchmarkScript = Join-Path $Root 'Examples/FluentExplorer/Invoke-FluentExplorerBenchmark.ps1'
        $script:Output = Join-Path $TestDrive 'FluentExplorer.html'
        & $script:BenchmarkScript -OutputPath $script:Output | Out-Null
        $script:Markup = [System.IO.File]::ReadAllText($script:Output)
    }

    It 'retains the original Report and Application defaults' {
        $Report = New-PSIReport -Title Legacy
        $Report.PSObject.Properties['Navigation'] | Should -BeNullOrEmpty
        $Report | Add-PSISection -Title One | Add-PSIRow | Out-Null
        $LegacyPath = Join-Path $TestDrive 'Legacy.html'
        Export-PSIReport -Report $Report -Path $LegacyPath | Out-Null
        [System.IO.File]::ReadAllText($LegacyPath) | Should -Not -Match 'data-psi-navigation="FluentExplorer"'
        $Application = New-PSIReport -Title Existing -Layout Application
        $Application.Navigation | Should -Be 'Sidebar'
        $Application.Density | Should -Be 'Comfortable'
        { New-PSIReport -Title Invalid -Navigation FluentExplorer } | Should -Throw
        { New-PSIReport -Title Invalid -Density Compact } | Should -Throw
    }
    It 'emits the opt-in shell and wide compact workspace' {
        $script:Markup | Should -Match 'data-psi-navigation="FluentExplorer" data-psi-density="Compact"'
        $script:Markup | Should -Match 'aria-label="Global navigation"'
        $script:Markup | Should -Match '--psi-app-nav-width: 84px'
        $script:Markup | Should -Match '\.psi-app-workspace \{ grid-template-columns: minmax\(0, 1fr\); width: 100%; max-width: none;'
        $script:Markup | Should -Match 'min-height: 88px; padding: 12px 14px'
        $script:Markup | Should -Match 'min-width: 641px'
        $script:Markup | Should -Match 'max-width: 640px'
    }
    It 'preserves view navigation and selected Fluent icons' {
        foreach ($Id in @('overview','services','notes')) {
            $script:Markup | Should -Match ('id="psi-app-item-' + $Id + '"')
            $script:Markup | Should -Match ('id="psi-view-' + $Id + '"')
        }
        $script:Markup | Should -Match 'data-psi-app-view-target="overview"[^>]*aria-current="page"'
        $script:Markup | Should -Match 'psi-icon-regular'
        $script:Markup | Should -Match 'psi-icon-filled'
        $script:Markup | Should -Match 'title="Overview"'
    }
    It 'keeps Light, Dark and Auto theme controls and palettes' {
        foreach ($Theme in @('Light','Dark','Auto')) { $script:Markup | Should -Match ('data-psi-theme="' + $Theme + '"') }
        $script:Markup | Should -Match 'data-theme="Auto"'
        $script:Markup | Should -Match '--psi-page: #f4f7fb'
        $script:Markup | Should -Match '--psi-page: #101923'
        $script:Markup | Should -Match 'prefers-color-scheme: dark'
    }
    It 'renders generic KPI, chart, table and text components' {
        $script:Markup | Should -Match 'Portfolio pulse'
        $script:Markup | Should -Match 'Services by status'
        $script:Markup | Should -Match 'Service health'
        $script:Markup | Should -Match 'No live infrastructure was queried'
    }
    It 'is standalone and has no duplicate HTML IDs' {
        $script:Markup | Should -Not -Match '<script\s+[^>]*src\s*=|<link\s+[^>]*href\s*=|<img\s+[^>]*src\s*=|\bfetch\s*\('
        $DocumentMarkup = [regex]::Replace($script:Markup, '(?is)<script\b[^>]*>.*?</script>', '')
        $Ids = [regex]::Matches($DocumentMarkup, '(?i)\bid="([^"]+)"') | ForEach-Object { $_.Groups[1].Value.ToLowerInvariant() }
        $Ids.Count | Should -BeGreaterThan 0
        @($Ids | Sort-Object -Unique).Count | Should -Be $Ids.Count
    }
    It 'rejects invalid navigation and density values' {
        { New-PSIReport -Title Invalid -Layout Application -Navigation Missing } | Should -Throw
        { New-PSIReport -Title Invalid -Layout Application -Density Spacious } | Should -Throw
    }
    It 'uses PowerShell 5.1 compatible syntax in new scripts' {
        foreach ($File in @($script:BenchmarkScript, (Join-Path $Root 'Public/New-PSIReport.ps1'), (Join-Path $Root 'Private/ConvertTo-PSIApplicationShell.ps1'))) {
            $Tokens = $null; $Errors = $null
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile($File, [ref] $Tokens, [ref] $Errors)
            @($Errors).Count | Should -Be 0
            $Ast.Extent.Text | Should -Not -Match '\?\?|\?\.'
        }
    }
}
