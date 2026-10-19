$ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path $ModuleRoot 'PSInsightHTML.psd1') -Force

Describe 'Generic relationship presentation contracts' {
    BeforeAll {
        $script:ResourceA = New-PSIResource -Definition @{ Id='resource-a'; Name='Service <A>'; Type='Application'; Status='Healthy'; Properties=@{ Region='North'; Password='DO_NOT_SHOW' } }
        $script:ResourceB = New-PSIResource -Definition @{ Id='resource-b'; Name='Service B'; Type='Database'; Status='Warning' }
        $script:Relationship = New-PSIRelationship -Definition @{ Id='relationship-a'; SourceResourceId='resource-a'; TargetResourceId='resource-b'; Type='depends-on'; Label='Uses data'; Status='Warning'; Category='Availability'; Direction='Directed' }
        $script:Model = New-PSIApplicationModel -Resources @($script:ResourceA,$script:ResourceB) -Relationships @($script:Relationship)
        $script:Hierarchy = @(
            @{ NodeId='resource-a'; ResourceId='resource-a'; Icon='ResourceServer' },
            @{ NodeId='resource-b'; ResourceId='resource-b'; ParentId='resource-a' }
        )
        function New-PSIRelationshipFixture {
            $Report = New-PSIReport -Title 'Fictional topology' -Layout Application -Theme Auto
            $null = $Report | Set-PSIApplicationModel -Model $script:Model
            $null = $Report | Add-PSIView -Id topology -Title Topology -Initial | Add-PSISection -Title Graph | Add-PSIRow
            return $Report
        }
        function Get-PSIRelationshipFixtureHtml {
            param([pscustomobject] $Report)
            $Path = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.html')
            try { $null = Export-PSIReport -Report $Report -Path $Path; return [System.IO.File]::ReadAllText($Path) }
            finally { if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force } }
        }
    }

    It 'exports three reusable public presentation commands' {
        foreach ($Name in @('Add-PSITree','Add-PSITopology','Add-PSIRelationshipExplorer')) {
            (Get-Command $Name -Module PSInsightHTML).Name | Should -Be $Name
        }
    }
    It 'keeps existing relationships valid and adds optional display metadata' {
        $script:Relationship.Direction | Should -Be 'Directed'
        $script:Relationship.Label | Should -Be 'Uses data'
        $script:Relationship.Category | Should -Be 'Availability'
        { New-PSIRelationship -Definition @{ Id='bad'; SourceResourceId='resource-a'; TargetResourceId='resource-b'; Type='links'; IsExternal=$true } } | Should -Throw '*evidence-only*'
    }
    It 'accepts only explicitly evidence-only external endpoints outside resource scope' {
        $External = New-PSIRelationship -Definition @{ Id='external-one'; SourceResourceId='external-source'; TargetResourceId='resource-a'; Type='observes'; IsExternal=$true; EvidenceOnly=$true }
        $Model = New-PSIApplicationModel -Resources @($script:ResourceA) -Relationships @($External)
        $Model.Resources.Count | Should -Be 1
        $Model.Relationships.Count | Should -Be 1
        $Ordinary = New-PSIRelationship -Definition @{ Id='ordinary-one'; SourceResourceId='external-source'; TargetResourceId='resource-a'; Type='observes' }
        { New-PSIApplicationModel -Resources @($script:ResourceA) -Relationships @($Ordinary) } | Should -Throw '*broken*'
    }
    It 'derives nodes and edges from generic application model records' {
        InModuleScope PSInsightHTML -Parameters @{ Model=$script:Model } {
            $Presentation = Resolve-PSIRelationshipPresentation -Model $Model
            $Presentation.Nodes.Count | Should -Be 2
            $Presentation.Edges.Count | Should -Be 1
            $Presentation.Edges[0].SourceId | Should -Be 'resource-a'
            $Presentation.Edges[0].TargetId | Should -Be 'resource-b'
        }
    }
    It 'uses relationship type and impact when optional display text is absent' {
        $Default = New-PSIRelationship -Definition @{ Id='default-label'; SourceResourceId='resource-a'; TargetResourceId='resource-b'; Type='depends-on'; Impact='Shared storage path' }
        $Model = New-PSIApplicationModel -Resources @($script:ResourceA,$script:ResourceB) -Relationships @($Default)
        InModuleScope PSInsightHTML -Parameters @{ Model=$Model } {
            $Edge = (Resolve-PSIRelationshipPresentation -Model $Model).Edges[0]
            $Edge.Label | Should -Be 'depends-on'
            $Edge.Description | Should -Be 'Shared storage path'
        }
    }
    It 'preserves multiple roots and provider-supplied parent links' {
        InModuleScope PSInsightHTML -Parameters @{ Model=$script:Model; Hierarchy=$script:Hierarchy } {
            $Presentation = Resolve-PSIRelationshipPresentation -Model $Model -Nodes $Hierarchy
            @($Presentation.Nodes | Where-Object { -not $_.ParentId }).Count | Should -Be 1
            (@($Presentation.Nodes | Where-Object Id -eq 'resource-b')[0]).ParentId | Should -Be 'resource-a'
            $Roots = Resolve-PSIRelationshipPresentation -Model $Model
            @($Roots.Nodes | Where-Object { -not $_.ParentId }).Count | Should -Be 2
        }
    }
    It 'repairs duplicate IDs, missing parents and cycles without failing export' {
        InModuleScope PSInsightHTML -Parameters @{ Model=$script:Model } {
            $Nodes = @(
                @{ NodeId='resource-a'; ResourceId='resource-a'; ParentId='resource-b' },
                @{ NodeId='resource-b'; ResourceId='resource-b'; ParentId='resource-a' },
                @{ NodeId='resource-b'; ResourceId='resource-b' },
                @{ NodeId='external-x'; Label='External'; IsExternal=$true; EvidenceOnly=$true; ParentId='missing' }
            )
            $Presentation = Resolve-PSIRelationshipPresentation -Model $Model -Nodes $Nodes
            $Presentation.Nodes.Count | Should -Be 3
            @($Presentation.Nodes | Where-Object { -not $_.ParentId }).Count | Should -BeGreaterThan 0
            ($Presentation.Diagnostics -join ' ') | Should -Match 'Duplicate|missing parent|cycle'
        }
    }
    It 'synthesizes external evidence endpoints without adding assessed resources' {
        InModuleScope PSInsightHTML -Parameters @{ Model=$script:Model } {
            $Presentation = Resolve-PSIRelationshipPresentation -Model $Model -Relationships @(@{ Id='external-link'; SourceId='outside'; TargetId='resource-a'; Type='observes'; IsExternal=$true; EvidenceOnly=$true })
            $External = @($Presentation.Nodes | Where-Object Id -eq 'outside')[0]
            $External.External | Should -BeTrue
            $External.EvidenceOnly | Should -BeTrue
            $External.ResourceId | Should -Be ''
            $Model.Resources.Count | Should -Be 2
        }
    }
    It 'renders a semantic tree with keyboard metadata and encoded labels' {
        $Report = New-PSIRelationshipFixture
        $Report | Add-PSITree -Id sample-tree -Title 'Sample tree' -Nodes $script:Hierarchy -DetailProperties @('Region','Password') | Out-Null
        $Html = Get-PSIRelationshipFixtureHtml $Report
        $Html | Should -Match 'role="tree"|role="treeitem"'
        $Html | Should -Match 'aria-expanded="true"'
        $Html | Should -Match 'aria-level="2"'
        $Html | Should -Match 'Service &lt;A&gt;'
        $Html | Should -Not -Match 'DO_NOT_SHOW'
        $Html | Should -Match 'ArrowDown|ArrowRight|Home|End'
    }
    It 'renders SVG topology with a text relationship list and display limit' {
        $Report = New-PSIRelationshipFixture
        $Report | Add-PSITopology -Id sample-topology -Title 'Sample topology' -MaxNodes 1 | Out-Null
        $Html = Get-PSIRelationshipFixtureHtml $Report
        $Html | Should -Match 'data-psi-rel-max="1"'
        $Html | Should -Match 'data-psi-rel-svg'
        $Html | Should -Match 'Relationship list'
        $Html | Should -Match 'data-psi-rel-edge="relationship-a"'
        $Html | Should -Match 'display limit'
        $Html | Should -Match 'role="group" aria-label="Sample topology graph"'
    }
    It 'renders a relationship master/detail component and generic filters' {
        $Report = New-PSIRelationshipFixture
        $Report | Add-PSIRelationshipExplorer -Id sample-links -Title 'Sample links' | Out-Null
        $Html = Get-PSIRelationshipFixtureHtml $Report
        $Html | Should -Match 'data-psi-rel-mode="Explorer"'
        $Html | Should -Match 'data-psi-rel-filter="type"'
        $Html | Should -Match 'data-psi-rel-filter="edge-type"'
        $Html | Should -Match 'data-psi-rel-filter="category"'
        $Html | Should -Match 'Incoming|Outgoing'
    }
    It 'includes cross-view targets and automatic view search registration' {
        $Report = New-PSIRelationshipFixture
        $Report | Add-PSITopology -Id sample-topology -Title 'Sample topology' | Out-Null
        $Html = Get-PSIRelationshipFixtureHtml $Report
        $Html | Should -Match '"Resource":"resources"'
        $Html | Should -Match 'selectEntity\(data.LinkViews.Resource'
        $Html | Should -Match '"EntityType":"View"'
        $Html | Should -Match '"ViewId":"topology"'
    }
    It 'keeps legacy report output and print projection separate from interactive topology' {
        $Legacy = New-PSIReport -Title Legacy
        $Legacy | Add-PSISection -Title Basic | Add-PSIRow | Out-Null
        $LegacyHtml = Get-PSIRelationshipFixtureHtml $Legacy
        $LegacyHtml | Should -Not -Match 'psi-relationships|data-psi-rel-component'
        $Report = New-PSIRelationshipFixture
        $Report | Add-PSITopology -Id sample-topology -Title 'Sample topology' | Out-Null
        $Html = Get-PSIRelationshipFixtureHtml $Report
        $Html | Should -Match 'id="psi-print-document"'
        $Print = [regex]::Match($Html, '(?s)<article class="psi-print-document".*?</footer></article>').Value
        $Print | Should -Not -Match 'data-psi-rel-svg|psi-rel-graph'
    }
    It 'embeds assets offline and provides mobile list fallback and visible focus' {
        $Report = New-PSIRelationshipFixture
        $Report | Add-PSITopology -Id sample-topology -Title 'Sample topology' | Out-Null
        $Html = Get-PSIRelationshipFixtureHtml $Report
        $Html | Should -Match '@media \(max-width: 760px\)'
        $Html | Should -Match 'psi-rel-topology \.psi-rel-viewport \{ display: none'
        $Html | Should -Match 'focus-visible'
        $Html | Should -Not -Match '<script\s+[^>]*src\s*=|<link\s+[^>]*href\s*=|<img\s+[^>]*src\s*=|fetch\('
    }
    It 'rejects invalid API values before adding a component' {
        $Report = New-PSIRelationshipFixture
        { $Report | Add-PSITopology -Id bad -Title Bad -MaxNodes 0 -ErrorAction Stop | Out-Null } | Should -Throw
        { $Report | Add-PSITree -Id 'bad id' -Title Bad -ErrorAction Stop | Out-Null } | Should -Throw
        $Report.Sections[0].Rows[0].Components.Count | Should -Be 0
    }
    It 'uses one normalized detail model for safe properties and links' {
        InModuleScope PSInsightHTML -Parameters @{ Model=$script:Model } {
            $Presentation = Resolve-PSIRelationshipPresentation -Model $Model -DetailProperties @('Region','Password')
            $Node = @($Presentation.Nodes | Where-Object Id -eq 'resource-a')[0]
            $Node.Details.Count | Should -Be 1
            $Node.Details[0].Label | Should -Be 'Region'
            $Node.Details[0].Value | Should -Be 'North'
        }
    }
}
