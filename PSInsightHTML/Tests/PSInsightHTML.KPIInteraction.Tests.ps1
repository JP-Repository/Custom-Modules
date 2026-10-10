$ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path $ModuleRoot 'PSInsightHTML.psd1') -Force

Describe 'PSInsightHTML KPI interaction polish' {
    BeforeAll {
        $Report = New-PSIReport -Title 'KPI interaction behavior' -Theme Auto
        $Report | Add-PSISection -Title 'Metrics' | Add-PSIRow |
            Add-PSIKPI -Title 'Healthy static' -Value 57 -Status Healthy |
            Add-PSIKPI -Title 'Evidence action' -Value 2 -Status Warning -DrillDown @(
                [pscustomobject]@{ Name = 'Sample'; Status = 'Warning' }
            ) |
            Add-PSIKPI -Title 'Filter action' -Value 1 -Status Critical -Filter @{
                Table = 'kpi-interaction-table'; Property = 'Status'; Value = 'Critical'
            } |
            Add-PSIKPI -Title 'Section action' -Value 1 -Status Neutral -Action @{
                Type = 'ScrollTo'; Target = 'psi-section-0'
            } | Out-Null
        $Report | Add-PSIRow | Add-PSITable -Id 'kpi-interaction-table' -Title 'Evidence' `
            -Data @([pscustomobject]@{ Name = 'Sample'; Status = 'Critical' }) `
            -Columns @('Name', 'Status') | Out-Null

        $Path = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.html')
        try {
            $null = Export-PSIReport -Report $Report -Path $Path
            $script:KpiInteractionHtml = [System.IO.File]::ReadAllText($Path)
        }
        finally {
            if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
        }
    }

    It 'uses a short transform shadow and surface transition on KPI cards' {
        $script:KpiInteractionHtml | Should -Match '\.psi-kpi-card \{[^}]*transition: transform 180ms ease, box-shadow 180ms ease, background-color 180ms ease;'
    }

    It 'limits pointer hover lift to hover-capable precise pointers' {
        $script:KpiInteractionHtml | Should -Match '@media \(hover: hover\) and \(pointer: fine\) \{\s*\.psi-kpi-card:hover \{[^}]*transform: translateY\(-2px\);[^}]*box-shadow: var\(--psi-shadow\);'
        $script:KpiInteractionHtml | Should -Match '\.psi-kpi-clickable:hover \{ background: var\(--psi-surface-interactive\); \}'
    }

    It 'gives keyboard focus the same restrained emphasis without removing its ring' {
        $script:KpiInteractionHtml | Should -Match '\.psi-kpi-clickable:focus-visible \{ transform: translateY\(-2px\); background: var\(--psi-surface-interactive\); box-shadow: var\(--psi-shadow\); \}'
        $script:KpiInteractionHtml | Should -Match '\.psi-kpi-clickable:focus-visible, \.psi-theme-control button:focus-visible[^}]*outline: 3px solid var\(--psi-focus-ring\);'
    }

    It 'disables KPI motion for reduced-motion and print output' {
        $script:KpiInteractionHtml | Should -Match '@media \(prefers-reduced-motion: reduce\) \{\s*\.psi-kpi-card \{ transition: none; \}\s*\.psi-kpi-card:hover, \.psi-kpi-clickable:focus-visible \{ transform: none; \}'
        $script:KpiInteractionHtml | Should -Match '\.psi-kpi-card \{ transform: none !important; transition: none !important; \}'
    }

    It 'preserves static markup and all clickable KPI action attributes' {
        $script:KpiInteractionHtml | Should -Match '<article class="psi-kpi-card psi-status-healthy"'
        @([regex]::Matches($script:KpiInteractionHtml, '<button type="button" class="psi-kpi-card psi-kpi-clickable')).Count | Should -Be 3
        $script:KpiInteractionHtml | Should -Match 'data-psi-drilldown data-psi-records='
        $script:KpiInteractionHtml | Should -Match 'data-psi-filter-action='
        $script:KpiInteractionHtml | Should -Match 'data-action="\{&quot;Type&quot;:&quot;ScrollTo&quot;,&quot;Target&quot;:&quot;psi-section-0&quot;\}"'
        $script:KpiInteractionHtml | Should -Match 'aria-label="View details for Evidence action: 2"'
    }
}
