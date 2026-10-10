$ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path $ModuleRoot 'PSInsightHTML.psd1') -Force

Describe 'PSInsightHTML generic findings explorer' {
    BeforeAll {
        $Report = New-PSIReport -Title 'Findings explorer behavior' -Theme Auto
        $Report | Add-PSISection -Title 'First findings' | Out-Null
        $Report | Add-PSIRow | Add-PSIFinding -Finding (New-PSIFinding -Id 'stable-critical' `
            -Title 'Critical sample' -Status Critical -AffectedObject 'object02.example.invalid' `
            -Impact 'Synthetic impact.' -Recommendation 'Review immediately.' -RuleId 'RULE-CRITICAL' `
            -Source 'Synthetic source' -EvidenceTableId 'explorer-evidence' `
            -EvidenceFilter @{ Property = 'Status'; Value = 'Critical' }) | Out-Null
        $Report | Add-PSIRow | Add-PSIFinding -Finding (New-PSIFinding -Title 'Warning one' `
            -Status Warning -AffectedObject 'object01.example.invalid' -Recommendation 'Review warning one.') | Out-Null
        $Report | Add-PSIRow | Add-PSIFinding -Finding (New-PSIFinding -Title 'Warning two' `
            -Status Warning -AffectedObject 'object01.example.invalid' -Recommendation 'Review warning two.') | Out-Null
        $Report | Add-PSIRow | Add-PSIFinding -Finding (New-PSIFinding -Title 'Unsafe label' `
            -Status Informational -AffectedObject 'Unsafe <node> & "sample"' -Recommendation 'Review safely.') | Out-Null
        $Report | Add-PSIRow | Add-PSIFinding -Finding (New-PSIFinding -Title 'Unspecified object' `
            -Status Unknown -AffectedObject '' -Recommendation 'Assign an object.') | Out-Null
        $Report | Add-PSIRow |
            Add-PSIFinding -Finding (New-PSIFinding -Title 'Mixed row finding' -Status Healthy `
                -AffectedObject 'object03.example.invalid' -Recommendation 'No action required.') |
            Add-PSIText -Text 'Unrelated row content remains visible.' | Out-Null

        $Report | Add-PSISection -Title 'Second findings' | Out-Null
        $Report | Add-PSIRow | Add-PSIFinding -Finding (New-PSIFinding -Title 'Second warning' `
            -Status Warning -AffectedObject 'alpha.example.invalid' -Recommendation 'Review alpha.') | Out-Null
        $Report | Add-PSIRow | Add-PSIFinding -Finding (New-PSIFinding -Title 'Second healthy' `
            -Status Healthy -AffectedObject 'beta.example.invalid' -Recommendation 'Review beta.') | Out-Null

        $Report | Add-PSISection -Title 'Single object findings' | Out-Null
        $Report | Add-PSIRow | Add-PSIFinding -Finding (New-PSIFinding -Title 'Single one' `
            -Status Warning -AffectedObject 'single.example.invalid' -Recommendation 'Review one.') | Out-Null
        $Report | Add-PSIRow | Add-PSIFinding -Finding (New-PSIFinding -Title 'Single two' `
            -Status Healthy -AffectedObject 'single.example.invalid' -Recommendation 'Review two.') | Out-Null

        $Report | Add-PSISection -Title 'Evidence' | Add-PSIRow |
            Add-PSITable -Id 'explorer-evidence' -Title 'Evidence records' `
                -Data @([pscustomobject]@{ Name = 'Synthetic record'; Status = 'Critical' }) `
                -Columns @('Name', 'Status') | Out-Null

        $Path = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.html')
        try {
            $null = Export-PSIReport -Report $Report -Path $Path
            $script:FindingsExplorerHtml = [System.IO.File]::ReadAllText($Path)
        }
        finally {
            if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
        }
    }

    It 'adds encoded generic metadata while preserving IDs and visible affected objects' {
        $script:FindingsExplorerHtml | Should -Match 'id="stable-critical" data-status="Critical" data-psi-finding-card data-psi-affected-object="object02\.example\.invalid" data-psi-finding-status="Critical"'
        $script:FindingsExplorerHtml | Should -Match 'data-psi-affected-object="Unsafe &lt;node&gt; &amp; &quot;sample&quot;"'
        $script:FindingsExplorerHtml | Should -Match '<dd>Unsafe &lt;node&gt; &amp; &quot;sample&quot;</dd>'
        $script:FindingsExplorerHtml | Should -Match 'data-psi-affected-object="" data-psi-finding-status="Unknown"'
    }

    It 'discovers qualifying sections independently and skips single-object sections' {
        $script:FindingsExplorerHtml | Should -Match "document\.querySelectorAll\('\.psi-section'\)"
        $script:FindingsExplorerHtml | Should -Match 'initializeFindingsExplorer\(section, sectionIndex\)'
        $script:FindingsExplorerHtml | Should -Match 'if \(cards\.length < 2\) \{ return; \}'
        $script:FindingsExplorerHtml | Should -Match 'if \(distinctNonEmpty\.length < 2\) \{ return; \}'
    }

    It 'builds unique counted object options plus All findings and Unspecified' {
        $script:FindingsExplorerHtml | Should -Match 'groups\.filter\(function \(item\) \{ return item\.value === value; \}\)\[0\]'
        $script:FindingsExplorerHtml | Should -Match "label: value \|\| 'Unspecified'"
        $script:FindingsExplorerHtml | Should -Match "option\.textContent = group\.label \+ ' \(' \+ group\.cards\.length \+ '\)'"
        $script:FindingsExplorerHtml | Should -Match "allOption\.textContent = 'All findings \(' \+ cards\.length \+ '\)'"
    }

    It 'defaults through severity count and alphabetical object ordering' {
        $script:FindingsExplorerHtml | Should -Match "\['Critical', 'Warning', 'Unknown', 'NotChecked', 'Informational', 'Healthy', 'Neutral'\]"
        $script:FindingsExplorerHtml | Should -Match 'left\.priority - right\.priority'
        $script:FindingsExplorerHtml | Should -Match 'right\.cards\.length - left\.cards\.length'
        $script:FindingsExplorerHtml | Should -Match 'left\.label\.localeCompare\(right\.label'
        $script:FindingsExplorerHtml | Should -Not -Match "select\.value = 'all'"
    }

    It 'filters original cards with hidden and updates count and status summaries' {
        $script:FindingsExplorerHtml | Should -Match "select\.addEventListener\('change', applyFindingSelection\)"
        $script:FindingsExplorerHtml | Should -Match 'card\.hidden = !show'
        $script:FindingsExplorerHtml | Should -Match "'Showing ' \+ visibleCards\.length \+ ' of ' \+ cards\.length \+ ' findings'"
        $script:FindingsExplorerHtml | Should -Match "'Showing all ' \+ cards\.length \+ ' findings'"
        $script:FindingsExplorerHtml | Should -Match "statusCount\.textContent = counts\[status\] \+ ' ' \+ status"
    }

    It 'uses an actual label native select and polite live summary' {
        $script:FindingsExplorerHtml | Should -Match "document\.createElement\('label'\)"
        $script:FindingsExplorerHtml | Should -Match "document\.createElement\('select'\)"
        $script:FindingsExplorerHtml | Should -Match "caption\.textContent = 'Affected object'"
        $script:FindingsExplorerHtml | Should -Match "summary\.setAttribute\('aria-live', 'polite'\)"
        $script:FindingsExplorerHtml | Should -Match "select\.setAttribute\('aria-describedby', summaryId\)"
        $script:FindingsExplorerHtml | Should -Match '\.psi-findings-explorer-control select:focus-visible \{ outline: 2px solid var\(--psi-focus-ring\);'
    }

    It 'collapses finding-only rows without hiding unrelated row content' {
        $script:FindingsExplorerHtml | Should -Match "components\.some\(function \(component\) \{ return !component\.hasAttribute\('data-psi-finding-card'\); \}\)"
        $script:FindingsExplorerHtml | Should -Match 'var hideRow = !hasUnrelatedContent && findingCards\.every'
        $script:FindingsExplorerHtml | Should -Match "row\.setAttribute\('data-psi-finding-row-hidden', 'true'\)"
        $script:FindingsExplorerHtml | Should -Match 'Unrelated row content remains visible\.'
    }

    It 'preserves evidence provenance and section navigation contracts' {
        $script:FindingsExplorerHtml | Should -Match '<button type="button" class="psi-finding-evidence" data-psi-insight='
        $script:FindingsExplorerHtml | Should -Match 'aria-label="View evidence for Critical sample"'
        $script:FindingsExplorerHtml | Should -Match 'Rule: RULE-CRITICAL'
        $script:FindingsExplorerHtml | Should -Match 'Source: Synthetic source'
        $script:FindingsExplorerHtml | Should -Match '<nav class="psi-report-nav" aria-label="Report sections">'
        $script:FindingsExplorerHtml | Should -Match "window\.addEventListener\('psi:layout-change', scheduleReportNavigation\)"
    }

    It 'hides explorer controls and restores all filtered cards and rows for print' {
        $script:FindingsExplorerHtml | Should -Match '\.psi-findings-explorer[^}]*display: none !important;'
        $script:FindingsExplorerHtml | Should -Match '\.psi-finding-card\[data-psi-finding-card\]\[hidden\] \{ display: block !important; \}'
        $script:FindingsExplorerHtml | Should -Match '\.psi-row\[data-psi-finding-row-hidden\]\[hidden\] \{ display: grid !important; \}'
    }

    It 'compares affected-object values directly without constructing raw selectors' {
        $script:FindingsExplorerHtml | Should -Match "card\.getAttribute\('data-psi-affected-object'\)"
        $script:FindingsExplorerHtml | Should -Match 'value === selectedGroup\.value'
        $script:FindingsExplorerHtml | Should -Not -Match "querySelectorAll\('\[data-psi-affected-object="
    }
}
