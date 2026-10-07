$ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path $ModuleRoot 'PSInsightHTML.psd1') -Force

Describe 'PSInsightHTML master overview and summaries' {
    BeforeAll {
        $script:OverviewRoot = Split-Path -Path $PSScriptRoot -Parent
        function Get-OverviewHtml {
            param([pscustomobject] $Report)
            $Path = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.html')
            try {
                $null = Export-PSIReport -Report $Report -Path $Path
                [System.IO.File]::ReadAllText($Path)
            }
            finally { if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force } }
        }
        function New-OverviewFixture {
            $Report = New-PSIReport -Title 'Fictional portfolio' -Theme Auto
            $Assessment = New-PSIAssessment -Id 'example-one' -Name 'Example Service' -Provider 'Fictional'
            $Assessment | Add-PSISection -Title 'Evidence' | Add-PSIRow | Out-Null
            $Evidence = @([pscustomobject]@{ Name='A'; Status='Warning' }, [pscustomobject]@{ Name='B'; Status='Healthy' })
            $Assessment | Add-PSITable -Id 'sample-evidence' -Title 'Evidence' -Data $Evidence | Out-Null
            $Assessment | Add-PSIFinding -Finding (New-PSIFinding -Id 'example-finding' -Title 'Review sample status' -Status Warning `
                -EvidenceTableId 'sample-evidence' -EvidenceFilter @{ Property='Status'; Operator='Equals'; Value='Warning' }) | Out-Null
            $Report | Add-PSIAssessment -Assessment $Assessment | Out-Null
            $Report
        }
    }

    It 'returns zero counts for no findings' {
        $Summary = Get-PSIFindingSummary -Findings @()
        $Summary.Total | Should -Be 0
        foreach ($Status in @('Critical','Warning','Healthy','Informational','Neutral','Unknown','NotChecked')) {
            $Summary.$Status | Should -Be 0
        }
        (Get-PSIReportSummary -Report (New-PSIReport -Title 'Empty')).OverallStatus | Should -Be 'Neutral'
    }

    It 'counts every canonical status and normalizes Info' {
        $Findings = @('Critical','Warning','Healthy','Informational','Neutral','Unknown','NotChecked','Info') |
            ForEach-Object { [pscustomobject]@{ Status = $_ } }
        $Summary = Get-PSIFindingSummary -Findings $Findings
        $Summary.Total | Should -Be 8
        $Summary.Informational | Should -Be 2
        foreach ($Status in @('Critical','Warning','Healthy','Neutral','Unknown','NotChecked')) {
            $Summary.$Status | Should -Be 1
        }
        $Pipelined = $Findings | Get-PSIFindingSummary
        $Pipelined.Total | Should -Be 8
    }

    It 'rejects unsupported finding statuses' {
        { Get-PSIFindingSummary -Findings @([pscustomobject]@{ Status='Invented' }) } | Should -Throw '*Unsupported PSInsightHTML status*'
    }

    It 'applies the single overall-status precedence for <Expected>' -ForEach @(
        @{ Statuses=@('Healthy','Critical'); Expected='Critical' },
        @{ Statuses=@('Informational','Warning'); Expected='Warning' },
        @{ Statuses=@('NotChecked','Unknown'); Expected='Unknown' },
        @{ Statuses=@('Informational','NotChecked'); Expected='NotChecked' },
        @{ Statuses=@('Healthy','Informational'); Expected='Informational' },
        @{ Statuses=@('Neutral','Healthy'); Expected='Healthy' },
        @{ Statuses=@('Neutral'); Expected='Neutral' }
    ) {
        $Report = New-PSIReport -Title 'Status'
        foreach ($Status in $Statuses) { $Report.Findings.Add((New-PSIFinding -Title $Status -Status $Status)) }
        (Get-PSIReportSummary -Report $Report).OverallStatus | Should -Be $Expected
    }

    It 'summarizes assessment sections, findings and severity without HTML' {
        $Assessment = New-PSIAssessment -Id 'a-1' -Name 'Service' -Provider 'Fictional'
        $Assessment | Add-PSISection -Title 'One' | Add-PSIRow | Out-Null
        $Assessment | Add-PSISection -Title 'Two' | Add-PSIRow | Out-Null
        $Assessment.Findings.Add((New-PSIFinding -Title 'Issue' -Status Critical))
        $Summary = Get-PSIAssessmentSummary -Assessment $Assessment
        $Summary.Id | Should -Be 'a-1'
        $Summary.SectionCount | Should -Be 2
        $Summary.FindingCount | Should -Be 1
        $Summary.Critical | Should -Be 1
        $Summary.OverallStatus | Should -Be 'Critical'
        $Summary.PSObject.Properties.Name | Should -Not -Contain 'Html'
    }

    It 'counts logical report content across multiple assessments' {
        $Report = New-OverviewFixture
        $Second = New-PSIAssessment -Name 'Other' -Provider 'Fictional'
        $Second | Add-PSISection -Title 'Other Section' | Add-PSIRow | Add-PSITable -Id 'other-table' -Title 'Other Data' -Data @() -Columns @('Name') | Out-Null
        $Report | Add-PSIAssessment -Assessment $Second | Out-Null
        $Report | Add-PSISection -Title 'Manual' | Add-PSIRow | Add-PSITable -Id 'manual-table' -Title 'Manual Data' -Data @() -Columns @('Name') | Out-Null
        $Summary = Get-PSIReportSummary -Report $Report
        $Summary.AssessmentCount | Should -Be 2
        $Summary.SectionCount | Should -Be 3
        $Summary.TableCount | Should -Be 3
        $Summary.FindingCount | Should -Be 1
        $Summary.AssessmentSummaries.Count | Should -Be 2
        $Summary.AssessmentSummaries[1].OverallStatus | Should -Be 'Neutral'
    }

    It 'adds an overview first without copying table evidence or Findings' {
        $Report = New-OverviewFixture
        $Data = $Report.Sections[0].Rows[0].Components[0].Properties.Data
        $Finding = $Report.Findings[0]
        $Result = $Report | Add-PSIReportOverview -IncludeTopFindings
        [object]::ReferenceEquals($Result, $Report) | Should -BeTrue
        $Report.Sections[0].Title | Should -Be 'Report Overview'
        $Report.Sections[1].Title | Should -Be 'Evidence'
        $Report.Findings.Count | Should -Be 1
        [object]::ReferenceEquals($Report.Findings[0], $Finding) | Should -BeTrue
        [object]::ReferenceEquals($Report.Sections[1].Rows[0].Components[0].Properties.Data, $Data) | Should -BeTrue
        (Get-PSIReportSummary -Report $Report).TableCount | Should -Be 1
        $Html = Get-OverviewHtml $Report
        @([regex]::Matches($Html, 'id="sample-evidence"')).Count | Should -Be 1
        @([regex]::Matches($Html, 'id="example-finding"')).Count | Should -Be 1
        @([regex]::Matches($Html, 'data-psi-insight=')).Count | Should -Be 1
    }

    It 'orders top findings by severity and preserves original order within each status' {
        $Report = New-PSIReport -Title 'Order'
        $Report | Add-PSISection -Title 'Findings' | Add-PSIRow | Out-Null
        foreach ($Item in @(
            @{ Title='Warning first'; Status='Warning' },
            @{ Title='Critical'; Status='Critical' },
            @{ Title='Warning second'; Status='Warning' },
            @{ Title='Informational'; Status='Informational' }
        )) { $Report | Add-PSIFinding -Finding (New-PSIFinding -Title $Item.Title -Status $Item.Status) | Out-Null }
        $Report | Add-PSIReportOverview -IncludeTopFindings -MaxFindings 3 | Out-Null
        $Titles = @($Report.Sections[0].Rows[-1].Components | Where-Object Type -eq 'KPI' |
            ForEach-Object { $_.Properties.Title })
        $Titles | Should -Be @('Critical','Warning first','Warning second')
        @($Titles) | Should -Not -Contain 'Informational'
    }

    It 'creates valid assessment and finding anchors while preserving manual section navigation' {
        $Report = New-OverviewFixture
        $Report | Add-PSISection -Title 'Manual Notes' | Add-PSIRow | Add-PSIText -Text 'Manual content' | Out-Null
        $Report | Add-PSIReportOverview -IncludeTopFindings | Out-Null
        $Html = Get-OverviewHtml $Report
        $Html | Should -Match '<nav class="psi-assessment-nav" aria-label="Assessment groups">'
        $Html | Should -Match 'href="#psi-section-0">Overview</a>'
        $Html | Should -Match 'href="#psi-section-1">Example Service</a>'
        $Html | Should -Match 'href="#psi-section-2">Manual Notes</a>'
        $Html | Should -Match 'href="#psi-section-1">Evidence</a>'
        $Html | Should -Match 'href="#psi-section-2">Manual Notes</a>'
        ([regex]::IsMatch($Html, '&quot;Target&quot;:&quot;example-finding&quot;')) | Should -BeTrue
        $Ids = @([regex]::Matches($Html, '\bid="([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
        @($Ids | Sort-Object -Unique).Count | Should -Be $Ids.Count
    }

    It 'uses distinct rendered anchors for duplicate finding IDs' {
        $Report = New-PSIReport -Title 'Duplicates'
        $Report | Add-PSISection -Title 'Findings' | Add-PSIRow | Out-Null
        $Report | Add-PSIFinding -Finding (New-PSIFinding -Id 'same' -Title 'One' -Status Warning) | Out-Null
        $Report | Add-PSIFinding -Finding (New-PSIFinding -Id 'same' -Title 'Two' -Status Warning) | Out-Null
        $Report | Add-PSIReportOverview -IncludeTopFindings | Out-Null
        $Html = Get-OverviewHtml $Report
        ([regex]::IsMatch($Html, '&quot;Target&quot;:&quot;same&quot;')) | Should -BeTrue
        ([regex]::IsMatch($Html, '&quot;Target&quot;:&quot;same-2&quot;')) | Should -BeTrue
        $Html | Should -Match 'id="same"'
        $Html | Should -Match 'id="same-2"'
    }

    It 'keeps empty and manual-only reports navigable' {
        $Report = New-PSIReport -Title 'Manual'
        $Report | Add-PSISection -Title 'Notes' | Add-PSIRow | Add-PSIText -Text 'Content' | Out-Null
        $Report | Add-PSIReportOverview -IncludeTopFindings | Out-Null
        $Html = Get-OverviewHtml $Report
        $Html | Should -Match 'No structured findings were supplied'
        $Html | Should -Match 'No assessments have been added'
        $Html | Should -Match '<nav class="psi-report-nav" aria-label="Report sections">'
        ([regex]::IsMatch($Html, '<nav class="psi-assessment-nav"')) | Should -BeFalse
    }
}
