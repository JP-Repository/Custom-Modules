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
        $script:Markup | Should -Match 'title="Summary"'
    }
    It 'keeps Light, Dark and Auto theme controls and palettes' {
        foreach ($Theme in @('Light','Dark','Auto')) { $script:Markup | Should -Match ('data-psi-theme="' + $Theme + '"') }
        $script:Markup | Should -Match 'data-theme="Auto"'
        $script:Markup | Should -Match '--psi-page: #e9eef4'
        $script:Markup | Should -Match '--psi-app-rail: #172b40'
        $script:Markup | Should -Match '--psi-page: #101923'
        $script:Markup | Should -Match 'prefers-color-scheme: dark'
    }
    It 'renders generic KPI, chart, table and text components' {
        $script:Markup | Should -Match 'Health Overview'
        $script:Markup | Should -Match 'Controllers by status'
        $script:Markup | Should -Match 'Replication and DNS'
        $script:Markup | Should -Match 'Service evidence'
        $script:Markup | Should -Match 'No live infrastructure was queried'
    }
    It 'renders status icons with accessible names in the Explorer' {
        $script:Markup | Should -Match 'class="psi-resource-status psi-status-critical" title="Status: Critical" aria-label="Status: Critical"><svg'
        $script:Markup | Should -Match 'class="psi-resource-status psi-status-warning" title="Status: Warning" aria-label="Status: Warning"><svg'
    }
    It 'registers an actual topology view with embedded graph assets' {
        $script:Markup | Should -Match 'data-psi-workspace-tab="topology"[^>]*aria-controls="psi-view-topology"'
        $TopologyView = [regex]::Match($script:Markup, '(?s)<section class="psi-app-view" id="psi-view-topology".*?</section>').Value
        $TopologyView | Should -Match 'data-psi-rel-mode="Topology"'
        $TopologyView | Should -Match 'data-psi-rel-svg'
        $script:Markup | Should -Match 'var layoutEdges = containment.length \? containment : visibleEdges'
        $script:Markup | Should -Match '\.psi-rel-viewport'
        $script:Markup | Should -Match 'html\[data-psi-navigation="FluentExplorer"\] \.psi-rel-topology \.psi-rel-viewport \{ display: block; \}'
    }
    It 'uses stable IDs and explicit, distinct containment and replication links' {
        $Match = [regex]::Match($script:Markup, '(?s)<script type="application/json" data-psi-rel-data>(.*?)</script>')
        $Match.Success | Should -BeTrue
        $Topology = $Match.Groups[1].Value | ConvertFrom-Json
        $Topology.Nodes.Count | Should -Be 11
        $Topology.Edges.Count | Should -Be 14
        foreach ($Id in @('forest','domain','hq','branch1','branch2','dc01','dc02','dc03','dc04','dc05','dc06')) {
            @($Topology.Nodes | Where-Object Id -eq $Id).Count | Should -Be 1
        }
        @($Topology.Edges | Where-Object Category -eq 'Containment').Count | Should -Be 10
        @($Topology.Edges | Where-Object Category -eq 'Replication').Count | Should -Be 4
        @($Topology.Edges | Where-Object Id -eq 'rep-dc01-dc03')[0].Status | Should -Be 'Warning'
        @($Topology.Nodes | Where-Object Id -eq 'dc01')[0].ResourceId | Should -Be 'dc01'
        $script:Markup | Should -Match 'data-psi-rel-edge-category'
    }
    It 'connects graph selection to the existing Resource Workspace without leaving Topology' {
        $script:Markup | Should -Match "resourceId: node.ResourceId \|\| ''"
        $script:Markup | Should -Match "select\(byId\[resourceId\], false, false\)"
        $script:Markup | Should -Match 'if \(view && openTarget !== false\) \{ openView\(view\); \}'
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
