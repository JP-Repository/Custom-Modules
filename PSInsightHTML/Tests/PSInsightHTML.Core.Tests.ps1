$ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path -Path $ModuleRoot -ChildPath 'PSInsightHTML.psd1') -Force

Describe 'PSInsightHTML core framework' {
    It 'accepts the Light, Dark, and Auto themes' {
        (New-PSIReport -Title 'Light report' -Theme Light).Theme | Should -Be 'Light'
        (New-PSIReport -Title 'Dark report' -Theme Dark).Theme | Should -Be 'Dark'
        (New-PSIReport -Title 'Auto report' -Theme Auto).Theme | Should -Be 'Auto'
    }

    It 'builds a generic report using the shared section, row, and text contracts' {
        $Report = New-PSIReport -Title 'Core test'
        $Result = $Report |
            Add-PSISection -Title 'Summary' |
            Add-PSIRow -Columns 12 |
            Add-PSIText -Text 'Fictional sample' -Size Large

        [object]::ReferenceEquals($Report, $Result) | Should -BeTrue
        $Report.Sections.Count | Should -Be 1
        $Report.Sections[0].Rows[0].Columns | Should -Be 12
        $Report.Sections[0].Rows[0].Components.Count | Should -Be 1
        $Report.Sections[0].Rows[0].Components[0].Type | Should -Be 'Text'
        $Report.Sections[0].Rows[0].Components[0].Properties.Size | Should -Be 'Large'
    }

    It 'exports self-contained HTML with theme tokens and encoded report content' {
        $Report = New-PSIReport -Title 'Core <script> test' -Subtitle 'Standalone & generic' -Theme Auto
        $Report |
            Add-PSISection -Title 'Overview & status' |
            Add-PSIRow |
            Add-PSIText -Text '<b>sample</b>' -Size Small

        $OutputPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([guid]::NewGuid().ToString() + '.html')
        try {
            $File = Export-PSIReport -Report $Report -Path $OutputPath
            $Html = Get-Content -LiteralPath $File.FullName -Raw

            $File.Exists | Should -BeTrue
            $Html | Should -Match '^<!DOCTYPE html>'
            $Html | Should -Match 'data-theme="Auto"'
            $Html | Should -Match '--psi-background'
            $Html | Should -Match 'prefers-color-scheme: dark'
            $Html | Should -Match '&lt;script&gt;'
            $Html | Should -Match '&lt;b&gt;sample&lt;/b&gt;'
            $Html | Should -Match 'Overview &amp; status'
            $Html | Should -Not -Match '<script\s+[^>]*src\s*=|<link\s+[^>]*href'
        }
        finally {
            if (Test-Path -LiteralPath $OutputPath) {
                Remove-Item -LiteralPath $OutputPath -Force
            }
        }
    }

    It 'renders section navigation, report metadata, and a framework footer' {
        $Report = New-PSIReport -Title 'Navigation test' -Theme Auto
        $Report | Add-PSISection -Title 'Summary' | Add-PSIRow | Add-PSIText -Text 'Sample'
        $Report | Add-PSISection -Title 'Details' | Add-PSIRow | Add-PSIText -Text 'More sample data'
        $OutputPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([guid]::NewGuid().ToString() + '.html')
        try {
            $null = Export-PSIReport -Report $Report -Path $OutputPath
            $Html = Get-Content -LiteralPath $OutputPath -Raw
            $Html | Should -Match '<nav class="psi-report-nav" aria-label="Report sections">'
            $Html | Should -Match 'href="#psi-section-0">Summary</a>'
            $Html | Should -Match 'href="#psi-section-1">Details</a>'
            $Html | Should -Match 'id="psi-section-0"'
            $Html | Should -Match 'id="psi-section-1"'
            $Html | Should -Match 'Module v0\.10\.0'
            $Html | Should -Match 'data-psi-theme-value>Auto</span>'
            $Html | Should -Match '<footer class="psi-footer">'
        }
        finally {
            if (Test-Path -LiteralPath $OutputPath) {
                Remove-Item -LiteralPath $OutputPath -Force
            }
        }
    }

    It 'exports only intended public commands and keeps helpers private' {
        $Commands = @(Get-Command -Module PSInsightHTML -CommandType Function | Select-Object -ExpandProperty Name | Sort-Object)
        $Commands -join ',' | Should -Be 'Add-PSIAlert,Add-PSIAssessment,Add-PSIChart,Add-PSIFilter,Add-PSIFinding,Add-PSIInsight,Add-PSIKeyValue,Add-PSIKPI,Add-PSIRecommendation,Add-PSIReportOverview,Add-PSIRow,Add-PSISection,Add-PSIStatus,Add-PSITable,Add-PSIText,Export-PSIReport,Get-PSIAssessmentSummary,Get-PSIFindingSummary,Get-PSIReportCatalog,Get-PSIReportSummary,New-PSIADDNSAssessment,New-PSIADGroupAssessment,New-PSIADGroupPolicyAssessment,New-PSIADReplicationAssessment,New-PSIADSitesSubnetsAssessment,New-PSIADUserInventory,New-PSIAssessment,New-PSICondition,New-PSIFinding,New-PSIReport'
        (Get-Command ConvertTo-PSIHtml -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
        (Get-Command New-PSIComponent -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
    }
}

Describe 'PSInsightHTML dashboard components' {
    It 'adds a KPI with generic values, status, display hints, and action metadata' {
        $Report = New-PSIReport -Title 'KPI contract'
        $Report | Add-PSISection -Title 'Summary' | Add-PSIRow | Add-PSIKPI `
            -Title 'Availability' -Value ([pscustomobject]@{ Percent = 99.9 }) `
            -Subtitle 'Rolling sample' -Status Healthy -Icon ([string] [char] 0x2197) -Trend '+0.1%' `
            -Action @{ Type = 'Filter'; Target = 'availability' }

        $Component = $Report.Sections[0].Rows[0].Components[0]
        $Component.Type | Should -Be 'KPI'
        $Component.Properties.Title | Should -Be 'Availability'
        $Component.Properties.Status | Should -Be 'Healthy'
        $Component.Properties.Trend | Should -Be '+0.1%'
        $Component.Properties.Action.Target | Should -Be 'availability'
    }

    It 'accepts the standardized status values for dashboard components' {
        $Statuses = @('Healthy', 'Warning', 'Critical', 'Info', 'Informational', 'Neutral', 'Unknown', 'NotChecked')
        foreach ($Status in $Statuses) {
            $Report = New-PSIReport -Title 'Status contract'
            $Report | Add-PSISection -Title 'Signals' | Add-PSIRow | Add-PSIStatus -Status $Status
            $ExpectedStatus = if ($Status -eq 'Info') { 'Informational' } else { $Status }
            $Report.Sections[0].Rows[0].Components[0].Properties.Status | Should -Be $ExpectedStatus
        }
    }

    It 'stores alert and recommendation content and optional metadata' {
        $Report = New-PSIReport -Title 'Action items'
        $Report | Add-PSISection -Title 'Operations' | Add-PSIRow |
            Add-PSIAlert -Status Critical -Title 'Elevated errors' -Message 'Fictional API errors increased.' `
                -Timestamp ([datetime]'2026-01-02T03:04:05Z') -Details @{ Count = 12 } -Action 'Review sample deployment.'
        $Report | Add-PSIRow |
            Add-PSIRecommendation -Status Warning -Title 'Increase capacity' `
                -Description 'The fictional queue has grown for several intervals.' -ActionText 'Review worker allocation.'

        $Alert = $Report.Sections[0].Rows[0].Components[0]
        $Recommendation = $Report.Sections[0].Rows[1].Components[0]
        $Alert.Type | Should -Be 'Alert'
        $Alert.Properties.Details.Count | Should -Be 12
        $Alert.Properties.Action | Should -Be 'Review sample deployment.'
        $Recommendation.Type | Should -Be 'Recommendation'
        $Recommendation.Properties.ActionText | Should -Be 'Review worker allocation.'
    }

    It 'renders all dashboard component types with theme tokens and encoded content' {
        $Report = New-PSIReport -Title 'Dashboard <sample>' -Theme Dark
        $Report | Add-PSISection -Title 'Summary' | Add-PSIRow |
            Add-PSIKPI -Title 'Requests' -Value 1200 -Status Healthy -Action @{ Target = 'requests' } |
            Add-PSIKPI -Title 'Errors' -Value 4 -Status Warning |
            Add-PSIStatus -Status Info -Label 'Queue' -Message 'Queue is <stable>.' |
            Add-PSIAlert -Status Critical -Title 'Threshold' -Message 'Rate > expected.' -Details @{ Rate = 4.2 } |
            Add-PSIRecommendation -Status Warning -Title 'Scale workers' -Description 'Review & adjust.' -ActionText 'Add capacity.'

        $OutputPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([guid]::NewGuid().ToString() + '.html')
        try {
            $null = Export-PSIReport -Report $Report -Path $OutputPath
            $Html = Get-Content -LiteralPath $OutputPath -Raw
            $Html | Should -Match 'data-theme="Dark"'
            $Html | Should -Match 'psi-kpi-card'
            $Html | Should -Match 'psi-status-panel'
            $Html | Should -Match 'psi-alert'
            $Html | Should -Match 'psi-recommendation'
            $Html | Should -Match 'data-action='
            $Html | Should -Match '&lt;sample&gt;'
            $Html | Should -Match 'Queue is &lt;stable&gt;\.'
            $Html | Should -Match 'Review &amp; adjust\.'
            $Html | Should -Match '--psi-status-critical'
            $Html | Should -Not -Match '<script\s+[^>]*src\s*=|<link\s+[^>]*href'
        }
        finally {
            if (Test-Path -LiteralPath $OutputPath) {
                Remove-Item -LiteralPath $OutputPath -Force
            }
        }
    }
}
