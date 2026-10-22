$ProjectRoot = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $ProjectRoot 'PSInsightHTML.psd1') -Force

Describe 'Fluent Resource Explorer and Context Inspector' {
    BeforeAll {
        $script:Root = Split-Path $PSScriptRoot -Parent
        $script:Output = Join-Path $TestDrive 'ResourceWorkspace.html'
        & (Join-Path $Root 'Examples/FluentExplorer/Invoke-FluentExplorerBenchmark.ps1') -OutputPath $script:Output | Out-Null
        $script:Html = [System.IO.File]::ReadAllText($script:Output)
        $script:DataMatch = [regex]::Match($script:Html, '(?s)<script type="application/json" id="psi-resource-data">([^<]*)</script>')
        $script:Registry = ConvertFrom-Json $script:DataMatch.Groups[1].Value
    }
    It 'keeps both shell panels opt-in' {
        $Plain = New-PSIReport -Title Plain
        $Plain | Add-PSISection -Title One | Add-PSIRow | Out-Null
        Export-PSIReport -Report $Plain -Path (Join-Path $TestDrive 'Plain.html') | Out-Null
        [System.IO.File]::ReadAllText((Join-Path $TestDrive 'Plain.html')) | Should -Not -Match 'data-psi-resource-explorer="true"'
        $App = New-PSIReport -Title Existing -Layout Application
        $App | Add-PSISection -Title One | Add-PSIRow | Out-Null
        Export-PSIReport -Report $App -Path (Join-Path $TestDrive 'Existing.html') | Out-Null
        [System.IO.File]::ReadAllText((Join-Path $TestDrive 'Existing.html')) | Should -Match 'data-psi-resource-explorer="false"'
        { $App | Add-PSIResourceExplorer -Id resources -Title Resources -Nodes @(@{ Id='one'; Label='One' }) } | Should -Throw '*FluentExplorer*'
    }
    It 'retains the existing in-view Add-PSIExplorer API' {
        $App = New-PSIReport -Title Existing -Layout Application
        $App | Add-PSIView -Id main -Title Main -Initial | Add-PSISection -Title Records | Add-PSIRow |
            Add-PSIExplorer -Id records -Title Records -Data @([pscustomobject]@{ Name='One'; Status='Healthy' }) -TitleProperty Name -StatusProperty Status | Out-Null
        $App.PSObject.Properties['ResourceExplorer'] | Should -BeNullOrEmpty
        $App.Sections[0].Rows[0].Components[0].Type | Should -Be 'Explorer'
    }
    It 'requires a Resource Explorer before adding an Inspector' {
        $App = New-PSIReport -Title Test -Layout Application -Navigation FluentExplorer
        { $App | Add-PSIInspector -Id context -Title Context -Items @(@{ Id='one'; ResourceId='one' }) } | Should -Throw '*Resource Explorer first*'
    }
    It 'renders the hierarchical node contract and selected state' {
        $script:Html | Should -Match 'data-psi-resource-node="forest"[^>]*aria-level="1"'
        $script:Html | Should -Match 'data-psi-resource-node="domain"[^>]*aria-level="2"'
        $script:Html | Should -Match 'data-psi-resource-node="dc01" data-psi-resource-parent="hq"[^>]*aria-level="5"[^>]*aria-selected="true"'
        $script:Html | Should -Match 'data-psi-resource-node="dc03"[^>]*data-psi-resource-status="Warning"'
        $script:Html | Should -Match 'role="tree"'
        $script:Html | Should -Match 'aria-expanded="true"'
    }
    It 'rejects duplicate, missing-parent, cyclic and invalid selected nodes' {
        $App = New-PSIReport -Title Test -Layout Application -Navigation FluentExplorer
        { $App | Add-PSIResourceExplorer -Id resources -Title Resources -Nodes @(@{ Id='one'; Label='One' },@{ Id='one'; Label='Again' }) } | Should -Throw '*duplicated*'
        { $App | Add-PSIResourceExplorer -Id resources -Title Resources -Nodes @(@{ Id='one'; Label='One'; ParentId='absent' }) } | Should -Throw '*missing parent*'
        { $App | Add-PSIResourceExplorer -Id resources -Title Resources -Nodes @(@{ Id='one'; Label='One'; ParentId='two' },@{ Id='two'; Label='Two'; ParentId='one' }) } | Should -Throw '*cycle*'
        { $App | Add-PSIResourceExplorer -Id resources -Title Resources -Nodes @(@{ Id='one'; Label='One' }) -SelectedId absent } | Should -Throw '*missing or not selectable*'
    }
    It 'rejects inspector ID and resource mapping conflicts' {
        $App = New-PSIReport -Title Test -Layout Application -Navigation FluentExplorer
        $App | Add-PSIResourceExplorer -Id resources -Title Resources -Nodes @(@{ Id='one'; Label='One' }) | Out-Null
        { $App | Add-PSIInspector -Id resources -Title Context -Items @(@{ Id='detail'; ResourceId='one' }) } | Should -Throw '*must differ*'
        { $App | Add-PSIInspector -Id context -Title Context -Items @(@{ Id='detail'; ResourceId='absent' }) } | Should -Throw '*unknown resource*'
        { $App | Add-PSIInspector -Id context -Title Context -Items @(@{ Id='detail'; ResourceId='one' },@{ Id='detail'; ResourceId='one' }) } | Should -Throw '*duplicated*'
    }
    It 'uses one normalized inspector lookup keyed by stable resource IDs' {
        $script:DataMatch.Success | Should -BeTrue
        @($script:Registry.PSObject.Properties).Count | Should -Be 6
        $script:Registry.dc01.ResourceId | Should -Be 'dc01'
        $script:Registry.dc03.Status | Should -Be 'Warning'
        $script:Registry.dc04.Status | Should -Be 'Critical'
        @($script:Registry.dc01.Properties | Where-Object Label -eq 'IPv4')[0].Value | Should -Be '192.0.2.10'
        $script:Html | Should -Not -Match 'data-psi-resource-node="dc01"[^>]*192\.0\.2\.10'
    }
    It 'provides properties, evidence, findings, recommendations and related-resource tabs' {
        $script:Registry.dc01.Sections.Id | Should -Contain 'Evidence'
        $script:Registry.dc01.Sections.Id | Should -Contain 'Findings'
        $script:Registry.dc01.Sections.Id | Should -Contain 'Recommendations'
        @($script:Registry.dc01.Sections | Where-Object Id -eq 'Findings')[0].Blocks.Count | Should -Be 0
        @($script:Registry.dc01.Sections | Where-Object Id -eq 'Recommendations')[0].Blocks.Count | Should -Be 0
        @($script:Registry.dc03.Sections | Where-Object Id -eq 'Findings')[0].Blocks.Count | Should -Be 1
        @($script:Registry.dc04.Sections | Where-Object Id -eq 'Findings')[0].Blocks.Count | Should -Be 1
        $script:Html | Should -Match 'role="tablist" aria-label="Resource details"'
        $script:Html | Should -Match 'aria-controls.*psi-inspector-panel'
    }
    It 'uses Fluent regular and filled icons and text status' {
        $script:Html | Should -Match 'psi-resource-icon"><svg[^>]*psi-icon-regular'
        $script:Html | Should -Match 'psi-icon-filled'
        $script:Html | Should -Match 'aria-label="Status: Critical"'
    }
    It 'has one set of panel controls and no duplicate DOM IDs' {
        $script:Html | Should -Match 'data-psi-resource-restore'
        $script:Html | Should -Match 'data-psi-inspector-restore'
        $WithoutScripts = [regex]::Replace($script:Html, '(?is)<script\b[^>]*>.*?</script>', '')
        $Ids = [regex]::Matches($WithoutScripts, '(?i)\bid="([^"]+)"') | ForEach-Object { $_.Groups[1].Value.ToLowerInvariant() }
        @($Ids | Sort-Object -Unique).Count | Should -Be $Ids.Count
    }
    It 'remains standalone and provides desktop, tablet and mobile styles' {
        $script:Html | Should -Not -Match '<script\s+[^>]*src\s*=|<link\s+[^>]*href\s*=|<img\s+[^>]*src\s*=|\bfetch\s*\('
        $script:Html | Should -Match '--psi-resource-explorer-width: 270px'
        $script:Html | Should -Match '--psi-resource-inspector-width: 340px'
        $script:Html | Should -Match '@media \(max-width: 900px\)'
        $script:Html | Should -Match '@media \(max-width: 640px\)'
    }
    It 'keeps new PowerShell source parseable with Windows PowerShell 5.1 syntax' {
        foreach ($File in @('Public/Add-PSIResourceExplorer.ps1','Public/Add-PSIInspector.ps1','Private/ConvertTo-PSIResourceWorkspace.ps1','Examples/FluentExplorer/Invoke-FluentExplorerBenchmark.ps1')) {
            $Tokens=$null; $Errors=$null
            $Ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:Root $File),[ref]$Tokens,[ref]$Errors)
            @($Errors).Count | Should -Be 0
            $Ast.Extent.Text | Should -Not -Match '\?\?|\?\.'
        }
    }
}
