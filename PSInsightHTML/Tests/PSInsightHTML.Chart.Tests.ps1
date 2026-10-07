$ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path -Path $ModuleRoot -ChildPath 'PSInsightHTML.psd1') -Force

Describe 'PSInsightHTML generic chart component' {
    BeforeAll {
        function New-PSIChartTestReport {
            param(
                [string] $Theme = 'Light'
            )
            $Report = New-PSIReport -Title 'Chart component test' -Theme $Theme
            $Report | Add-PSISection -Title 'Charts' | Add-PSIRow | Out-Null
            $Report
        }

        function Get-PSIChartTestHtml {
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

    It 'imports Add-PSIChart and keeps the SVG renderer private' {
        (Get-Command Add-PSIChart -Module PSInsightHTML -ErrorAction Stop).Name | Should -Be 'Add-PSIChart'
        (Get-Command ConvertTo-PSIChartMarkup -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
    }

    It 'creates a chart component from generic object data and preserves the report reference' {
        $Report = New-PSIChartTestReport
        $Data = @(
            [pscustomobject]@{ Period = 'Morning'; Requests = 22 }
            [pscustomobject]@{ Period = 'Afternoon'; Requests = 31 }
        )
        $Result = $Report | Add-PSIChart -Title 'Sample requests' -ChartType Bar `
            -Data $Data -CategoryProperty Period -ValueProperty Requests

        [object]::ReferenceEquals($Report, $Result) | Should -BeTrue
        $Component = $Report.Sections[0].Rows[0].Components[0]
        $Component.Type | Should -Be 'Chart'
        $Component.Properties.Data.Count | Should -Be 2
        $Component.Properties.CategoryProperty | Should -Be 'Period'
        $Component.Properties.ValueProperty | Should -Be 'Requests'
    }

    It 'accepts every supported chart type' {
        foreach ($ChartType in @('Bar', 'Line', 'Doughnut', 'Pie')) {
            $Report = New-PSIChartTestReport
            $Report | Add-PSIChart -Title 'One type' -ChartType $ChartType `
                -Data @([pscustomobject]@{ Category = 'A'; Value = 2 }) `
                -CategoryProperty Category -ValueProperty Value
            $Report.Sections[0].Rows[0].Components[0].Properties.ChartType | Should -Be $ChartType
        }
    }

    It 'rejects unsupported chart types' {
        $Report = New-PSIChartTestReport
        {
            $Report | Add-PSIChart -Title 'Invalid chart' -ChartType Radar `
                -Data @() -CategoryProperty Category -ValueProperty Value
        } | Should -Throw
    }

    It 'preserves series and status properties for multi-series charts' {
        $Report = New-PSIChartTestReport
        $Data = @([pscustomobject]@{ Time = '09:00'; Metric = 'Requests'; Amount = 7; Health = 'Healthy' })
        $Report | Add-PSIChart -Title 'Series test' -ChartType Line -Data $Data `
            -CategoryProperty Time -ValueProperty Amount -SeriesProperty Metric -StatusProperty Health

        $Properties = $Report.Sections[0].Rows[0].Components[0].Properties
        $Properties.SeriesProperty | Should -Be 'Metric'
        $Properties.StatusProperty | Should -Be 'Health'
    }

    It 'adds accessible, keyboard-operable chart points that dispatch generic table filter metadata' {
        $Report = New-PSIChartTestReport
        $Data = @(
            [pscustomobject]@{ Status = 'Healthy'; Count = 4 }
            [pscustomobject]@{ Status = 'Warning'; Count = 2 }
        )
        $Report | Add-PSIChart -Title 'Filterable status' -ChartType Bar -Data $Data `
            -CategoryProperty Status -ValueProperty Count `
            -FilterMetadata @{ Table = 'inventory'; Property = 'Health'; ValueProperty = 'Status' }

        $Html = Get-PSIChartTestHtml -Report $Report
        $Html | Should -Match 'class="psi-chart-filter-point" role="button" tabindex="0"'
        $Html | Should -Match 'aria-label="Filter table by Health: Healthy"'
        $Html | Should -Match 'data-psi-chart-filter="\{&quot;'
        $Html | Should -Match '&quot;tableId&quot;:&quot;inventory&quot;'
        $Html | Should -Match "source: 'chart'"
        $Html | Should -Match 'psi:apply-filter'
        $Html | Should -Match "event.key === 'Enter' \|\| event.key === ' '"
    }

    It 'leaves conflicting category-to-filter mappings non-interactive' {
        $Report = New-PSIChartTestReport
        $Data = @(
            [pscustomobject]@{ Category = 'Same'; Region = 'East'; Count = 2 }
            [pscustomobject]@{ Category = 'Same'; Region = 'West'; Count = 3 }
        )
        $Report | Add-PSIChart -Title 'Ambiguous mapping' -ChartType Bar -Data $Data `
            -CategoryProperty Category -ValueProperty Count `
            -FilterMetadata @{ Table = 'inventory'; Property = 'Region'; ValueProperty = 'Region' }

        $Html = Get-PSIChartTestHtml -Report $Report
        $Html | Should -Not -Match 'data-psi-chart-filter='
    }

    It 'validates filter metadata while keeping it optional' {
        $Report = New-PSIChartTestReport
        { $Report | Add-PSIChart -Title 'Missing target' -ChartType Bar -Data @() `
                -CategoryProperty Category -ValueProperty Value -FilterMetadata @{ Property = 'Status' } } | Should -Throw '*Table*'
    }

    It 'renders the empty-data message without requiring a JavaScript chart library' {
        $Report = New-PSIChartTestReport
        $Report | Add-PSIChart -Title 'Empty chart' -ChartType Pie -Data @() `
            -CategoryProperty Category -ValueProperty Value -EmptyMessage 'No sample values.'

        $Html = Get-PSIChartTestHtml -Report $Report
        $Html | Should -Match 'data-chart-type="Pie"'
        $Html | Should -Match '<svg'
        $Html | Should -Match 'No sample values\.'
        $Html | Should -Not -Match '<script\s+[^>]*src\s*=|Chart\.js|cdn\.'
    }

    It 'handles null values as gaps and reports omitted points' {
        $Report = New-PSIChartTestReport
        $Data = @(
            [pscustomobject]@{ Time = '09:00'; Value = 14 }
            [pscustomobject]@{ Time = '09:15'; Value = $null }
            [pscustomobject]@{ Time = '09:30'; Value = 18 }
        )
        $Report | Add-PSIChart -Title 'Null values' -ChartType Line -Data $Data `
            -CategoryProperty Time -ValueProperty Value

        $Html = Get-PSIChartTestHtml -Report $Report
        $Html | Should -Match '2 points; 1 null values omitted'
        $Html | Should -Match '09:15'
    }

    It 'renders status-aware slices with theme tokens in dark theme' {
        $Report = New-PSIChartTestReport -Theme Dark
        $Data = @(
            [pscustomobject]@{ Status = 'Healthy'; Count = 8 }
            [pscustomobject]@{ Status = 'Warning'; Count = 3 }
            [pscustomobject]@{ Status = 'Critical'; Count = 1 }
        )
        $Report | Add-PSIChart -Title 'Status distribution' -ChartType Doughnut `
            -Data $Data -CategoryProperty Status -ValueProperty Count -ShowLabels $true

        $Html = Get-PSIChartTestHtml -Report $Report
        $Html | Should -Match 'data-theme="Dark"'
        $Html | Should -Match 'fill="var\(--psi-status-healthy\)"'
        $Html | Should -Match 'fill="var\(--psi-status-warning\)"'
        $Html | Should -Match 'fill="var\(--psi-status-critical\)"'
        $Html | Should -Match '--psi-chart-1'
    }

    It 'HTML-encodes chart labels, titles, and data' {
        $Report = New-PSIChartTestReport
        $Data = @([pscustomobject]@{ Category = '<script>'; Value = 4 })
        $Report | Add-PSIChart -Title 'Chart <name>' -ChartType Bar -Data $Data `
            -CategoryProperty Category -ValueProperty Value

        $Html = Get-PSIChartTestHtml -Report $Report
        $Html | Should -Match 'Chart &lt;name&gt;'
        $Html | Should -Match '&lt;script&gt;'
        $Html | Should -Not -Match '<script\s+[^>]*src\s*=|Chart\.js|cdn\.'
    }

    It 'renders line, bar, pie, and doughnut SVG elements with no external dependencies' {
        $Report = New-PSIChartTestReport
        $Data = @([pscustomobject]@{ Category = 'Sample'; Value = 5 })
        foreach ($ChartType in @('Bar', 'Line', 'Pie', 'Doughnut')) {
            $Report | Add-PSIChart -Title $ChartType -ChartType $ChartType -Data $Data `
                -CategoryProperty Category -ValueProperty Value -Width 720 -Height 280
        }

        $Html = Get-PSIChartTestHtml -Report $Report
        foreach ($ChartType in @('Bar', 'Line', 'Pie', 'Doughnut')) {
            $Html | Should -Match "data-chart-type=`"$ChartType`""
        }
        $Html | Should -Not -Match '<script[^>]+src=|<link\s+[^>]*href|https://cdn\.'
    }
}
