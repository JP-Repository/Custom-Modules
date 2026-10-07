$ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path -Path $ModuleRoot -ChildPath 'PSInsightHTML.psd1') -Force

Describe 'PSInsightHTML structured findings' {
    BeforeAll {
        function New-PSIFindingTestReport {
            $Report = New-PSIReport -Title 'Finding test' -Theme Auto
            $Report | Add-PSISection -Title 'Assessment' | Add-PSIRow | Out-Null
            return $Report
        }
        function Get-PSIFindingTestHtml {
            param([pscustomobject] $Report)
            $Path = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.html')
            try {
                $null = Export-PSIReport -Report $Report -Path $Path
                return [System.IO.File]::ReadAllText($Path)
            }
            finally { if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force } }
        }
    }

    It 'creates the exact structured object with a safe generated ID and no HTML' {
        $Finding = New-PSIFinding -Title 'Sample' -Status Critical
        @($Finding.PSObject.Properties.Name) | Should -Be @('Id', 'Title', 'Status', 'Category', 'Description', 'AffectedObject', 'Impact', 'Recommendation', 'RuleId', 'Source', 'EvidenceTableId', 'EvidenceFilter', 'EvidenceColumns')
        $Finding.Id | Should -Match '^psi-finding-[0-9a-f]{32}$'
        $Finding.Status | Should -Be 'Critical'
        $Finding.EvidenceFilter | Should -BeOfType [hashtable]
        $Finding.EvidenceTableId | Should -Be ''
    }

    It 'preserves safe caller IDs and sanitizes unsafe ones' {
        (New-PSIFinding -Id 'sample-rule-01' -Title 'One' -Status Warning).Id | Should -Be 'sample-rule-01'
        (New-PSIFinding -Id ' 42 <sample> ' -Title 'Two' -Status Warning).Id | Should -Be 'psi-finding-42-sample'
    }

    It 'accepts all canonical severities and normalizes Info' {
        foreach ($Status in @('Healthy', 'Warning', 'Critical', 'Informational', 'Neutral', 'Unknown', 'NotChecked')) {
            (New-PSIFinding -Title 'Sample' -Status $Status).Status | Should -Be $Status
        }
        (New-PSIFinding -Title 'Sample' -Status Info).Status | Should -Be 'Informational'
        { New-PSIFinding -Title 'Sample' -Status Danger } | Should -Throw '*Unsupported PSInsightHTML status*'
    }

    It 'adds a Finding component with hashtable properties and preserves the report reference' {
        $Report = New-PSIFindingTestReport
        $Finding = New-PSIFinding -Title 'Sample' -Status Warning -Category 'Operations'
        $Result = $Report | Add-PSIFinding -Finding $Finding
        [object]::ReferenceEquals($Report, $Result) | Should -BeTrue
        $Component = $Report.Sections[0].Rows[0].Components[0]
        $Component.Type | Should -Be 'Finding'
        $Component.Properties | Should -BeOfType [hashtable]
        $Component.Properties.Status | Should -Be 'Warning'
    }

    It 'renders duplicate caller IDs with deterministic unique suffixes, including reserved IDs' {
        $Report = New-PSIFindingTestReport
        $Report | Add-PSIFinding -Finding (New-PSIFinding -Id 'same-id' -Title 'One' -Status Warning) | Out-Null
        $Report | Add-PSIFinding -Finding (New-PSIFinding -Id 'same-id' -Title 'Two' -Status Warning) | Out-Null
        $Report | Add-PSIFinding -Finding (New-PSIFinding -Id 'psi-section-0' -Title 'Three' -Status Info) | Out-Null
        $Report | Add-PSIFinding -Finding (New-PSIFinding -Id 'evidence-table' -Title 'Four' -Status Neutral) | Out-Null
        $Report | Add-PSITable -Id 'evidence-table' -Title 'Sample' -Data @() -Columns @('Name') | Out-Null
        $Html = Get-PSIFindingTestHtml -Report $Report
        $Html | Should -Match 'id="same-id" data-status="Warning"'
        $Html | Should -Match 'id="same-id-2" data-status="Warning"'
        $Html | Should -Match 'id="psi-section-0-2" data-status="Informational"'
        $Html | Should -Match 'id="evidence-table-2" data-status="Neutral"'
        $Ids = @([regex]::Matches($Html, '\bid="([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
        @($Ids | Sort-Object -Unique).Count | Should -Be $Ids.Count
    }

    It 'renders severity, category, description, impact, recommendation and provenance' {
        $Report = New-PSIFindingTestReport
        $Report | Add-PSIFinding -Finding (New-PSIFinding -Title 'Credential age' -Status Critical -Category 'Security' `
            -Description 'Two sample records match.' -AffectedObject 'Sample users' -Impact 'Exposure may increase.' `
            -Recommendation 'Review the policy.' -RuleId 'RULE-01' -Source 'Synthetic source') | Out-Null
        $Html = Get-PSIFindingTestHtml -Report $Report
        $Html | Should -Match 'psi-finding-card psi-status-critical'
        $Html | Should -Match 'psi-status-badge psi-status-critical">Critical</span>'
        foreach ($Text in @('Security', 'Credential age', 'Two sample records match.', 'Affected object', 'Sample users', 'Impact', 'Exposure may increase.', 'Recommendation', 'Review the policy.', 'Rule: RULE-01', 'Source: Synthetic source')) {
            $Html | Should -Match ([regex]::Escape($Text))
        }
    }

    It 'renders Warning and Informational using canonical theme classes' {
        $Report = New-PSIFindingTestReport
        $Report | Add-PSIFinding -Finding (New-PSIFinding -Title 'Warning sample' -Status Warning) | Out-Null
        $Report | Add-PSIFinding -Finding (New-PSIFinding -Title 'Info sample' -Status Info) | Out-Null
        $Html = Get-PSIFindingTestHtml -Report $Report
        $Html | Should -Match 'psi-finding-card psi-status-warning'
        $Html | Should -Match 'psi-finding-card psi-status-informational'
        $Html | Should -Match 'psi-status-badge psi-status-informational">Informational</span>'
        $Html | Should -Match 'border-left: 4px solid var\(--psi-component-status\)'
    }

    It 'omits absent optional content and an evidence button' {
        $Report = New-PSIFindingTestReport
        $Report | Add-PSIFinding -Finding (New-PSIFinding -Title 'Minimal' -Status Neutral -Description 'Sample only.') | Out-Null
        $Html = Get-PSIFindingTestHtml -Report $Report
        $Card = [regex]::Match($Html, '<article class="psi-finding-card.*?</article>', 'Singleline').Value
        $Card | Should -Match '<h3>Minimal</h3>'
        $Card | Should -Not -Match 'View Evidence|psi-finding-category|psi-finding-details|psi-finding-recommendation|psi-finding-footer|Rule:|Source:'
    }

    It 'normalizes short evidence filters to the existing Insight condition contract' {
        $Finding = New-PSIFinding -Title 'Age' -Status Critical -EvidenceTableId 'records' `
            -EvidenceFilter @{ Property = 'Age'; Value = 180; Operator = 'GreaterThanOrEqual' } -EvidenceColumns @('Name', 'Age')
        $Report = New-PSIFindingTestReport
        $Report | Add-PSIFinding -Finding $Finding | Out-Null
        $Report | Add-PSITable -Id 'records' -Title 'Records' -Data @([pscustomobject]@{ Name = 'Sample'; Age = 202 }) | Out-Null
        $Html = Get-PSIFindingTestHtml -Report $Report
        $Button = [regex]::Match($Html, '<button[^>]+data-psi-insight="([^"]+)"[^>]*>View Evidence', 'Singleline')
        $Button.Success | Should -BeTrue
        $Definition = [System.Net.WebUtility]::HtmlDecode($Button.Groups[1].Value) | ConvertFrom-Json
        $Definition.tableId | Should -Be 'records'
        $Definition.conditions.Count | Should -Be 1
        $Definition.conditions[0].Property | Should -Be 'Age'
        $Definition.conditions[0].Operator | Should -Be 'GreaterThanOrEqual'
        $Definition.conditions[0].Value | Should -Be 180
        @($Definition.evidenceColumns) | Should -Be @('Name', 'Age')
        @($Definition.exportColumns) | Should -Be @('Name', 'Age')
        $Html | Should -Not -Match 'data-psi-records='
    }

    It 'accepts the existing Insight Table and Conditions filter shape' {
        $Finding = New-PSIFinding -Title 'State' -Status Warning `
            -EvidenceFilter @{ Table = 'records'; Conditions = @(@{ Property = 'State'; Operator = 'Equals'; Value = 'Warning' }) }
        $Finding.EvidenceTableId | Should -Be 'records'
        $Report = New-PSIFindingTestReport
        $Report | Add-PSIFinding -Finding $Finding | Out-Null
        $Report | Add-PSITable -Id 'records' -Title 'Records' -Data @([pscustomobject]@{ State = 'Warning' }) | Out-Null
        $Html = Get-PSIFindingTestHtml -Report $Report
        $Html | Should -Match '&quot;tableId&quot;:&quot;records&quot;'
        $Html | Should -Match '&quot;Property&quot;:&quot;State&quot;'
    }

    It 'uses the existing evidence dialog, table registry and export controls' {
        $Report = New-PSIFindingTestReport
        $Report | Add-PSIFinding -Finding (New-PSIFinding -Title 'Evidence' -Status Critical -EvidenceTableId 'records' -EvidenceColumns @('Name') `
            -EvidenceFilter @{ Property = 'Name'; Value = 'Sample' }) | Out-Null
        $Report | Add-PSITable -Id 'records' -Title 'Records' -Data @([pscustomobject]@{ Name = 'Sample' }) | Out-Null
        $Html = Get-PSIFindingTestHtml -Report $Report
        ([regex]::Matches($Html, 'role="dialog" aria-modal="true"')).Count | Should -Be 1
        $Html | Should -Match 'window.PSIDataEngine.getRecords\(definition.tableId\)'
        $Html | Should -Match 'context\.controlConditions'
        foreach ($Token in @('data-psi-dialog-search', 'data-psi-dialog-filters', 'data-psi-dialog-pagination', 'data-psi-dialog-head', 'data-psi-export-format="csv"', 'data-psi-export-format="xlsx"', 'data-psi-export-format="print"')) {
            $Html | Should -Match $Token
        }
    }

    It 'uses visible table columns when evidence columns are omitted' {
        $Report = New-PSIFindingTestReport
        $Report | Add-PSIFinding -Finding (New-PSIFinding -Title 'All records' -Status Info -EvidenceTableId 'records') | Out-Null
        $Report | Add-PSITable -Id 'records' -Title 'Records' -Data @([pscustomobject]@{ Name = 'Sample' }) | Out-Null
        $Html = Get-PSIFindingTestHtml -Report $Report
        $Html | Should -Match '&quot;useVisibleColumns&quot;:true'
        $Html | Should -Match 'tableWidget.querySelectorAll\(''thead th\[data-psi-column\]''\)'
        $Html | Should -Match 'requestedExportColumns'
    }

    It 'rejects evidence filters without a table and mismatched references' {
        { New-PSIFinding -Title 'Bad' -Status Warning -EvidenceFilter @{ Property = 'State'; Value = 'Warning' } } | Should -Throw '*requires an EvidenceTableId*'
        { New-PSIFinding -Title 'Bad' -Status Warning -EvidenceTableId 'one' -EvidenceFilter @{ Table = 'two'; Conditions = @() } } | Should -Throw '*same table*'
        { New-PSIFinding -Title 'Bad' -Status Warning -EvidenceTableId 'one' -EvidenceFilter @{ Property = 'State'; Operator = 'RunScript'; Value = 'x' } } | Should -Throw '*not supported*'
    }

    It 'encodes all user-visible finding fields and evidence attributes' {
        $Unsafe = '<script>"&'' sample'
        $Report = New-PSIFindingTestReport
        $Finding = New-PSIFinding -Title $Unsafe -Status Critical -Category $Unsafe -Description $Unsafe `
            -AffectedObject $Unsafe -Impact $Unsafe -Recommendation $Unsafe -RuleId $Unsafe -Source $Unsafe `
            -EvidenceTableId 'records' -EvidenceFilter @{ Property = 'Name'; Value = $Unsafe }
        $Report | Add-PSIFinding -Finding $Finding | Out-Null
        $Report | Add-PSITable -Id 'records' -Title 'Records' -Data @([pscustomobject]@{ Name = $Unsafe }) | Out-Null
        $Html = Get-PSIFindingTestHtml -Report $Report
        $Card = [regex]::Match($Html, '<article class="psi-finding-card.*?</article>', 'Singleline').Value
        $Card | Should -Not -Match '<script>"&'
        $Card | Should -Match '&lt;script&gt;'
        $Card | Should -Match '&amp;'
        $Card | Should -Match '&quot;'
        $Card | Should -Match '&#39;|&#x27;|&#039;'
        $Card | Should -Match 'data-psi-insight="[^\"]*&quot;'
    }

    It 'keeps Insight, Alert, Recommendation and Table components available beside Findings' {
        $Report = New-PSIFindingTestReport
        $Report | Add-PSIFinding -Finding (New-PSIFinding -Title 'Finding' -Status Warning) | Out-Null
        $Report | Add-PSIAlert -Status Critical -Title 'Alert' -Message 'Sample' | Out-Null
        $Report | Add-PSIRecommendation -Title 'Recommendation' -Description 'Sample' | Out-Null
        $Report | Add-PSIInsight -Title 'Insight' -Value 1 | Out-Null
        $Report | Add-PSITable -Title 'Table' -Data @([pscustomobject]@{ Status = 'Healthy' }) | Out-Null
        $Html = Get-PSIFindingTestHtml -Report $Report
        foreach ($ClassName in @('psi-finding-card', 'psi-alert', 'psi-recommendation', 'psi-insight-card', 'psi-table-card')) {
            $Html | Should -Match $ClassName
        }
        $Html | Should -Match 'psi-status-badge psi-status-healthy">Healthy</span>'
    }
}
