BeforeAll {
    . (Join-Path (Get-Location).Path 'Providers/ActiveDirectory/Groups/Private/PSIADGroups.Provider.ps1')
}

Describe 'PSInsightHTML fictional group provider' {
    BeforeAll {
        $script:GroupSample = New-PSIADGroupSampleData
    }

    It 'generates deterministic group, membership, and nesting datasets' {
        $Again = New-PSIADGroupSampleData
        $script:GroupSample.GroupInventory.Count | Should -Be 320
        $script:GroupSample.GroupMemberships.Count | Should -BeGreaterThan 3000
        $script:GroupSample.NestedGroupRelationships.Count | Should -BeGreaterThan 50
        $Again.GroupMemberships.Count | Should -Be $script:GroupSample.GroupMemberships.Count
        $Again.GroupInventory[0] | ConvertTo-Json -Compress | Should -Be ($script:GroupSample.GroupInventory[0] | ConvertTo-Json -Compress)
    }

    It 'contains category, scope, empty, large, ownership, and disabled-user examples' {
        @($script:GroupSample.GroupInventory.GroupCategory | Sort-Object -Unique) | Should -Be @('Distribution', 'Security')
        @($script:GroupSample.GroupInventory.GroupScope | Sort-Object -Unique) | Should -Be @('Domain Local', 'Global', 'Universal')
        @($script:GroupSample.GroupInventory | Where-Object MemberCount -eq 0).Count | Should -BeGreaterThan 0
        @($script:GroupSample.GroupInventory | Where-Object MemberCount -ge 500).Count | Should -BeGreaterThan 0
        @($script:GroupSample.GroupInventory | Where-Object HasOwner -eq 'No').Count | Should -BeGreaterThan 0
        @($script:GroupSample.GroupInventory | Where-Object { [string]::IsNullOrWhiteSpace($_.Description) }).Count | Should -BeGreaterThan 0
        @($script:GroupSample.GroupInventory | Where-Object HasDisabledMembers -eq 'Yes').Count | Should -BeGreaterThan 0
    }

    It 'reconciles direct member counts and nested relationship rows' {
        $MembershipCounts = @{}
        foreach ($Row in $script:GroupSample.GroupMemberships) {
            if (-not $MembershipCounts.ContainsKey($Row.GroupName)) { $MembershipCounts[$Row.GroupName] = 0 }
            $MembershipCounts[$Row.GroupName]++
        }
        $NestedCounts = @{}
        foreach ($Row in $script:GroupSample.NestedGroupRelationships) {
            if (-not $NestedCounts.ContainsKey($Row.ParentGroup)) { $NestedCounts[$Row.ParentGroup] = 0 }
            $NestedCounts[$Row.ParentGroup]++
        }
        foreach ($Group in $script:GroupSample.GroupInventory) {
            $ExpectedMembers = if ($MembershipCounts.ContainsKey($Group.GroupName)) { $MembershipCounts[$Group.GroupName] } else { 0 }
            $ExpectedNested = if ($NestedCounts.ContainsKey($Group.GroupName)) { $NestedCounts[$Group.GroupName] } else { 0 }
            $Group.MemberCount | Should -Be $ExpectedMembers
            $Group.MemberCount | Should -Be ($Group.DirectUserCount + $Group.DirectGroupCount)
            $Group.NestedGroupCount | Should -Be $ExpectedNested
            $Group.DirectGroupCount | Should -Be $ExpectedNested
        }
    }

    It 'records only direct forward nesting edges with valid sample scope combinations' {
        $Names = @{}
        foreach ($Group in $script:GroupSample.GroupInventory) { $Names[$Group.GroupName] = $Group }
        foreach ($Row in $script:GroupSample.NestedGroupRelationships) {
            $Row.RelationshipDepth | Should -Be 1
            $Row.RelationshipType | Should -Be 'Direct'
            $Names.ContainsKey($Row.ParentGroup) | Should -BeTrue
            $Names.ContainsKey($Row.ChildGroup) | Should -BeTrue
            [int] ($Row.ChildGroup -replace '^.*-', '') | Should -BeGreaterThan ([int] ($Row.ParentGroup -replace '^.*-', ''))
            if ($Row.ParentScope -eq 'Global') { $Row.ChildScope | Should -Be 'Global' }
            if ($Row.ParentScope -eq 'Universal') { $Row.ChildScope | Should -Not -Be 'Domain Local' }
        }
    }

    It 'supports configurable thresholds and rejects invalid definitions' {
        $Adjusted = New-PSIADGroupSampleData -GroupCount 250 -Thresholds @{ LargeGroupMemberThreshold=400; EmptyGroupMaximumMembers=2 }
        $Adjusted.GroupInventory.Count | Should -Be 250
        $Adjusted.Thresholds.LargeGroupMemberThreshold | Should -Be 400
        $Adjusted.Thresholds.EmptyGroupMaximumMembers | Should -Be 2
        { New-PSIADGroupSampleData -Thresholds @{ LargeGroupMemberThreshold=0 } } | Should -Throw
        { New-PSIADGroupSampleData -Thresholds @{ UnknownThreshold=1 } } | Should -Throw
        { New-PSIADGroupSampleData -Thresholds @{ EmptyGroupMaximumMembers=500 } } | Should -Throw
    }

    It 'builds aggregate chart counts from the inventory without embedding records again' {
        $Category = @(Get-PSIADGroupDistribution -Data $script:GroupSample.GroupInventory -Property GroupCategory)
        ($Category | Measure-Object -Property Count -Sum).Sum | Should -Be 320
        $Scope = @(Get-PSIADGroupDistribution -Data $script:GroupSample.GroupInventory -Property GroupScope)
        ($Scope | Measure-Object -Property Count -Sum).Sum | Should -Be 320
    }
}

Describe 'PSInsightHTML group assessment report' {
    BeforeAll {
        $script:GroupReportPath = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.html')
        & (Join-Path (Get-Location).Path 'Examples/ActiveDirectory/Groups/New-GroupAssessmentReport.ps1') -OutputPath $script:GroupReportPath -NoBrowser -Theme Dark | Out-Null
        $script:GroupHtml = [System.IO.File]::ReadAllText($script:GroupReportPath)
    }
    AfterAll {
        if (Test-Path -LiteralPath $script:GroupReportPath) { Remove-Item -LiteralPath $script:GroupReportPath -Force }
    }

    It 'renders the expected sections and fictional sample declaration' {
        foreach ($Title in @(
            'Executive Summary', 'Group Category and Scope', 'Membership Overview', 'Nested Group Analysis',
            'Empty and Large Groups', 'Disabled User Membership', 'Ownership and Data Quality',
            'Investigation Insights', 'Group Inventory', 'Membership Inventory',
            'Findings and Recommendations', 'Method and Data Handling'
        )) { $script:GroupHtml | Should -Match ([regex]::Escape($Title)) }
        $script:GroupHtml | Should -Match 'Fictional sample data only'
        $script:GroupHtml | Should -Match 'no live directory connection'
        $script:GroupHtml | Should -Match 'data-theme="Dark"'
        $script:GroupHtml | Should -Match 'data-psi-theme="Auto"'
    }

    It 'renders each substantial dataset once as one registered table source' {
        foreach ($Entry in @(@('group-inventory', 320), @('group-memberships', 5421), @('group-nesting', 125))) {
            $Id = $Entry[0]
            $Markup = [regex]::Match($script:GroupHtml, '<section class="psi-table-card" id="' + $Id + '".*?</section>', [System.Text.RegularExpressions.RegexOptions]::Singleline).Value
            $Markup | Should -Not -BeNullOrEmpty
            ([regex]::Matches($Markup, '<tr data-psi-data-row>')).Count | Should -Be $Entry[1]
            ([regex]::Matches($script:GroupHtml, 'id="' + $Id + '"')).Count | Should -Be 1
        }
        $script:GroupHtml | Should -Not -Match 'data-psi-records='
    }

    It 'renders eight observation KPIs and routes numeric actions to multiselect table filters' {
        ([regex]::Matches($script:GroupHtml, 'class="psi-kpi-card')).Count | Should -Be 8
        ([regex]::Matches($script:GroupHtml, 'data-psi-filter-action=')).Count | Should -Be 7
        $Actions = @([regex]::Matches($script:GroupHtml, 'data-psi-filter-action="([^"]+)"') | ForEach-Object {
            [System.Net.WebUtility]::HtmlDecode($_.Groups[1].Value) | ConvertFrom-Json
        })
        foreach ($Property in @('MemberCount', 'NestedGroupCount')) {
            @($Actions | Where-Object Property -eq $Property).Count | Should -BeGreaterThan 0
            $script:GroupHtml | Should -Match ('data-psi-filter-property="' + $Property + '"[^>]*data-psi-filter-type="MultiSelect"')
        }
    }

    It 'renders eight Insights with shared-table evidence and exports' {
        ([regex]::Matches($script:GroupHtml, 'data-psi-insight=')).Count | Should -Be 8
        foreach ($Title in @('Empty Groups', 'Large Groups', 'Groups With Disabled Members', 'Groups With Nested Groups', 'Groups Without Owner', 'Groups Missing Description', 'Disabled User Membership Records', 'Direct Nested Relationships')) {
            $script:GroupHtml | Should -Match ([regex]::Escape($Title))
        }
        foreach ($Id in @('group-inventory','group-memberships','group-nesting')) {
            $script:GroupHtml | Should -Match ('&quot;tableId&quot;:&quot;' + $Id + '&quot;')
        }
        $script:GroupHtml | Should -Match 'data-psi-export-scope="evidence"'
        $script:GroupHtml | Should -Match 'data-psi-dialog-backdrop'
    }

    It 'uses search, filters, sorting, pagination, charts, and export controls' {
        $script:GroupHtml | Should -Match 'data-psi-chart-filter='
        $script:GroupHtml | Should -Match 'data-psi-filter-property="GroupCategory"'
        $script:GroupHtml | Should -Match 'data-psi-filter-property="GroupScope"'
        $script:GroupHtml | Should -Match 'data-psi-filter-property="HasOwner"'
        $script:GroupHtml | Should -Match 'data-psi-filter-property="MemberCount"'
        $script:GroupHtml | Should -Match 'data-psi-filter-property="NestedGroupCount"'
        $script:GroupHtml | Should -Match 'data-psi-filter-property="MemberType"'
        $script:GroupHtml | Should -Match 'data-psi-filter-property="MemberEnabled"'
        $script:GroupHtml | Should -Match 'data-psi-search'
        $script:GroupHtml | Should -Match 'data-psi-sort='
        $script:GroupHtml | Should -Match 'data-psi-pagination'
        foreach ($Format in @('csv','xlsx','print')) { $script:GroupHtml | Should -Match ('data-psi-export-format="' + $Format + '"') }
        $script:GroupHtml | Should -Match '@media print'
    }

    It 'uses explicit export field allowlists and keeps source-only DNs out of the report' {
        $GroupMarkup = [regex]::Match($script:GroupHtml, '<section class="psi-table-card" id="group-inventory".*?</section>', [System.Text.RegularExpressions.RegexOptions]::Singleline).Value
        $ExportAttribute = [regex]::Match($GroupMarkup, 'data-psi-export-config="([^"]+)"').Groups[1].Value
        $Export = [System.Net.WebUtility]::HtmlDecode($ExportAttribute) | ConvertFrom-Json
        @($Export.columns) | Should -Contain 'GroupName'
        @($Export.columns) | Should -Not -Contain 'DistinguishedName'
        @($Export.columns) | Should -Not -Contain 'HasOwner'
        $script:GroupHtml | Should -Not -Match 'OU=Sample Groups,DC=corp,DC=example,DC=invalid'
        $script:GroupHtml | Should -Not -Match 'OU=Sample Users,DC=corp,DC=example,DC=invalid'
        $script:GroupHtml | Should -Match 'LargeGroupMemberThreshold = 500'
        $script:GroupHtml | Should -Match 'EmptyGroupMaximumMembers = 0'
    }

    It 'is standalone and contains no network dependency or duplicate bulk metadata' {
        $script:GroupHtml | Should -Match '<style>'
        $script:GroupHtml | Should -Match '<script>'
        $script:GroupHtml | Should -Not -Match '<script\s+[^>]*src\s*=|<link\s+[^>]*href\s*=|<img\s+[^>]*src\s*=|\bfetch\s*\('
        $script:GroupHtml | Should -Not -Match 'data-psi-records='
    }
}
