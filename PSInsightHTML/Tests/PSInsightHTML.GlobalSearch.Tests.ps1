$ProjectRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path $ProjectRoot 'PSInsightHTML.psd1') -Force

Describe 'Application global search and command palette' {
    BeforeAll {
        $script:Root = Split-Path -Path $PSScriptRoot -Parent
        $script:DemoPath = Join-Path ([System.IO.Path]::GetTempPath()) (([guid]::NewGuid().ToString()) + '.html')
        & (Join-Path $script:Root 'Examples/New-AdaptiveDemoReport.ps1') -OutputPath $script:DemoPath -NoBrowser | Out-Null
        $script:Html = [System.IO.File]::ReadAllText($script:DemoPath)
        $Match = [regex]::Match($script:Html, '<script type="application/json" id="psi-global-search-index">([^<]*)</script>')
        if (-not $Match.Success) { throw 'Search index missing from adaptive demo.' }
        $script:Index = @($Match.Groups[1].Value | ConvertFrom-Json)
        $script:SearchScript = [System.IO.File]::ReadAllText((Join-Path $script:Root 'Assets/JavaScript/psi-search.js'))
    }
    AfterAll {
        if (Test-Path -LiteralPath $script:DemoPath) { Remove-Item -LiteralPath $script:DemoPath -Force }
    }
    It 'embeds one compact index and a visible global search entry' {
        $script:Html | Should -Match 'data-psi-global-search-trigger'
        $script:Html | Should -Match 'role="dialog" aria-modal="true"'
        $script:Html | Should -Match 'role="combobox" aria-autocomplete="list"'
        $script:Index.Count | Should -BeGreaterThan 20
        ([regex]::Matches($script:Html, 'id="psi-global-search-index"')).Count | Should -Be 1
    }
    It 'indexes views, checks, findings, resources, evidence, and exceptions with cross-view targets' {
        foreach ($Kind in @('View','Check','Finding','Resource','Evidence','Exception')) {
            @($script:Index | Where-Object EntityType -eq $Kind).Count | Should -BeGreaterThan 0
        }
        foreach ($Item in $script:Index) {
            $Item.ViewId | Should -Not -BeNullOrEmpty
            if ($Item.EntityType -ne 'View') { $Item.TargetId | Should -Be $Item.Id }
        }
        @($script:Index | Where-Object { $_.EntityType -eq 'Check' -and $_.Category }).Count | Should -BeGreaterThan 0
    }
    It 'keeps status and severity but excludes raw evidence, metadata, and resource properties' {
        @($script:Index | Where-Object { $_.Status -or $_.Severity }).Count | Should -BeGreaterThan 0
        foreach ($Item in $script:Index) {
            $Item.PSObject.Properties.Name | Should -Not -Contain 'Data'
            $Item.PSObject.Properties.Name | Should -Not -Contain 'Metadata'
            $Item.PSObject.Properties.Name | Should -Not -Contain 'Properties'
        }
        InModuleScope PSInsightHTML {
            $Record = [pscustomobject]@{ Id='resource-one'; Name='Visible name'; Type='Service'; Status='Healthy'; Description='Visible description'; Properties=@{ Password='DO_NOT_INDEX_SECRET' }; Metadata=@{ Token='DO_NOT_INDEX_SECRET' } }
            $Component = [pscustomobject]@{ Type='Explorer'; Properties=@{ EntityType='Resource'; Data=@($Record); TitleProperty='Name'; SubtitleProperty='Type' } }
            $Row = [pscustomobject]@{ Components=@($Component) }
            $Section = [pscustomobject]@{ Rows=@($Row) }
            $View = [pscustomobject]@{ Id='resources'; Title='Resources'; Subtitle='Items'; Group='Workspace'; Icon='ResourceServer'; Sections=@($Section) }
            $Report = [pscustomobject]@{ Views=@($View) }
            $Result = @(Get-PSIApplicationSearchIndex -Report $Report)
            $Result.Count | Should -Be 2
            ($Result | ConvertTo-Json -Depth 5) | Should -Not -Match 'DO_NOT_INDEX_SECRET|Password|Token'
        }
    }
    It 'has explicit ranking tiers, a result cap, and safe text rendering' {
        $script:SearchScript | Should -Match 'item\._title === q'
        $script:SearchScript | Should -Match 'item\._id === q'
        $script:SearchScript | Should -Match 'words\.every'
        $script:SearchScript | Should -Match 'matches\.slice\(0, 20\)'
        $script:SearchScript | Should -Match 'node\.textContent = value'
        $script:SearchScript | Should -Not -Match '\.innerHTML\s*='
    }
    It 'registers generic view, theme, export, and local-search commands with contextual availability' {
        foreach ($Action in @('OpenView','Theme','OpenExport','FocusActiveTable','ClearFilters')) {
            $script:SearchScript | Should -Match ("ActionType: '" + $Action + "'")
        }
        $script:SearchScript | Should -Match 'Available: filtersActive'
        $script:SearchScript | Should -Match 'Available: function \(\) \{ return !!activeSearch\(\)'
        $script:Html | Should -Match 'data-psi-global-mode="Commands"'
    }
    It 'provides keyboard and accessible navigation hooks' {
        foreach ($Key in @('ArrowDown','ArrowUp','Enter','Escape','Tab')) { $script:SearchScript | Should -Match $Key }
        $script:SearchScript | Should -Match 'event\.ctrlKey \|\| event\.metaKey'
        $script:SearchScript | Should -Match 'window\.PSIApplication\.selectEntity'
        $script:Html | Should -Match 'aria-activedescendant|aria-controls="psi-global-search-results"'
        $script:Html | Should -Match 'role="listbox"'
    }
    It 'preserves standalone output and leaves legacy report layout without the palette' {
        $script:Html | Should -Not -Match '<script\s+[^>]*src\s*=|<link\s+[^>]*href\s*=|<img\s+[^>]*src\s*=|\bfetch\s*\('
        $LegacyPath = Join-Path ([System.IO.Path]::GetTempPath()) (([guid]::NewGuid().ToString()) + '.html')
        try {
            $Legacy = New-PSIReport -Title 'Legacy report'
            $Legacy | Add-PSISection -Title 'Section' | Add-PSIRow | Out-Null
            Export-PSIReport -Report $Legacy -Path $LegacyPath | Out-Null
            ([System.IO.File]::ReadAllText($LegacyPath)) | Should -Not -Match 'psi-global-search-index|data-psi-global-search-trigger'
        }
        finally { if (Test-Path -LiteralPath $LegacyPath) { Remove-Item -LiteralPath $LegacyPath -Force } }
    }
}
