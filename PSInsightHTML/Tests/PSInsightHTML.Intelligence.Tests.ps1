$ProjectRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path $ProjectRoot 'PSInsightHTML.psd1') -Force

Describe 'Generic application intelligence contracts' {
    BeforeAll {
        $script:Resource = New-PSIResource -Definition @{ Id='resource-one'; Name='Sample <node>'; Type='Service'; Status='Warning'; Properties=@{ Owner='Fictional team' } }
        $script:Finding = New-PSIApplicationFinding -Definition @{
            Id='finding-one'; Title='Queue <review>'; Summary='Sample observation'; Severity='Warning'; Status='Open'; Category='Processing'
            AffectedResourceIds=@('resource-one'); EvidenceIds=@('evidence-one')
            Recommendation=@{ Action='Review queue'; ExpectedState='Stable'; AutomationHint='Descriptive only' }
            Validation=@{ Method='Compare snapshots'; ExpectedResult='Stable'; Command='Get-SampleOnly'; EvidenceRequired=$true }
        }
        $script:Evidence = New-PSIEvidenceRecord -Definition @{
            Id='evidence-one'; Title='Sample <evidence>'; Type='Observation'; Source='Fictional source'; CollectedAt=[datetime] '2026-10-16'
            Data=@{ Result='<script>alert(1)</script>' }; FindingIds=@('finding-one'); ResourceIds=@('resource-one')
        }
        $script:Relationship = New-PSIRelationship -Definition @{
            Id='relationship-one'; SourceResourceId='resource-one'; TargetResourceId='resource-one'; Type='depends-on'; FindingIds=@('finding-one')
        }
        $script:Resource.FindingIds = @('finding-one')
        $script:Resource.EvidenceIds = @('evidence-one')
        $script:Resource.RelationshipIds = @('relationship-one')
        $script:Finding.Relationships = @('relationship-one')
    }

    It 'creates typed Finding, Resource, Evidence and Relationship records' {
        $script:Finding.Severity | Should -Be 'Warning'
        $script:Resource.Properties.Owner | Should -Be 'Fictional team'
        $script:Evidence.Data.Result | Should -Be '<script>alert(1)</script>'
        $script:Relationship.Direction | Should -Be 'Directed'
    }

    It 'rejects missing fields, invalid severity and invalid lifecycle status' {
        { New-PSIApplicationFinding -Definition @{ Id='missing'; Title='Bad'; Status='Open' } } | Should -Throw
        { New-PSIApplicationFinding -Definition @{ Id='bad'; Title='Bad'; Severity='Severe'; Status='Open' } } | Should -Throw
        { New-PSIApplicationFinding -Definition @{ Id='bad'; Title='Bad'; Severity='Warning'; Status='Undecided' } } | Should -Throw
        { New-PSIResource -Definition @{ Id='resource-x'; Name='Bad'; Type='Service'; Status='Broken' } } | Should -Throw
        { New-PSIEvidenceRecord -Definition @{ Id='evidence-x'; Title='Bad'; Type='Text'; Source='Sample'; CollectedAt='yesterday' } } | Should -Throw
    }

    It 'rejects malformed recommendation and validation data' {
        { New-PSIApplicationFinding -Definition @{ Id='bad'; Title='Bad'; Severity='Info'; Status='Open'; Recommendation='run this' } } | Should -Throw
        { New-PSIApplicationFinding -Definition @{ Id='bad'; Title='Bad'; Severity='Info'; Status='Open'; Validation=@{ Unknown='value' } } } | Should -Throw
    }

    It 'rejects duplicate IDs and broken resource, evidence and relationship references' {
        { New-PSIApplicationModel -Resources @($script:Resource,$script:Resource) } | Should -Throw '*duplicate*'
        { New-PSIApplicationModel -Findings @($script:Finding) } | Should -Throw '*broken*'
        $Bad = New-PSIResource -Definition @{ Id='resource-bad'; Name='Bad'; Type='Service'; Status='Unknown'; RelationshipIds=@('missing') }
        { New-PSIApplicationModel -Resources @($Bad) } | Should -Throw '*broken*'
        $BadRelationship = New-PSIRelationship -Definition @{ Id='relation-bad'; SourceResourceId='resource-one'; TargetResourceId='missing'; Type='depends-on' }
        { New-PSIApplicationModel -Resources @($script:Resource) -Relationships @($BadRelationship) } | Should -Throw '*broken*'
    }

    It 'rejects malformed records supplied directly to the model' {
        { New-PSIApplicationModel -Findings @([pscustomobject]@{ Id='finding-raw'; Title='Bad'; Severity='Severe'; Status='Open' }) } | Should -Throw
        { New-PSIApplicationModel -Resources @([pscustomobject]@{ Id='resource-raw'; Name='Bad'; Type='Service'; Status='Offline' }) } | Should -Throw
    }

    It 'validates reciprocal evidence and relationship links and aggregates generic counts' {
        $Model = New-PSIApplicationModel -Findings @($script:Finding) -Resources @($script:Resource) -Evidence @($script:Evidence) -Relationships @($script:Relationship)
        $Model.Summary.FindingsBySeverity.Warning | Should -Be 1
        $Model.Summary.FindingsByCategory.Processing | Should -Be 1
        $Model.Summary.ResourcesByStatus.Warning | Should -Be 1
        $Model.Summary.EvidenceCount | Should -Be 1
        $Model.Summary.ResourcesWithCriticalFindings | Should -Be 0
    }

    It 'renders linked investigation details with encoded content and no external assets' {
        $Model = New-PSIApplicationModel -Findings @($script:Finding) -Resources @($script:Resource) -Evidence @($script:Evidence) -Relationships @($script:Relationship)
        $Report = New-PSIReport -Title 'Sample' -Layout Application
        $Report | Set-PSIApplicationModel -Model $Model | Out-Null
        $Report | Add-PSIView -Id findings -Title Findings -Initial | Add-PSISection -Title Findings | Add-PSIRow |
            Add-PSIExplorer -Id findings-list -Title Findings -Data $Model.Findings -TitleProperty Title -EntityType Finding | Out-Null
        $Report | Add-PSIView -Id resources -Title Resources | Add-PSISection -Title Resources | Add-PSIRow |
            Add-PSIExplorer -Id resources-list -Title Resources -Data $Model.Resources -TitleProperty Name -EntityType Resource | Out-Null
        $Report | Add-PSIView -Id evidence -Title Evidence | Add-PSISection -Title Evidence | Add-PSIRow |
            Add-PSIExplorer -Id evidence-list -Title Evidence -Data $Model.Evidence -TitleProperty Title -EntityType Evidence | Out-Null
        $Path = Join-Path ([System.IO.Path]::GetTempPath()) (([guid]::NewGuid().ToString()) + '.html')
        try {
            Export-PSIReport -Report $Report -Path $Path | Out-Null
            $Html = [System.IO.File]::ReadAllText($Path)
            $Html | Should -Match 'data-psi-cross-view="resources" data-psi-cross-id="resource-one"'
            $Html | Should -Match 'data-psi-cross-view="evidence" data-psi-cross-id="evidence-one"'
            $Html | Should -Match 'data-psi-cross-view="findings" data-psi-cross-id="finding-one"'
            $Html | Should -Match 'Sample &lt;node&gt;'
            $Html | Should -Match '&lt;script&gt;alert\(1\)&lt;/script&gt;'
            $Html | Should -Not -Match '<script>alert\(1\)</script>|<script\s+[^>]*src\s*=|<link\s+[^>]*href\s*=|\bfetch\s*\('
        }
        finally { if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force } }
    }

    It 'supports custom view IDs and rejects broken cross-view mappings' {
        $Resource = New-PSIResource -Definition @{ Id='asset-one'; Name='Sample asset'; Type='Service'; Status='Healthy' }
        $Finding = New-PSIApplicationFinding -Definition @{ Id='issue-one'; Title='Sample issue'; Severity='Info'; Status='Open'; AffectedResourceIds=@('asset-one') }
        $Model = New-PSIApplicationModel -Findings @($Finding) -Resources @($Resource)
        $Report = New-PSIReport -Title 'Custom views' -Layout Application
        $Report | Set-PSIApplicationModel -Model $Model | Out-Null
        $Map = @{ Finding='observations'; Resource='assets'; Evidence='proof' }
        $Report | Add-PSIView -Id observations -Title Observations -Initial | Add-PSISection -Title Observations | Add-PSIRow |
            Add-PSIExplorer -Id issues -Title Issues -Data $Model.Findings -TitleProperty Title -EntityType Finding -LinkViews $Map | Out-Null
        $Report | Add-PSIView -Id assets -Title Assets | Add-PSISection -Title Assets | Add-PSIRow |
            Add-PSIExplorer -Id assets-list -Title Assets -Data $Model.Resources -TitleProperty Name -EntityType Resource -LinkViews $Map | Out-Null
        $Path = Join-Path ([System.IO.Path]::GetTempPath()) (([guid]::NewGuid().ToString()) + '.html')
        try {
            Export-PSIReport -Report $Report -Path $Path | Out-Null
            [System.IO.File]::ReadAllText($Path) | Should -Match 'data-psi-cross-view="assets" data-psi-cross-id="asset-one"'
            $Report.Views[0].Sections[0].Rows[0].Components[0].Properties.LinkViews.Resource = 'missing'
            { Export-PSIReport -Report $Report -Path $Path } | Should -Throw '*missing*'
        }
        finally { if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force } }
    }

    It 'rejects attaching intelligence to legacy Report layout while retaining legacy findings' {
        $Legacy = New-PSIReport -Title Legacy
        $Model = New-PSIApplicationModel
        { $Legacy | Set-PSIApplicationModel -Model $Model } | Should -Throw
        $Old = New-PSIFinding -Title 'Old finding' -Status Warning
        $Old.Title | Should -Be 'Old finding'
    }
}
