$ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path $ModuleRoot 'PSInsightHTML.psd1') -Force

Describe 'PSInsightHTML Fluent renderer' {
    BeforeAll {
        $script:FluentReport = New-PSIReport -Title 'Fluent <sample>' -Theme Auto -Layout Application
        $script:FluentReport | Add-PSIView -Id overview -Title Overview -Initial | Out-Null
        $script:FluentReport | Add-PSISection -Title Summary | Add-PSIRow |
            Add-PSIKPI -Title Healthy -Value 1 -Status Healthy -Filter @{ Table = 'services'; Property = 'Status'; Value = 'Healthy' } | Out-Null
        $script:FluentReport | Add-PSIRow |
            Add-PSIInsight -Title Warnings -Value 1 -Status Warning -Filter @{ Table = 'services'; Conditions = @(@{ Property = 'Status'; Operator = 'Equals'; Value = 'Warning' }) } | Out-Null
        $script:FluentReport | Add-PSIRow |
            Add-PSIChart -Title Distribution -ChartType Bar -Data @([pscustomobject]@{ Status = 'Healthy'; Count = 1 }) -CategoryProperty Status -ValueProperty Count | Out-Null
        $script:FluentReport | Add-PSIRow |
            Add-PSITable -Id services -Title Services -Data @(
                [pscustomobject]@{ Name = 'Sample one'; Status = 'Healthy' },
                [pscustomobject]@{ Name = '<img src=x onerror=alert(1)>'; Status = 'Warning' }
            ) -Columns @('Name', 'Status') -Filters @(Add-PSIFilter -Property Status -Values @('Healthy', 'Warning')) -PageSize 1 | Out-Null
        $script:FluentReport | Add-PSIView -Id details -Title Details | Out-Null
        $script:FluentReport | Add-PSISection -Title Notes | Add-PSIRow | Add-PSIText -Text 'Fictional & offline' | Out-Null
        $script:FluentPath = Join-Path $TestDrive 'Fluent.html'
        Export-PSIReport -Report $script:FluentReport -Path $script:FluentPath -Renderer Fluent | Out-Null
        $script:FluentHtml = [System.IO.File]::ReadAllText($script:FluentPath)
        $Match = [regex]::Match($script:FluentHtml, '(?s)<script type="application/json" id="pf-data">(.*?)</script>')
        if (-not $Match.Success) { throw 'Fluent model was not embedded.' }
        $script:FluentModel = $Match.Groups[1].Value | ConvertFrom-Json
    }

    It 'embeds an offline application shell, themes and print styles' {
        $script:FluentHtml | Should -Match '^<!DOCTYPE html>'
        $script:FluentHtml | Should -Match 'data-theme="Auto"'
        $script:FluentHtml | Should -Match 'id="pf-rail" aria-label="Report navigation"'
        $script:FluentHtml | Should -Match 'id="pf-palette"'
        $script:FluentHtml | Should -Match 'id="pf-pane"'
        $script:FluentHtml | Should -Match 'prefers-color-scheme: dark'
        $script:FluentHtml | Should -Match '--pf-canvas: #e9eef4;'
        $script:FluentHtml | Should -Match '--pf-surface: #f8fafc;'
        $script:FluentHtml | Should -Match '@media print'
        $Document = [regex]::Replace($script:FluentHtml, '(?s)<script\b[^>]*>.*?</script>', '')
        $Document | Should -Not -Match '<script\s+[^>]*src\s*=|<link\s+[^>]*href\s*=|<img\s+[^>]*src\s*='
    }

    It 'projects navigation and generic components without placeholders' {
        @($script:FluentModel.pages).Count | Should -Be 2
        @($script:FluentModel.meta.unsupported).Count | Should -Be 0
        $Types = @($script:FluentModel.sections | ForEach-Object { $_.rows } | ForEach-Object { $_.items } | ForEach-Object { $_.t })
        foreach ($Expected in @('KPI', 'Insight', 'Chart', 'Table', 'Text')) { $Types | Should -Contain $Expected }
        $Types | Should -Not -Contain 'Unsupported'
    }

    It 'preserves table rows, filters, page size and evidence references' {
        $Items = @($script:FluentModel.sections | ForEach-Object { $_.rows } | ForEach-Object { $_.items })
        $Table = @($Items | Where-Object { $_.t -eq 'Table' })[0]
        @($Table.rows).Count | Should -Be 2
        $Table.rows[0][0] | Should -Be 'Sample one'
        $Table.rows[1][0] | Should -Be '<img src=x onerror=alert(1)>'
        @($Table.filters).Count | Should -Be 1
        $Table.pageSize | Should -Be 1
        $Insight = @($Items | Where-Object { $_.t -eq 'Insight' })[0]
        $Insight.evidence.table | Should -Be 'services'
        $Document = [regex]::Replace($script:FluentHtml, '(?s)<script\b[^>]*>.*?</script>', '')
        $Document | Should -Not -Match '<img src=x onerror=alert\(1\)>'
    }

    It 'selects Fluent through Auto or a preference and retains explicit Classic' {
        $Previous = [Environment]::GetEnvironmentVariable('PSINSIGHTHTML_RENDERER')
        try {
            [Environment]::SetEnvironmentVariable('PSINSIGHTHTML_RENDERER', 'Fluent')
            $Path = Join-Path $TestDrive 'Selected.html'
            Export-PSIReport -Report $script:FluentReport -Path $Path | Out-Null
            ([System.IO.File]::ReadAllText($Path)) | Should -Match 'id="pf-app"'
            [Environment]::SetEnvironmentVariable('PSINSIGHTHTML_RENDERER', $null)
            Export-PSIReport -Report $script:FluentReport -Path $Path -Renderer Auto | Out-Null
            ([System.IO.File]::ReadAllText($Path)) | Should -Match 'id="pf-app"'
            Export-PSIReport -Report $script:FluentReport -Path $Path -Renderer Classic | Out-Null
            ([System.IO.File]::ReadAllText($Path)) | Should -Not -Match 'id="pf-app"'
        }
        finally { [Environment]::SetEnvironmentVariable('PSINSIGHTHTML_RENDERER', $Previous) }
    }

    It 'supports Light, Dark and Auto initial themes' {
        foreach ($Theme in @('Light', 'Dark', 'Auto')) {
            $script:FluentReport.Theme = $Theme
            $Path = Join-Path $TestDrive ($Theme + '.html')
            Export-PSIReport -Report $script:FluentReport -Path $Path -Renderer Fluent | Out-Null
            ([System.IO.File]::ReadAllText($Path)) | Should -Match ('data-theme="' + $Theme + '"')
        }
        $script:FluentReport.Theme = 'Auto'
    }
}
