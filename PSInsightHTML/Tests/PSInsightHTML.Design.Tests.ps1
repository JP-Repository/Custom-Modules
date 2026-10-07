$ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path $ModuleRoot 'PSInsightHTML.psd1') -Force

Describe 'PSInsightHTML visual structure' {
    BeforeAll {
        function Get-DesignHtml {
            param([pscustomobject] $Report)
            $Path = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.html')
            try {
                $null = Export-PSIReport -Report $Report -Path $Path
                [System.IO.File]::ReadAllText($Path)
            }
            finally {
                if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
            }
        }
    }

    It 'collapses three or more configured table filters while retaining every select' {
        $Report = New-PSIReport -Title 'Filters'
        $Filters = @('Status', 'Region', 'Type') | ForEach-Object {
            Add-PSIFilter -Property $_ -Values @('One', 'Two')
        }
        $Report | Add-PSISection -Title 'Records' | Add-PSIRow |
            Add-PSITable -Title 'Assets' -Data @([pscustomobject]@{ Status='One'; Region='Two'; Type='One' }) -Filters $Filters | Out-Null
        $Html = Get-DesignHtml -Report $Report
        $Html | Should -Match '<details class="psi-table-filter-disclosure"><summary>Filters \(3\)</summary>'
        $Html | Should -Match 'data-psi-filter-property="Status"'
        $Html | Should -Match 'data-psi-filter-property="Region"'
        $Html | Should -Match 'data-psi-filter-property="Type"'
        $Html | Should -Match 'data-psi-search'
        $Html | Should -Match 'data-psi-export-toolbar'
        $Html | Should -Match 'data-psi-active-filters'
    }

    It 'keeps one configured filter inline' {
        $Report = New-PSIReport -Title 'Inline filter'
        $Filter = Add-PSIFilter -Property 'Status' -Values @('Healthy', 'Warning')
        $Report | Add-PSISection -Title 'Records' | Add-PSIRow |
            Add-PSITable -Title 'Assets' -Data @([pscustomobject]@{ Status='Healthy' }) -Filters @($Filter) | Out-Null
        $Html = Get-DesignHtml -Report $Report
        $Html | Should -Match 'class="psi-table-filterbar psi-table-filterbar-inline"'
        $Html | Should -Not -Match '<details class="psi-table-filter-disclosure"'
    }

    It 'uses the same filter disclosure in the shared evidence dialog' {
        $Report = New-PSIReport -Title 'Evidence'
        $Rows = @([pscustomobject]@{ Name='Example'; Status='Warning' })
        $Report | Add-PSISection -Title 'Summary' | Add-PSIRow |
            Add-PSIKPI -Title 'Issues' -Value 1 -DrillDown $Rows | Out-Null
        $Html = Get-DesignHtml -Report $Report
        $Html | Should -Match 'class="psi-dialog-filter-disclosure"'
        $Html | Should -Match 'data-psi-dialog-filter-summary'
        $Html | Should -Match 'data-psi-dialog-filters'
    }

    It 'marks assessment navigation and section context without provider-specific CSS' {
        $Report = New-PSIReport -Title 'Assessment navigation'
        $Assessment = New-PSIAssessment -Id 'sample-service' -Name 'Sample service' -Provider 'Fictional'
        $Assessment | Add-PSISection -Title 'Summary' | Add-PSIRow | Add-PSIText -Text 'Example' | Out-Null
        $Report | Add-PSIAssessment -Assessment $Assessment | Add-PSIReportOverview | Out-Null
        $Html = Get-DesignHtml -Report $Report
        $Html | Should -Match 'data-psi-nav-assessment="overview"'
        $Html | Should -Match 'data-psi-nav-assessment="sample-service"'
        $Html | Should -Match 'data-psi-overview="true"'
        $Html | Should -Match 'data-psi-assessment-key="sample-service"'
        $Html | Should -Match 'aria-current.*location'
    }

    It 'embeds semantic theme, print, and focus styles without external stylesheets' {
        $Report = New-PSIReport -Title 'Theme' -Theme Auto
        $Report | Add-PSISection -Title 'Summary' | Add-PSIRow | Add-PSIText -Text 'Sample' | Out-Null
        $Html = Get-DesignHtml -Report $Report
        foreach ($Token in @('--psi-page', '--psi-surface-subtle', '--psi-surface-elevated', '--psi-border-strong', '--psi-focus')) {
            $Html | Should -Match ([regex]::Escape($Token))
        }
        $Html | Should -Match '\[data-theme="Dark"\]'
        $Html | Should -Match '@media print'
        $Html | Should -Match '\.psi-table-toolbar, \.psi-active-filter-row'
        $Html | Should -Match ':focus-visible'
        $Html | Should -Not -Match '<link\s+[^>]*href=|<script\s+[^>]*src='
    }
}
