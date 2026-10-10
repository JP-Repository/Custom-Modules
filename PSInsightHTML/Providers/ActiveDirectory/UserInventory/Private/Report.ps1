[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $WorkbookPath,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $OutputPath,

    [Parameter()]
    [ValidateSet('Light', 'Dark', 'Auto')]
    [string] $Theme = 'Auto',

    [Parameter()]
    [datetime] $AsOfDate = (Get-Date),

    [Parameter()]
    [hashtable] $Thresholds = @{},

    [Parameter()]
    [hashtable] $InsightThresholds = @{ Stale90Days = 90; Stale180Days = 180; PasswordAgeDays = 365 },

    [Parameter()]
    [switch] $NoBrowser,
    [Parameter()][switch] $AsAssessment
)

$ModuleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent
$ProviderPath = Join-Path -Path $PSScriptRoot -ChildPath 'PSIADUserInventory.Provider.ps1'
. $ProviderPath

if ([string]::IsNullOrWhiteSpace($WorkbookPath)) {
    $WorkbookPath = Join-Path -Path (Join-Path -Path $ModuleRoot -ChildPath 'Examples/Data') -ChildPath 'Active_Directory_Enterprise_User_Inventory_5000.xlsx'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path -Path (Join-Path -Path $ModuleRoot -ChildPath 'Reports') -ChildPath 'PSInsightHTML-ADUserInventory.html'
}

# Policy thresholds are intentionally unset unless supplied by the report owner.
# Each positive number is interpreted as an inclusive warning threshold in days.
$PolicyThresholds = [ordered]@{
    PasswordAgeWarningDays = $null
    InactiveUserWarningDays = $null
    AccountExpiryWarningDays = $null
}
foreach ($ThresholdName in $Thresholds.Keys) {
    if ($ThresholdName -notin @($PolicyThresholds.Keys)) {
        throw "Unsupported report threshold '$ThresholdName'. Supported values: $(@($PolicyThresholds.Keys) -join ', ')."
    }
    $PolicyThresholds[$ThresholdName] = $Thresholds[$ThresholdName]
}

$SourceRecords = @(Import-PSIADUserInventoryWorkbook -Path $WorkbookPath -WorksheetName 'AD_User_Accounts')
if ($SourceRecords.Count -eq 0) {
    throw "The AD user inventory worksheet in '$WorkbookPath' did not contain any user records."
}
$Analysis = Get-PSIADUserInventoryAnalysis -Data $SourceRecords -AsOfDate $AsOfDate -Thresholds $PolicyThresholds
$EmptyFieldProfile = @(Get-PSIADUserInventoryEmptyFieldProfile -Data $SourceRecords)
$EmptyCellCount = [int] (($EmptyFieldProfile | Measure-Object -Property EmptyCount -Sum).Sum)
$CompletelyEmptyFieldCount = @($EmptyFieldProfile | Where-Object { $_.EmptyCount -eq $SourceRecords.Count }).Count

# Build reusable assessment content through the shared component API.
$Report = New-PSIAssessment -Name 'User Inventory' -Provider 'ActiveDirectory' `
    -Title 'Active Directory User Inventory' `
    -Description 'Account lifecycle, organization, and data-quality overview'

$StatusFilter = Add-PSIFilter -Property 'AccountStatus' -Label 'Account status' -Values @($Analysis.Records | Select-Object -ExpandProperty AccountStatus -Unique | Sort-Object)
$DepartmentFilter = Add-PSIFilter -Property 'Department' -Label 'Department' -Values @($Analysis.Records | Select-Object -ExpandProperty Department -Unique | Sort-Object)
$EmployeeTypeFilter = Add-PSIFilter -Property 'EmployeeType' -Label 'Employee type' -Values @($Analysis.Records | Select-Object -ExpandProperty EmployeeType -Unique | Sort-Object)
$CountryFilter = Add-PSIFilter -Property 'Country' -Label 'Country' -Values @($Analysis.Records | Select-Object -ExpandProperty Country -Unique | Sort-Object)

# This is the reviewed HTML field allowlist. Source attributes such as phone,
# address, employee/badge IDs, manager DNs, VIP flags, and unused attributes
# remain outside the generated report.
$InventoryColumns = @(
    'DisplayName', 'UserPrincipalName', 'AccountStatus', 'EmployeeType',
    'Department', 'Office', 'Country', 'CloudSyncStatus',
    'PasswordLastSetDisplay', 'PasswordAgeDays', 'PasswordNeverExpires', 'LastLogonDisplay',
    'LastLogonAgeDays', 'AccountExpiresDisplay', 'ExpirationState'
)
$InventoryColumnLabels = @{
    DisplayName            = 'Display name'
    UserPrincipalName      = 'User principal name'
    AccountStatus          = 'Account status'
    EmployeeType           = 'Employee type'
    Department             = 'Department'
    Office                 = 'Office'
    Country                = 'Country'
    CloudSyncStatus        = 'Cloud sync status'
    PasswordLastSetDisplay = 'Password last set'
    PasswordAgeDays        = 'Password age (days)'
    PasswordNeverExpires   = 'Password never expires'
    LastLogonDisplay       = 'Last logon'
    LastLogonAgeDays       = 'Last logon age (days)'
    AccountExpiresDisplay  = 'Account expires'
    ExpirationState        = 'Expiration state'
}
$DrillDownColumns = @(
    'DisplayName', 'UserPrincipalName', 'AccountStatus', 'EmployeeType', 'Department', 'Office', 'Country',
    'CloudSyncStatus', 'PasswordLastSetDisplay', 'PasswordAgeDays', 'PasswordNeverExpires', 'LastLogonDisplay', 'LastLogonAgeDays',
    'AccountExpiresDisplay', 'ExpirationState'
)
$EvidenceColumns = @($DrillDownColumns)
$ExportColumns = @(
    'DisplayName', 'UserPrincipalName', 'AccountStatus', 'Department', 'Country', 'CloudSyncStatus',
    'PasswordLastSetDisplay', 'PasswordAgeDays', 'PasswordNeverExpires', 'LastLogonDisplay', 'LastLogonAgeDays',
    'AccountExpiresDisplay', 'ExpirationState'
)
$InsightDefinitions = @(New-PSIADUserInventoryInsightDefinition -Analysis $Analysis -Thresholds $InsightThresholds)
$PasswordAgeKpiValue = if ($null -ne $Analysis.PasswordAgeMedianDays) { '{0:N0} days' -f $Analysis.PasswordAgeMedianDays } else { 'No dates' }
$LastLogonAgeKpiValue = if ($null -ne $Analysis.LastLogonAgeMedianDays) { '{0:N0} days' -f $Analysis.LastLogonAgeMedianDays } else { 'No dates' }

$null = $Report |
    Add-PSISection -Title 'Executive Summary' |
    Add-PSIRow -Columns 12 |
    Add-PSIKPI -Title 'User accounts' -Value $Analysis.UserCount -Subtitle 'Records in the selected account worksheet' -Status Info -Icon 'users' |
    Add-PSIKPI -Title 'Enabled' -Value $Analysis.EnabledCount -Subtitle 'Select to filter the inventory' -Status Healthy -Icon 'healthy' `
        -Filter @{ Table = 'ad-user-inventory'; Property = 'AccountStatus'; Value = 'Enabled' } |
    Add-PSIKPI -Title 'Disabled' -Value $Analysis.DisabledCount -Subtitle 'Select to filter the inventory' -Status Info -Icon 'info' `
        -Filter @{ Table = 'ad-user-inventory'; Property = 'AccountStatus'; Value = 'Disabled' } |
    Add-PSIKPI -Title 'Departments' -Value @($Analysis.Records.Department | Select-Object -Unique).Count -Subtitle 'Distinct source department values' -Status Info -Icon 'domain'

$null = $Report |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text ("Source workbook: {0} $([char] 0x00B7) As of: {1} $([char] 0x00B7) Account status is reported as source data; Disabled is not automatically treated as a security finding." -f [System.IO.Path]::GetFileName($WorkbookPath), $Analysis.AsOfDate.ToString('yyyy-MM-dd'))

$null = $Report |
    Add-PSISection -Title 'Account Status' |
    Add-PSIRow -Columns 12 |
    Add-PSIStatus -Status Info -Label 'Source account state' -Message ("{0:N0} Enabled and {1:N0} Disabled accounts. The report does not infer risk severity from the Enabled/Disabled value." -f $Analysis.EnabledCount, $Analysis.DisabledCount) |
    Add-PSIRow -Columns 12 |
    Add-PSIChart -Title 'Enabled and Disabled Accounts' -ChartType Doughnut `
        -Data (New-PSIADUserInventoryDistribution -Data $Analysis.Records -Property 'AccountStatus') `
        -CategoryProperty 'Category' -ValueProperty 'Count' `
        -FilterMetadata @{ Table = 'ad-user-inventory'; Property = 'AccountStatus'; ValueProperty = 'Category' } `
        -Width 720 -Height 320 -ShowLegend $true -ShowLabels $true

$null = $Report |
    Add-PSISection -Title 'Organization and Synchronization' |
    Add-PSIRow -Columns 6 |
    Add-PSIChart -Title 'Accounts by Department' -ChartType Bar `
        -Data (New-PSIADUserInventoryDistribution -Data $Analysis.Records -Property 'Department') `
        -CategoryProperty 'Category' -ValueProperty 'Count' `
        -FilterMetadata @{ Table = 'ad-user-inventory'; Property = 'Department'; ValueProperty = 'Category' } `
        -Width 900 -Height 340 -ShowLegend $false -ShowLabels $false |
    Add-PSIChart -Title 'Accounts by Employee Type' -ChartType Doughnut `
        -Data (New-PSIADUserInventoryDistribution -Data $Analysis.Records -Property 'EmployeeType') `
        -CategoryProperty 'Category' -ValueProperty 'Count' `
        -FilterMetadata @{ Table = 'ad-user-inventory'; Property = 'EmployeeType'; ValueProperty = 'Category' } `
        -Width 720 -Height 320 -ShowLegend $true -ShowLabels $true

$null = $Report |
    Add-PSIRow -Columns 6 |
    Add-PSIChart -Title 'Accounts by Country' -ChartType Bar `
        -Data (New-PSIADUserInventoryDistribution -Data $Analysis.Records -Property 'Country') `
        -CategoryProperty 'Category' -ValueProperty 'Count' `
        -FilterMetadata @{ Table = 'ad-user-inventory'; Property = 'Country'; ValueProperty = 'Category' } `
        -Width 900 -Height 340 -ShowLegend $false -ShowLabels $false |
    Add-PSIChart -Title 'Cloud Sync Status' -ChartType Bar `
        -Data (New-PSIADUserInventoryDistribution -Data $Analysis.Records -Property 'CloudSyncStatus') `
        -CategoryProperty 'Category' -ValueProperty 'Count' `
        -FilterMetadata @{ Table = 'ad-user-inventory'; Property = 'CloudSyncStatus'; ValueProperty = 'Category' } `
        -Width 900 -Height 340 -ShowLegend $false -ShowLabels $false

$null = $Report |
    Add-PSISection -Title 'Password, Logon, and Expiration Analysis' |
    Add-PSIRow -Columns 12 |
    Add-PSIKPI -Title 'Median password age' -Value $PasswordAgeKpiValue `
        -Subtitle ("Based on {0:N0} parsed pwdLastSet values" -f $Analysis.PasswordDateCount) -Status Info -Icon 'security' |
    Add-PSIKPI -Title 'Median last-logon age' -Value $LastLogonAgeKpiValue `
        -Subtitle ("Based on {0:N0} parsed lastLogonTimestamp values" -f $Analysis.LastLogonDateCount) -Status Info -Icon 'users' |
    Add-PSIKPI -Title 'Expiration set to Never' -Value $Analysis.ExpirationStates.Never -Subtitle 'Handled as a distinct source value, not a date' -Status Info -Icon 'info' |
    Add-PSIKPI -Title 'Past expiration date' -Value $Analysis.ExpirationStates.Expired -Subtitle 'Compared with the report as-of calendar date' -Status Info -Icon 'info'

$null = $Report |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text ("Report-defined investigation thresholds: inactive $([char] 0x2265){0} days, inactive $([char] 0x2265){1} days, password age $([char] 0x2265){2} days. Password-age evidence excludes accounts with DONT_EXPIRE_PASSWD (userAccountControl flag 0x00010000). The raw userAccountControl attribute is not included in the report." -f $InsightThresholds.Stale90Days, $InsightThresholds.Stale180Days, $InsightThresholds.PasswordAgeDays)

for ($InsightIndex = 0; $InsightIndex -lt $InsightDefinitions.Count; $InsightIndex += 3) {
    $null = $Report | Add-PSIRow -Columns 12
    $EndIndex = [math]::Min($InsightIndex + 2, $InsightDefinitions.Count - 1)
    for ($DefinitionIndex = $InsightIndex; $DefinitionIndex -le $EndIndex; $DefinitionIndex++) {
        $Definition = $InsightDefinitions[$DefinitionIndex]
        $null = $Report | Add-PSIInsight -Title $Definition.Title -Value $Definition.Value `
            -Description $Definition.Description -Status $Definition.Status -Icon $Definition.Icon `
            -Filter @{ Table = 'ad-user-inventory'; Conditions = @($Definition.Conditions) } `
            -EvidenceColumns $EvidenceColumns -ExportColumns $ExportColumns -ColumnLabels $InventoryColumnLabels
    }
}

$null = $Report |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text ("Expiration states: {0:N0} Never $([char] 0x00B7) {1:N0} expired by the as-of date $([char] 0x00B7) {2:N0} expire today $([char] 0x00B7) {3:N0} have a future expiration $([char] 0x00B7) {4:N0} missing an expiration value. Date strings were parsed to typed DateTime values before age calculations. Source timestamps have no timezone marker; comparisons use calendar dates. Password median: {5:N0} days; maximum: {6:N0} days. Last-logon median: {7:N0} days; maximum: {8:N0} days." -f `
        $Analysis.ExpirationStates.Never, $Analysis.ExpirationStates.Expired, $Analysis.ExpirationStates.Today, $Analysis.ExpirationStates.Future, $Analysis.ExpirationStates.Missing, `
        $Analysis.PasswordAgeMedianDays, $Analysis.PasswordAgeMaximumDays, $Analysis.LastLogonAgeMedianDays, $Analysis.LastLogonAgeMaximumDays)

$null = $Report |
    Add-PSISection -Title 'User Inventory' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'ad-user-inventory' -Title 'User Account Inventory' -Data $Analysis.Records `
        -Columns $InventoryColumns -ColumnLabels $InventoryColumnLabels `
        -Filters @($StatusFilter, $DepartmentFilter, $EmployeeTypeFilter, $CountryFilter) `
        -PageSize 25 -EnableSearch $true -EnableSorting $true -EnablePagination $true `
        -ExportColumns $ExportColumns -WorksheetName 'User Inventory' `
        -NullValueText 'Not recorded' `
        -EmptyMessage 'No user accounts match the current search and filter selections.'

$DataQualityData = @(
    $EmptyFieldProfile |
        ForEach-Object {
            [pscustomobject]@{
                SourceField     = $_.Field
                EmptyRecords    = $_.EmptyCount
                EmptyPercent    = $_.EmptyPercent
                UniquePopulated = $_.UniqueNonEmpty
            }
        }
)

$null = $Report |
    Add-PSISection -Title 'Data Quality Profile' |
    Add-PSIRow -Columns 12 |
    Add-PSIKPI -Title 'Blank source cells' -Value $EmptyCellCount -Subtitle 'Counts empty cells; does not assume every field is required' -Status Info -Icon 'database' |
    Add-PSIKPI -Title 'Entirely empty attributes' -Value $CompletelyEmptyFieldCount -Subtitle 'Source columns with no populated records' -Status Info -Icon 'info'

$null = $Report |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text 'The source does not define requiredness for optional contact or extension attributes. Blank counts are shown as a profile only, not classified as control failures.' |
    Add-PSITable -Title 'Source Fields Containing Empty Values' -Data $DataQualityData `
        -Columns @('SourceField', 'EmptyRecords', 'EmptyPercent', 'UniquePopulated') `
        -ColumnLabels @{ SourceField = 'Source field'; EmptyRecords = 'Empty records'; EmptyPercent = 'Empty (%)'; UniquePopulated = 'Unique populated values' } `
        -PageSize 15 -EnableSearch $true -EnableSorting $true -EnablePagination $true `
        -EmptyMessage 'No empty source cells were found.'

$ThresholdDescriptions = [System.Collections.Generic.List[string]]::new()
foreach ($ThresholdName in $PolicyThresholds.Keys) {
    if ($null -ne $PolicyThresholds[$ThresholdName]) {
        $ThresholdDescriptions.Add(('{0}: {1} days' -f $ThresholdName, $PolicyThresholds[$ThresholdName]))
    }
}
$ThresholdSummary = if ($ThresholdDescriptions.Count -gt 0) {
    'Configured inclusive warning thresholds: ' + ($ThresholdDescriptions -join '; ') + '.'
}
else {
    'No policy thresholds were supplied. Password age, last-logon age, and expiration are descriptive analysis only; no threshold-based findings or recommendations are generated.'
}

$null = $Report |
    Add-PSISection -Title 'Threshold-Based Findings and Recommendations' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text $ThresholdSummary

if ($Analysis.Findings.Count -gt 0) {
    $null = $Report |
        Add-PSIRow -Columns 12 |
        Add-PSIStatus -Status Warning -Label 'Configured thresholds met' -Message ("{0:N0} user records met one or more explicitly supplied warning thresholds. Findings are listed below." -f $Analysis.Findings.Count)

    $FindingTypes = @($Analysis.Findings | Select-Object -ExpandProperty Finding -Unique | Sort-Object)
    $FindingFilter = Add-PSIFilter -Property 'Finding' -Label 'Finding type' -Values $FindingTypes
    $null = $Report |
        Add-PSIRow -Columns 12 |
        Add-PSITable -Id 'ad-user-findings' -Title 'Records Meeting Configured Thresholds' -Data $Analysis.Findings `
            -Columns @('DisplayName', 'UserPrincipalName', 'AccountStatus', 'Department', 'Finding', 'ObservedDays', 'ThresholdDays') `
            -ColumnLabels @{ DisplayName = 'Display name'; UserPrincipalName = 'User principal name'; AccountStatus = 'Account status'; ObservedDays = 'Observed days'; ThresholdDays = 'Configured threshold (days)' } `
            -Filters @($FindingFilter) -PageSize 25 -EnableSearch $true -EnableSorting $true -EnablePagination $true

    foreach ($FindingType in $FindingTypes) {
        $MatchingFindings = @($Analysis.Findings | Where-Object { $_.Finding -eq $FindingType })
        $ThresholdDays = [int] $MatchingFindings[0].ThresholdDays
        $null = $Report |
            Add-PSIRow -Columns 12 |
            Add-PSIAlert -Status Warning -Title $FindingType `
                -Message ("{0:N0} records meet the configured {1}-day threshold as of {2:yyyy-MM-dd}." -f $MatchingFindings.Count, $ThresholdDays, $Analysis.AsOfDate) `
                -Timestamp $Analysis.AsOfDate -Details @{ ThresholdDays = $ThresholdDays; MatchingRecords = $MatchingFindings.Count }
        $null = $Report |
            Add-PSIRow -Columns 12 |
            Add-PSIRecommendation -Status Warning -Title ("Review: {0}" -f $FindingType) `
                -Description ("Review the matching records against the configured {0}-day rule and the organization's approved identity policy." -f $ThresholdDays) `
                -ActionText 'Use the findings table to review the listed records and apply the organization-approved process.'
    }
}
else {
    $NoFindingMessage = if ($ThresholdDescriptions.Count -eq 0) {
        'No threshold rules were configured, so no security findings or remediation recommendations were inferred.'
    }
    else {
        'No records met the explicitly configured warning thresholds for this report snapshot.'
    }
    $null = $Report |
        Add-PSIRow -Columns 12 |
        Add-PSIStatus -Status Info -Label 'No policy findings generated' -Message $NoFindingMessage |
        Add-PSITable -Id 'ad-user-findings' -Title 'Records Meeting Configured Thresholds' -Data @() `
            -Columns @('DisplayName', 'UserPrincipalName', 'AccountStatus', 'Department', 'Finding', 'ObservedDays', 'ThresholdDays') `
            -ColumnLabels @{ DisplayName = 'Display name'; UserPrincipalName = 'User principal name'; AccountStatus = 'Account status'; ObservedDays = 'Observed days'; ThresholdDays = 'Configured threshold (days)' } `
            -PageSize 25 -EnableSearch $true -EnableSorting $true -EnablePagination $true `
            -EmptyMessage 'No records met configured thresholds. No policy thresholds are enabled by default.'
}

$null = $Report |
    Add-PSISection -Title 'Report Method and Data Handling' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text ("This report reads the AD_User_Accounts worksheet and uses an explicit {0}-field presentation allowlist. It omits phone numbers, street addresses, employee and badge identifiers, manager and distinguished names, VIP flags, cost centers, and unused source attributes. Date/time source values are timezone-unspecified ISO strings. Account expiration value Never is retained as a distinct state and excluded from date arithmetic. As-of date: {1:yyyy-MM-dd}." -f $InventoryColumns.Count, $Analysis.AsOfDate)

$Assessment = $Report
if ($AsAssessment) { return $Assessment }

# Standalone output uses the same assessment object as composed output.
$StandaloneReport = New-PSIReport -Title $Assessment.Title -Subtitle $Assessment.Description -Theme $Theme
$null = $StandaloneReport | Add-PSIAssessment -Assessment $Assessment
$OutputFile = Export-PSIReport -Report $StandaloneReport -Path $OutputPath
Write-Host "Generated report: $($OutputFile.FullName)"
Write-Host ("Inventory rows: {0:N0}; policy findings: {1:N0}; thresholds configured: {2}" -f $Analysis.UserCount, $Analysis.Findings.Count, $ThresholdDescriptions.Count)
Write-Host 'Verified: report file exists.'

if (-not $NoBrowser) {
    $IsWindowsHost = $env:OS -eq 'Windows_NT'
    $IsMacHost = $false
    $IsLinuxHost = $false
    if (-not $IsWindowsHost -and $PSVersionTable.PSEdition -eq 'Core') {
        $IsMacHost = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)
        $IsLinuxHost = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Linux)
    }

    $OpenCommand = if ($IsWindowsHost) { 'Start-Process' } elseif ($IsMacHost) { 'open' } elseif ($IsLinuxHost) { 'xdg-open' } else { $null }
    if ($OpenCommand) {
        try {
            if ($OpenCommand -eq 'Start-Process') {
                Start-Process -FilePath $OutputFile.FullName -ErrorAction Stop
            }
            else {
                $OpenProcess = Start-Process -FilePath $OpenCommand -ArgumentList @($OutputFile.FullName) -PassThru -ErrorAction Stop
                if ($OpenProcess.WaitForExit(5000) -and $OpenProcess.ExitCode -ne 0) {
                    throw "'$OpenCommand' exited with code $($OpenProcess.ExitCode)."
                }
            }
            Write-Host "Browser open requested with $OpenCommand."
        }
        catch {
            Write-Warning "Could not open the report in the default browser: $($_.Exception.Message)"
        }
    }
    else {
        Write-Warning 'Could not detect a supported operating system for opening the report.'
    }
}

$OutputFile
