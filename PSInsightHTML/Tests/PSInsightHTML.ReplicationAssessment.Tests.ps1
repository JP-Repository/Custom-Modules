BeforeAll {
    . (Join-Path (Get-Location).Path 'Providers/ActiveDirectory/Replication/Private/PSIADReplication.Provider.ps1')
}

Describe 'PSInsightHTML fictional replication provider' {
    BeforeAll { $script:ReplicationSample = New-PSIADReplicationSampleData }

    It 'generates the same fictional DCs, partner rows, and error rows on repeated runs' {
        $Again = New-PSIADReplicationSampleData
        $script:ReplicationSample.DomainControllerInventory.Count | Should -Be 56
        $script:ReplicationSample.ReplicationRelationships.Count | Should -Be 672
        $script:ReplicationSample.ReplicationErrors.Count | Should -Be 65
        $script:ReplicationSample.SiteReplicationSummary.Count | Should -Be 8
        $Again.ReplicationErrors.Count | Should -Be 65
        ($Again.ReplicationRelationships[0] | ConvertTo-Json -Compress) | Should -Be ($script:ReplicationSample.ReplicationRelationships[0] | ConvertTo-Json -Compress)
        @($script:ReplicationSample.DomainControllerInventory | Where-Object { $_.DCName -notlike '*.corp.example.invalid' }).Count | Should -Be 0
    }

    It 'models four naming contexts and unique source/destination partner relationships' {
        @($script:ReplicationSample.ReplicationRelationships.NamingContext | Sort-Object -Unique).Count | Should -Be 4
        @($script:ReplicationSample.ReplicationRelationships | Group-Object SourceDC,DestinationDC,NamingContext | Where-Object Count -ne 1).Count | Should -Be 0
        foreach ($Dc in $script:ReplicationSample.DomainControllerInventory) {
            $Dc.InboundPartnerCount | Should -Be 3
            $Outbound = @($script:ReplicationSample.ReplicationRelationships | Where-Object SourceDC -eq $Dc.DCName)
            $Dc.OutboundPartnerCount | Should -Be @($Outbound | Select-Object -ExpandProperty DestinationDC -Unique).Count
            $Inbound = @($script:ReplicationSample.ReplicationRelationships | Where-Object DestinationDC -eq $Dc.DCName)
            $Dc.FailingPartnerCount | Should -Be @($Inbound | Where-Object IsFailure -eq 'Yes' | Select-Object -ExpandProperty SourceDC -Unique).Count
        }
    }

    It 'calculates ages, current outcomes, recovered rows, and unknown successes consistently' {
        @($script:ReplicationSample.ReplicationRelationships.ReplicationState | Sort-Object -Unique) | Should -Be @('Critical','Healthy','Unknown','Warning')
        foreach ($Row in $script:ReplicationSample.ReplicationRelationships) {
            if ($null -eq $Row.LastSuccess) {
                $Row.ReplicationAgeMinutes | Should -BeNullOrEmpty
                $Row.AgeBucket | Should -Be 'Never successful'
            }
            else {
                $Calculated = [int] ($script:ReplicationSample.AsOfDate - [datetime]::ParseExact($Row.LastSuccess, 'yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)).TotalMinutes
                $Row.ReplicationAgeMinutes | Should -Be $Calculated
            }
            if ($Row.LastResultCode -eq 0) {
                $Row.ConsecutiveFailures | Should -Be 0
                $Row.IsFailure | Should -Be 'No'
                $Row.LastAttempt | Should -Be $Row.LastSuccess
            }
            else {
                $Row.ConsecutiveFailures | Should -BeGreaterThan 0
                $Row.IsFailure | Should -Be 'Yes'
            }
        }
        @($script:ReplicationSample.ReplicationRelationships | Where-Object RecoveryState -eq 'Recovered').Count | Should -BeGreaterThan 0
        @($script:ReplicationSample.ReplicationRelationships | Where-Object { $null -eq $_.LastSuccess }).Count | Should -BeGreaterThan 0
        @($script:ReplicationSample.ReplicationRelationships | Where-Object PartnerAvailability -eq 'Unavailable in sample').Count | Should -BeGreaterThan 0
    }

    It 'projects only current failures into the error dataset with reviewed code categories' {
        $Failures = @($script:ReplicationSample.ReplicationRelationships | Where-Object IsFailure -eq 'Yes')
        $Failures.Count | Should -Be $script:ReplicationSample.ReplicationErrors.Count
        @($script:ReplicationSample.ReplicationErrors.ErrorCode | Sort-Object -Unique) | Should -Be @(1722,8453,8524)
        @($script:ReplicationSample.ReplicationErrors.ErrorCategory | Sort-Object -Unique) | Should -Be @('Access','DNS','RPC')
        @($script:ReplicationSample.ReplicationErrors | Where-Object { $_.ConsecutiveFailures -lt 1 }).Count | Should -Be 0
    }

    It 'reconciles site summaries to destination relationship rows' {
        ($script:ReplicationSample.SiteReplicationSummary | Measure-Object -Property DomainControllerCount -Sum).Sum | Should -Be 56
        ($script:ReplicationSample.SiteReplicationSummary | Measure-Object -Property ReplicationRelationshipCount -Sum).Sum | Should -Be 672
        ($script:ReplicationSample.SiteReplicationSummary | Measure-Object -Property FailureCount -Sum).Sum | Should -Be 65
        foreach ($Site in $script:ReplicationSample.SiteReplicationSummary) {
            $Rows = @($script:ReplicationSample.ReplicationRelationships | Where-Object DestinationSite -eq $Site.SiteName)
            $Site.ReplicationRelationshipCount | Should -Be $Rows.Count
            ($Site.HealthyCount + $Site.WarningCount + $Site.CriticalCount + $Site.UnknownCount) | Should -Be $Rows.Count
            $Site.FailureCount | Should -Be @($Rows | Where-Object IsFailure -eq 'Yes').Count
        }
    }

    It 'applies only centrally configured thresholds and rejects invalid combinations' {
        $Adjusted = New-PSIADReplicationSampleData -DomainControllerCount 50 -Thresholds @{ WarningReplicationAgeMinutes=90; CriticalReplicationAgeMinutes=240; ConsecutiveFailureThreshold=4; MultipleFailingPartnerThreshold=3 }
        $Adjusted.DomainControllerInventory.Count | Should -Be 50
        $Adjusted.ReplicationRelationships.Count | Should -Be 600
        $Adjusted.Thresholds.WarningReplicationAgeMinutes | Should -Be 90
        $Adjusted.Thresholds.CriticalReplicationAgeMinutes | Should -Be 240
        foreach ($Row in $Adjusted.ReplicationRelationships) {
            $Expected = Get-PSIADReplicationState -AgeMinutes $Row.ReplicationAgeMinutes -LastResultCode $Row.LastResultCode -ConsecutiveFailures $Row.ConsecutiveFailures -Thresholds $Adjusted.Thresholds
            $Row.ReplicationState | Should -Be $Expected
        }
        { New-PSIADReplicationSampleData -Thresholds @{ WarningReplicationAgeMinutes=180 } } | Should -Throw
        { New-PSIADReplicationSampleData -Thresholds @{ ConsecutiveFailureThreshold=0 } } | Should -Throw
        { New-PSIADReplicationSampleData -Thresholds @{ MultipleFailingPartnerThreshold=1 } } | Should -Throw
        { New-PSIADReplicationSampleData -Thresholds @{ Unsupported=1 } } | Should -Throw
    }

    It 'builds small chart aggregates that reconcile to shared datasets' {
        $States = @(Get-PSIADReplicationDistribution -Data $script:ReplicationSample.ReplicationRelationships -Property ReplicationState)
        ($States | Measure-Object -Property Count -Sum).Sum | Should -Be 672
        $Codes = @(Get-PSIADReplicationDistribution -Data $script:ReplicationSample.ReplicationErrors -Property ErrorCode)
        ($Codes | Measure-Object -Property Count -Sum).Sum | Should -Be 65
    }
}

Describe 'PSInsightHTML replication assessment report' {
    BeforeAll {
        $script:ReplicationReportPath = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.html')
        & (Join-Path (Get-Location).Path 'Examples/ActiveDirectory/Replication/New-ReplicationAssessmentReport.ps1') -OutputPath $script:ReplicationReportPath -NoBrowser -Theme Dark | Out-Null
        $script:ReplicationHtml = [System.IO.File]::ReadAllText($script:ReplicationReportPath)
    }
    AfterAll { if (Test-Path -LiteralPath $script:ReplicationReportPath) { Remove-Item -LiteralPath $script:ReplicationReportPath -Force } }

    It 'renders twelve sections and declares sample data and report thresholds' {
        foreach ($Title in @(
            'Executive Summary','Domain Controller Overview','Replication Health Overview','Replication Age Analysis',
            'Replication Failure Analysis','Site Replication Analysis','Naming Context Analysis','Investigation Insights',
            'Replication Relationship Inventory','Error Evidence','Findings and Recommendations','Method and Thresholds'
        )) { $script:ReplicationHtml.Contains($Title) | Should -BeTrue }
        $script:ReplicationHtml.Contains('Fictional sample data only') | Should -BeTrue
        $script:ReplicationHtml.Contains('no live directory connection') | Should -BeTrue
        foreach ($Token in @('WarningReplicationAgeMinutes = 60','CriticalReplicationAgeMinutes = 180','ConsecutiveFailureThreshold = 3','MultipleFailingPartnerThreshold = 2')) {
            $script:ReplicationHtml.Contains($Token) | Should -BeTrue
        }
    }

    It 'renders each substantive dataset once and no bulk KPI or Insight payload' {
        foreach ($Entry in @(@('replication-dcs',56),@('replication-relationships',672),@('replication-errors',65),@('replication-sites',8))) {
            $Id = $Entry[0]
            $Markup = [regex]::Match($script:ReplicationHtml, '<section class="psi-table-card" id="' + $Id + '".*?</section>', [System.Text.RegularExpressions.RegexOptions]::Singleline).Value
            $Markup | Should -Not -BeNullOrEmpty
            ([regex]::Matches($Markup, '<tr data-psi-data-row>')).Count | Should -Be $Entry[1]
            ([regex]::Matches($script:ReplicationHtml, 'id="' + $Id + '"')).Count | Should -Be 1
        }
        $script:ReplicationHtml.Contains('data-psi-records=') | Should -BeFalse
    }

    It 'renders eight KPIs, six charts, and nine reference-only Insights' {
        ([regex]::Matches($script:ReplicationHtml, 'class="psi-kpi-card')).Count | Should -Be 8
        ([regex]::Matches($script:ReplicationHtml, 'class="psi-chart-card')).Count | Should -Be 6
        ([regex]::Matches($script:ReplicationHtml, 'data-psi-insight=')).Count | Should -Be 9
        foreach ($Title in @('Replication Failures','Repeated Consecutive Failures','Age at Warning Threshold','Age at Critical Threshold','RPC-coded Failures','Inter-site Replication Issues','DCs With Multiple Failing Partners','Never Successful / Missing Last Success','Recovered After Previous Failures')) {
            $script:ReplicationHtml.Contains($Title) | Should -BeTrue
        }
        foreach ($Id in @('replication-dcs','replication-relationships','replication-errors')) {
            $script:ReplicationHtml.Contains('&quot;tableId&quot;:&quot;' + $Id + '&quot;') | Should -BeTrue
        }
        $script:ReplicationHtml.Contains('data-psi-dialog-backdrop') | Should -BeTrue
        $script:ReplicationHtml.Contains('data-psi-export-scope="evidence"') | Should -BeTrue
    }

    It 'uses existing chart filters, table controls, and export formats' {
        $script:ReplicationHtml.Contains('data-psi-chart-filter=') | Should -BeTrue
        foreach ($Property in @('ReplicationState','SourceSite','DestinationSite','NamingContextLabel','LastResultCode','LinkType','AgeBucket','IsFailure','CriticalAge','ErrorCode')) {
            $script:ReplicationHtml.Contains('data-psi-filter-property="' + $Property + '"') | Should -BeTrue
        }
        foreach ($Markup in @('data-psi-search','data-psi-sort=','data-psi-pagination','data-psi-export-format="csv"','data-psi-export-format="xlsx"','data-psi-export-format="print"','@media print')) {
            $script:ReplicationHtml.Contains($Markup) | Should -BeTrue
        }
    }

    It 'uses explicit table and evidence export allowlists' {
        foreach ($Id in @('replication-dcs','replication-relationships','replication-errors','replication-sites')) {
            $Markup = [regex]::Match($script:ReplicationHtml, '<section class="psi-table-card" id="' + $Id + '".*?</section>', [System.Text.RegularExpressions.RegexOptions]::Singleline).Value
            $ConfigAttribute = [regex]::Match($Markup, 'data-psi-export-config="([^"]+)"').Groups[1].Value
            $ConfigAttribute | Should -Not -BeNullOrEmpty
            $Config = [System.Net.WebUtility]::HtmlDecode($ConfigAttribute) | ConvertFrom-Json
            @($Config.columns).Count | Should -BeGreaterThan 0
        }
        $RelationshipMarkup = [regex]::Match($script:ReplicationHtml, '<section class="psi-table-card" id="replication-relationships".*?</section>', [System.Text.RegularExpressions.RegexOptions]::Singleline).Value
        $ExportAttribute = [regex]::Match($RelationshipMarkup, 'data-psi-export-config="([^"]+)"').Groups[1].Value
        $Config = [System.Net.WebUtility]::HtmlDecode($ExportAttribute) | ConvertFrom-Json
        @($Config.columns) | Should -Contain 'SourceDC'
        @($Config.columns) | Should -Contain 'LastResultCode'
        @($Config.columns) | Should -Not -Contain 'ErrorCategory'
        $script:ReplicationHtml.Contains('&quot;exportColumns&quot;:') | Should -BeTrue
    }

    It 'is a standalone Light/Dark/Auto report without external assets or fetch' {
        $script:ReplicationHtml.StartsWith('<!DOCTYPE html>') | Should -BeTrue
        $script:ReplicationHtml.Contains('<style>') | Should -BeTrue
        $script:ReplicationHtml.Contains('<script>') | Should -BeTrue
        $script:ReplicationHtml.Contains('data-theme="Dark"') | Should -BeTrue
        foreach ($Theme in @('Light','Dark','Auto')) { $script:ReplicationHtml.Contains('data-psi-theme="' + $Theme + '"') | Should -BeTrue }
        [regex]::IsMatch($script:ReplicationHtml, '<script\s+[^>]*src\s*=|<link\s+[^>]*href\s*=|<img\s+[^>]*src\s*=|\bfetch\s*\(') | Should -BeFalse
    }
}
