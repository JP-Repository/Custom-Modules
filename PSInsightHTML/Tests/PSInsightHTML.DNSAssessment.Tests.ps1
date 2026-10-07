BeforeAll {
    . (Join-Path (Get-Location).Path 'Providers/ActiveDirectory/DNS/Private/PSIADDNS.Provider.ps1')
}

Describe 'PSInsightHTML fictional DNS provider' {
    BeforeAll { $script:DNSSample = New-PSIADDNSSampleData }

    It 'generates deterministic fictional datasets without a live connection' {
        $Again = New-PSIADDNSSampleData
        $script:DNSSample.DNSServerInventory.Count | Should -Be 56
        $script:DNSSample.DNSClientResolvers.Count | Should -Be 106
        $script:DNSSample.DNSZones.Count | Should -Be 24
        $script:DNSSample.DNSForwarders.Count | Should -Be 105
        $script:DNSSample.DNSConditionalForwarders.Count | Should -Be 12
        ($Again.DNSServerInventory[0] | ConvertTo-Json -Compress) | Should -Be ($script:DNSSample.DNSServerInventory[0] | ConvertTo-Json -Compress)
        $Again.DNSClientResolvers.Count | Should -Be 106
        @($script:DNSSample.DNSServerInventory | Where-Object { $_.ServerName -notlike '*.example.invalid' }).Count | Should -Be 0
    }

    It 'models root and child domains across eight sites with DNS-capable DCs' {
        @($script:DNSSample.DNSServerInventory.Domain | Sort-Object -Unique) | Should -Be @('branch.corp.example.invalid','corp.example.invalid')
        @($script:DNSSample.DNSServerInventory.Site | Sort-Object -Unique).Count | Should -Be 8
        @($script:DNSSample.DNSServerInventory | Where-Object IsDomainController -ne 'Yes').Count | Should -Be 0
        @($script:DNSSample.DNSServerInventory | Where-Object DNSServiceState -eq 'Running').Count | Should -BeGreaterThan 40
    }

    It 'keeps one resolver row per ordered address and reconciles server observations' {
        $KnownAddresses = @{}
        foreach ($Server in $script:DNSSample.DNSServerInventory) { $KnownAddresses[$Server.IPv4Address] = $true }
        foreach ($Server in $script:DNSSample.DNSServerInventory) {
            $Rows = @($script:DNSSample.DNSClientResolvers | Where-Object ServerName -eq $Server.ServerName)
            $Server.ResolverCount | Should -Be $Rows.Count
            $ExpectedOrders = if ($Rows.Count -gt 0) { @(1..$Rows.Count) } else { @() }
            @($Rows.ResolverOrder) | Should -Be $ExpectedOrders
            $Server.PublicResolverCount | Should -Be @($Rows | Where-Object IsPublicResolver -eq 'Yes').Count
            $Server.UnrecognizedResolverCount | Should -Be @($Rows | Where-Object ResolutionState -eq 'Unrecognized').Count
            $Server.HasPublicResolver | Should -Be $(if ($Server.PublicResolverCount -gt 0) { 'Yes' } else { 'No' })
            $Server.HasMixedResolvers | Should -Be $(if ($Server.PublicResolverCount -gt 0 -and @($Rows | Where-Object IsInternalResolver -eq 'Yes').Count -gt 0) { 'Yes' } else { 'No' })
        }
        @($script:DNSSample.DNSServerInventory | Where-Object ResolverCount -eq 0).Count | Should -BeGreaterThan 0
        @($script:DNSSample.DNSServerInventory | Where-Object ResolverCount -eq 1).Count | Should -BeGreaterThan 0
        @($script:DNSSample.DNSServerInventory | Where-Object HasDuplicateResolvers -eq 'Yes').Count | Should -BeGreaterThan 0
    }

    It 'classifies internal, external sample, loopback, and unrecognized addresses explicitly' {
        @($script:DNSSample.DNSClientResolvers.ResolverType | Sort-Object -Unique) | Should -Contain 'External sample'
        @($script:DNSSample.DNSClientResolvers.ResolverType | Sort-Object -Unique) | Should -Contain 'Unrecognized'
        @($script:DNSSample.DNSClientResolvers.ResolverType | Sort-Object -Unique) | Should -Contain 'Loopback'
        @($script:DNSSample.DNSClientResolvers.ResolverType | Sort-Object -Unique) | Should -Contain 'Self reference'
        foreach ($Resolver in $script:DNSSample.DNSClientResolvers) {
            if ($Resolver.IsPublicResolver -eq 'Yes') {
                @($script:DNSSample.ExternalSampleResolverAddresses) | Should -Contain $Resolver.ResolverAddress
                $Resolver.IsInternalResolver | Should -Be 'No'
            }
            if ($Resolver.ResolutionState -eq 'Unrecognized') {
                @($script:DNSSample.ExternalSampleResolverAddresses) | Should -Not -Contain $Resolver.ResolverAddress
                $Resolver.IsInternalResolver | Should -Be 'No'
            }
        }
    }

    It 'models AD-integrated, reverse, update, aging, and scope variations without policy verdicts' {
        @($script:DNSSample.DNSZones | Where-Object IsADIntegrated -eq 'Yes').Count | Should -BeGreaterThan 15
        @($script:DNSSample.DNSZones | Where-Object ReverseLookup -eq 'Yes').Count | Should -BeGreaterThan 0
        @($script:DNSSample.DNSZones | Where-Object DynamicUpdate -eq 'Nonsecure and secure').Count | Should -BeGreaterThan 0
        @($script:DNSSample.DNSZones | Where-Object AgingEnabled -eq 'No').Count | Should -BeGreaterThan 0
        @($script:DNSSample.DNSZones.ReplicationScope | Sort-Object -Unique) | Should -Be @('Domain','Forest','Not applicable')
        foreach ($Zone in $script:DNSSample.DNSZones) {
            if ($Zone.IsADIntegrated -eq 'No') { $Zone.ReplicationScope | Should -Be 'Not applicable' }
            if ($Zone.AgingEnabled -eq 'No') {
                $Zone.NoRefreshIntervalDays | Should -BeNullOrEmpty
                $Zone.RefreshIntervalDays | Should -BeNullOrEmpty
            }
        }
    }

    It 'reconciles standard forwarders with server counts and profile types' {
        foreach ($Server in $script:DNSSample.DNSServerInventory) {
            $Rows = @($script:DNSSample.DNSForwarders | Where-Object ServerName -eq $Server.ServerName)
            $Server.ForwarderCount | Should -Be $Rows.Count
            $Rows.Count | Should -BeGreaterThan 0
        }
        @($script:DNSSample.DNSForwarders | Where-Object IsPublic -eq 'Yes').Count | Should -BeGreaterThan 0
        @($script:DNSSample.DNSServerInventory.ForwarderProfile | Sort-Object -Unique).Count | Should -BeGreaterThan 2
    }

    It 'keeps conditional targets as separate rows and does not claim availability was tested' {
        @($script:DNSSample.DNSConditionalForwarders.ZoneName | Sort-Object -Unique).Count | Should -Be 6
        foreach ($Zone in @($script:DNSSample.DNSConditionalForwarders.ZoneName | Sort-Object -Unique)) {
            @($script:DNSSample.DNSConditionalForwarders | Where-Object ZoneName -eq $Zone).Count | Should -Be 2
        }
        @($script:DNSSample.DNSConditionalForwarders | Where-Object ForwarderState -eq 'Review candidate').Count | Should -BeGreaterThan 0
        @($script:DNSSample.DNSConditionalForwarders | Where-Object TargetVerification -ne 'Not checked').Count | Should -Be 0
    }

    It 'applies the configured resolver minimum and rejects unsupported rules' {
        $Adjusted = New-PSIADDNSSampleData -DNSServerCount 50 -Rules @{ MinimumResolverCount=3 }
        $Adjusted.DNSServerInventory.Count | Should -Be 50
        $Adjusted.Rules.MinimumResolverCount | Should -Be 3
        foreach ($Server in $Adjusted.DNSServerInventory) {
            $Server.BelowResolverMinimum | Should -Be $(if ($Server.ResolverCount -lt 3) { 'Yes' } else { 'No' })
        }
        { New-PSIADDNSSampleData -Rules @{ MinimumResolverCount=0 } } | Should -Throw
        { New-PSIADDNSSampleData -Rules @{ MinimumResolverCount=5 } } | Should -Throw
        { New-PSIADDNSSampleData -Rules @{ Unsupported=2 } } | Should -Throw
    }

    It 'creates small chart distributions whose counts match their source dataset' {
        ($script:DNSSample.DNSServerInventory | Measure-Object).Count | Should -Be 56
        $ResolverStates = @(Get-PSIADDNSDistribution -Data $script:DNSSample.DNSClientResolvers -Property ResolutionState)
        ($ResolverStates | Measure-Object -Property Count -Sum).Sum | Should -Be 106
        $ZoneTypes = @(Get-PSIADDNSDistribution -Data $script:DNSSample.DNSZones -Property ZoneType)
        ($ZoneTypes | Measure-Object -Property Count -Sum).Sum | Should -Be 24
    }
}

Describe 'PSInsightHTML DNS assessment report' {
    BeforeAll {
        $script:DNSReportPath = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.html')
        & (Join-Path (Get-Location).Path 'Examples/ActiveDirectory/DNS/New-DNSAssessmentReport.ps1') -OutputPath $script:DNSReportPath -NoBrowser -Theme Dark | Out-Null
        $script:DNSHtml = [System.IO.File]::ReadAllText($script:DNSReportPath)
    }
    AfterAll { if (Test-Path -LiteralPath $script:DNSReportPath) { Remove-Item -LiteralPath $script:DNSReportPath -Force } }

    It 'renders twelve sections and declares the fictional sample and rule' {
        foreach ($Title in @('Executive Summary','DNS Server Overview','DNS Client Resolver Analysis','Zone Configuration','Aging and Scavenging','Forwarder Analysis','Conditional Forwarders','Investigation Insights','DNS Server Inventory','Zone and Resolver Evidence','Findings and Recommendations','Method and Data Handling')) {
            $script:DNSHtml.Contains($Title) | Should -BeTrue
        }
        $script:DNSHtml.Contains('Fictional sample data only') | Should -BeTrue
        $script:DNSHtml.Contains('no live directory or DNS connection') | Should -BeTrue
        $script:DNSHtml.Contains('MinimumResolverCount = 2') | Should -BeTrue
        $script:DNSHtml.Contains('Target availability is Not checked') | Should -BeTrue
    }

    It 'renders each major dataset once without duplicating bulk data in cards or dialogs' {
        foreach ($Entry in @(@('dns-servers',56),@('dns-resolvers',106),@('dns-zones',24),@('dns-forwarders',105),@('dns-conditional-forwarders',12))) {
            $Id = $Entry[0]
            $Markup = [regex]::Match($script:DNSHtml, '<section class="psi-table-card" id="' + $Id + '".*?</section>', [System.Text.RegularExpressions.RegexOptions]::Singleline).Value
            $Markup | Should -Not -BeNullOrEmpty
            ([regex]::Matches($Markup, '<tr data-psi-data-row>')).Count | Should -Be $Entry[1]
            ([regex]::Matches($script:DNSHtml, 'id="' + $Id + '"')).Count | Should -Be 1
        }
        $script:DNSHtml.Contains('data-psi-records=') | Should -BeFalse
    }

    It 'renders eight KPIs, nine charts, and twelve reference-only Insights' {
        ([regex]::Matches($script:DNSHtml, 'class="psi-kpi-card')).Count | Should -Be 8
        ([regex]::Matches($script:DNSHtml, 'class="psi-chart-card')).Count | Should -Be 9
        ([regex]::Matches($script:DNSHtml, 'data-psi-insight=')).Count | Should -Be 12
        foreach ($Title in @('Servers With Public / External Resolvers','Unknown / Unrecognized Resolver Addresses','Servers With Only One Resolver','Mixed Internal + External Resolvers','Zones Without Aging','Servers Without Scavenging','Zones Allowing Nonsecure Dynamic Updates','Conditional Forwarder Review')) {
            $script:DNSHtml.Contains($Title) | Should -BeTrue
        }
        foreach ($Id in @('dns-servers','dns-resolvers','dns-zones','dns-conditional-forwarders')) {
            $script:DNSHtml.Contains('&quot;tableId&quot;:&quot;' + $Id + '&quot;') | Should -BeTrue
        }
        $script:DNSHtml.Contains('data-psi-dialog-backdrop') | Should -BeTrue
        $script:DNSHtml.Contains('data-psi-export-scope="evidence"') | Should -BeTrue
    }

    It 'uses existing filters, search, sorting, pagination, chart actions, and export controls' {
        $script:DNSHtml.Contains('data-psi-chart-filter=') | Should -BeTrue
        foreach ($Property in @('Site','ResolutionState','ResolverType','ZoneType','DynamicUpdate','ReplicationScope','AgingEnabled','ScavengingEnabled','ForwarderProfile','ForwarderState')) {
            $script:DNSHtml.Contains('data-psi-filter-property="' + $Property + '"') | Should -BeTrue
        }
        foreach ($Marker in @('data-psi-search','data-psi-sort=','data-psi-pagination','data-psi-export-format="csv"','data-psi-export-format="xlsx"','data-psi-export-format="print"','@media print')) {
            $script:DNSHtml.Contains($Marker) | Should -BeTrue
        }
    }

    It 'uses explicit export field allowlists on all five substantial tables' {
        foreach ($Id in @('dns-servers','dns-resolvers','dns-zones','dns-forwarders','dns-conditional-forwarders')) {
            $Markup = [regex]::Match($script:DNSHtml, '<section class="psi-table-card" id="' + $Id + '".*?</section>', [System.Text.RegularExpressions.RegexOptions]::Singleline).Value
            $Attribute = [regex]::Match($Markup, 'data-psi-export-config="([^"]+)"').Groups[1].Value
            $Attribute | Should -Not -BeNullOrEmpty
            $Config = [System.Net.WebUtility]::HtmlDecode($Attribute) | ConvertFrom-Json
            @($Config.columns).Count | Should -BeGreaterThan 0
        }
        $Markup = [regex]::Match($script:DNSHtml, '<section class="psi-table-card" id="dns-servers".*?</section>', [System.Text.RegularExpressions.RegexOptions]::Singleline).Value
        $Config = [System.Net.WebUtility]::HtmlDecode([regex]::Match($Markup, 'data-psi-export-config="([^"]+)"').Groups[1].Value) | ConvertFrom-Json
        @($Config.columns) | Should -Contain 'ServerName'
        @($Config.columns) | Should -Not -Contain 'HasPublicResolver'
        @($Config.columns) | Should -Not -Contain 'HasDuplicateResolvers'
        $script:DNSHtml.Contains('&quot;exportColumns&quot;:') | Should -BeTrue
    }

    It 'remains standalone and supports Light, Dark, and Auto without external dependencies' {
        $script:DNSHtml.StartsWith('<!DOCTYPE html>') | Should -BeTrue
        $script:DNSHtml.Contains('<style>') | Should -BeTrue
        $script:DNSHtml.Contains('<script>') | Should -BeTrue
        $script:DNSHtml.Contains('data-theme="Dark"') | Should -BeTrue
        foreach ($Theme in @('Light','Dark','Auto')) { $script:DNSHtml.Contains('data-psi-theme="' + $Theme + '"') | Should -BeTrue }
        [regex]::IsMatch($script:DNSHtml, '<script\s+[^>]*src\s*=|<link\s+[^>]*href\s*=|<img\s+[^>]*src\s*=|\bfetch\s*\(') | Should -BeFalse
    }
}
