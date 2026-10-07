$ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path -Path $ModuleRoot -ChildPath 'PSInsightHTML.psd1') -Force

Describe 'PSInsightHTML declarative table conditions' {
    BeforeAll {
        function New-PSIConditionTestReport {
            $Report = New-PSIReport -Title 'Condition test' -Theme Auto
            $Report | Add-PSISection -Title 'Sample' | Add-PSIRow | Out-Null
            return $Report
        }
        function Get-PSIConditionTestHtml {
            param([pscustomobject] $Report)
            $Path = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.html')
            try {
                $null = Export-PSIReport -Report $Report -Path $Path
                return [System.IO.File]::ReadAllText($Path)
            }
            finally { if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force } }
        }
    }

    It 'returns the exact pure definition contract and normalizes Info' {
        $Condition = New-PSICondition -Property State -Operator Equals -Value Ready -Status Info
        @($Condition.PSObject.Properties.Name) | Should -Be @('Property', 'Operator', 'Value', 'Status', 'Scope')
        $Condition.Property | Should -Be 'State'
        $Condition.Status | Should -Be 'Informational'
        $Condition.Scope | Should -Be 'Cell'
        (Get-Command New-PSICondition -Module PSInsightHTML) | Should -Not -BeNullOrEmpty
        (Get-Command Test-PSICondition -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
    }

    It 'requires a value for binary operators and rejects invalid regex at creation' {
        { New-PSICondition -Property State -Operator Equals -Status Warning } | Should -Throw '*requires a Value*'
        { New-PSICondition -Property State -Operator Match -Value '[' -Status Warning } | Should -Throw '*Match pattern is invalid*'
        { New-PSICondition -Property State -Operator Execute -Value x -Status Warning } | Should -Throw
        { New-PSICondition -Property State -Operator Equals -Value x -Status Danger } | Should -Throw
        { New-PSICondition -Property State -Operator Equals -Value x -Status Warning -Scope Page } | Should -Throw
    }

    It 'supports case-insensitive string Equals and NotEquals' {
        InModuleScope PSInsightHTML {
            (Test-PSICondition -InputObject @{ State = 'READY' } -Condition (New-PSICondition -Property State -Operator Equals -Value 'ready' -Status Healthy)) | Should -BeTrue
            (Test-PSICondition -InputObject @{ State = 'READY' } -Condition (New-PSICondition -Property State -Operator NotEquals -Value 'stopped' -Status Warning)) | Should -BeTrue
            (Test-PSICondition -InputObject @{ State = 'READY' } -Condition (New-PSICondition -Property State -Operator NotEquals -Value 'ready' -Status Warning)) | Should -BeFalse
        }
    }

    It 'compares numeric strings and numbers without lexical ordering' {
        InModuleScope PSInsightHTML {
            (Test-PSICondition -InputObject @{ Age = 202 } -Condition (New-PSICondition -Property Age -Operator GreaterThan -Value '180' -Status Critical)) | Should -BeTrue
            (Test-PSICondition -InputObject @{ Age = 9 } -Condition (New-PSICondition -Property Age -Operator LessThan -Value 10 -Status Warning)) | Should -BeTrue
            (Test-PSICondition -InputObject @{ Age = '02' } -Condition (New-PSICondition -Property Age -Operator Equals -Value 2 -Status Info)) | Should -BeTrue
        }
    }

    It 'supports GreaterThanOrEqual and LessThanOrEqual at the boundary' {
        InModuleScope PSInsightHTML {
            (Test-PSICondition -InputObject @{ Age = 60 } -Condition (New-PSICondition -Property Age -Operator GreaterThanOrEqual -Value 60 -Status Warning)) | Should -BeTrue
            (Test-PSICondition -InputObject @{ Age = 60 } -Condition (New-PSICondition -Property Age -Operator LessThanOrEqual -Value 60 -Status Warning)) | Should -BeTrue
            (Test-PSICondition -InputObject @{ Age = 59 } -Condition (New-PSICondition -Property Age -Operator GreaterThanOrEqual -Value 60 -Status Warning)) | Should -BeFalse
        }
    }

    It 'compares dates and uses string order only when numeric and date comparisons do not apply' {
        InModuleScope PSInsightHTML {
            (Test-PSICondition -InputObject @{ Checked = [datetime]'2026-10-07' } -Condition (New-PSICondition -Property Checked -Operator GreaterThan -Value ([datetime]'2026-10-06') -Status Healthy)) | Should -BeTrue
            (Test-PSICondition -InputObject @{ Checked = '2026-10-07' } -Condition (New-PSICondition -Property Checked -Operator LessThan -Value '2026-10-08' -Status Warning)) | Should -BeTrue
            (Test-PSICondition -InputObject @{ Checked = [datetimeoffset]'2026-10-07T12:00:00+05:30' } -Condition (New-PSICondition -Property Checked -Operator GreaterThan -Value ([datetimeoffset]'2026-10-07T06:00:00Z') -Status Healthy)) | Should -BeTrue
            (Test-PSICondition -InputObject @{ State = 'beta' } -Condition (New-PSICondition -Property State -Operator GreaterThan -Value 'alpha' -Status Info)) | Should -BeTrue
        }
    }

    It 'supports booleans without treating them as numeric values' {
        InModuleScope PSInsightHTML {
            (Test-PSICondition -InputObject @{ Flag = $true } -Condition (New-PSICondition -Property Flag -Operator Equals -Value $true -Status Warning)) | Should -BeTrue
            (Test-PSICondition -InputObject @{ Flag = $true } -Condition (New-PSICondition -Property Flag -Operator Equals -Value 'true' -Status Warning)) | Should -BeTrue
            (Test-PSICondition -InputObject @{ Flag = $true } -Condition (New-PSICondition -Property Flag -Operator GreaterThan -Value 0 -Status Warning)) | Should -BeFalse
        }
    }

    It 'uses case-insensitive Contains and .NET regex Match' {
        InModuleScope PSInsightHTML {
            (Test-PSICondition -InputObject @{ Note = 'Sample Network Check' } -Condition (New-PSICondition -Property Note -Operator Contains -Value 'NETWORK' -Status Info)) | Should -BeTrue
            (Test-PSICondition -InputObject @{ Note = 'node-42' } -Condition (New-PSICondition -Property Note -Operator Match -Value '^NODE-\d+$' -Status Healthy)) | Should -BeTrue
            (Test-PSICondition -InputObject @{ Note = 'node-x' } -Condition (New-PSICondition -Property Note -Operator Match -Value '^NODE-\d+$' -Status Healthy)) | Should -BeFalse
        }
    }

    It 'treats null deterministically and rejects non-comparable values' {
        InModuleScope PSInsightHTML {
            (Test-PSICondition -InputObject @{ Note = $null } -Condition (New-PSICondition -Property Note -Operator IsNull -Status Warning)) | Should -BeTrue
            (Test-PSICondition -InputObject @{ Note = '' } -Condition (New-PSICondition -Property Note -Operator IsNotNull -Status Healthy)) | Should -BeTrue
            (Test-PSICondition -InputObject @{ Note = $null } -Condition (New-PSICondition -Property Note -Operator Equals -Value $null -Status Info)) | Should -BeTrue
            (Test-PSICondition -InputObject @{ Note = $null } -Condition (New-PSICondition -Property Note -Operator NotEquals -Value 'x' -Status Warning)) | Should -BeTrue
            (Test-PSICondition -InputObject @{ Note = @{ A = 1 } } -Condition (New-PSICondition -Property Note -Operator GreaterThan -Value 2 -Status Critical)) | Should -BeFalse
        }
    }

    It 'keeps malformed manually supplied regex from crashing evaluation' {
        InModuleScope PSInsightHTML {
            $Rule = [pscustomobject]@{ Property = 'Note'; Operator = 'Match'; Value = '['; Status = 'Warning'; Scope = 'Cell' }
            (Test-PSICondition -InputObject @{ Note = 'sample' } -Condition $Rule) | Should -BeFalse
        }
    }

    It 'uses the first matching cell condition without sorting severity' {
        $Report = New-PSIConditionTestReport
        $Conditions = @(
            New-PSICondition -Property Age -Operator GreaterThan -Value 60 -Status Warning
            New-PSICondition -Property Age -Operator GreaterThan -Value 180 -Status Critical
        )
        $Report | Add-PSITable -Title 'Ages' -Data @([pscustomobject]@{ Age = 202 }) -Conditions $Conditions | Out-Null
        $Html = Get-PSIConditionTestHtml -Report $Report
        $Html | Should -Match 'class="psi-numeric-cell psi-cell-status-warning">202</td>'
        $Html | Should -Not -Match 'class="psi-numeric-cell psi-cell-status-critical">202</td>'
    }

    It 'formats only the target cell and keeps independent property states' {
        $Report = New-PSIConditionTestReport
        $Data = @([pscustomobject]@{ Name = 'sample'; Age = 202; Flag = $true })
        $Conditions = @(
            New-PSICondition -Property Age -Operator GreaterThan -Value 180 -Status Critical
            New-PSICondition -Property Flag -Operator Equals -Value $true -Status Warning
        )
        $Report | Add-PSITable -Title 'Ages' -Data $Data -Columns @('Name', 'Age', 'Flag') -Conditions $Conditions | Out-Null
        $Html = Get-PSIConditionTestHtml -Report $Report
        $Html | Should -Match '<td>sample</td>'
        $Html | Should -Match 'class="psi-numeric-cell psi-cell-status-critical">202</td>'
        $Html | Should -Match 'class="psi-cell-status-warning">True</td>'
    }

    It 'applies a subtle row class separately from a cell class' {
        $Report = New-PSIConditionTestReport
        $Data = @([pscustomobject]@{ Name = 'sample'; Status = 'Critical'; Age = 202 })
        $Conditions = @(
            New-PSICondition -Property Status -Operator Equals -Value Critical -Status Warning -Scope Row
            New-PSICondition -Property Age -Operator GreaterThan -Value 180 -Status Critical
        )
        $Report | Add-PSITable -Title 'Ages' -Data $Data -Conditions $Conditions | Out-Null
        $Html = Get-PSIConditionTestHtml -Report $Report
        $Html | Should -Match '<tr data-psi-data-row class="psi-row-status-warning">'
        $Html | Should -Match 'class="psi-numeric-cell psi-cell-status-critical">202</td>'
        $Html | Should -Match 'psi-row-status-warning.*--psi-condition-color: var\(--psi-status-warning\)'
    }

    It 'retains automatic status badges and lets explicit rules override them' {
        $Report = New-PSIConditionTestReport
        $Data = @([pscustomobject]@{ Name = 'sample'; State = 'Critical' })
        $Report | Add-PSITable -Title 'Automatic' -Data $Data | Out-Null
        $Report | Add-PSITable -Title 'Explicit' -Data $Data -Conditions @((New-PSICondition -Property State -Operator Equals -Value Critical -Status Warning)) | Out-Null
        $Html = Get-PSIConditionTestHtml -Report $Report
        $TableSections = [regex]::Matches($Html, '<section class="psi-table-card"[^>]*>.*?</section>', 'Singleline')
        $Automatic = $TableSections[0].Value
        $Explicit = $TableSections[1].Value
        $Automatic | Should -Match 'psi-status-badge psi-status-critical">Critical</span>'
        $Explicit | Should -Match 'class="psi-cell-status-warning">Critical</td>'
        $Explicit | Should -Not -Match 'psi-status-badge psi-status-critical">Critical</span>'
    }

    It 'keeps omitted conditions and all table interactions unchanged' {
        $Report = New-PSIConditionTestReport
        $Data = @([pscustomobject]@{ Name = 'sample'; State = 'Healthy' })
        $Filter = Add-PSIFilter -Property State -Values @('Healthy', 'Critical')
        $Report | Add-PSITable -Title 'Unchanged' -Data $Data -Filters @($Filter) -PageSize 5 | Out-Null
        $Html = Get-PSIConditionTestHtml -Report $Report
        $Report.Sections[0].Rows[0].Components[0].Properties.Conditions.Count | Should -Be 0
        $Html | Should -Match '<tr data-psi-data-row>'
        $Html | Should -Match 'psi-status-badge psi-status-healthy">Healthy</span>'
        foreach ($Attribute in @('data-psi-search', 'data-psi-sort', 'data-psi-filter-property', 'data-psi-pagination', 'data-page-size="5"')) {
            $Html | Should -Match $Attribute
        }
    }

    It 'keeps CSV and XLSX exports tied to raw displayed cell values' {
        $Report = New-PSIConditionTestReport
        $Report | Add-PSITable -Title 'Export' -Data @([pscustomobject]@{ Name = 'sample'; Age = 202 }) `
            -Columns @('Name', 'Age') -Conditions @((New-PSICondition -Property Age -Operator GreaterThan -Value 180 -Status Critical)) | Out-Null
        $Html = Get-PSIConditionTestHtml -Report $Report
        $Html | Should -Match 'class="psi-numeric-cell psi-cell-status-critical">202</td>'
        $Html | Should -Not -Match '<td[^>]*>Critical</td>'
        $Html | Should -Match 'data-psi-export-format="csv"'
        $Html | Should -Match 'data-psi-export-format="xlsx"'
        $Html | Should -Match 'return !cell \|\| cell.classList.contains\(''psi-null-value''\) \? null : cell.textContent.trim\(\)'
        $Html | Should -Match 'toCsv\(context.records'
        $Html | Should -Match 'toXlsx\(context.records'
    }

    It 'HTML-encodes source data even when a condition matches' {
        $Report = New-PSIConditionTestReport
        $Report | Add-PSITable -Title 'Safe' -Data @([pscustomobject]@{ Note = '<script>alert(1)</script>' }) `
            -Conditions @((New-PSICondition -Property Note -Operator Contains -Value 'alert' -Status Critical)) | Out-Null
        $Html = Get-PSIConditionTestHtml -Report $Report
        $Html | Should -Match 'class="psi-cell-status-critical">&lt;script&gt;alert\(1\)&lt;/script&gt;</td>'
        $Html | Should -Not -Match '<script>alert\(1\)</script>'
        $Html | Should -Not -Match 'Invoke-Expression|\beval\('
    }
}
