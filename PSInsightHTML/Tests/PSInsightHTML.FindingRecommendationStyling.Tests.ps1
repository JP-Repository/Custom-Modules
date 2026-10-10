$ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path $ModuleRoot 'PSInsightHTML.psd1') -Force

Describe 'PSInsightHTML finding recommendation severity styling' {
    BeforeAll {
        $Report = New-PSIReport -Title 'Finding recommendation behavior' -Theme Auto
        $Report | Add-PSISection -Title 'Findings' | Add-PSIRow | Out-Null
        $Statuses = @('Critical', 'Warning', 'Healthy', 'Informational', 'Neutral', 'Unknown', 'NotChecked')
        foreach ($Status in $Statuses) {
            $Parameters = @{
                Title = "$Status finding"
                Status = $Status
                Category = 'Synthetic category'
                Description = 'Synthetic description.'
                AffectedObject = 'Sample object'
                Impact = 'Sample impact.'
                Recommendation = "Review the $Status sample."
                RuleId = "RULE-$Status"
                Source = 'Synthetic source'
            }
            if ($Status -eq 'Critical') {
                $Parameters.EvidenceTableId = 'finding-recommendation-evidence'
                $Parameters.EvidenceFilter = @{ Property = 'Status'; Value = 'Critical' }
            }
            $Report | Add-PSIFinding -Finding (New-PSIFinding @Parameters) | Out-Null
        }
        $Report | Add-PSIRow |
            Add-PSIRecommendation -Title 'Standalone recommendation' -Description 'Standalone behavior.' -Status Warning | Out-Null
        $Report | Add-PSIRow |
            Add-PSITable -Id 'finding-recommendation-evidence' -Title 'Evidence' `
                -Data @([pscustomobject]@{ Name = 'Sample'; Status = 'Critical' }) `
                -Columns @('Name', 'Status') | Out-Null

        $Path = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.html')
        try {
            $null = Export-PSIReport -Report $Report -Path $Path
            $script:FindingRecommendationHtml = [System.IO.File]::ReadAllText($Path)
        }
        finally {
            if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
        }
    }

    It 'keeps the recommendation subsection inside every status-bearing finding card' {
        foreach ($Status in @('critical', 'warning', 'healthy', 'informational', 'neutral', 'unknown', 'not-checked')) {
            $Card = [regex]::Match(
                $script:FindingRecommendationHtml,
                '<article class="psi-finding-card psi-status-' + $Status + '".*?</article>',
                'Singleline'
            ).Value
            $Card | Should -Not -BeNullOrEmpty
            $Card | Should -Match '<div class="psi-finding-recommendation"><strong>Recommendation</strong><p>'
        }
    }

    It 'maps critical warning and healthy context to existing status surfaces and outlines' {
        $script:FindingRecommendationHtml | Should -Match '\.psi-status-critical \{[^}]*--psi-component-surface: var\(--psi-critical-surface\);[^}]*--psi-component-outline: var\(--psi-critical-outline\);'
        $script:FindingRecommendationHtml | Should -Match '\.psi-status-warning \{[^}]*--psi-component-surface: var\(--psi-warning-surface\);[^}]*--psi-component-outline: var\(--psi-warning-outline\);'
        $script:FindingRecommendationHtml | Should -Match '\.psi-status-healthy \{[^}]*--psi-component-surface: var\(--psi-healthy-surface\);[^}]*--psi-component-outline: var\(--psi-healthy-outline\);'
    }

    It 'maps informational and neutral-family context to existing semantic tokens' {
        $script:FindingRecommendationHtml | Should -Match '\.psi-status-informational \{[^}]*--psi-component-surface: var\(--psi-informational-surface\);[^}]*--psi-component-outline: var\(--psi-informational-outline\);'
        foreach ($Status in @('neutral', 'unknown', 'not-checked')) {
            $script:FindingRecommendationHtml | Should -Match ('\.psi-status-' + $Status + ' \{[^}]*--psi-component-surface: var\(--psi-neutral-surface\);[^}]*--psi-component-outline: var\(--psi-neutral-outline\);')
        }
    }

    It 'uses inherited status context for a restrained panel and readable text' {
        $script:FindingRecommendationHtml | Should -Match '\.psi-finding-recommendation \{[^}]*background: var\(--psi-component-surface, var\(--psi-surface-raised\)\);[^}]*border: 1px solid var\(--psi-component-outline, var\(--psi-border\)\);[^}]*border-left: 3px solid var\(--psi-component-status\);'
        $script:FindingRecommendationHtml | Should -Match '\.psi-finding-recommendation strong \{ color: var\(--psi-component-status\);'
        $script:FindingRecommendationHtml | Should -Match '\.psi-finding-recommendation p \{[^}]*color: var\(--psi-text\);'
    }

    It 'preserves evidence controls provenance and standalone recommendations' {
        $script:FindingRecommendationHtml | Should -Match '<button type="button" class="psi-finding-evidence" data-psi-insight='
        $script:FindingRecommendationHtml | Should -Match 'aria-label="View evidence for Critical finding"'
        $script:FindingRecommendationHtml | Should -Match 'Rule: RULE-Critical'
        $script:FindingRecommendationHtml | Should -Match 'Source: Synthetic source'
        $script:FindingRecommendationHtml | Should -Match '<article class="psi-recommendation psi-status-warning" data-status="Warning">'
        $script:FindingRecommendationHtml | Should -Match '<h3>Standalone recommendation</h3>'
    }

    It 'keeps a severity border when printed without relying on the tint' {
        $script:FindingRecommendationHtml | Should -Match '\.psi-finding-recommendation \{ background: transparent !important; border-color: var\(--psi-border-strong\) !important; border-left-color: var\(--psi-component-status\) !important; \}'
    }
}
