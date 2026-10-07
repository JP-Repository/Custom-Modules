$ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path -Path $ModuleRoot -ChildPath 'PSInsightHTML.psd1') -Force

Describe 'PSInsightHTML v1 status and action contracts' {
    BeforeAll {
        function New-PSIContractReport {
            $Report = New-PSIReport -Title 'Contract test' -Theme Auto
            $Report | Add-PSISection -Title 'Signals' | Add-PSIRow | Out-Null
            return $Report
        }

        function Get-PSIContractHtml {
            param([pscustomobject] $Report)
            $Path = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([guid]::NewGuid().ToString() + '.html')
            try {
                $null = Export-PSIReport -Report $Report -Path $Path
                return [System.IO.File]::ReadAllText($Path)
            }
            finally {
                if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
            }
        }
    }

    It 'normalizes casing and the Info alias using the private shared helper' {
        InModuleScope PSInsightHTML {
            (Resolve-PSIStatus -Status ' info ') | Should -Be 'Informational'
            (Resolve-PSIStatus -Status 'nEuTrAl') | Should -Be 'Neutral'
            (Resolve-PSIStatus -Status 'notchecked') | Should -Be 'NotChecked'
            { Resolve-PSIStatus -Status 'Danger' -ErrorAction Stop } | Should -Throw '*Unsupported PSInsightHTML status*'
            (Resolve-PSIStatus -Status 'Danger' -AllowInvalid) | Should -BeNullOrEmpty
        }
        (Get-Command Resolve-PSIStatus -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
    }

    It 'accepts every canonical status and persists the canonical value' {
        foreach ($Status in @('Healthy', 'Warning', 'Critical', 'Informational', 'Neutral', 'Unknown', 'NotChecked')) {
            $Report = New-PSIContractReport
            $Report | Add-PSIStatus -Status $Status | Out-Null
            $Report.Sections[0].Rows[0].Components[0].Properties.Status | Should -Be $Status
        }
    }

    It 'normalizes Info in KPI, Alert, Recommendation, and Insight properties' {
        $Report = New-PSIContractReport
        $Report | Add-PSIKPI -Title 'Sample' -Value 1 -Status Info | Out-Null
        $Report | Add-PSIAlert -Title 'Sample alert' -Message 'Sample' -Status Info | Out-Null
        $Report | Add-PSIRecommendation -Title 'Sample recommendation' -Description 'Sample' -Status Info | Out-Null
        $Report | Add-PSIInsight -Title 'Sample insight' -Value 1 -Status Info | Out-Null
        foreach ($Component in $Report.Sections[0].Rows[0].Components) {
            $Component.Properties.Status | Should -Be 'Informational'
            $Component.Properties | Should -BeOfType [hashtable]
        }
    }

    It 'rejects unsupported status input on public components' {
        $Report = New-PSIContractReport
        { $Report | Add-PSIKPI -Title 'Bad' -Value 1 -Status Danger -ErrorAction Stop | Out-Null } | Should -Throw '*Unsupported PSInsightHTML status*'
        $Report.Sections[0].Rows[0].Components.Count | Should -Be 0
    }

    It 'renders Informational, Neutral, Unknown and NotChecked badges with shared theme tokens' {
        $Report = New-PSIContractReport
        $Rows = @(
            [pscustomobject]@{ Name = 'A'; Status = 'Info' }
            [pscustomobject]@{ Name = 'B'; Status = 'Neutral' }
            [pscustomobject]@{ Name = 'C'; Status = 'Unknown' }
            [pscustomobject]@{ Name = 'D'; Status = 'NotChecked' }
        )
        $Report | Add-PSITable -Title 'Signals' -Data $Rows -Columns @('Name', 'Status') | Out-Null
        $Html = Get-PSIContractHtml -Report $Report
        $Html | Should -Match 'psi-status-badge psi-status-informational">Informational</span>'
        $Html | Should -Match 'psi-status-badge psi-status-neutral">Neutral</span>'
        $Html | Should -Match 'psi-status-badge psi-status-unknown">Unknown</span>'
        $Html | Should -Match 'psi-status-badge psi-status-not-checked">NotChecked</span>'
        $Html | Should -Match '--psi-status-informational: var\(--psi-status-info\)'
        $Html | Should -Match '--psi-status-neutral: var\(--psi-status-unknown\)'
    }

    It 'uses semantic status tokens for Informational and Neutral chart points' {
        $Report = New-PSIContractReport
        $Data = @(
            [pscustomobject]@{ Category = 'A'; Count = 2; Status = 'Info' }
            [pscustomobject]@{ Category = 'B'; Count = 3; Status = 'Neutral' }
        )
        $Report | Add-PSIChart -Title 'Status distribution' -ChartType Bar -Data $Data -CategoryProperty Category -ValueProperty Count -StatusProperty Status | Out-Null
        $Html = Get-PSIContractHtml -Report $Report
        $Html | Should -Match 'var\(--psi-status-informational\)'
        $Html | Should -Match 'var\(--psi-status-neutral\)'
    }

    It 'generates one browser status registry used by the evidence dialog' {
        $Report = New-PSIContractReport
        $Report | Add-PSIKPI -Title 'Evidence' -Value 1 -DrillDown @([pscustomobject]@{ Name = 'A'; Status = 'Info' }) | Out-Null
        $Html = Get-PSIContractHtml -Report $Report
        $Html | Should -Match 'window\.PSIStatus ='
        $Html | Should -Match '"Info":"Informational"'
        $Html | Should -Match 'window\.PSIStatus\.normalize\(text\)'
        $Html | Should -Match 'window\.PSIStatus\.classSuffix\(status\)'
        $Html | Should -Not -Match "\['Healthy', 'Warning', 'Critical', 'Info'"
    }

    It 'renders ScrollTo as an accessible button with encoded Action data' {
        $Report = New-PSIContractReport
        $Report | Add-PSIKPI -Title 'Go to sample' -Value 1 -Action @{ Type = 'ScrollTo'; Target = 'psi-section-0' } | Out-Null
        $Html = Get-PSIContractHtml -Report $Report
        $Html | Should -Match '<button type="button" class="psi-kpi-card psi-kpi-clickable'
        $Html | Should -Match 'data-action="[^\"]*&quot;ScrollTo&quot;'
        $Html | Should -Match 'Go to section'
        $Html | Should -Match 'scrollIntoView'
    }

    It 'renders FilterTable with safe metadata and table event dispatch' {
        $Report = New-PSIContractReport
        $Report | Add-PSIKPI -Title 'Critical sample' -Value 1 -Action @{ Type = 'FilterTable'; Target = 'sample-table'; Property = 'Status'; Value = 'Critical' } | Out-Null
        $Report | Add-PSITable -Title 'Sample' -Data @([pscustomobject]@{ Name = 'A'; Status = 'Critical' }) -Id 'sample-table' | Out-Null
        $Html = Get-PSIContractHtml -Report $Report
        $Html | Should -Match '<button type="button" class="psi-kpi-card psi-kpi-clickable'
        $Html | Should -Match '&quot;FilterTable&quot;'
        $Html | Should -Match "source: 'kpi-action'"
        $Html | Should -Match "Operator: 'Equals', Value: detail.value"
        $Html | Should -Match 'equalValue\(text, expected\)'
    }

    It 'accepts object Action metadata and serializes supported keys consistently' {
        $Report = New-PSIContractReport
        $Report | Add-PSIKPI -Title 'Navigate' -Value 1 -Action ([pscustomobject]@{ type = 'scrollto'; target = 'psi-section-0' }) | Out-Null
        $Html = Get-PSIContractHtml -Report $Report
        $Html | Should -Match '<button type="button" class="psi-kpi-card psi-kpi-clickable'
        $Html | Should -Match 'data-action="\{&quot;Type&quot;:&quot;ScrollTo&quot;,&quot;Target&quot;:&quot;psi-section-0&quot;\}"'
    }

    It 'ignores unknown Action types while keeping their data safely encoded' {
        $Report = New-PSIContractReport
        $Report | Add-PSIKPI -Title 'Unsafe' -Value 1 -Action @{ Type = 'RunScript'; Target = '<script>alert(1)</script>' } | Out-Null
        $Html = Get-PSIContractHtml -Report $Report
        $Html | Should -Match '<article class="psi-kpi-card psi-status-unknown"'
        $Html | Should -Match '&lt;script&gt;alert\(1\)&lt;/script&gt;'
        $Html | Should -Not -Match '<script>alert\(1\)</script>'
        $Html | Should -Not -Match '\beval\('
    }

    It 'preserves legacy KPI Filter and DrillDown activation' {
        $Report = New-PSIContractReport
        $Report | Add-PSIKPI -Title 'Filtered' -Value 1 -Filter @{ Table = 'sample-table'; Property = 'Status'; Value = 'Critical' } | Out-Null
        $Report | Add-PSIKPI -Title 'Details' -Value 1 -DrillDown @([pscustomobject]@{ Name = 'A' }) | Out-Null
        $Html = Get-PSIContractHtml -Report $Report
        $Html | Should -Match 'data-psi-filter-action='
        $Html | Should -Match 'data-psi-drilldown data-psi-records='
        $Html | Should -Match 'role="dialog" aria-modal="true"'
        $Html | Should -Match "trigger.hasAttribute\('data-psi-filter-action'\)"
    }
}
