$script:InsightModuleRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path -Path $script:InsightModuleRoot -ChildPath 'PSInsightHTML.psd1') -Force

Describe 'PSInsightHTML generic Insight and evidence engine' {
    BeforeAll { $script:InsightModuleRoot = (Get-Location).Path }
    It 'exports a reusable generic Add-PSIInsight component contract' {
        $Report = New-PSIReport -Title 'Insight contract'
        $Report | Add-PSISection -Title 'Signals' | Add-PSIRow | Add-PSIInsight `
            -Title 'Queue depth' -Value 14 -Description 'Fictional queue sample' -Status Warning -Icon 'warning' `
            -Filter @{ Table = 'sample-table'; Conditions = @([pscustomobject]@{ Property = 'State'; Operator = 'Equals'; Value = 'Warning' }) } `
            -EvidenceColumns @('Name', 'State') -ExportColumns @('Name') -ColumnLabels @{ Name = 'Resource name' }
        $Component = $Report.Sections[0].Rows[0].Components[0]
        $Component.Type | Should -Be 'Insight'
        $Component.Properties.Value | Should -Be 14
        $Component.Properties.Filter.Table | Should -Be 'sample-table'
        $Component.Properties.EvidenceColumns | Should -Be @('Name', 'State')
        $Component.Properties.ExportColumns | Should -Be @('Name')
        { $Report | Add-PSIRow | Add-PSIInsight -Title 'Bad' -Value 0 -Filter @{ Table = 'sample-table'; Conditions = @([pscustomobject]@{ Property = 'State'; Operator = 'Regex'; Value = 'x' }) } } | Should -Throw '*not supported*'
    }

    It 'renders reference-only evidence metadata and reuses the existing dialog shell' {
        $Report = New-PSIReport -Title 'Evidence & filters' -Theme Auto
        $Report | Add-PSISection -Title 'Generic signals' | Add-PSIRow | Add-PSIInsight `
            -Title 'Warnings <sample>' -Value 1 -Description 'Searchable evidence' -Status Warning `
            -Filter @{ Table = 'shared-records'; Conditions = @([pscustomobject]@{ Property = 'Status'; Operator = 'Equals'; Value = 'Warning' }) } `
            -EvidenceColumns @('Name', 'Status') -ExportColumns @('Name') | Out-Null
        $Report | Add-PSIRow | Add-PSITable -Id 'shared-records' -Title 'Shared records' -Data @([pscustomobject]@{ Name = 'Node A'; Status = 'Warning' }) -Columns @('Name', 'Status') | Out-Null
        $Path = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.html')
        try {
            $null = Export-PSIReport -Report $Report -Path $Path
            $Html = [System.IO.File]::ReadAllText($Path)
            $Html | Should -Match 'data-psi-insight=".*shared-records'
            $Html | Should -Match 'Warnings &lt;sample&gt;'
            $Html | Should -Match 'data-psi-dialog-backdrop'
            $Html | Should -Match 'data-psi-export-scope="evidence"'
            $Html | Should -Match 'data-psi-dialog-pagination'
            $Html | Should -Match 'data-psi-dialog-apply'
            $Html | Should -Not -Match 'data-psi-records=.*Node A'
            $Html | Should -Match 'PSIDataEngine'
            $Html | Should -Match 'PSIExport = \{'
            $Html | Should -Match 'data-psi-export-format="csv"'
            $Html | Should -Match 'data-psi-export-format="xlsx"'
            $Html | Should -Match 'data-psi-export-format="print"'
        }
        finally { if (Test-Path $Path) { Remove-Item $Path -Force } }
    }

    It 'keeps dataset records in one table representation and provides CSV escaping and UTF-8 download' {
        $Interaction = [System.IO.File]::ReadAllText((Join-Path $script:InsightModuleRoot 'Assets/JavaScript/psi-interactions.js'))
        $Table = [System.IO.File]::ReadAllText((Join-Path $script:InsightModuleRoot 'Assets/JavaScript/psi-table.js'))
        $Interaction | Should -Match 'window\.PSIExport\.attachToolbar'
        $Interaction | Should -Match 'records: filteredRecords'
        $Interaction | Should -Match 'columns: exportColumns'
        $Exporter = [System.IO.File]::ReadAllText((Join-Path $script:InsightModuleRoot 'Assets/JavaScript/psi-export.js'))
        $Exporter | Should -Match 'replace\(/"/g'
        $Exporter | Should -Match 'text/csv;charset=utf-8'
        $Exporter | Should -Match 'ufeff'
        $Exporter | Should -Match 'records\.forEach'
        $Table | Should -Match 'widget\.__psiRecords = records'
        $Table | Should -Match 'Object\.defineProperty\(values, name'
        $Table | Should -Match 'matches\(record, externalConditions\)'
        $Table | Should -Match 'detail\.conditions'
        $Table | Should -Match 'window\.PSIDataEngine\.datasets\[widget\.id\] = records'
        $Table | Should -Match 'widget\.__psiContext = function'
        $Table | Should -Match "case 'In':"
        $Interaction | Should -Match 'getContext\(definition\.tableId\)'
        $Interaction | Should -Match 'currentContextConditions'
    }

    It 'registers one table-backed dataset and carries active filters and search into evidence' {
        $Table = [System.IO.File]::ReadAllText((Join-Path $script:InsightModuleRoot 'Assets/JavaScript/psi-table.js'))
        $Interaction = [System.IO.File]::ReadAllText((Join-Path $script:InsightModuleRoot 'Assets/JavaScript/psi-interactions.js'))
        $Table | Should -Match 'window\.PSIDataEngine\.datasets\[widget\.id\] = records'
        $Table | Should -Match 'getRecords = function \(tableId\)'
        $Table | Should -Match 'controlConditions: controlConditions, searchText: searchText'
        $Interaction | Should -Match 'definition\.conditions \|\| \[\]\)\.concat\(currentContextConditions, context\.controlConditions'
        $Interaction | Should -Match 'record\.element\.textContent\.toLocaleLowerCase\(\)\.indexOf\(context\.searchText\)'
        $Interaction | Should -Match 'empty\.hidden = filteredRecords\.length > 0'
    }
}

Describe 'AD user inventory report-defined insight definitions' {
    BeforeAll {
        $script:InsightModuleRoot = (Get-Location).Path
        . (Join-Path $script:InsightModuleRoot 'Providers/ActiveDirectory/UserInventory/Private/PSIADUserInventory.Provider.ps1')
        $AsOf = [datetime]::new(2026, 9, 27)
        $Source = @(
            [pscustomobject]@{ displayName='Expired Enabled'; userPrincipalName='expired@example.invalid'; accountStatus='Enabled'; employeeType='Staff'; department='Ops'; physicalDeliveryOfficeName='HQ'; co='Example'; 'extensionAttribute3 (CloudSyncStatus)'='Synced'; pwdLastSet='2025-09-01 00:00:00'; lastLogonTimestamp='2026-01-01 00:00:00'; accountExpires='2026-09-01'; userAccountControl=66048 },
            [pscustomobject]@{ displayName='Stale'; userPrincipalName='stale@example.invalid'; accountStatus='Disabled'; employeeType='Staff'; department='Ops'; physicalDeliveryOfficeName='HQ'; co='Example'; 'extensionAttribute3 (CloudSyncStatus)'=''; pwdLastSet='2025-09-01 00:00:00'; lastLogonTimestamp='2026-01-01 00:00:00'; accountExpires='Never'; userAccountControl=512 },
            [pscustomobject]@{ displayName='Never logged'; userPrincipalName='never@example.invalid'; accountStatus='Enabled'; employeeType='Staff'; department='Ops'; physicalDeliveryOfficeName='HQ'; co='Example'; 'extensionAttribute3 (CloudSyncStatus)'=''; pwdLastSet='2025-09-01 00:00:00'; lastLogonTimestamp=''; accountExpires='Never'; userAccountControl=512 }
        )
        $script:InsightAnalysis = Get-PSIADUserInventoryAnalysis -Data $Source -AsOfDate $AsOf
        $script:InsightDefinitions = @(New-PSIADUserInventoryInsightDefinition -Analysis $script:InsightAnalysis -Thresholds @{ Stale90Days = 90; Stale180Days = 180; PasswordAgeDays = 365 })
    }

    It 'calculates enabled-expired, stale, never-logged-on, and missing sync from normalized records' {
        ($script:InsightDefinitions | Where-Object Title -eq 'Enabled + Expired').Value | Should -Be 1
        ($script:InsightDefinitions | Where-Object Title -eq ('Stale {0} 90 Days' -f [char] 0x2265)).Value | Should -Be 2
        ($script:InsightDefinitions | Where-Object Title -eq ('Stale {0} 180 Days' -f [char] 0x2265)).Value | Should -Be 2
        ($script:InsightDefinitions | Where-Object Title -eq 'Never Logged On').Value | Should -Be 1
        ($script:InsightDefinitions | Where-Object Title -eq 'Cloud Sync Missing').Value | Should -Be 2
        ($script:InsightDefinitions | Where-Object Title -eq ('Password {0} 365 Days' -f [char] 0x2265)).Value | Should -Be 2
        ($script:InsightDefinitions | Where-Object Title -eq 'Password Never Expires').Value | Should -Be 1
        @($script:InsightDefinitions).Count | Should -Be 8
    }

    It 'uses report thresholds and refuses inconsistent threshold configuration' {
        $Custom = @(New-PSIADUserInventoryInsightDefinition -Analysis $script:InsightAnalysis -Thresholds @{ Stale90Days = 200; Stale180Days = 300 })
        $Custom[1].Title | Should -Be ('Stale {0} 200 Days' -f [char] 0x2265)
        $Custom[1].Conditions[0].Value | Should -Be 200
        ($Custom | Where-Object Title -eq ('Password {0} 365 Days' -f [char] 0x2265)).Title | Should -Be ('Password {0} 365 Days' -f [char] 0x2265)
        { New-PSIADUserInventoryInsightDefinition -Analysis $script:InsightAnalysis -Thresholds @{ Stale90Days = 300; Stale180Days = 200 } } | Should -Throw '*greater than or equal*'
    }

    It 'uses the documented UAC flag only to derive a provider-level boolean and never exposes raw UAC by default' {
        $Flagged = $script:InsightAnalysis.Records | Where-Object UserPrincipalName -eq 'expired@example.invalid'
        $Flagged.PasswordNeverExpires | Should -BeTrue
        $Flagged.PSObject.Properties.Name | Should -Not -Contain 'userAccountControl'
        $script:InsightDefinitions[5].Conditions[0].Property | Should -Be 'PasswordNeverExpires'
        $script:InsightDefinitions[5].Conditions[0].Value | Should -BeTrue
    }
}
