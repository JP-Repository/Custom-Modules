$script:PSInsightHTMLProjectRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path -Path $script:PSInsightHTMLProjectRoot -ChildPath 'PSInsightHTML.psd1') -Force

Describe 'PSInsightHTML generic filter engine' {
    BeforeAll {
        function New-PSIFilterTestReport {
            param(
                [Parameter()]
                [string] $Theme = 'Light'
            )
            $Data = @(
                [pscustomobject]@{ Name = 'node-east-01'; Region = 'East'; Status = 'Healthy'; Notes = 'Nominal' }
                [pscustomobject]@{ Name = 'node-east-02'; Region = 'East'; Status = 'Warning'; Notes = 'Queue elevated' }
                [pscustomobject]@{ Name = 'node-central-01'; Region = 'Central'; Status = 'Critical'; Notes = 'Sample failure' }
            )
            $Filters = @(
                (Add-PSIFilter -Property Status -Values @('Healthy', 'Warning', 'Critical'))
                (Add-PSIFilter -Property Region -Values @('East', 'Central') -Type Select)
            )
            $Report = New-PSIReport -Title 'Generic filter report' -Theme $Theme
            $null = $Report | Add-PSISection -Title 'Inventory' | Add-PSIRow |
                Add-PSITable -Id 'filter-test-table' -Title 'Generic records' -Data $Data -Filters $Filters -PageSize 1 -EnableSearch $true
            $Report
        }

        function Get-PSIFilterTestHtml {
            param([Parameter(Mandatory = $true)][pscustomobject] $Report)
            $Path = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([guid]::NewGuid().ToString() + '.html')
            try {
                $null = Export-PSIReport -Report $Report -Path $Path
                [System.IO.File]::ReadAllText($Path)
            }
            finally {
                if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
            }
        }
    }

    It 'creates generic select and multi-select filter definitions' {
        $SelectFilter = Add-PSIFilter -Property 'Environment' -Values @('Production', 'Staging') -Label 'Environment'
        $MultiFilter = Add-PSIFilter -Property 'Owner' -Values @('Platform', 'Data') -Type MultiSelect

        $SelectFilter.Property | Should -Be 'Environment'
        $SelectFilter.Label | Should -Be 'Environment'
        $SelectFilter.Type | Should -Be 'Select'
        ($SelectFilter.Values -join ',') | Should -Be 'Production,Staging'
        $MultiFilter.Type | Should -Be 'MultiSelect'
        $MultiFilter.Label | Should -Be 'Owner'
        { Add-PSIFilter -Property 'Status' -Values @() } | Should -Throw
        { Add-PSIFilter -Property 'Status' -Values @('Healthy', 'healthy') } | Should -Throw
    }

    It 'renders labelled filter controls, values, active-filter area, and clear-all affordance' {
        $Html = Get-PSIFilterTestHtml -Report (New-PSIFilterTestReport)
        $Html | Should -Match 'data-psi-filterbar'
        $Html | Should -Match 'data-psi-filter-property="Status"'
        $Html | Should -Match 'data-psi-filter-property="Region"'
        $Html | Should -Match '<option value="Warning">Warning</option>'
        $Html | Should -Match '<option value="" selected>All</option>'
        $Html | Should -Match 'Search'
        $Html | Should -Match 'data-psi-active-filters aria-live="polite"'
        $Html | Should -Match 'data-psi-clear-filters hidden'
        $Html | Should -Match 'data-psi-result-count aria-live="polite">3 results'
    }

    It 'supports native multi-select controls and individual filter chips' {
        $Report = New-PSIFilterTestReport
        $Report | Add-PSIRow | Add-PSITable -Id 'multi-table' -Title 'Owners' `
            -Data @([pscustomobject]@{ Owner = 'Platform' }) `
            -Filters @((Add-PSIFilter -Property Owner -Values @('Platform', 'Data') -Type MultiSelect)) | Out-Null
        $Html = Get-PSIFilterTestHtml -Report $Report
        $Html | Should -Match 'multiple aria-describedby="psi-filter-help-multi-table-filter-0"'
        $Html | Should -Match 'Use the selection list to choose one or more values\.'
        $Html | Should -Match 'psi-filter-chip'
        $Html | Should -Match 'Remove .* filter '
    }

    It 'applies all selected property filters and search before sorting and pagination' {
        $Script = [System.IO.File]::ReadAllText((Join-Path -Path (Get-Location).Path -ChildPath 'Assets/JavaScript/psi-table.js'))
        $Script | Should -Match 'uiConditions\.every'
        $Script | Should -Match 'externalConditions'
        $Script | Should -Match 'window\.PSIDataEngine\.matches'
        $FilterIndex = $Script.IndexOf('var filteredRecords = records.filter')
        $CountIndex = $Script.IndexOf('var total = filteredRows.length')
        $PageIndex = $Script.IndexOf('var pageCount = paginationEnabled')
        ($FilterIndex -ge 0 -and $FilterIndex -lt $CountIndex -and $CountIndex -lt $PageIndex) | Should -BeTrue
        $Script | Should -Match "Showing ' \+ \(start \+ 1\)"
    }

    It 'clears a single selection, clears all controls and search, and updates live counts' {
        $Script = [System.IO.File]::ReadAllText((Join-Path -Path (Get-Location).Path -ChildPath 'Assets/JavaScript/psi-table.js'))
        $Script | Should -Match 'data-psi-clear-filters'
        $Script | Should -Match "searchInput\.value = ''"
        $Script | Should -Match "chip\.addEventListener\('click'"
        $Script | Should -Match 'resultCount\.textContent'
        $Script | Should -Match 'activeFilterList\.appendChild\(chip\)'
    }

    It 'connects generic KPI filter actions to the shared table-filter event and retains drill-down' {
        $Report = New-PSIFilterTestReport
        $Records = @([pscustomobject]@{ Name = 'Investigate this record'; Region = 'East'; Status = 'Warning' })
        $Report | Add-PSIRow | Add-PSIKPI -Title 'Warnings' -Value 1 -Status Warning `
            -Filter @{ Table = 'filter-test-table'; Property = 'Status'; Value = 'Warning' } -DrillDown $Records | Out-Null
        $Html = Get-PSIFilterTestHtml -Report $Report
        $Html | Should -Match 'data-psi-filter-action=".*filter-test-table'
        $Html | Should -Match 'data-psi-drilldown'
        $Html | Should -Match 'psi:apply-filter'
        $Html | Should -Match 'document\.dispatchEvent\(new CustomEvent'
        $Html | Should -Match 'tableId: action\.tableId \|\| action\.Table'
        $Html | Should -Match 'data-psi-dialog-backdrop'
    }

    It 'renders filter controls with the existing Light, Dark, and Auto theme tokens' {
        foreach ($Theme in @('Light', 'Dark', 'Auto')) {
            $Html = Get-PSIFilterTestHtml -Report (New-PSIFilterTestReport -Theme $Theme)
            $Html | Should -Match "data-theme=`"$Theme`""
            $Html | Should -Match 'psi-filter-control select'
            $Html | Should -Match 'var\(--psi-surface\)'
            $Html | Should -Match 'prefers-color-scheme: dark'
        }
    }

    It 'generates the full demo and derives controller counts and filters from its data' {
        $DemoPath = Join-Path -Path (Get-Location).Path -ChildPath 'Examples/New-DemoReport.ps1'
        $OutputPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([guid]::NewGuid().ToString() + '.html')
        try {
            & $DemoPath -NoBrowser -OutputPath $OutputPath | Out-Null
            $Html = [System.IO.File]::ReadAllText($OutputPath)
            $InventoryMarkup = [regex]::Match($Html, '<section class="psi-table-card" id="controller-inventory".*?</section>', [System.Text.RegularExpressions.RegexOptions]::Singleline).Value
            $Rows = [regex]::Matches($InventoryMarkup, '<tr data-psi-data-row>')
            $Rows.Count | Should -Be 57
            ([regex]::Matches($InventoryMarkup, '<span class="psi-status-badge psi-status-healthy">Healthy</span>')).Count | Should -Be 49
            ([regex]::Matches($InventoryMarkup, '<span class="psi-status-badge psi-status-warning">Warning</span>')).Count | Should -Be 5
            ([regex]::Matches($InventoryMarkup, '<span class="psi-status-badge psi-status-unknown">Unknown</span>')).Count | Should -Be 3
            $Html | Should -Match 'data-psi-filter-property="Status"'
            $Html | Should -Match 'data-psi-filter-property="Site"'
            $Html | Should -Match 'data-psi-clear-filters'
            $Html | Should -Match 'data-psi-filter-action'
            $Html | Should -Match 'data-psi-records='
            $Html | Should -Match 'Controller Status Distribution'
            $Html | Should -Match 'Controllers by Site'
            $Html | Should -Match 'Filter table by Status: Warning'
            $Html | Should -Match 'Filter table by Site: North'
            $Html | Should -Match '&quot;tableId&quot;:&quot;controller-inventory&quot;'
            $Html | Should -Match 'data-chart-type="Bar"'
            $Html | Should -Match 'data-chart-type="Line"'
            $Html | Should -Match 'data-chart-type="Doughnut"'
            $Html | Should -Match 'data-chart-type="Pie"'
            $Html | Should -Not -Match '<script\s+[^>]*src\s*=|<link\s+[^>]*href\s*='
        }
        finally {
            if (Test-Path -LiteralPath $OutputPath) { Remove-Item -LiteralPath $OutputPath -Force }
        }
    }
}
