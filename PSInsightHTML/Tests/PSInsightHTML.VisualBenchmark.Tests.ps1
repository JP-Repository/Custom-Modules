$ProjectRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path $ProjectRoot 'PSInsightHTML.psd1') -Force

Describe 'PSInsightHTML visual benchmark contracts' {
    BeforeAll {
        $script:VisualBenchmarkRoot = (Get-Location).Path
    }
    It 'reads hashtable, ordered dictionary, and object properties with defaults' {
        InModuleScope PSInsightHTML {
            (Get-PSIProperty -InputObject @{ TITLE = 'Hash' } -Name 'title') | Should -Be 'Hash'
            (Get-PSIProperty -InputObject ([ordered]@{ Label = 'Ordered' }) -Name 'label') | Should -Be 'Ordered'
            (Get-PSIProperty -InputObject ([pscustomobject]@{ Title = 'Object' }) -Name 'Title') | Should -Be 'Object'
            (Get-PSIProperty -InputObject @{} -Name 'Missing' -DefaultValue 'Fallback') | Should -Be 'Fallback'
            (Get-PSIProperty -InputObject $null -Name 'Missing' -DefaultValue 'Fallback') | Should -Be 'Fallback'
        }
    }

    It 'encodes untrusted text through the private HTML helper' {
        InModuleScope PSInsightHTML {
            (ConvertTo-PSIHtmlEncoded -Value '<script>"&') | Should -Be '&lt;script&gt;&quot;&amp;'
            (ConvertTo-PSIHtmlEncoded -Value $null) | Should -Be ''
        }
    }

    It 'keeps KeyValue properties in a hashtable and returns the same report' {
        $Report = New-PSIReport -Title 'KeyValue contract'
        $Report | Add-PSISection -Title 'Overview' | Add-PSIRow | Out-Null
        $Result = $Report | Add-PSIKeyValue -Title 'Environment' -Data ([ordered]@{ Domain = 'corp.example'; Owner = $null }) -Span 6
        [object]::ReferenceEquals($Report, $Result) | Should -BeTrue
        $Component = $Report.Sections[0].Rows[0].Components[0]
        $Component.Type | Should -Be 'KeyValue'
        $Component.Properties | Should -BeOfType [hashtable]
        $Component.Properties.Data | Should -BeOfType [System.Collections.IDictionary]
        $Component.Properties.Span | Should -Be 6
    }

    It 'stores KPI and table spans and retains the established component model' {
        $Report = New-PSIReport -Title 'Span contract'
        $Report | Add-PSISection -Title 'Summary' | Add-PSIRow |
            Add-PSIKPI -Title 'Health' -Value 57 -Status Informational -Span 3 |
            Add-PSITable -Title 'Inventory' -Data @([pscustomobject]@{ Name = 'Sample'; Status = 'Healthy' }) -Span 12 | Out-Null
        $Report.Sections[0].Rows[0].Components[0].Properties.Span | Should -Be 3
        $Report.Sections[0].Rows[0].Components[1].Properties.Span | Should -Be 12
        $Report.Sections[0].Rows[0].Components[0].Properties | Should -BeOfType [hashtable]
        $Report.Sections[0].Rows[0].Components[1].Properties | Should -BeOfType [hashtable]
        { $Report | Add-PSIKPI -Title 'Invalid' -Value 1 -Span 13 } | Should -Throw
        { $Report | Add-PSIKeyValue -Title 'Invalid' -Data @{} -Span 0 } | Should -Throw
        { $Report | Add-PSITable -Title 'Invalid' -Data @() -Span 13 } | Should -Throw
    }

    It 'renders Informational and Neutral consistently across status components and table cells' {
        $Report = New-PSIReport -Title 'Status aliases'
        $Report | Add-PSISection -Title 'Signals' | Add-PSIRow |
            Add-PSIStatus -Status Informational |
            Add-PSIAlert -Status Neutral -Title 'Note' -Message 'Sample note' |
            Add-PSIRecommendation -Status Informational -Title 'Review' -Description 'Sample review' |
            Add-PSIInsight -Status Neutral -Title 'Measure' -Value 1 |
            Add-PSITable -Title 'States' -Data @(
                [pscustomobject]@{ Name = 'First'; Status = 'Informational' },
                [pscustomobject]@{ Name = 'Second'; Status = 'Neutral' }
            ) | Out-Null
        $Path = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.html')
        try {
            $null = Export-PSIReport -Report $Report -Path $Path
            $Html = [System.IO.File]::ReadAllText($Path)
            $Html | Should -Match 'psi-status-badge psi-status-informational'
            $Html | Should -Match 'psi-status-badge psi-status-neutral'
            $Html | Should -Match 'psi-status-panel psi-status-informational'
            $Html | Should -Match 'psi-alert psi-status-neutral'
            $Html | Should -Match 'psi-recommendation psi-status-informational'
            $Html | Should -Match 'psi-insight-card psi-status-neutral'
        }
        finally {
            if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
        }
    }

    It 'emphasizes numeric table values without changing text or status cells' {
        $Report = New-PSIReport -Title 'Numeric cells'
        $Report | Add-PSISection -Title 'Counts' | Add-PSIRow |
            Add-PSITable -Title 'Sample counts' -Data @(
                [pscustomobject]@{ Name = 'Group A'; MemberCount = 7; Status = 'Informational' }
            ) -EnableExport $false | Out-Null
        $Path = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.html')
        try {
            $null = Export-PSIReport -Report $Report -Path $Path
            $Html = [System.IO.File]::ReadAllText($Path)
            $Html | Should -Match '<td class="psi-numeric-cell">7</td>'
            $Html | Should -Match '<td>Group A</td>'
            $Html | Should -Match 'psi-status-badge psi-status-informational'
        }
        finally {
            if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
        }
    }

    It 'renders encoded KeyValue rows, spans, status aliases, and an empty table state offline' {
        $Report = New-PSIReport -Title 'Benchmark' -Theme Auto
        $Report | Add-PSISection -Title 'Assessment' | Add-PSIRow |
            Add-PSIKPI -Title 'Accounts' -Value 7 -Status Informational -Span 3 |
            Add-PSIKeyValue -Title 'Identity' -Data ([ordered]@{ '<label>' = '<script>'; Empty = $null }) -Span 6 |
            Add-PSITable -Title 'No records' -Data @() -Span 12 | Out-Null
        $Path = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.html')
        try {
            $File = Export-PSIReport -Report $Report -Path $Path
            $Html = [System.IO.File]::ReadAllText($File.FullName)
            $Html | Should -Match 'psi-keyvalue-card'
            $Html | Should -Match 'psi-status-informational'
            $Html | Should -Match 'style="--psi-component-span: 3"'
            $Html | Should -Match 'style="--psi-component-span: 6"'
            $Html | Should -Match 'style="--psi-component-span: 12"'
            $Html | Should -Match '&lt;label&gt;'
            $Html | Should -Match '&lt;script&gt;'
            $Html | Should -Not -Match '<dd><script>'
            $Html | Should -Match 'No data available\.'
            $Html | Should -Match '--psi-success-tint'
            $Html | Should -Match '\.psi-keyvalue-card'
            $Html | Should -Not -Match '<script\s+[^>]*src\s*=|<link\s+[^>]*href\s*=|<img\s+[^>]*src\s*='
        }
        finally {
            if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
        }
    }

    It 'generates the synthetic assessment with all six benchmark sections' {
        $Path = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.html')
        try {
            & (Join-Path $script:VisualBenchmarkRoot 'Examples/New-DemoReport.ps1') -OutputPath $Path -NoBrowser | Out-Null
            (Test-Path -LiteralPath $Path -PathType Leaf) | Should -BeTrue
            $Html = [System.IO.File]::ReadAllText($Path)
            foreach ($Title in @('Executive Summary','Environment Overview','Domain Statistics','Privileged Group Statistics','Domain Administrators','Security Observations')) {
                $Html | Should -Match ([regex]::Escape($Title))
            }
            $Html | Should -Match 'Sample Administrator 01'
            $Html | Should -Match 'data-theme="Auto"'
            $Html | Should -Not -Match '<script\s+[^>]*src\s*=|<link\s+[^>]*href\s*=|<img\s+[^>]*src\s*=|\bfetch\s*\('
        }
        finally {
            if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
        }
    }
}
