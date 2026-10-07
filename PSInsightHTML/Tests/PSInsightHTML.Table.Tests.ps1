$ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path -Path $ModuleRoot -ChildPath 'PSInsightHTML.psd1') -Force

Describe 'PSInsightHTML generic table component' {
    BeforeAll {
        function New-PSITableTestReport {
            $Report = New-PSIReport -Title 'Generic table test'
            $Report | Add-PSISection -Title 'Table tests' | Add-PSIRow | Out-Null
            $Report
        }

        function Get-PSITableTestHtml {
            param(
                [Parameter(Mandatory = $true)]
                [pscustomobject] $Report
            )

            $OutputPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([guid]::NewGuid().ToString() + '.html')
            try {
                $null = Export-PSIReport -Report $Report -Path $OutputPath
                [System.IO.File]::ReadAllText($OutputPath)
            }
            finally {
                if (Test-Path -LiteralPath $OutputPath) {
                    Remove-Item -LiteralPath $OutputPath -Force
                }
            }
        }
    }

    It 'imports the public table command and does not expose its renderer helper' {
        (Get-Command Add-PSITable -Module PSInsightHTML -ErrorAction Stop).Name | Should -Be 'Add-PSITable'
        (Get-Command Get-PSITableValue -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
    }

    It 'adds a table component to the current report row' {
        $Report = New-PSITableTestReport
        $Rows = @([pscustomobject]@{ Name = 'Sample service'; Status = 'Healthy' })
        $Result = $Report | Add-PSITable -Title 'Services' -Data $Rows

        [object]::ReferenceEquals($Report, $Result) | Should -BeTrue
        $Component = $Report.Sections[0].Rows[0].Components[0]
        $Component.Type | Should -Be 'Table'
        $Component.Properties.Title | Should -Be 'Services'
        $Component.Properties.Data.Count | Should -Be 1
    }

    It 'discovers a stable union of generic object columns automatically' {
        $Report = New-PSITableTestReport
        $Rows = @(
            [pscustomobject]@{ Name = 'One'; Status = 'Healthy' }
            [pscustomobject]@{ Name = 'Two'; Owner = 'Sample team' }
        )
        $Report | Add-PSITable -Title 'Automatic columns' -Data $Rows

        ($Report.Sections[0].Rows[0].Components[0].Properties.Columns -join ',') | Should -Be 'Name,Status,Owner'
    }

    It 'preserves explicit column selection and order and stores friendly labels' {
        $Report = New-PSITableTestReport
        $Rows = @([pscustomobject]@{ Name = 'One'; Status = 'Warning'; Owner = 'Sample team' })
        $Report | Add-PSITable -Title 'Selected columns' -Data $Rows `
            -Columns @('Status', 'Name') -ColumnLabels @{ Status = 'Health'; Name = 'Service name' }

        $Component = $Report.Sections[0].Rows[0].Components[0]
        ($Component.Properties.Columns -join ',') | Should -Be 'Status,Name'
        $Component.Properties.ColumnLabels.Status | Should -Be 'Health'
        $Html = Get-PSITableTestHtml -Report $Report
        $Html | Should -Match '>Health<'
        $Html | Should -Match '>Service name<'
    }

    It 'supports an empty dataset and renders the empty state' {
        $Report = New-PSITableTestReport
        $Report | Add-PSITable -Title 'No data' -Data @() -EmptyMessage 'Nothing to show.'

        $Component = $Report.Sections[0].Rows[0].Components[0]
        $Component.Properties.Data.Count | Should -Be 0
        $Component.Properties.Columns.Count | Should -Be 0
        (Get-PSITableTestHtml -Report $Report) | Should -Match 'Nothing to show\.'
    }

    It 'renders missing and null cells using the configured null text' {
        $Report = New-PSITableTestReport
        $Rows = @(
            [pscustomobject]@{ Name = 'Null owner'; Owner = $null }
            [pscustomobject]@{ Name = 'Missing owner' }
        )
        $Report | Add-PSITable -Title 'Null handling' -Data $Rows -Columns @('Name', 'Owner') -NullValueText 'Not supplied'

        $Html = Get-PSITableTestHtml -Report $Report
        ([regex]::Matches($Html, 'Not supplied')).Count | Should -Be 2
    }

    It 'HTML-encodes values and friendly column labels' {
        $Report = New-PSITableTestReport
        $Rows = @([pscustomobject]@{ Name = '<script>alert(1)</script>'; Notes = '<img src=x>' })
        $Report | Add-PSITable -Title 'Encoding' -Data $Rows `
            -Columns @('Name', 'Notes') -ColumnLabels @{ Name = '<b>Name</b>' }

        $Html = Get-PSITableTestHtml -Report $Report
        $Html | Should -Match '&lt;script&gt;alert\(1\)&lt;/script&gt;'
        $Html | Should -Match '&lt;img src=x&gt;'
        $Html | Should -Match '&lt;b&gt;Name&lt;/b&gt;'
        $Html | Should -Not -Match '<script>alert|<img'
    }

    It 'renders standardized status values as themed status badges' {
        $Report = New-PSITableTestReport
        $Rows = @(
            [pscustomobject]@{ Name = 'A'; Status = 'Healthy' }
            [pscustomobject]@{ Name = 'B'; Status = 'Warning' }
            [pscustomobject]@{ Name = 'C'; Status = 'Critical' }
        )
        $Report | Add-PSITable -Title 'Status values' -Data $Rows -Columns @('Name', 'Status')

        $Html = Get-PSITableTestHtml -Report $Report
        $Html | Should -Match 'psi-status-healthy'
        $Html | Should -Match 'psi-status-warning'
        $Html | Should -Match 'psi-status-critical'
        $Html | Should -Match '--psi-status-critical'
    }

    It 'stores the configured pagination page size and enablement setting' {
        $Report = New-PSITableTestReport
        $Report | Add-PSITable -Title 'Page size' -Data @() -PageSize 7 -EnablePagination $true

        $Component = $Report.Sections[0].Rows[0].Components[0]
        $Component.Properties.PageSize | Should -Be 7
        $Component.Properties.EnablePagination | Should -BeTrue
        (Get-PSITableTestHtml -Report $Report) | Should -Match 'data-page-size="7"'
    }

    It 'stores and renders search configuration' {
        $Report = New-PSITableTestReport
        $Report | Add-PSITable -Title 'Search enabled' -Data @() -EnableSearch $true
        $Report | Add-PSITable -Title 'Search disabled' -Data @() -EnableSearch $false

        $Components = $Report.Sections[0].Rows[0].Components
        $Components[0].Properties.EnableSearch | Should -BeTrue
        $Components[1].Properties.EnableSearch | Should -BeFalse
        $Html = Get-PSITableTestHtml -Report $Report
        $Html | Should -Match 'Search this table'
        $Html | Should -Match 'data-search-enabled="false"'
    }

    It 'stores and renders sorting configuration' {
        $Report = New-PSITableTestReport
        $Rows = @([pscustomobject]@{ Name = 'Sample' })
        $Report | Add-PSITable -Title 'Sorting enabled' -Data $Rows -EnableSorting $true
        $Report | Add-PSITable -Title 'Sorting disabled' -Data $Rows -EnableSorting $false

        $Components = $Report.Sections[0].Rows[0].Components
        $Components[0].Properties.EnableSorting | Should -BeTrue
        $Components[1].Properties.EnableSorting | Should -BeFalse
        $Html = Get-PSITableTestHtml -Report $Report
        $Html | Should -Match 'data-sort-enabled="false"'
        $Html | Should -Match 'data-psi-sort='
    }

    It 'embeds table search, sorting, and pagination behavior without external scripts' {
        $Report = New-PSITableTestReport
        $Report | Add-PSITable -Title 'Interactive' -Data @([pscustomobject]@{ Name = 'Sample' })
        $Html = Get-PSITableTestHtml -Report $Report

        $Html | Should -Match '<script>'
        $Html | Should -Match 'addEventListener\(''input'''
        $Html | Should -Match 'localeCompare'
        $Html | Should -Match 'body\.appendChild\(row\)'
        $Html | Should -Match 'data-psi-previous'
        $Html | Should -Not -Match '<script[^>]+src=|<link\s+[^>]*href'
    }
}
