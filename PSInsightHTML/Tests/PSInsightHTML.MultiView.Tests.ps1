$ProjectRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path $ProjectRoot 'PSInsightHTML.psd1') -Force

Describe 'PSInsightHTML generic multi-view application workspace' {
    BeforeAll {
        $script:WorkspaceRoot = Split-Path -Path $PSScriptRoot -Parent
        $script:Output = Join-Path ([System.IO.Path]::GetTempPath()) (([guid]::NewGuid().ToString()) + '.html')
        $script:ViewReport = New-PSIReport -Title 'Sample <workspace>' -Layout Application -Theme Dark
        $script:ViewReport | Add-PSIView -Id overview -Title 'Overview <sample>' -Subtitle 'Current & expected' -Icon NavigationHome -Initial `
            -Commands @(@{ Label='Open findings'; Icon='SeverityWarning'; TargetView='findings' }) |
            Add-PSISection -Title 'Snapshot' | Add-PSIRow | Add-PSIText -Text 'Only this view is visible first.' | Out-Null
        $script:ViewReport | Add-PSIView -Id findings -Title 'Findings' -Subtitle 'Review observations' -Icon SeverityWarning |
            Add-PSISection -Title 'Queue' | Add-PSIRow |
            Add-PSIExplorer -Id 'sample-explorer' -Title 'Evidence <queue>' `
                -Data @([pscustomobject]@{ Name='<script>alert(1)</script>'; Category='Sample'; Status='Warning'; Note=$null }) `
                -TitleProperty Name -SubtitleProperty Category -StatusProperty Status `
                -DetailProperties @('Name','Status','Note') | Out-Null
        Export-PSIReport -Report $script:ViewReport -Path $script:Output | Out-Null
        $script:Markup = [System.IO.File]::ReadAllText($script:Output)
    }
    AfterAll {
        if (Test-Path -LiteralPath $script:Output) { Remove-Item -LiteralPath $script:Output -Force }
    }

    It 'registers multiple views while retaining the same flat report sections' {
        $script:ViewReport.Views.Count | Should -Be 2
        $script:ViewReport.Sections.Count | Should -Be 2
        [object]::ReferenceEquals($script:ViewReport.Sections[1], $script:ViewReport.Views[1].Sections[0]) | Should -BeTrue
        $script:ViewReport.Views[1].Sections[0].ViewId | Should -Be 'findings'
    }

    It 'rejects duplicate IDs, invalid icons, and a view on a Report layout' {
        { $script:ViewReport | Add-PSIView -Id FINDINGS -Title Duplicate } | Should -Throw
        { $script:ViewReport | Add-PSIView -Id third -Title Third -Icon Nonexistent -Initial } | Should -Throw
        { (New-PSIReport -Title Legacy) | Add-PSIView -Id sample -Title Sample } | Should -Throw
    }

    It 'rejects sections before the first view and incomplete views' {
        $Invalid = New-PSIReport -Title Invalid -Layout Application
        $Invalid | Add-PSISection -Title Orphan | Out-Null
        { $Invalid | Add-PSIView -Id late -Title Late } | Should -Throw
        $Empty = New-PSIReport -Title Empty -Layout Application
        $Empty | Add-PSIView -Id empty -Title Empty | Out-Null
        { Export-PSIReport -Report $Empty -Path $script:Output } | Should -Throw
    }

    It 'validates view command targets and renders only the current view commands' {
        $script:Markup | Should -Match 'data-psi-app-command-view="overview" data-psi-app-command-target="findings"'
        $script:Markup | Should -Match 'Open findings'
        $Bad = New-PSIReport -Title Bad -Layout Application
        $Bad | Add-PSIView -Id first -Title First -Commands @(@{ Label='Missing'; Icon='Document'; TargetView='absent' }) |
            Add-PSISection -Title First | Add-PSIRow | Out-Null
        { Export-PSIReport -Report $Bad -Path $script:Output } | Should -Throw
    }

    It 'maps each navigation button to exactly one view and initializes the selected view' {
        $script:Markup | Should -Match 'data-psi-workspace="Views"'
        $script:Markup | Should -Match 'id="psi-app-item-overview"[^>]*data-psi-app-view-target="overview"[^>]*aria-controls="psi-view-overview"[^>]*aria-current="page"'
        $script:Markup | Should -Match 'id="psi-app-item-findings"[^>]*data-psi-app-view-target="findings"[^>]*aria-controls="psi-view-findings"'
        $script:Markup | Should -Match 'id="psi-view-overview"[^>]*data-psi-app-view="overview"[^>]*tabindex="-1">'
        $script:Markup | Should -Match 'id="psi-view-findings"[^>]*data-psi-app-view="findings"[^>]*tabindex="-1" hidden>'
    }

    It 'emits Regular and Filled Fluent icons and updates the active view title' {
        $script:Markup | Should -Match 'psi-app-nav-icon"><svg[^>]*psi-icon-regular[^>]*><path[^>]*fill="currentColor"/></svg><svg[^>]*psi-icon-filled[^>]*><path[^>]*fill="currentColor"/>'
        $script:Markup | Should -Match 'data-psi-app-view-title>Overview &lt;sample&gt;'
        $script:Markup | Should -Match 'data-psi-app-view-subtitle>Current &amp; expected'
        $script:Markup | Should -Match 'function activateView\(id, moveFocus\)'
        $script:Markup | Should -Match 'active\.focus\(\{ preventScroll: true \}\)'
    }

    It 'encodes view and explorer content, including untrusted labels and nulls' {
        $script:Markup | Should -Match 'Sample &lt;workspace&gt;'
        $script:Markup | Should -Match 'Evidence &lt;queue&gt;'
        $script:Markup | Should -Match '&lt;script&gt;alert\(1\)&lt;/script&gt;'
        $script:Markup | Should -Not -Match '<script>alert\(1\)</script>'
        $script:Markup | Should -Match 'psi-app-explorer-detail'
    }

    It 'renders an empty explorer and rejects duplicate explorer IDs' {
        $Empty = New-PSIReport -Title Empty -Layout Application
        $Empty | Add-PSIView -Id empty -Title Empty | Add-PSISection -Title Empty | Add-PSIRow |
            Add-PSIExplorer -Id empty-list -Title Empty -Data @() -TitleProperty Name | Out-Null
        Export-PSIReport -Report $Empty -Path $script:Output | Out-Null
        [System.IO.File]::ReadAllText($script:Output) | Should -Match 'No records available\.'
        $Empty | Add-PSIRow | Add-PSIExplorer -Id empty-list -Title Duplicate -Data @() -TitleProperty Name | Out-Null
        { Export-PSIReport -Report $Empty -Path $script:Output } | Should -Throw
    }

    It 'preserves the standalone theme, search, and native view accessibility contracts' {
        $script:Markup | Should -Match 'data-theme="Dark"'
        $script:Markup | Should -Match 'data-psi-theme="Light"'
        $script:Markup | Should -Match 'data-psi-theme="Auto"'
        $script:Markup | Should -Match 'data-psi-explorer-search'
        $script:Markup | Should -Match 'aria-selected="true"'
        $script:Markup | Should -Match 'role="tablist"'
        $script:Markup | Should -Match 'role="tabpanel"'
        $script:Markup | Should -Not -Match '<script\s+[^>]*src\s*=|<link\s+[^>]*href\s*=|<img\s+[^>]*src\s*=|\bfetch\s*\('
    }

    It 'preserves a plain Report and the earlier document-style Application shell' {
        $Legacy = New-PSIReport -Title Legacy
        $Legacy | Add-PSISection -Title One | Add-PSIRow | Add-PSIText -Text Sample | Out-Null
        Export-PSIReport -Report $Legacy -Path $script:Output | Out-Null
        $Html = [System.IO.File]::ReadAllText($script:Output)
        $Html | Should -Not -Match 'data-psi-layout="Application"|data-psi-app-view'
        $Document = New-PSIReport -Title Document -Layout Application
        $Document | Add-PSISection -Title One | Add-PSIRow | Add-PSIText -Text Sample | Out-Null
        Export-PSIReport -Report $Document -Path $script:Output | Out-Null
        $Html = [System.IO.File]::ReadAllText($script:Output)
        $Html | Should -Match 'data-psi-workspace="Document"'
        $Html | Should -Match 'href="#psi-section-0"'
        $Html | Should -Not -Match 'class="psi-app-view"'
    }

    It 'generates all nine fictional demo views from the public component API' {
        $Path = Join-Path ([System.IO.Path]::GetTempPath()) (([guid]::NewGuid().ToString()) + '.html')
        try {
            & (Join-Path $script:WorkspaceRoot 'Examples/New-AdaptiveDemoReport.ps1') -OutputPath $Path -NoBrowser | Out-Null
            $Html = [System.IO.File]::ReadAllText($Path)
            foreach ($Id in @('overview','checks','findings','resources','exceptions','security','policies','dependencies','evidence')) {
                $Html | Should -Match ('id="psi-view-' + $Id + '"')
            }
            ([regex]::Matches($Html, 'data-psi-app-view="')).Count | Should -Be 9
            $Html | Should -Match 'adaptive-findings'
            $Html | Should -Match 'adaptive-resources'
            $Html | Should -Match 'adaptive-evidence'
        }
        finally {
            if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
        }
    }
}
