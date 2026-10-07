$script:PSInsightHTMLProjectRoot = (Get-Location).Path

Describe 'PSInsightHTML AD user inventory example' {
    BeforeAll {
        $script:PSInsightHTMLProjectRoot = (Get-Location).Path
        $script:ADInventoryProviderPath = Join-Path -Path $script:PSInsightHTMLProjectRoot -ChildPath 'Providers/ActiveDirectory/UserInventory/Private/PSIADUserInventory.Provider.ps1'
        $script:ADInventoryReportPath = Join-Path -Path $script:PSInsightHTMLProjectRoot -ChildPath 'Examples/New-ADUserInventoryReport.ps1'
        $script:ADInventoryWorkbookPath = Join-Path -Path $script:PSInsightHTMLProjectRoot -ChildPath 'Examples/Data/Active_Directory_Enterprise_User_Inventory_5000.xlsx'
        . $script:ADInventoryProviderPath
        $script:ADInventorySource = @(Import-PSIADUserInventoryWorkbook -Path $script:ADInventoryWorkbookPath)
        $script:ADInventoryAsOf = [datetime]::new(2026, 9, 27)
        $script:ADInventoryAnalysis = Get-PSIADUserInventoryAnalysis -Data $script:ADInventorySource -AsOfDate $script:ADInventoryAsOf
        $script:ADInventoryInsightDefinitions = @(New-PSIADUserInventoryInsightDefinition -Analysis $script:ADInventoryAnalysis)
        $script:ADInventoryReportOutput = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([guid]::NewGuid().ToString() + '.html')
        & $script:ADInventoryReportPath -WorkbookPath $script:ADInventoryWorkbookPath -OutputPath $script:ADInventoryReportOutput `
            -AsOfDate $script:ADInventoryAsOf -Theme Dark -NoBrowser | Out-Null
        $script:ADInventoryHtml = [System.IO.File]::ReadAllText($script:ADInventoryReportOutput)
    }

    AfterAll {
        if ($script:ADInventoryReportOutput -and (Test-Path -LiteralPath $script:ADInventoryReportOutput)) {
            Remove-Item -LiteralPath $script:ADInventoryReportOutput -Force
        }
    }

    It 'imports the selected worksheet as 5,000 generic records and retains field types' {
        $script:ADInventorySource.Count | Should -Be 5000
        @($script:ADInventorySource[0].PSObject.Properties).Count | Should -Be 43
        $script:ADInventorySource[0].userAccountControl | Should -BeOfType [long]
        $script:ADInventorySource[0].pwdLastSet | Should -BeOfType [string]
        $script:ADInventorySource[0].PSObject.Properties.Name | Should -Contain 'extensionAttribute15 (Unused)'
        { Import-PSIADUserInventoryWorkbook -Path $script:ADInventoryWorkbookPath -WorksheetName 'Missing Worksheet' } | Should -Throw '*was not found*'
    }

    It 'normalizes ISO timestamps before calculating age and treats Never as a non-date sentinel' {
        $ParsedDate = ConvertTo-PSIADInventoryDate -Value '2026-09-01 12:30:00'
        $ParsedDate | Should -BeOfType [datetime]
        $ParsedDate.ToString('yyyy-MM-dd HH:mm:ss') | Should -Be '2026-09-01 12:30:00'
        (ConvertTo-PSIADInventoryDate -Value 'Never') | Should -BeNullOrEmpty
        { ConvertTo-PSIADInventoryDate -Value 'not a date' } | Should -Throw '*ISO format*'

        $script:ADInventoryAnalysis.UserCount | Should -Be 5000
        $script:ADInventoryAnalysis.PasswordDateCount | Should -Be 5000
        $script:ADInventoryAnalysis.LastLogonDateCount | Should -Be 5000
        $script:ADInventoryAnalysis.ExpirationStates.Never | Should -Be 3497
        $script:ADInventoryAnalysis.EnabledCount | Should -Be 4289
        $script:ADInventoryAnalysis.DisabledCount | Should -Be 711
        $script:ADInventoryAnalysis.Findings.Count | Should -Be 0
    }

    It 'calculates findings only from explicitly supplied positive thresholds' {
        $Sample = [pscustomobject]@{
            sAMAccountName = 'sample.user'
            userPrincipalName = 'sample.user@example.invalid'
            displayName = 'Sample User'
            accountStatus = 'Enabled'
            employeeType = 'Employee'
            department = 'Operations'
            company = 'Sample'
            physicalDeliveryOfficeName = 'HQ'
            co = 'Example Country'
            userAccountControl = 512
            pwdLastSet = '2026-01-01 00:00:00'
            lastLogonTimestamp = '2025-12-01 00:00:00'
            accountExpires = '2026-09-29'
            'extensionAttribute3 (CloudSyncStatus)' = 'Synced'
        }
        $Analysis = Get-PSIADUserInventoryAnalysis -Data @($Sample) -AsOfDate $script:ADInventoryAsOf `
            -Thresholds @{ PasswordAgeWarningDays = 90; InactiveUserWarningDays = 90; AccountExpiryWarningDays = 3 }

        $Analysis.Findings.Count | Should -Be 3
        @($Analysis.Findings.Finding | Select-Object -Unique).Count | Should -Be 3
        { Get-PSIADUserInventoryAnalysis -Data @($Sample) -AsOfDate $script:ADInventoryAsOf -Thresholds @{ PasswordAgeWarningDays = 0 } } | Should -Throw '*positive whole number*'
        { Get-PSIADUserInventoryAnalysis -Data @($Sample) -AsOfDate $script:ADInventoryAsOf -Thresholds @{ UnknownRule = 90 } } | Should -Throw '*Unsupported report threshold*'
    }

    It 'derives supported quick-view counts from the full inventory using the configured report date' {
        ($script:ADInventoryInsightDefinitions | Where-Object Title -eq 'Enabled + Expired').Value | Should -Be 0
        ($script:ADInventoryInsightDefinitions | Where-Object Title -eq 'Cloud Sync Missing').Value | Should -Be 399
        ($script:ADInventoryInsightDefinitions | Where-Object Title -eq 'Never Logged On').Value | Should -Be 0
        ($script:ADInventoryInsightDefinitions | Where-Object Title -eq 'Password Never Expires').Value | Should -Be 1269
        @($script:ADInventoryInsightDefinitions | Where-Object Title -like 'Password ≥*').Count | Should -Be 1
    }

    It 'profiles blank source fields without declaring optional blanks to be failures' {
        $Profile = @(Get-PSIADUserInventoryEmptyFieldProfile -Data $script:ADInventorySource)
        ($Profile | Where-Object Field -eq 'mobile').EmptyCount | Should -Be 1251
        ($Profile | Where-Object Field -eq 'extensionAttribute9 (Unused)').EmptyCount | Should -Be 5000
        $script:ADInventoryHtml | Should -Match 'does not define requiredness'
        $script:ADInventoryHtml | Should -Match 'Blank source cells'
    }

    It 'renders the requested components, filters, charts, and generic chart-to-table actions' {
        $script:ADInventoryHtml | Should -Match 'data-theme="Dark"'
        $script:ADInventoryHtml | Should -Match 'Enabled and Disabled Accounts'
        $script:ADInventoryHtml | Should -Match 'Accounts by Department'
        $script:ADInventoryHtml | Should -Match 'Accounts by Employee Type'
        $script:ADInventoryHtml | Should -Match 'Accounts by Country'
        $script:ADInventoryHtml | Should -Match 'Cloud Sync Status'
        foreach ($FilterProperty in @('AccountStatus', 'Department', 'EmployeeType', 'Country')) {
            $script:ADInventoryHtml | Should -Match "data-psi-filter-property=`"$FilterProperty`""
        }
        $script:ADInventoryHtml | Should -Match 'data-psi-chart-filter='
        $script:ADInventoryHtml | Should -Match 'data-psi-filter-action='
        $script:ADInventoryHtml | Should -Match 'data-psi-insight='
        $script:ADInventoryHtml | Should -Match 'Enabled \+ Expired'
        $script:ADInventoryHtml | Should -Match 'Stale ≥ 90 Days'
        $script:ADInventoryHtml | Should -Match 'Cloud Sync Missing'
        $script:ADInventoryHtml | Should -Match 'Password ≥ 365 Days'
        $script:ADInventoryHtml | Should -Match 'Password Never Expires'
        $script:ADInventoryHtml | Should -Match 'data-psi-export-scope="evidence"'
        $script:ADInventoryHtml | Should -Match 'Apply these filters to inventory'
        $script:ADInventoryHtml | Should -Not -Match 'data-psi-records='
        $script:ADInventoryHtml | Should -Match 'Expiration set to Never'
        $script:ADInventoryHtml | Should -Match 'Never is retained as a distinct state'
        $script:ADInventoryHtml | Should -Match 'No policy thresholds were supplied'
        $script:ADInventoryHtml | Should -Match 'No security findings or remediation recommendations were inferred'
    }

    It 'keeps the HTML field allowlist narrow and the report standalone' {
        $script:ADInventoryHtml | Should -Match 'data-psi-column="DisplayName"'
        $script:ADInventoryHtml | Should -Match 'data-psi-column="UserPrincipalName"'
        $script:ADInventoryHtml | Should -Not -Match '<th[^>]*>telephoneNumber'
        $script:ADInventoryHtml | Should -Not -Match '<th[^>]*>streetAddress'
        $script:ADInventoryHtml | Should -Not -Match '<th[^>]*>employeeID'
        $script:ADInventoryHtml | Should -Not -Match '<th[^>]*>distinguishedName'
        $script:ADInventoryHtml | Should -Not -Match '<script\s+[^>]*src\s*=|<link\s+[^>]*href\s*=|<img\s+[^>]*src\s*='
        $script:ADInventoryHtml | Should -Match '<style>'
        $script:ADInventoryHtml | Should -Match '<script>'
    }

    It 'keeps the complete inventory as one shared table-backed record source for Insight references' {
        $InventoryMarkup = [regex]::Match($script:ADInventoryHtml, '<section class="psi-table-card" id="ad-user-inventory".*?</section>', [System.Text.RegularExpressions.RegexOptions]::Singleline).Value
        ([regex]::Matches($InventoryMarkup, '<tr data-psi-data-row>')).Count | Should -Be 5000
        ([regex]::Matches($script:ADInventoryHtml, 'data-psi-insight=')).Count | Should -Be 8
        ([regex]::Matches($script:ADInventoryHtml, 'data-psi-records=')).Count | Should -Be 0
        ([regex]::Matches($script:ADInventoryHtml, 'id="ad-user-inventory"')).Count | Should -Be 1
    }
}
