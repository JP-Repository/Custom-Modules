$script:SitesSubnetsProjectRoot = Split-Path $PSScriptRoot -Parent

Describe 'PSInsightHTML fictional Sites and Subnets provider' {
    BeforeAll {
        $script:SitesSubnetsProjectRoot = (Get-Location).Path
        . (Join-Path $script:SitesSubnetsProjectRoot 'Providers/ActiveDirectory/SitesSubnets/Private/PSIADSitesSubnets.Provider.ps1')
        $script:Topology = New-PSIADSitesSubnetsSampleData
    }

    It 'generates deterministic, normalized, demo-safe topology datasets' {
        $Again = New-PSIADSitesSubnetsSampleData
        $script:Topology.Source | Should -Match 'Fictional sample data only; no live directory connection'
        $script:Topology.SiteInventory.Count | Should -Be 8
        $script:Topology.SubnetInventory.Count | Should -Be 60
        $script:Topology.DomainControllerPlacement.Count | Should -Be 56
        $script:Topology.SiteLinkInventory.Count | Should -Be 6
        $script:Topology.SubnetOverlapEvidence.Count | Should -Be 17
        $script:Topology.SiteLinkMembership.Count | Should -Be 18
        ($Again.DomainControllerPlacement | ConvertTo-Json -Depth 4) | Should -Be ($script:Topology.DomainControllerPlacement | ConvertTo-Json -Depth 4)
        @($script:Topology.DomainControllerPlacement.DCName | Select-Object -Unique).Count | Should -Be 56
        $script:Topology.DomainControllerPlacement.DCName | Should -Match 'example.invalid'
    }

    It 'canonicalizes CIDR ranges and chooses the longest prefix, independent of source order' {
        $Broad = ConvertTo-PSIADSubnetDefinition -CIDR '10.77.2.7/28' -SiteName East
        $Narrow = ConvertTo-PSIADSubnetDefinition -CIDR '10.77.2.1/29' -SiteName West
        $Broad.SubnetCIDR | Should -Be '10.77.2.0/28'
        $Narrow.RangeEnd | Should -Be 172818951
        (Find-PSIADBestSubnetMatch -IPv4Address '10.77.2.1' -Subnets @($Broad,$Narrow)).Best.SiteName | Should -Be West
        (Find-PSIADBestSubnetMatch -IPv4Address '10.77.2.1' -Subnets @($Narrow,$Broad)).Best.SiteName | Should -Be West
        (Find-PSIADBestSubnetMatch -IPv4Address '10.77.2.10' -Subnets @($Narrow,$Broad)).Best.SiteName | Should -Be East
        { ConvertTo-PSIADSubnetDefinition -CIDR '10.77.2.0/33' -SiteName East } | Should -Throw
        { ConvertTo-PSIADSubnetDefinition -CIDR '10.77.256.0/24' -SiteName East } | Should -Throw
    }

    It 'distinguishes no match, configured-site mismatch, and equal-prefix ambiguity' {
        $NoMatch = $script:Topology.DomainControllerPlacement | Where-Object SiteAssignmentState -eq 'NoSubnetMatch'
        @($NoMatch).Count | Should -Be 1
        $NoMatch[0].MatchedSubnet | Should -BeNullOrEmpty
        @($script:Topology.DomainControllerPlacement | Where-Object SiteAssignmentState -eq 'SiteMismatch').Count | Should -Be 3
        $A = ConvertTo-PSIADSubnetDefinition -CIDR '10.99.0.0/24' -SiteName North
        $B = ConvertTo-PSIADSubnetDefinition -CIDR '10.99.0.0/24' -SiteName South
        (Find-PSIADBestSubnetMatch -IPv4Address '10.99.0.4' -Subnets @($A,$B)).IsAmbiguous | Should -BeTrue
        (Find-PSIADBestSubnetMatch -IPv4Address '10.88.0.4' -Subnets @($A,$B)).Best | Should -BeNullOrEmpty
    }

    It 'records overlap evidence separately and identifies cross-site overlap' {
        @($script:Topology.SubnetOverlapEvidence | Where-Object CrossSite -eq Yes).Count | Should -BeGreaterThan 0
        @($script:Topology.SubnetOverlapEvidence | Where-Object CrossSite -eq No).Count | Should -BeGreaterThan 0
        @($script:Topology.SubnetInventory | Where-Object CrossSiteOverlap -eq Yes).Count | Should -BeGreaterThan 0
        $script:Topology.SubnetInventory[0].PSObject.Properties.Name | Should -Not -Contain 'RangeStart'
    }

    It 'keeps link membership and provider rule thresholds consistent' {
        foreach ($Link in $script:Topology.SiteLinkInventory) {
            @($script:Topology.SiteLinkMembership | Where-Object SiteLinkName -eq $Link.SiteLinkName).Count | Should -Be $Link.SiteCount
        }
        @($script:Topology.SiteInventory | Where-Object HasDomainController -eq No).Count | Should -Be 1
        @($script:Topology.SiteInventory | Where-Object DomainControllerCount -eq 1).Count | Should -Be 1
        @($script:Topology.SiteInventory | Where-Object HasSiteLink -eq No).Count | Should -Be 2
        $Other = New-PSIADSitesSubnetsSampleData -Rules @{HighSiteLinkCostThreshold=300;LongReplicationIntervalMinutes=240;ExpectedMinimumDCsPerSite=2}
        @($Other.SiteLinkInventory | Where-Object CostBand -eq 'At or above threshold').Count | Should -Be 1
        @($Other.SiteInventory | Where-Object TopologyState -eq 'Review candidate').Count | Should -Be 2
        { New-PSIADSitesSubnetsSampleData -Rules @{HighSiteLinkCostThreshold=0} } | Should -Throw
        { New-PSIADSitesSubnetsSampleData -Rules @{UnknownRule=1} } | Should -Throw
    }

    It 'produces chart aggregate counts consistent with the source dataset' {
        $SiteDistribution = @(Get-PSIADSitesSubnetsDistribution -Data $script:Topology.DomainControllerPlacement -Property ConfiguredSite)
        ($SiteDistribution | Measure-Object Count -Sum).Sum | Should -Be 56
        $PrefixDistribution = @(Get-PSIADSitesSubnetsDistribution -Data $script:Topology.SubnetInventory -Property PrefixLength)
        ($PrefixDistribution | Measure-Object Count -Sum).Sum | Should -Be 60
    }
}

Describe 'PSInsightHTML Sites and Subnets assessment report' {
    BeforeAll {
        $script:SitesSubnetsProjectRoot = (Get-Location).Path
        $script:SitesSubnetsReportScript = Join-Path $script:SitesSubnetsProjectRoot 'Examples/ActiveDirectory/SitesSubnets/New-SitesSubnetsAssessmentReport.ps1'
        $script:SitesSubnetsTempReport = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.html')
        & $script:SitesSubnetsReportScript -OutputPath $script:SitesSubnetsTempReport -Theme Dark -NoBrowser | Out-Null
        $script:SitesSubnetsHtml = [System.IO.File]::ReadAllText($script:SitesSubnetsTempReport)
    }
    AfterAll {
        if ($script:SitesSubnetsTempReport -and (Test-Path $script:SitesSubnetsTempReport)) { Remove-Item $script:SitesSubnetsTempReport -Force }
    }

    It 'renders the requested sections and explicit fictional-data and threshold disclosures' {
        foreach ($Title in @('Executive Summary','Site Overview','Domain Controller Placement','Subnet Coverage','Subnet Overlap Analysis','Site Link Configuration','Topology Observations','Investigation Insights','Site Inventory','Subnet Inventory','Domain Controller Placement Inventory','Site Link Inventory','Findings and Recommendations','Method and Data Handling')) {
            $script:SitesSubnetsHtml | Should -Match ([regex]::Escape($Title))
        }
        $script:SitesSubnetsHtml | Should -Match 'Fictional sample data only'
        $script:SitesSubnetsHtml | Should -Match 'ExpectedMinimumDCsPerSite = 1'
        $script:SitesSubnetsHtml | Should -Match 'HighSiteLinkCostThreshold = 200'
        $script:SitesSubnetsHtml | Should -Match 'LongReplicationIntervalMinutes = 180'
        $script:SitesSubnetsHtml | Should -Match 'data-theme="Dark"'
        $script:SitesSubnetsHtml | Should -Match 'data-psi-theme="Auto"'
    }

    It 'renders each normalized dataset exactly once and uses no repeated bulk payload' {
        $Expected = @{'ss-sites'=8;'ss-subnets'=60;'ss-dcs'=56;'ss-links'=6;'ss-overlaps'=17;'ss-membership'=18}
        foreach ($Id in $Expected.Keys) {
            $Markup = [regex]::Match($script:SitesSubnetsHtml, '<section class="psi-table-card" id="' + $Id + '".*?</section>', [System.Text.RegularExpressions.RegexOptions]::Singleline).Value
            $Markup | Should -Not -BeNullOrEmpty
            ([regex]::Matches($Markup, '<tr data-psi-data-row>')).Count | Should -Be $Expected[$Id]
            ([regex]::Matches($script:SitesSubnetsHtml, 'id="' + $Id + '"')).Count | Should -Be 1
        }
        $script:SitesSubnetsHtml | Should -Not -Match 'data-psi-records='
    }

    It 'provides nine reference-based Insights and the existing Evidence Viewer controls' {
        ([regex]::Matches($script:SitesSubnetsHtml, 'data-psi-insight=')).Count | Should -Be 9
        foreach ($Title in @('DCs Without Matching Subnet','DC Site Assignment Mismatches','Overlapping Subnets','Cross-Site Overlapping Subnets','Sites Without Domain Controllers','Sites With Single Domain Controller','High-Cost Site Links','Long Replication Interval Site Links','Sites Missing Site-Link Participation')) {
            $script:SitesSubnetsHtml | Should -Match ([regex]::Escape($Title))
        }
        $script:SitesSubnetsHtml | Should -Match 'data-psi-export-scope="evidence"'
        $script:SitesSubnetsHtml | Should -Match 'data-psi-dialog-search'
    }

    It 'uses table search, filters, sorting, pagination, chart filtering, and explicit export allowlists' {
        $script:SitesSubnetsHtml | Should -Match 'data-psi-search'
        $script:SitesSubnetsHtml | Should -Match 'data-psi-pagination'
        $script:SitesSubnetsHtml | Should -Match 'data-psi-chart-filter='
        $script:SitesSubnetsHtml | Should -Match 'data-psi-filter-property="SiteAssignmentState"'
        $script:SitesSubnetsHtml | Should -Match 'data-psi-export-format="csv"'
        $script:SitesSubnetsHtml | Should -Match 'data-psi-export-format="xlsx"'
        $script:SitesSubnetsHtml | Should -Match 'data-psi-export-format="print"'
        $script:SitesSubnetsHtml | Should -Match '@media print'
        foreach ($Id in @('ss-sites','ss-subnets','ss-dcs','ss-links','ss-overlaps','ss-membership')) {
            $Markup = [regex]::Match($script:SitesSubnetsHtml, '<section class="psi-table-card" id="' + $Id + '".*?</section>', [System.Text.RegularExpressions.RegexOptions]::Singleline).Value
            $ConfigMatch = [regex]::Match($Markup, 'data-psi-export-config="([^"]+)"')
            $ConfigMatch.Success | Should -BeTrue
            $Config = [System.Net.WebUtility]::HtmlDecode($ConfigMatch.Groups[1].Value) | ConvertFrom-Json
            @($Config.columns).Count | Should -BeGreaterThan 0
            @($Config.columns) | Should -Not -Contain 'RangeStart'
            @($Config.columns) | Should -Not -Contain 'RangeEnd'
        }
    }

    It 'is self-contained with no fetch or external asset references' {
        $script:SitesSubnetsHtml | Should -Match '<style>'
        $script:SitesSubnetsHtml | Should -Match '<script>'
        $script:SitesSubnetsHtml | Should -Not -Match '<script\s+[^>]*src\s*=|<link\s+[^>]*href\s*=|<img\s+[^>]*src\s*=|\bfetch\s*\('
    }
}
