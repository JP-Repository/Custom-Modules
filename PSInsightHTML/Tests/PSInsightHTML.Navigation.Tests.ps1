$ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path $ModuleRoot 'PSInsightHTML.psd1') -Force

Describe 'PSInsightHTML sticky section navigation' {
    BeforeAll {
        function Get-NavigationHtml {
            param([pscustomobject] $Report)
            $Path = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.html')
            try {
                $null = Export-PSIReport -Report $Report -Path $Path
                [System.IO.File]::ReadAllText($Path)
            }
            finally {
                if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
            }
        }

        function New-NavigationReport {
            $Report = New-PSIReport -Title 'Navigation behavior'
            foreach ($Title in @('Environment Overview', 'Priority Findings', 'Environment Overview')) {
                $Report | Add-PSISection -Title $Title | Add-PSIRow | Add-PSIText -Text 'Fictional content' | Out-Null
            }
            $Report
        }
    }

    It 'renders generic section links and unique section anchors' {
        $Html = Get-NavigationHtml -Report (New-NavigationReport)
        $Html | Should -Match '<div class="psi-navigation-stack" data-psi-navigation-stack>'
        $Html | Should -Match '<nav class="psi-report-nav" aria-label="Report sections">'
        foreach ($Index in 0..2) {
            $Html | Should -Match ('data-psi-nav-section="psi-section-{0}" href="#psi-section-{0}"' -f $Index)
        }
        $Ids = @([regex]::Matches($Html, '\bid="(psi-section-[^"]+)"') | ForEach-Object { $_.Groups[1].Value })
        $Targets = @([regex]::Matches($Html, 'data-psi-nav-section="([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
        $Ids.Count | Should -Be 3
        @($Ids | Sort-Object -Unique).Count | Should -Be $Ids.Count
        $Targets.Count | Should -Be $Ids.Count
        @($Targets | Sort-Object -Unique).Count | Should -Be $Targets.Count
    }

    It 'embeds sticky horizontal navigation and section anchor offsets' {
        $Html = Get-NavigationHtml -Report (New-NavigationReport)
        $Html | Should -Match '\.psi-navigation-stack \{ position: sticky; top: 0; z-index: 30;'
        $Html | Should -Match '\.psi-navigation-stack \.psi-report-nav, \.psi-navigation-stack \.psi-assessment-nav \{[^}]*flex-wrap: nowrap;[^}]*overflow-x: auto;'
        $Html | Should -Match '\.psi-section \{[^}]*scroll-margin-top: var\(--psi-navigation-offset, 84px\);'
        $Html | Should -Match 'html \{ scroll-behavior: smooth; scroll-padding-top: var\(--psi-navigation-offset, 84px\); \}'
        $Html | Should -Match '@media \(prefers-reduced-motion: reduce\)'
        $Html | Should -Match '@media print \{'
        $Html | Should -Match '\.psi-navigation-stack, \.psi-assessment-nav, \.psi-section-nav-details, \.psi-report-nav,'
    }

    It 'embeds active section tracking for scroll resize click and hash navigation' {
        $Html = Get-NavigationHtml -Report (New-NavigationReport)
        $Html | Should -Match 'function updateReportNavigation\(\)'
        $Html | Should -Match "setAttribute\('aria-current', 'location'\)"
        $Html | Should -Match "window\.addEventListener\('scroll', scheduleReportNavigation"
        $Html | Should -Match "window\.addEventListener\('resize', scheduleReportNavigation\)"
        $Html | Should -Match "window\.addEventListener\('hashchange', scheduleReportNavigation\)"
        $Html | Should -Match "link\.addEventListener\('click'"
    }

    It 'retains assessment navigation in the shared sticky stack without child overlap' {
        $Report = New-PSIReport -Title 'Assessment navigation behavior'
        $Assessment = New-PSIAssessment -Id 'sample' -Name 'Sample assessment' -Provider 'Fictional'
        $Assessment | Add-PSISection -Title 'Assessment summary' | Add-PSIRow | Add-PSIText -Text 'Fictional content' | Out-Null
        $Report | Add-PSIAssessment -Assessment $Assessment | Add-PSIReportOverview | Out-Null
        $Html = Get-NavigationHtml -Report $Report
        $Html | Should -Match '<div class="psi-navigation-stack" data-psi-navigation-stack>\s*<nav class="psi-assessment-nav"'
        $Html | Should -Match '<details class="psi-section-nav-details">'
        $Html | Should -Match '\.psi-navigation-stack \.psi-assessment-nav \{ position: static; z-index: auto; \}'
        $Html | Should -Match 'function updateAssessmentNavigation\(\)'
        $Html | Should -Match 'data-psi-nav-assessment="overview"'
        $Html | Should -Match 'data-psi-nav-assessment="sample"'
    }
}
