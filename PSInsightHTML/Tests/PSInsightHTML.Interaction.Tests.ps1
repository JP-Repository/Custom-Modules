$ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path -Path $ModuleRoot -ChildPath 'PSInsightHTML.psd1') -Force

Describe 'PSInsightHTML visual and interaction layer' {
    BeforeAll {
        function New-PSIInteractionTestReport {
            $Report = New-PSIReport -Title 'Interaction test' -Theme Auto
            $Report | Add-PSISection -Title 'Interactive examples' | Add-PSIRow | Out-Null
            $Report
        }

        function Get-PSIInteractionTestHtml {
            param([Parameter(Mandatory = $true)][pscustomobject] $Report)
            $OutputPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([guid]::NewGuid().ToString() + '.html')
            try {
                $null = Export-PSIReport -Report $Report -Path $OutputPath
                [System.IO.File]::ReadAllText($OutputPath)
            }
            finally {
                if (Test-Path -LiteralPath $OutputPath) { Remove-Item -LiteralPath $OutputPath -Force }
            }
        }
    }

    It 'renders the reusable inline SVG icon system and keeps its helper private' {
        InModuleScope PSInsightHTML {
            foreach ($Name in @('dashboard', 'server', 'domain', 'replication', 'security', 'certificate', 'users', 'cloud', 'database', 'network', 'warning', 'critical', 'info', 'healthy', 'settings', 'search', 'arrow', 'close', 'theme/light', 'theme/dark')) {
                $Markup = Get-PSIIcon -Name $Name
                $Markup | Should -Match '<svg'
                $Markup | Should -Match 'currentColor'
            }
            (Get-PSIIcon -Name 'replication') | Should -Match 'viewBox="0 0 24 24"'
        }
        (Get-Command Get-PSIIcon -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
    }

    It 'renders accessible Light, Dark, and Auto controls with persistent theme behavior' {
        $Report = New-PSIInteractionTestReport
        $Html = Get-PSIInteractionTestHtml -Report $Report
        $Html | Should -Match 'data-psi-theme="Light" aria-pressed="false"'
        $Html | Should -Match 'data-psi-theme="Dark" aria-pressed="false"'
        $Html | Should -Match 'data-psi-theme="Auto" aria-pressed="false"'
        $Html | Should -Match 'role="group" aria-label="Report color theme"'
        $Html | Should -Match 'prefers-color-scheme: dark'
        $Html | Should -Match 'localStorage\.setItem\('
        $Html | Should -Match "setAttribute\('data-theme'"
    }

    It 'keeps a KPI without drill-down as a noninteractive article' {
        $Report = New-PSIInteractionTestReport
        $Report | Add-PSIKPI -Title 'Availability' -Value '99.98%' -Status Healthy -Icon 'healthy' | Out-Null
        $Html = Get-PSIInteractionTestHtml -Report $Report
        $Html | Should -Match '<article class="psi-kpi-card psi-status-healthy"'
        $Html | Should -Not -Match '<button[^>]+data-psi-drilldown'
        $Html | Should -Not -Match '<section class="psi-dialog" role="dialog"'
    }

    It 'renders a drill-down KPI as a keyboard-accessible button with generic serialized records' {
        $Report = New-PSIInteractionTestReport
        $Records = @(
            [pscustomobject]@{ Resource = 'Sample node A'; Status = 'Critical'; Notes = '<script>unsafe</script>' }
            [pscustomobject]@{ Resource = 'Sample node B'; Status = 'Warning'; Notes = $null }
        )
        $Report | Add-PSIKPI -Title 'Findings' -Value 2 -Status Critical -Icon 'security' -DrillDown $Records | Out-Null
        $Html = Get-PSIInteractionTestHtml -Report $Report

        $Html | Should -Match '<button type="button" class="psi-kpi-card psi-kpi-clickable'
        $Html | Should -Match 'data-psi-drilldown'
        $Html | Should -Match 'data-psi-records=".*Sample node A'
        $Html | Should -Match 'aria-label="View details for Findings: 2"'
        $Html | Should -Match 'View details'
        $Html | Should -Match '&lt;script&gt;unsafe&lt;/script&gt;'
        $Html | Should -Not -Match '<script>unsafe'
        $Html | Should -Match 'data-action='
    }

    It 'includes an accessible generic detail dialog with search, close, status badges, and Escape handling' {
        $Report = New-PSIInteractionTestReport
        $Report | Add-PSIKPI -Title 'Failed jobs' -Value 1 -Status Critical -DrillDown @([pscustomobject]@{ Job = 'Nightly sample'; Status = 'Critical'; Detail = 'Long text value' }) | Out-Null
        $Html = Get-PSIInteractionTestHtml -Report $Report
        $Html | Should -Match 'role="dialog" aria-modal="true"'
        $Html | Should -Match 'aria-labelledby="psi-dialog-title"'
        $Html | Should -Match 'data-psi-dialog-close aria-label="Close details"'
        $Html | Should -Match 'data-psi-dialog-search'
        $Html | Should -Match 'data-psi-dialog-head'
        $Html | Should -Match 'data-psi-dialog-body'
        $Html | Should -Match "event\.key === 'Escape'"
        $Html | Should -Match 'textContent = text'
        $Html | Should -Match 'psi-status-badge psi-status-'
        $Html | Should -Match 'event\.target === backdrop'
    }

    It 'keeps SVG charts connected to theme tokens in Light and Dark report themes' {
        foreach ($Theme in @('Light', 'Dark')) {
            $Report = New-PSIReport -Title 'Themed chart' -Theme $Theme
            $Report | Add-PSISection -Title 'Chart' | Add-PSIRow |
                Add-PSIChart -Title 'Sample counts' -ChartType Bar `
                    -Data @([pscustomobject]@{ Name = 'Healthy'; Count = 4 }) `
                    -CategoryProperty Name -ValueProperty Count -StatusProperty Name
            $Html = Get-PSIInteractionTestHtml -Report $Report
            $Html | Should -Match "data-theme=`"$Theme`""
            $Html | Should -Match 'data-chart-type="Bar"'
            $Html | Should -Match 'var\(--psi-chart-'
            $Html | Should -Match '\[data-theme="Dark"\]'
        }
    }

    It 'renders the full fictional demo with clickable sample KPIs, existing tables, and all chart types' {
        $ProjectPath = Split-Path -Path $PSScriptRoot -Parent
        $DemoPath = Join-Path -Path $ProjectPath -ChildPath 'Examples/New-DemoReport.ps1'
        $OutputPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([guid]::NewGuid().ToString() + '.html')
        try {
            & $DemoPath -NoBrowser -OutputPath $OutputPath | Out-Null
            $Html = [System.IO.File]::ReadAllText($OutputPath)

            foreach ($Text in @('Domain Controllers', 'Healthy Controllers', 'Replication Errors', 'DNS Issues', 'Service Inventory', 'Fictional Application Services')) {
                $Html | Should -Match $Text
            }
            foreach ($ChartType in @('Bar', 'Line', 'Doughnut', 'Pie')) {
                $Html | Should -Match "data-chart-type=`"$ChartType`""
            }
            $Html | Should -Match 'data-psi-drilldown'
            $Html | Should -Match 'data-psi-dialog-backdrop'
            $Html | Should -Match 'data-psi-search'
            $Html | Should -Match 'data-psi-sort='
            $Html | Should -Match 'data-psi-pagination'
            $Html | Should -Match 'psi-table-empty'
            $Html | Should -Match 'psi-alert'
            $Html | Should -Match 'psi-recommendation'
            $Html | Should -Match 'psi-footer'
            $Html | Should -Match 'psi-brand-mark'
            $Html | Should -Match 'data-psi-theme="Auto"'
        }
        finally {
            if (Test-Path -LiteralPath $OutputPath) { Remove-Item -LiteralPath $OutputPath -Force }
        }
    }

    It 'keeps generated reports self-contained without external asset references' {
        $Report = New-PSIInteractionTestReport
        $Report | Add-PSIKPI -Title 'Details' -Value 1 -Status Info -DrillDown @([pscustomobject]@{ Name = 'Sample'; Status = 'Info' }) | Out-Null
        $Report | Add-PSITable -Title 'Inventory' -Data @([pscustomobject]@{ Name = 'Sample' }) | Out-Null
        $Html = Get-PSIInteractionTestHtml -Report $Report
        $Html | Should -Not -Match '<link\s+[^>]*href\s*='
        $Html | Should -Not -Match '<script\s+[^>]*src\s*='
        $Html | Should -Not -Match '<img\s+[^>]*src\s*='
        $Html | Should -Match '<style>'
        $Html | Should -Match '<script>'
        $Html | Should -Match 'data-psi-dialog-backdrop'
    }
}
