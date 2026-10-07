$ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path $ModuleRoot 'PSInsightHTML.psd1') -Force

Describe 'PSInsightHTML generic export configuration and rendering' {
    BeforeAll {
        function New-PSIExportTestReport {
            $Report = New-PSIReport -Title 'Fictional services' -Theme Auto
            $Report | Add-PSISection -Title 'Inventory' | Add-PSIRow | Out-Null
            $Report
        }
        function Get-PSIExportTestHtml {
            param([pscustomobject] $Report, [bool] $EnableReportPrint = $true)
            $Path = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.html')
            try {
                Export-PSIReport -Report $Report -Path $Path -EnableReportPrint $EnableReportPrint | Out-Null
                [System.IO.File]::ReadAllText($Path)
            }
            finally { if (Test-Path $Path) { Remove-Item $Path -Force } }
        }
    }

    It 'restricts table export to visible, explicitly selected fields and preserves order and labels' {
        $Report = New-PSIExportTestReport
        $Report | Add-PSITable -Id 'services' -Title 'Services' -Data @([pscustomobject]@{ Name='Sample'; Status='Healthy'; Secret='private' }) `
            -Columns @('Name', 'Status') -ColumnLabels @{ Name='Service name' } -ExportColumns @('Status', 'Name') | Out-Null
        $Html = Get-PSIExportTestHtml -Report $Report
        $Match = [regex]::Match($Html, 'data-psi-export-config="([^"]+)"')
        $Match.Success | Should -BeTrue
        $Config = [System.Net.WebUtility]::HtmlDecode($Match.Groups[1].Value) | ConvertFrom-Json
        @($Config.columns) | Should -Be @('Status', 'Name')
        $Config.labels.Name | Should -Be 'Service name'
        $Html | Should -Not -Match 'private|Secret'
        { $Report | Add-PSITable -Title 'Bad' -Data @() -Columns @('Name') -ExportColumns @('Secret') } | Should -Throw '*visible table column*'
        { $Report | Add-PSITable -Title 'Bad' -Data @() -Columns @('Name') -ExportColumns @('Name', 'Name') } | Should -Throw '*unique*'
    }

    It 'supports configurable formats, disabled table export, and optional report printing' {
        $Report = New-PSIExportTestReport
        $Report | Add-PSITable -Id 'enabled' -Title 'Enabled' -Data @() -Columns @('Name') `
            -ExportFormats @('Csv', 'Print') -ExportFileName 'service summary' -WorksheetName 'Services' | Out-Null
        $Report | Add-PSITable -Id 'disabled' -Title 'Disabled' -Data @() -Columns @('Name') -EnableExport $false | Out-Null
        $Html = Get-PSIExportTestHtml -Report $Report -EnableReportPrint $false
        $Enabled = [regex]::Match($Html, '<section class="psi-table-card" id="enabled".*?</section>', 'Singleline').Value
        $Disabled = [regex]::Match($Html, '<section class="psi-table-card" id="disabled".*?</section>', 'Singleline').Value
        $Enabled | Should -Match 'data-psi-export-format="csv"'
        $Enabled | Should -Match 'data-psi-export-format="print"'
        $Enabled | Should -Not -Match 'data-psi-export-format="xlsx"'
        $Enabled | Should -Match 'service summary'
        $Disabled | Should -Not -Match 'data-psi-export-toolbar'
        $Html | Should -Not -Match '<div class="psi-export-toolbar" data-psi-export-toolbar data-psi-export-scope="report"'
        { $Report | Add-PSITable -Title 'Bad format' -Data @() -ExportFormats @('Xls') } | Should -Throw
    }

    It 'renders accessible table, evidence, and report toolbars with standalone print styling' {
        $Report = New-PSIExportTestReport
        $Report | Add-PSIInsight -Title 'Warnings' -Value 1 -Filter @{ Table='services'; Conditions=@() } `
            -EvidenceColumns @('Name', 'Status') -ExportColumns @('Name') | Out-Null
        $Report | Add-PSITable -Id 'services' -Title 'Services' -Data @([pscustomobject]@{ Name='Sample'; Status='Warning' }) -Columns @('Name','Status') | Out-Null
        $Html = Get-PSIExportTestHtml -Report $Report
        foreach ($Scope in @('table','evidence','report')) { $Html | Should -Match "data-psi-export-scope=`"$Scope`"" }
        $Html | Should -Match 'aria-haspopup="menu"'
        $Html | Should -Match 'aria-expanded="false"'
        $Html | Should -Match 'role="menuitem"'
        $Html | Should -Match 'data-psi-export-feedback role="status"'
        $Html | Should -Match '@media print'
        $Html | Should -Match 'window\.PSIExport\.attachToolbar'
        $Html | Should -Not -Match '<script\s+[^>]*src\s*=|<link\s+[^>]*href\s*=|<img\s+[^>]*src\s*=|fetch\('
        ([regex]::Matches($Html, 'data-psi-data-row>')).Count | Should -Be 1
    }

    It 'exports the full sorted result array and keeps evidence export tied to its active result set' {
        $Root = Split-Path $PSScriptRoot -Parent
        $Table = [System.IO.File]::ReadAllText((Join-Path $Root 'Assets/JavaScript/psi-table.js'))
        $Interaction = [System.IO.File]::ReadAllText((Join-Path $Root 'Assets/JavaScript/psi-interactions.js'))
        $Export = [System.IO.File]::ReadAllText((Join-Path $Root 'Assets/JavaScript/psi-export.js'))
        $Table | Should -Match 'widget\.__psiResults = filteredRecords'
        $Table | Should -Match 'records: widget\.__psiResults'
        $Interaction | Should -Match 'records: filteredRecords'
        $Export | Should -Match 'toCsv\(context\.records'
        $Export | Should -Match 'toXlsx\(context\.records'
        $Export | Should -Match 'No matching records to export'
        $Export | Should -Match '\[=\+\\-@\]'
        $Export | Should -Match 'function safeName\(value\)'
        $Export | Should -Match 'replace\(/\[\^A-Za-z0-9_-\]\+/g'
        $Export | Should -Match 'safeName\(report\) \+ ''_'' \+ safeName\(context\)'
        $Export | Should -Match 'event\.stopPropagation\(\)'
        $Export | Should -Match '0x04034b50'
        $Export | Should -Match '0x02014b50'
        $Export | Should -Match '0x06054b50'
    }
}
