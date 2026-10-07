$ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path $ModuleRoot 'PSInsightHTML.psd1') -Force

Describe 'PSInsightHTML composable assessments' {
    BeforeAll {
        $script:AssessmentModuleRoot = Split-Path -Path $PSScriptRoot -Parent
        function Get-AssessmentTestHtml {
            param([pscustomobject] $Report)
            $Path = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.html')
            try {
                $null = Export-PSIReport -Report $Report -Path $Path
                [System.IO.File]::ReadAllText($Path)
            }
            finally { if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force } }
        }
    }

    It 'creates a typed assessment with a generated ID and structured collections' {
        $Assessment = New-PSIAssessment -Name 'Sample' -Provider 'Example' -Metadata @{ Scope = 'Fictional' }
        $Assessment.PSObject.TypeNames[0] | Should -Be 'PSInsightHTML.Assessment'
        $Assessment.Id | Should -Match '^psi-assessment-[0-9a-f]{32}$'
        $Assessment.Title | Should -Be 'Sample'
        $Assessment.Sections.GetType() | Should -Be ([System.Collections.Generic.List[object]])
        $Assessment.Findings.GetType() | Should -Be ([System.Collections.Generic.List[object]])
        $Assessment.Metadata.Scope | Should -Be 'Fictional'
        @($Assessment.PSObject.Properties.Name) | Should -Be @('Id','Name','Title','Provider','Description','Metadata','Sections','Findings')
    }

    It 'preserves a caller ID and accepts existing section, row, and component builders' {
        $Assessment = New-PSIAssessment -Id 'sample-01' -Name 'Sample'
        $Result = $Assessment | Add-PSISection -Title 'Overview' | Add-PSIRow | Add-PSIText -Text 'Structured sample'
        [object]::ReferenceEquals($Assessment, $Result) | Should -BeTrue
        $Assessment.Id | Should -Be 'sample-01'
        $Assessment.Sections[0].Rows[0].Components[0].Type | Should -Be 'Text'
    }

    It 'appends sections and findings by reference and returns the same report' {
        $Assessment = New-PSIAssessment -Name 'First' -Provider 'Example'
        $Assessment | Add-PSISection -Title 'Evidence' | Add-PSIRow | Out-Null
        $Finding = New-PSIFinding -Title 'Example finding' -Status Warning -EvidenceTableId 'first-table'
        $Assessment | Add-PSIFinding -Finding $Finding | Out-Null
        $Assessment | Add-PSITable -Id 'first-table' -Title 'Evidence' -Data @([pscustomobject]@{ Name='Sample'; Status='Warning' }) | Out-Null
        $Report = New-PSIReport -Title 'Composed'
        $Result = $Report | Add-PSIAssessment -Assessment $Assessment
        [object]::ReferenceEquals($Result, $Report) | Should -BeTrue
        [object]::ReferenceEquals($Report.Sections[0], $Assessment.Sections[0]) | Should -BeTrue
        [object]::ReferenceEquals($Report.Findings[0], $Finding) | Should -BeTrue
        $Report.Assessments[0].SectionCount | Should -Be 1
        $Report.Assessments[0].PSObject.Properties.Name | Should -Not -Contain 'Sections'
        $Html = Get-AssessmentTestHtml $Report
        $Html | Should -Match 'data-psi-insight=' 
        $Html | Should -Match 'id="first-table"'
    }

    It 'composes multiple assessments into one report' {
        $Report = New-PSIReport -Title 'Portfolio'
        foreach ($Name in @('One','Two')) {
            $Assessment = New-PSIAssessment -Name $Name
            $Assessment | Add-PSISection -Title $Name | Add-PSIRow | Add-PSIText -Text $Name | Out-Null
            $Report | Add-PSIAssessment -Assessment $Assessment | Out-Null
        }
        $Report.Assessments.Count | Should -Be 2
        $Report.Sections.Count | Should -Be 2
        $Html = Get-AssessmentTestHtml $Report
        $Html | Should -Match 'id="psi-section-1"'
    }

    It 'rejects duplicate explicit table IDs at addition time' {
        $Report = New-PSIReport -Title 'IDs'
        $Report | Add-PSISection -Title 'Data' | Add-PSIRow | Out-Null
        $Report | Add-PSITable -Id 'same-table' -Title 'One' -Data @() -Columns @('Name') | Out-Null
        { $Report | Add-PSITable -Id 'same-table' -Title 'Two' -Data @() -Columns @('Name') | Out-Null } | Should -Throw "*Table ID 'same-table' already exists*"
        $Report.Sections[0].Rows[0].Components.Count | Should -Be 1
    }

    It 'rejects colliding assessment table IDs before changing the report' {
        $Report = New-PSIReport -Title 'IDs'
        foreach ($Name in @('One','Two')) {
            $Assessment = New-PSIAssessment -Name $Name
            $Assessment | Add-PSISection -Title $Name | Add-PSIRow | Add-PSITable -Id 'shared-table' -Title 'Data' -Data @() -Columns @('Name') | Out-Null
            if ($Name -eq 'One') { $Report | Add-PSIAssessment -Assessment $Assessment | Out-Null }
        }
        { $Report | Add-PSIAssessment -Assessment $Assessment | Out-Null } | Should -Throw "*Table ID 'shared-table' already exists*"
        $Report.Sections.Count | Should -Be 1
        $Report.Assessments.Count | Should -Be 1
    }

    It 'generates distinct IDs for tables without supplied IDs' {
        $Report = New-PSIReport -Title 'Generated IDs'
        $Report | Add-PSISection -Title 'Data' | Add-PSIRow | Out-Null
        $Report | Add-PSITable -Title 'One' -Data @() -Columns @('Name') | Out-Null
        $Report | Add-PSITable -Title 'Two' -Data @() -Columns @('Name') | Out-Null
        $Ids = @($Report.Sections[0].Rows[0].Components | ForEach-Object { $_.Properties.Id })
        $Ids[0] | Should -Match '^psi-table-[0-9a-f]{32}$'
        $Ids[0] | Should -Not -Be $Ids[1]
    }

    It 'omits a broken evidence action while still rendering its finding' {
        $Assessment = New-PSIAssessment -Name 'Missing evidence'
        $Assessment | Add-PSISection -Title 'Findings' | Add-PSIRow | Add-PSIFinding -Finding (
            New-PSIFinding -Title 'Missing table finding' -Status Warning -EvidenceTableId 'missing-table') | Out-Null
        $Report = New-PSIReport -Title 'Missing evidence'
        $Report | Add-PSIAssessment -Assessment $Assessment | Out-Null
        $Html = Get-AssessmentTestHtml $Report
        $Html | Should -Match 'Missing table finding'
        $Html | Should -Not -Match 'View Evidence'
    }

    It 'keeps the six provider assessment commands private to structured content with -AsAssessment' -ForEach @(
        @{ Command = 'New-PSIADDNSAssessment' },
        @{ Command = 'New-PSIADReplicationAssessment' },
        @{ Command = 'New-PSIADSitesSubnetsAssessment' },
        @{ Command = 'New-PSIADGroupAssessment' },
        @{ Command = 'New-PSIADGroupPolicyAssessment' },
        @{ Command = 'New-PSIADUserInventory' }
    ) {
        $Path = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.html')
        $StandalonePath = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.html')
        try {
            $Assessment = & $Command -UseSampleData -AsAssessment -Path $Path -NoBrowser
            $Assessment.PSObject.TypeNames[0] | Should -Be 'PSInsightHTML.Assessment'
            $Assessment.Provider | Should -Be 'ActiveDirectory'
            $Assessment.Sections.Count | Should -BeGreaterThan 0
            $Assessment.PSObject.Properties.Name | Should -Not -Contain 'Html'
            (Test-Path -LiteralPath $Path) | Should -BeFalse
            $null = & $Command -UseSampleData -Path $StandalonePath -NoBrowser
            $StandaloneHtml = [System.IO.File]::ReadAllText($StandalonePath)
            @([regex]::Matches($StandaloneHtml, '<section class="psi-section"')).Count | Should -Be $Assessment.Sections.Count
            $AssessmentTableCount = @($Assessment.Sections | ForEach-Object { $_.Rows } | ForEach-Object { $_.Components } | Where-Object Type -eq 'Table').Count
            @([regex]::Matches($StandaloneHtml, '<section class="psi-table-card"')).Count | Should -Be $AssessmentTableCount
        }
        finally {
            if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
            if (Test-Path -LiteralPath $StandalonePath) { Remove-Item -LiteralPath $StandalonePath -Force }
        }
    }

    It 'generates a self-contained composed demo with unique IDs and valid evidence targets' {
        $Path = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.html')
        try {
            $null = & (Join-Path $script:AssessmentModuleRoot 'Examples/New-ComposedADAssessmentDemo.ps1') -OutputPath $Path -NoBrowser
            $Html = [System.IO.File]::ReadAllText($Path)
            $Html | Should -Match '<!DOCTYPE html>'
            ([regex]::IsMatch($Html, '<nav class="psi-assessment-nav" aria-label="Assessment groups">')) | Should -BeTrue
            @([regex]::Matches($Html, '<article class="psi-finding-card')).Count | Should -Be 4
            @([regex]::Matches($Html, '<section class="psi-section"')).Count | Should -Be 64
            ([regex]::IsMatch($Html, '<details class="psi-section-nav-details">')) | Should -BeTrue
            $Html | Should -Not -Match '<script\s+[^>]*src\s*=|<link\s+[^>]*href\s*=|<img\s+[^>]*src\s*=|\bfetch\s*\('
            $Ids = @([regex]::Matches($Html, '\bid="([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
            @($Ids | Sort-Object -Unique).Count | Should -Be $Ids.Count
            $TableIds = @([regex]::Matches($Html, '<section class="psi-table-card" id="([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
            $TableIds.Count | Should -BeGreaterThan 20
            @($TableIds | Sort-Object -Unique).Count | Should -Be $TableIds.Count
            $Evidence = @([regex]::Matches($Html, 'data-psi-insight="([^"]+)"') | ForEach-Object {
                [System.Net.WebUtility]::HtmlDecode($_.Groups[1].Value) | ConvertFrom-Json
            })
            $Evidence.Count | Should -BeGreaterThan 0
            foreach ($Definition in $Evidence) { $TableIds | Should -Contain $Definition.tableId }
        }
        finally { if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force } }
    }
}
