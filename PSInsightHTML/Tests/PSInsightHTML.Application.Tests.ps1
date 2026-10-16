$ProjectRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path $ProjectRoot 'PSInsightHTML.psd1') -Force

Describe 'PSInsightHTML opt-in application shell and Fluent icons' {
    BeforeAll {
        $script:ApplicationRoot = Split-Path -Path $PSScriptRoot -Parent
        $script:TempHtml = Join-Path ([System.IO.Path]::GetTempPath()) (([guid]::NewGuid().ToString()) + '.html')
        $Report = New-PSIReport -Title 'Application test' -Theme Auto -Layout Application `
            -NavigationGroups @(@{ Label='Workspace'; Items=@(
                @{ Id='overview'; Label='Overview'; Target='psi-section-0'; Icon='NavigationHome'; Selected=$true },
                @{ Id='findings'; Label='Findings'; Target='psi-section-1'; Icon='SeverityWarning' }
            ) })
        $Report | Add-PSISection -Title 'Overview' | Add-PSIRow |
            Add-PSIKPI -Title 'Services' -Value 3 -Icon ResourceServer -Status Healthy | Out-Null
        $Report | Add-PSISection -Title 'Findings' | Add-PSIRow |
            Add-PSITable -Id 'app-sample' -Title 'Sample records' -Data @(
                [pscustomobject]@{ Name='Example'; Status='Warning' }
            ) | Out-Null
        Export-PSIReport -Report $Report -Path $script:TempHtml | Out-Null
        $script:ApplicationHtml = [System.IO.File]::ReadAllText($script:TempHtml)
    }
    AfterAll {
        if (Test-Path -LiteralPath $script:TempHtml) { Remove-Item -LiteralPath $script:TempHtml -Force }
    }

    It 'preserves the default report object and requires explicit application opt-in' {
        $Legacy = New-PSIReport -Title 'Legacy'
        $Legacy.PSObject.Properties.Name | Should -Not -Contain 'Layout'
        { New-PSIReport -Title 'Invalid' -NavigationGroups @(@{ Label='Bad' }) } | Should -Throw
        $script:ApplicationHtml | Should -Match 'data-psi-layout="Application"'
    }

    It 'embeds visible path geometry for all seven primary navigation roles' {
        $DemoPath = Join-Path ([System.IO.Path]::GetTempPath()) (([guid]::NewGuid().ToString()) + '.html')
        try {
            & (Join-Path $script:ApplicationRoot 'Examples/New-AdaptiveDemoReport.ps1') -OutputPath $DemoPath -NoBrowser | Out-Null
            $Demo = [System.IO.File]::ReadAllText($DemoPath)
            foreach ($Id in @('overview', 'findings', 'resources', 'security', 'policies', 'dependencies', 'evidence')) {
                $Demo | Should -Match ('id="psi-app-item-' + $Id + '"[^>]*>\s*<span class="psi-app-nav-icon"><svg[^>]*psi-icon-regular[^>]*><path d="[^"]+" fill="currentColor"/></svg><svg[^>]*psi-icon-filled[^>]*><path d="[^"]+" fill="currentColor"/></svg>')
            }
        }
        finally {
            if (Test-Path -LiteralPath $DemoPath) { Remove-Item -LiteralPath $DemoPath -Force }
        }
    }

    It 'uses regular and filled geometry for inactive and selected navigation' {
        $script:ApplicationHtml | Should -Match 'id="psi-app-item-overview"[^>]*aria-current="location"'
        $script:ApplicationHtml | Should -Match 'id="psi-app-item-findings"[^>]*class="psi-app-nav-item"[^>]*>'
        $script:ApplicationHtml | Should -Match '\.psi-app-nav-item\[aria-current="location"\] \.psi-icon-regular \{ display: none; \}'
        $script:ApplicationHtml | Should -Match '\.psi-app-nav-item\[aria-current="location"\] \.psi-icon-filled \{ display: inline-block; \}'
        InModuleScope PSInsightHTML {
            $Regular = Get-PSIIcon -Name NavigationHome -Variant Regular -Strict
            $Filled = Get-PSIIcon -Name NavigationHome -Variant Filled -Strict
            $Regular | Should -Not -Be $Filled
            $Regular | Should -Match '<path d="[^"]+" fill="currentColor"/>'
            $Filled | Should -Match '<path d="[^"]+" fill="currentColor"/>'
        }
    }

    It 'rejects missing curated icon roles and invalid application navigation' {
        InModuleScope PSInsightHTML {
            { Get-PSIIcon -Name MissingRole -Strict } | Should -Throw
        }
        $Bad = New-PSIReport -Title 'Bad' -Layout Application `
            -NavigationGroups @(@{ Label='Bad'; Items=@(@{ Id='bad'; Label='Bad'; Target='psi-section-9'; Icon='NavigationHome' }) })
        $Bad | Add-PSISection -Title 'Only section' | Add-PSIRow | Out-Null
        { Export-PSIReport -Report $Bad -Path $script:TempHtml } | Should -Throw
    }

    It 'embeds command bar, section, KPI, and theme icon paths' {
        $script:ApplicationHtml | Should -Match 'data-psi-app-find-table[^>]*>[\s\S]*?<svg[^>]*psi-icon-fluent[^>]*><path'
        $script:ApplicationHtml | Should -Match 'data-psi-theme="Light"[^>]*><svg[^>]*psi-icon-fluent[^>]*><path'
        $script:ApplicationHtml | Should -Match 'data-psi-theme="Dark"[^>]*><svg[^>]*psi-icon-fluent[^>]*><path'
        $script:ApplicationHtml | Should -Match 'data-psi-theme="Auto"[^>]*><svg[^>]*psi-icon-fluent[^>]*><path'
        $script:ApplicationHtml | Should -Match 'data-psi-export-trigger[^>]*>[\s\S]*?<svg[^>]*psi-icon-fluent[^>]*><path'
        $script:ApplicationHtml | Should -Match 'psi-app-section-icon"><svg[^>]*psi-icon-fluent[^>]*><path'
        $script:ApplicationHtml | Should -Match 'psi-kpi-icon[^>]*><svg[^>]*psi-icon-fluent[^>]*><path'
    }

    It 'keeps the application standalone and includes the Fluent attribution' {
        $script:ApplicationHtml | Should -Match '<template id="psi-fluent-icon-attribution">'
        $script:ApplicationHtml | Should -Match 'MIT License'
        $script:ApplicationHtml | Should -Not -Match '<script\s+[^>]*src\s*=|<link\s+[^>]*href\s*=|<img\s+[^>]*src\s*=|\bfetch\s*\('
    }

    It 'generates a standalone regular and filled icon showcase' {
        $Showcase = Join-Path ([System.IO.Path]::GetTempPath()) (([guid]::NewGuid().ToString()) + '.html')
        try {
            & (Join-Path $script:ApplicationRoot 'Examples/New-FluentIconShowcase.ps1') -OutputPath $Showcase | Out-Null
            $Html = [System.IO.File]::ReadAllText($Showcase)
            $Html | Should -Match '<th>Name</th><th>Regular</th><th>Filled</th>'
            ([regex]::Matches($Html, '<svg class="psi-icon psi-icon-fluent"')).Count | Should -Be 16
            $Html | Should -Not -Match '<script\s+[^>]*src\s*=|<link\s+[^>]*href\s*=|<img\s+[^>]*src\s*='
        }
        finally {
            if (Test-Path -LiteralPath $Showcase) { Remove-Item -LiteralPath $Showcase -Force }
        }
    }
}
