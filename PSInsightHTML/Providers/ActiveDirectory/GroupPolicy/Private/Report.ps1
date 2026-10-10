[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $OutputPath,

    [Parameter()]
    [ValidateSet('Light', 'Dark', 'Auto')]
    [string] $Theme = 'Auto',

    [Parameter()]
    [ValidateRange(100, 250)]
    [int] $GpoCount = 180,

    [Parameter()]
    [datetime] $AsOfDate = [datetime]::new(2026, 9, 27),

    [Parameter()]
    [switch] $NoBrowser,
    [Parameter()][switch] $AsAssessment
)

$ModuleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent
. (Join-Path $PSScriptRoot 'PSIADGroupPolicy.Provider.ps1')
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path (Join-Path $ModuleRoot 'Reports') 'PSInsightHTML-GPOAssessment.html'
}

$Sample = New-PSIADGroupPolicySampleData -GpoCount $GpoCount -AsOfDate $AsOfDate
$Gpos = $Sample.Gpos
$Links = $Sample.Links
$SecurityFilters = $Sample.SecurityFilters
$Delegations = $Sample.Delegations
$WmiAssignments = $Sample.WmiAssignments
$LinkedCount = @($Gpos | Where-Object { $_.LinkState -eq 'Linked' }).Count
$UnlinkedCount = @($Gpos | Where-Object { $_.LinkState -eq 'Unlinked' }).Count
$EmptyCount = @($Gpos | Where-Object { $_.SettingsState -eq 'Empty' }).Count
$UserDisabledCount = @($Gpos | Where-Object { $_.UserConfiguration -eq 'Disabled' }).Count
$ComputerDisabledCount = @($Gpos | Where-Object { $_.ComputerConfiguration -eq 'Disabled' }).Count
$UserEnabledCount = $Gpos.Count - $UserDisabledCount
$ComputerEnabledCount = $Gpos.Count - $ComputerDisabledCount
$BothDisabledCount = @($Gpos | Where-Object { $_.ConfigurationState -eq 'Both disabled' }).Count
$DisabledLinkCount = @($Links | Where-Object { $_.LinkEnabled -eq 'No' }).Count
$DisabledLinkGpoCount = @($Gpos | Where-Object { $_.DisabledLinkCount -gt 0 }).Count
$EnforcedLinkCount = @($Links | Where-Object { $_.Enforced -eq 'Yes' }).Count
$WmiGpoCount = $WmiAssignments.Count
$CustomFilterCount = @($Gpos | Where-Object { $_.SecurityFilterType -in @('Custom group', 'Mixed') }).Count
$DemoHealthyCount = @($Gpos | Where-Object { $_.DemoAssessment -eq 'Healthy' }).Count

$GpoColumns = @(
    'GpoName', 'GpoId', 'Created', 'Modified', 'UserConfiguration', 'ComputerConfiguration',
    'ConfigurationState', 'UserVersion', 'ComputerVersion', 'SettingsState', 'LinkState',
    'LinkCount', 'DisabledLinkCount', 'WmiFilterName', 'WmiUsage', 'SecurityFilterType', 'SecurityFilteringSummary', 'DemoAssessment'
)
$GpoLabels = @{
    GpoName = 'GPO name'; GpoId = 'GPO ID'; Created = 'Created'; Modified = 'Modified'
    UserConfiguration = 'User configuration'; ComputerConfiguration = 'Computer configuration'
    ConfigurationState = 'Configuration state'; UserVersion = 'User version'; ComputerVersion = 'Computer version'
    SettingsState = 'Settings'; LinkState = 'Link state'; LinkCount = 'Link count'
    DisabledLinkCount = 'Disabled links'; WmiFilterName = 'WMI filter'; WmiUsage = 'WMI usage'
    SecurityFilterType = 'Security filtering type'; SecurityFilteringSummary = 'Apply principals'
    DemoAssessment = 'Sample baseline check'
}
$GpoEvidenceColumns = @('GpoName', 'GpoId', 'UserConfiguration', 'ComputerConfiguration', 'SettingsState', 'LinkState', 'LinkCount', 'DisabledLinkCount', 'WmiFilterName', 'SecurityFilterType', 'DemoAssessment')
$GpoExportColumns = @('GpoName', 'GpoId', 'Created', 'Modified', 'UserConfiguration', 'ComputerConfiguration', 'ConfigurationState', 'UserVersion', 'ComputerVersion', 'SettingsState', 'LinkState', 'LinkCount', 'DisabledLinkCount', 'WmiFilterName', 'SecurityFilterType', 'DemoAssessment')
$LinkColumns = @('GpoName', 'Target', 'TargetType', 'LinkEnabled', 'Enforced', 'LinkOrder')
$LinkLabels = @{ GpoName='GPO name'; Target='Link target'; TargetType='Target type'; LinkEnabled='Link enabled'; Enforced='Enforced'; LinkOrder='Link order' }
$SecurityColumns = @('GpoName', 'Principal', 'Permission', 'ApplyState', 'FilterType')
$SecurityLabels = @{ GpoName='GPO name'; Principal='Principal'; Permission='Permission'; ApplyState='Apply GPO'; FilterType='Filtering type' }
$DelegationColumns = @('GpoName', 'Trustee', 'PermissionLevel', 'Source')
$DelegationLabels = @{ GpoName='GPO name'; Trustee='Trustee'; PermissionLevel='Permission level'; Source='Permission source' }
$WmiColumns = @('GpoName', 'FilterName', 'Description', 'QuerySummary')
$WmiLabels = @{ GpoName='GPO name'; FilterName='WMI filter'; Description='Description'; QuerySummary='Query summary' }

$GpoFilters = @(
    Add-PSIFilter -Property LinkState -Label 'Link state' -Values @('Linked', 'Unlinked')
    Add-PSIFilter -Property ConfigurationState -Label 'Configuration' -Values @($Gpos.ConfigurationState | Sort-Object -Unique)
    Add-PSIFilter -Property SettingsState -Label 'Settings' -Values @('Configured', 'Empty')
    Add-PSIFilter -Property SecurityFilterType -Label 'Security filtering' -Values @($Gpos.SecurityFilterType | Sort-Object -Unique)
    Add-PSIFilter -Property WmiUsage -Label 'WMI usage' -Values @('Has filter', 'No filter')
    Add-PSIFilter -Property DemoAssessment -Label 'Sample baseline check' -Values @('Healthy', 'Info')
)
$LinkFilters = @(
    Add-PSIFilter -Property TargetType -Label 'Target type' -Values @($Links.TargetType | Sort-Object -Unique)
    Add-PSIFilter -Property LinkEnabled -Label 'Link enabled' -Values @('Yes', 'No')
    Add-PSIFilter -Property Enforced -Label 'Enforced' -Values @('Yes', 'No')
)
$SecurityTableFilters = @(
    Add-PSIFilter -Property FilterType -Label 'Filtering type' -Values @($SecurityFilters.FilterType | Sort-Object -Unique)
    Add-PSIFilter -Property ApplyState -Label 'Apply state' -Values @('Yes', 'No')
)
$DelegationTableFilters = @(
    Add-PSIFilter -Property Source -Label 'Permission source' -Values @('Explicit', 'Inherited')
)
$WmiTableFilters = @(
    Add-PSIFilter -Property FilterName -Label 'WMI filter' -Values @($WmiAssignments.FilterName | Sort-Object -Unique)
)

# Build reusable assessment content through the shared component API.
$Report = New-PSIAssessment -Name 'Group Policy' -Provider 'ActiveDirectory' -Title 'Active Directory Group Policy Assessment' `
    -Description 'Fictional enterprise configuration snapshot for PSInsightHTML'

$null = $Report |
    Add-PSISection -Title 'Executive Summary' |
    Add-PSIRow -Columns 12 |
    Add-PSIKPI -Title 'Total GPOs' -Value $Gpos.Count -Subtitle 'Fictional objects in this sample' -Status Info -Icon 'domain' |
    Add-PSIKPI -Title 'Linked GPOs' -Value $LinkedCount -Subtitle 'Select to filter the inventory' -Status Info -Icon 'network' -Filter @{ Table='gpo-inventory'; Property='LinkState'; Value='Linked' } |
    Add-PSIKPI -Title 'Unlinked GPOs' -Value $UnlinkedCount -Subtitle 'Investigation candidate; no risk inferred' -Status Info -Icon 'info' -Filter @{ Table='gpo-inventory'; Property='LinkState'; Value='Unlinked' } |
    Add-PSIKPI -Title 'Empty GPOs' -Value $EmptyCount -Subtitle 'No user or computer settings configured' -Status Info -Icon 'info' -Filter @{ Table='gpo-inventory'; Property='SettingsState'; Value='Empty' }
$null = $Report |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text ("Fictional sample data only $([char] 0x00B7) {0:N0} GPOs $([char] 0x00B7) {1:N0} link records $([char] 0x00B7) {2:N0} security-filter entries $([char] 0x00B7) {3:N0} delegation entries $([char] 0x00B7) as of {4:yyyy-MM-dd}. Counts describe configuration, not security severity." -f $Gpos.Count, $Links.Count, $SecurityFilters.Count, $Delegations.Count, $Sample.AsOfDate)

$null = $Report |
    Add-PSISection -Title 'Group Policy Inventory Overview' |
    Add-PSIRow -Columns 12 |
    Add-PSIStatus -Status Info -Label 'Observed link distribution' -Message ("{0:N0} linked and {1:N0} unlinked GPOs. A GPO can have multiple links; link records are assessed separately from GPO objects." -f $LinkedCount, $UnlinkedCount) |
    Add-PSIRow -Columns 12 |
    Add-PSIStatus -Status Healthy -Label 'Narrow sample baseline check' -Message ("{0:N0} GPOs pass this fictional configuration check: at least one link, no disabled links, configured settings, and at least one enabled configuration portion. This is not a security or compliance assessment." -f $DemoHealthyCount) |
    Add-PSIRow -Columns 6 |
    Add-PSIChart -Title 'Linked vs Unlinked GPOs' -ChartType Doughnut `
        -Data (Get-PSIADGroupPolicyDistribution -Data $Gpos -Property LinkState) -CategoryProperty Category -ValueProperty Count `
        -FilterMetadata @{ Table='gpo-inventory'; Property='LinkState'; ValueProperty='Category' } -ShowLabels $true |
    Add-PSIChart -Title 'Security Filtering Types' -ChartType Bar `
        -Data (Get-PSIADGroupPolicyDistribution -Data $Gpos -Property SecurityFilterType) -CategoryProperty Category -ValueProperty Count `
        -FilterMetadata @{ Table='gpo-inventory'; Property='SecurityFilterType'; ValueProperty='Category' } -ShowLegend $false

$null = $Report |
    Add-PSISection -Title 'GPO Configuration State' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text ("User configuration enabled: {0:N0}; disabled: {1:N0}. Computer configuration enabled: {2:N0}; disabled: {3:N0}. Both portions disabled: {4:N0}; no configured settings: {5:N0}. Empty settings and disabled portions are distinct states and may overlap." -f $UserEnabledCount, $UserDisabledCount, $ComputerEnabledCount, $ComputerDisabledCount, $BothDisabledCount, $EmptyCount) |
    Add-PSIRow -Columns 6 |
    Add-PSIChart -Title 'User and Computer Configuration' -ChartType Bar `
        -Data (Get-PSIADGroupPolicyDistribution -Data $Gpos -Property ConfigurationState) -CategoryProperty Category -ValueProperty Count `
        -FilterMetadata @{ Table='gpo-inventory'; Property='ConfigurationState'; ValueProperty='Category' } -ShowLegend $false |
    Add-PSIChart -Title 'Configured vs Empty GPOs' -ChartType Pie `
        -Data (Get-PSIADGroupPolicyDistribution -Data $Gpos -Property SettingsState) -CategoryProperty Category -ValueProperty Count `
        -FilterMetadata @{ Table='gpo-inventory'; Property='SettingsState'; ValueProperty='Category' } -ShowLabels $true

$null = $Report |
    Add-PSISection -Title 'GPO Link Analysis' |
    Add-PSIRow -Columns 12 |
    Add-PSIKPI -Title 'Link records' -Value $Links.Count -Subtitle 'One row per GPO-to-target link' -Status Info -Icon 'network' |
    Add-PSIKPI -Title 'Disabled links' -Value $DisabledLinkCount -Subtitle 'Link state only; reason not inferred' -Status Info -Icon 'info' -Filter @{ Table='gpo-links'; Property='LinkEnabled'; Value='No' } |
    Add-PSIKPI -Title 'Enforced links' -Value $EnforcedLinkCount -Subtitle 'Observed link option' -Status Info -Icon 'security' -Filter @{ Table='gpo-links'; Property='Enforced'; Value='Yes' } |
    Add-PSIKPI -Title 'GPOs with multiple links' -Value @($Gpos | Where-Object { $_.LinkCount -gt 1 }).Count -Subtitle 'Each target remains a separate link record' -Status Info -Icon 'domain' |
    Add-PSIRow -Columns 12 |
    Add-PSIChart -Title 'Enabled vs Disabled Link Records' -ChartType Bar `
        -Data (Get-PSIADGroupPolicyDistribution -Data $Links -Property LinkEnabled) -CategoryProperty Category -ValueProperty Count `
        -FilterMetadata @{ Table='gpo-links'; Property='LinkEnabled'; ValueProperty='Category' } -ShowLegend $false |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'gpo-links' -Title 'GPO Link Inventory' -Data $Links -Columns $LinkColumns -ColumnLabels $LinkLabels `
        -Filters $LinkFilters -PageSize 25 -ExportColumns $LinkColumns -WorksheetName 'GPO Links' -NullValueText 'Not recorded'

$null = $Report |
    Add-PSISection -Title 'Security Filtering and Delegation' |
    Add-PSIRow -Columns 12 |
    Add-PSIStatus -Status Info -Label 'Configuration detail' -Message ("{0:N0} GPOs use custom-group or mixed filtering. These are recorded configurations, not automatic security findings. Security filtering and delegation are listed separately." -f $CustomFilterCount) |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'gpo-security-filters' -Title 'Security Filtering Principals' -Data $SecurityFilters `
        -Columns $SecurityColumns -ColumnLabels $SecurityLabels -Filters $SecurityTableFilters -PageSize 25 `
        -ExportColumns $SecurityColumns -WorksheetName 'Security Filtering' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'gpo-delegation' -Title 'GPO Delegation' -Data $Delegations `
        -Columns $DelegationColumns -ColumnLabels $DelegationLabels -Filters $DelegationTableFilters -PageSize 25 `
        -ExportColumns $DelegationColumns -WorksheetName 'Delegation'

$null = $Report |
    Add-PSISection -Title 'WMI Filter Usage' |
    Add-PSIRow -Columns 12 |
    Add-PSIStatus -Status Info -Label 'WMI targeting' -Message ("{0:N0} GPOs reference one of the fictional WMI filter definitions. Query summaries appear in the table, not in the KPI cards." -f $WmiGpoCount) |
    Add-PSIRow -Columns 12 |
    Add-PSIChart -Title 'GPOs With and Without WMI Filters' -ChartType Doughnut `
        -Data (Get-PSIADGroupPolicyDistribution -Data $Gpos -Property WmiUsage) -CategoryProperty Category -ValueProperty Count `
        -FilterMetadata @{ Table='gpo-inventory'; Property='WmiUsage'; ValueProperty='Category' } -ShowLabels $true |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'gpo-wmi-assignments' -Title 'WMI Filter Assignments' -Data $WmiAssignments `
        -Columns $WmiColumns -ColumnLabels $WmiLabels -Filters $WmiTableFilters -PageSize 25 `
        -ExportColumns $WmiColumns -WorksheetName 'WMI Assignments'

$GpoInsightDefinitions = @(
    [pscustomobject]@{ Title='Unlinked GPOs'; Value=$UnlinkedCount; Description='Objects with zero links; review whether they are intentionally retained.'; Icon='info'; Table='gpo-inventory'; Conditions=@([pscustomobject]@{ Property='LinkState'; Operator='Equals'; Value='Unlinked' }); EvidenceColumns=$GpoEvidenceColumns; ExportColumns=$GpoExportColumns; Labels=$GpoLabels },
    [pscustomobject]@{ Title='Empty GPOs'; Value=$EmptyCount; Description='Objects with no configured user or computer settings.'; Icon='info'; Table='gpo-inventory'; Conditions=@([pscustomobject]@{ Property='SettingsState'; Operator='Equals'; Value='Empty' }); EvidenceColumns=$GpoEvidenceColumns; ExportColumns=$GpoExportColumns; Labels=$GpoLabels },
    [pscustomobject]@{ Title='Both Sections Disabled'; Value=$BothDisabledCount; Description='User and Computer portions are both disabled.'; Icon='settings'; Table='gpo-inventory'; Conditions=@([pscustomobject]@{ Property='ConfigurationState'; Operator='Equals'; Value='Both disabled' }); EvidenceColumns=$GpoEvidenceColumns; ExportColumns=$GpoExportColumns; Labels=$GpoLabels },
    [pscustomobject]@{ Title='GPOs With Disabled Links'; Value=$DisabledLinkGpoCount; Description='At least one link is disabled; link details are in the separate link dataset.'; Icon='network'; Table='gpo-inventory'; Conditions=@([pscustomobject]@{ Property='DisabledLinkCount'; Operator='GreaterThanOrEqual'; Value=1 }); EvidenceColumns=$GpoEvidenceColumns; ExportColumns=$GpoExportColumns; Labels=$GpoLabels },
    [pscustomobject]@{ Title='GPOs Using WMI Filters'; Value=$WmiGpoCount; Description='WMI targeting is present; confirm its documented purpose.'; Icon='server'; Table='gpo-inventory'; Conditions=@([pscustomobject]@{ Property='WmiUsage'; Operator='Equals'; Value='Has filter' }); EvidenceColumns=$GpoEvidenceColumns; ExportColumns=$GpoExportColumns; Labels=$GpoLabels },
    [pscustomobject]@{ Title='Disabled Link Records'; Value=$DisabledLinkCount; Description='Individual disabled links with their target and order.'; Icon='network'; Table='gpo-links'; Conditions=@([pscustomobject]@{ Property='LinkEnabled'; Operator='Equals'; Value='No' }); EvidenceColumns=$LinkColumns; ExportColumns=$LinkColumns; Labels=$LinkLabels },
    [pscustomobject]@{ Title='Custom or Mixed Filtering'; Value=$CustomFilterCount; Description='Review configured apply principals without inferring a vulnerability.'; Icon='security'; Table='gpo-inventory'; Conditions=@([pscustomobject]@{ Property='SecurityFilterType'; Operator='In'; Values=@('Custom group', 'Mixed') }); EvidenceColumns=$GpoEvidenceColumns; ExportColumns=$GpoExportColumns; Labels=$GpoLabels }
)

$null = $Report |
    Add-PSISection -Title 'Investigation Insights' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text 'Select an Insight to inspect matching evidence. Its records come from the existing inventory or link table and inherit active table filters and search. Evidence export uses the matching result set.'
for ($InsightIndex = 0; $InsightIndex -lt $GpoInsightDefinitions.Count; $InsightIndex += 3) {
    $null = $Report | Add-PSIRow -Columns 12
    $LastIndex = [math]::Min($InsightIndex + 2, $GpoInsightDefinitions.Count - 1)
    for ($CurrentIndex = $InsightIndex; $CurrentIndex -le $LastIndex; $CurrentIndex++) {
        $Definition = $GpoInsightDefinitions[$CurrentIndex]
        $null = $Report | Add-PSIInsight -Title $Definition.Title -Value $Definition.Value -Description $Definition.Description `
            -Status Info -Icon $Definition.Icon -Filter @{ Table=$Definition.Table; Conditions=@($Definition.Conditions) } `
            -EvidenceColumns $Definition.EvidenceColumns -ExportColumns $Definition.ExportColumns -ColumnLabels $Definition.Labels
    }
}

$null = $Report |
    Add-PSISection -Title 'Group Policy Inventory' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'gpo-inventory' -Title 'GPO Inventory' -Data $Gpos -Columns $GpoColumns -ColumnLabels $GpoLabels `
        -Filters $GpoFilters -PageSize 25 -ExportColumns $GpoExportColumns -WorksheetName 'GPO Inventory' `
        -NullValueText 'None' -EmptyMessage 'No GPOs match the current search and filters.'

$ObservationRows = @(
    [pscustomobject]@{ Observation='Unlinked GPOs'; Count=$UnlinkedCount; Interpretation='Investigation candidate; an intentionally retained GPO may be valid.' },
    [pscustomobject]@{ Observation='Empty GPOs'; Count=$EmptyCount; Interpretation='No configured settings in the sample snapshot.' },
    [pscustomobject]@{ Observation='Both portions disabled'; Count=$BothDisabledCount; Interpretation='Configuration state only; may be intentional.' },
    [pscustomobject]@{ Observation='Disabled link records'; Count=$DisabledLinkCount; Interpretation='Review link intent and target before taking action.' },
    [pscustomobject]@{ Observation='GPOs using WMI filters'; Count=$WmiGpoCount; Interpretation='Document targeting purpose and confirm query maintenance.' }
)
$null = $Report |
    Add-PSISection -Title 'Findings and Recommendations' |
    Add-PSIRow -Columns 12 |
    Add-PSIStatus -Status Info -Label 'Review candidates only' -Message 'The observations below are evidence-linked configuration facts. This sample defines no security risk threshold and makes no vulnerability claim.' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'gpo-observations' -Title 'Observed Configuration Candidates' -Data $ObservationRows `
        -Columns @('Observation', 'Count', 'Interpretation') -ExportColumns @('Observation', 'Count', 'Interpretation') -PageSize 10 |
    Add-PSIRow -Columns 12 |
    Add-PSIRecommendation -Status Info -Title 'Review unlinked and empty objects' `
        -Description ("The sample contains {0:N0} unlinked and {1:N0} empty GPOs. Confirm intended retention with the policy owner." -f $UnlinkedCount, $EmptyCount) `
        -ActionText 'Use the Insight evidence before changing or removing a GPO.' |
    Add-PSIRecommendation -Status Info -Title 'Review disabled links and portions' `
        -Description ("The sample contains {0:N0} disabled link records and {1:N0} GPOs with both configuration portions disabled." -f $DisabledLinkCount, $BothDisabledCount) `
        -ActionText 'Compare each configuration with approved deployment plans.' |
    Add-PSIRecommendation -Status Info -Title 'Document WMI targeting' `
        -Description ("{0:N0} GPOs reference fictional WMI filters. The report does not assess query correctness." -f $WmiGpoCount) `
        -ActionText 'Review filter ownership, query intent, and change history.'

$null = $Report |
    Add-PSISection -Title 'Method and Data Handling' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text ("{0} The provider generates {1:N0} GPOs deterministically with distinct GPO, link, security filtering, delegation, and WMI assignment records. GPO links are separate rows because a single GPO may target several OUs, the domain, or a site. All paths and principals use the reserved example.invalid domain. No live directory, GroupPolicy module, or network source is queried." -f $Sample.Source, $Gpos.Count) |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text 'Tables, evidence, and export use explicit field allowlists. Charts contain only small category counts; KPI and Insight actions reference table IDs and conditions rather than embedding full records. Dates are fictional ISO calendar dates. Counts and review suggestions are descriptive and require human confirmation.'

$Assessment = $Report
if ($AsAssessment) { return $Assessment }

# Standalone output uses the same assessment object as composed output.
$StandaloneReport = New-PSIReport -Title $Assessment.Title -Subtitle $Assessment.Description -Theme $Theme
$null = $StandaloneReport | Add-PSIAssessment -Assessment $Assessment
$OutputFile = Export-PSIReport -Report $StandaloneReport -Path $OutputPath
Write-Host "Generated report: $($OutputFile.FullName)"
Write-Host ("Fictional sample: {0:N0} GPOs; {1:N0} links; {2:N0} security-filter entries; {3:N0} delegation entries; {4:N0} WMI assignments." -f $Gpos.Count, $Links.Count, $SecurityFilters.Count, $Delegations.Count, $WmiAssignments.Count)

if (-not $NoBrowser) {
    $IsWindowsHost = $env:OS -eq 'Windows_NT'
    $IsMacHost = $false
    $IsLinuxHost = $false
    if (-not $IsWindowsHost -and $PSVersionTable.PSEdition -eq 'Core') {
        $IsMacHost = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)
        $IsLinuxHost = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Linux)
    }
    try {
        if ($IsWindowsHost) { Start-Process -FilePath $OutputFile.FullName -ErrorAction Stop }
        elseif ($IsMacHost) { Start-Process -FilePath 'open' -ArgumentList @($OutputFile.FullName) -Wait -ErrorAction Stop }
        elseif ($IsLinuxHost) { Start-Process -FilePath 'xdg-open' -ArgumentList @($OutputFile.FullName) -Wait -ErrorAction Stop }
        else { throw 'No supported browser-open command was detected.' }
        Write-Host 'Browser open requested.'
    }
    catch { Write-Warning "Could not open the report in the default browser: $($_.Exception.Message)" }
}

$OutputFile
