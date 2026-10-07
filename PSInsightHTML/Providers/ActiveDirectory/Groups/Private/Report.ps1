[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $OutputPath,

    [Parameter()]
    [ValidateSet('Light', 'Dark', 'Auto')]
    [string] $Theme = 'Auto',

    [Parameter()]
    [ValidateRange(250, 400)]
    [int] $GroupCount = 320,

    [Parameter()]
    [hashtable] $Thresholds = @{},

    [Parameter()]
    [datetime] $AsOfDate = [datetime]::new(2026, 9, 27),

    [Parameter()]
    [switch] $NoBrowser,
    [Parameter()][switch] $AsAssessment
)

$ModuleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent
. (Join-Path $PSScriptRoot 'PSIADGroups.Provider.ps1')
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path (Join-Path $ModuleRoot 'Reports') 'PSInsightHTML-GroupAssessment.html'
}

$Sample = New-PSIADGroupSampleData -GroupCount $GroupCount -Thresholds $Thresholds -AsOfDate $AsOfDate
$Groups = $Sample.GroupInventory
$Memberships = $Sample.GroupMemberships
$Nested = $Sample.NestedGroupRelationships
$Rules = $Sample.Thresholds
$SecurityCount = @($Groups | Where-Object GroupCategory -eq 'Security').Count
$DistributionCount = $Groups.Count - $SecurityCount
$EmptyCount = @($Groups | Where-Object { $_.MemberCount -le $Rules.EmptyGroupMaximumMembers }).Count
$LargeCount = @($Groups | Where-Object { $_.MemberCount -ge $Rules.LargeGroupMemberThreshold }).Count
$DisabledGroupCount = @($Groups | Where-Object { $_.DisabledUserCount -gt 0 }).Count
$DisabledMembershipCount = @($Memberships | Where-Object { $_.MemberType -eq 'User' -and $_.MemberEnabled -eq 'No' }).Count
$NestedGroupCount = @($Groups | Where-Object { $_.NestedGroupCount -gt 0 }).Count
$UnmanagedCount = @($Groups | Where-Object { [string]::IsNullOrWhiteSpace($_.ManagedBy) }).Count
$MissingDescriptionCount = @($Groups | Where-Object { [string]::IsNullOrWhiteSpace($_.Description) }).Count
$EmptyFilterValues = @($Groups | Where-Object { $_.MemberCount -le $Rules.EmptyGroupMaximumMembers } | Select-Object -ExpandProperty MemberCount -Unique)
$LargeFilterValues = @($Groups | Where-Object { $_.MemberCount -ge $Rules.LargeGroupMemberThreshold } | Select-Object -ExpandProperty MemberCount -Unique)
$NestedFilterValues = @($Groups | Where-Object { $_.NestedGroupCount -gt 0 } | Select-Object -ExpandProperty NestedGroupCount -Unique)
$EmptyKpiFilter = if ($EmptyFilterValues.Count -gt 0) { @{ Table='group-inventory'; Property='MemberCount'; Values=$EmptyFilterValues } } else { @{} }
$LargeKpiFilter = if ($LargeFilterValues.Count -gt 0) { @{ Table='group-inventory'; Property='MemberCount'; Values=$LargeFilterValues } } else { @{} }
$NestedKpiFilter = if ($NestedFilterValues.Count -gt 0) { @{ Table='group-inventory'; Property='NestedGroupCount'; Values=$NestedFilterValues } } else { @{} }

# These allowlists govern what enters the HTML, evidence, and downloaded files.
# Provider-only distinguished names and account keys are intentionally excluded.
$GroupColumns = @('GroupName', 'GroupCategory', 'GroupScope', 'MemberCount', 'DirectUserCount', 'DirectGroupCount', 'DisabledUserCount', 'NestedGroupCount', 'ManagedBy', 'Description', 'Created', 'Modified', 'MemberCountBucket', 'HasOwner', 'HasDisabledMembers')
$GroupLabels = @{
    GroupName='Group name'; GroupCategory='Category'; GroupScope='Scope'; MemberCount='Direct members'
    DirectUserCount='Direct users'; DirectGroupCount='Direct groups'; DisabledUserCount='Disabled direct users'
    NestedGroupCount='Nested child groups'; ManagedBy='Managed by'; Description='Description'
    Created='Created'; Modified='Modified'; MemberCountBucket='Member count bucket'
    HasOwner='Has owner'; HasDisabledMembers='Has disabled users'
}
$GroupExportColumns = @('GroupName', 'GroupCategory', 'GroupScope', 'MemberCount', 'DirectUserCount', 'DirectGroupCount', 'DisabledUserCount', 'ManagedBy', 'Description', 'Created', 'Modified')
$GroupEvidenceColumns = @('GroupName', 'GroupCategory', 'GroupScope', 'MemberCount', 'DirectUserCount', 'DirectGroupCount', 'DisabledUserCount', 'ManagedBy', 'Description', 'Created', 'Modified')
$MemberColumns = @('GroupName', 'MemberName', 'MemberType', 'MemberEnabled')
$MemberLabels = @{ GroupName='Parent group'; MemberName='Direct member'; MemberType='Member type'; MemberEnabled='User enabled' }
$NestedColumns = @('ParentGroup', 'ChildGroup', 'ParentScope', 'ChildScope', 'RelationshipDepth', 'RelationshipType')
$NestedLabels = @{ ParentGroup='Parent group'; ChildGroup='Child group'; ParentScope='Parent scope'; ChildScope='Child scope'; RelationshipDepth='Depth'; RelationshipType='Relationship' }

$GroupFilters = @(
    Add-PSIFilter -Property GroupCategory -Label 'Category' -Values @('Security', 'Distribution')
    Add-PSIFilter -Property GroupScope -Label 'Scope' -Values @('Global', 'Universal', 'Domain Local')
    Add-PSIFilter -Property HasOwner -Label 'Has owner' -Values @('Yes', 'No')
    Add-PSIFilter -Property HasDisabledMembers -Label 'Has disabled users' -Values @('Yes', 'No')
    Add-PSIFilter -Property MemberCount -Label 'Exact direct member count' -Values @($Groups.MemberCount | Sort-Object -Unique) -Type MultiSelect
    Add-PSIFilter -Property NestedGroupCount -Label 'Direct child group count' -Values @($Groups.NestedGroupCount | Sort-Object -Unique) -Type MultiSelect
    Add-PSIFilter -Property MemberCountBucket -Label 'Direct member count' -Values @($Groups.MemberCountBucket | Sort-Object -Unique)
)
$MemberFilters = @(
    Add-PSIFilter -Property MemberType -Label 'Member type' -Values @('User', 'Group')
    Add-PSIFilter -Property MemberEnabled -Label 'User enabled' -Values @('Yes', 'No', 'Not applicable')
)
$NestedFilters = @(
    Add-PSIFilter -Property ParentScope -Label 'Parent scope' -Values @('Global', 'Universal', 'Domain Local')
    Add-PSIFilter -Property ChildScope -Label 'Child scope' -Values @('Global', 'Universal', 'Domain Local')
)

# Build reusable assessment content through the shared component API.
$Report = New-PSIAssessment -Name 'Groups' -Provider 'ActiveDirectory' -Title 'Active Directory Group Assessment' `
    -Description 'Fictional group inventory and membership review | PSInsightHTML'

$null = $Report |
    Add-PSISection -Title 'Executive Summary' |
    Add-PSIRow -Columns 12 |
    Add-PSIKPI -Title 'Total Groups' -Value $Groups.Count -Subtitle 'Fictional groups in this snapshot' -Status Info -Icon 'domain' |
    Add-PSIKPI -Title 'Security Groups' -Value $SecurityCount -Subtitle 'Select to filter group inventory' -Status Info -Icon 'security' -Filter @{ Table='group-inventory'; Property='GroupCategory'; Value='Security' } |
    Add-PSIKPI -Title 'Distribution Groups' -Value $DistributionCount -Subtitle 'Select to filter group inventory' -Status Info -Icon 'users' -Filter @{ Table='group-inventory'; Property='GroupCategory'; Value='Distribution' } |
    Add-PSIKPI -Title 'Empty Groups' -Value $EmptyCount -Subtitle "Direct members <= $($Rules.EmptyGroupMaximumMembers)" -Status Info -Icon 'info' -Filter $EmptyKpiFilter |
    Add-PSIRow -Columns 12 |
    Add-PSIKPI -Title 'Groups With Disabled Members' -Value $DisabledGroupCount -Subtitle 'Direct disabled-user memberships' -Status Info -Icon 'users' -Filter @{ Table='group-inventory'; Property='HasDisabledMembers'; Value='Yes' } |
    Add-PSIKPI -Title 'Nested Groups' -Value $NestedGroupCount -Subtitle 'Contain direct child groups' -Status Info -Icon 'network' -Filter $NestedKpiFilter |
    Add-PSIKPI -Title 'Unmanaged Groups' -Value $UnmanagedCount -Subtitle 'ManagedBy is empty' -Status Info -Icon 'info' -Filter @{ Table='group-inventory'; Property='HasOwner'; Value='No' } |
    Add-PSIKPI -Title 'Large Groups' -Value $LargeCount -Subtitle "Direct members >= $($Rules.LargeGroupMemberThreshold)" -Status Info -Icon 'users' -Filter $LargeKpiFilter
$null = $Report | Add-PSIRow -Columns 12 | Add-PSIText -Size Small -Text (
    "Fictional sample data only · {0:N0} groups · {1:N0} direct membership records · {2:N0} direct nested-group relationships · as of {3:yyyy-MM-dd}. All KPI states describe observations, not vulnerabilities." -f $Groups.Count, $Memberships.Count, $Nested.Count, $Sample.AsOfDate)

$null = $Report |
    Add-PSISection -Title 'Group Category and Scope' |
    Add-PSIRow -Columns 12 |
    Add-PSIStatus -Status Info -Label 'Group classification' -Message 'Category and scope describe each fictional group. Select a chart segment to filter the group inventory.' |
    Add-PSIRow -Columns 6 |
    Add-PSIChart -Title 'Security vs Distribution' -ChartType Doughnut -Data (Get-PSIADGroupDistribution -Data $Groups -Property GroupCategory) -CategoryProperty Category -ValueProperty Count -ShowLabels $true -FilterMetadata @{ Table='group-inventory'; Property='GroupCategory'; ValueProperty='Category' } |
    Add-PSIChart -Title 'Groups by Scope' -ChartType Bar -Data (Get-PSIADGroupDistribution -Data $Groups -Property GroupScope) -CategoryProperty Category -ValueProperty Count -ShowLegend $false -FilterMetadata @{ Table='group-inventory'; Property='GroupScope'; ValueProperty='Category' }

$null = $Report |
    Add-PSISection -Title 'Membership Overview' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Normal -Text ("{0:N0} direct user memberships and {1:N0} direct group memberships are represented as separate relationship rows. Member Count is direct users plus direct child groups; it does not include transitive members." -f ($Memberships.Count - $Nested.Count), $Nested.Count) |
    Add-PSIRow -Columns 6 |
    Add-PSIChart -Title 'Groups by Direct Member Count' -ChartType Bar -Data (Get-PSIADGroupDistribution -Data $Groups -Property MemberCountBucket) -CategoryProperty Category -ValueProperty Count -ShowLegend $false -FilterMetadata @{ Table='group-inventory'; Property='MemberCountBucket'; ValueProperty='Category' } |
    Add-PSIChart -Title 'Direct Member Types' -ChartType Pie -Data (Get-PSIADGroupDistribution -Data $Memberships -Property MemberType) -CategoryProperty Category -ValueProperty Count -ShowLabels $true -FilterMetadata @{ Table='group-memberships'; Property='MemberType'; ValueProperty='Category' }

$null = $Report |
    Add-PSISection -Title 'Nested Group Analysis' |
    Add-PSIRow -Columns 12 |
    Add-PSIStatus -Status Info -Label 'Direct relationships only' -Message ("{0:N0} parent groups contain {1:N0} direct child-group relationships. Depth is 1 for each recorded edge; transitive reach and permissions are not calculated." -f $NestedGroupCount, $Nested.Count) |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'group-nesting' -Title 'Direct Nested Group Relationships' -Data $Nested -Columns $NestedColumns -ColumnLabels $NestedLabels -Filters $NestedFilters -PageSize 25 -ExportColumns $NestedColumns -WorksheetName 'Direct Nesting' -NullValueText 'Not provided'

$null = $Report |
    Add-PSISection -Title 'Empty and Large Groups' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Normal -Text ("{0:N0} groups have at most {1} direct members; {2:N0} groups have at least {3} direct members. These are configurable investigation thresholds, not policy or risk classifications." -f $EmptyCount, $Rules.EmptyGroupMaximumMembers, $LargeCount, $Rules.LargeGroupMemberThreshold) |
    Add-PSIRow -Columns 12 |
    Add-PSIStatus -Status Info -Label 'Review in context' -Message 'An intentionally empty group or a large broad-access group can be valid. Inspect ownership, purpose, and membership before taking action.'

$null = $Report |
    Add-PSISection -Title 'Disabled User Membership' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Normal -Text ("{0:N0} groups contain {1:N0} direct memberships from fictional disabled users. This is an inventory observation; it does not establish that these memberships are inappropriate." -f $DisabledGroupCount, $DisabledMembershipCount) |
    Add-PSIRow -Columns 6 |
    Add-PSIChart -Title 'Groups With Disabled Direct Users' -ChartType Doughnut -Data (Get-PSIADGroupDistribution -Data $Groups -Property HasDisabledMembers) -CategoryProperty Category -ValueProperty Count -ShowLabels $true -FilterMetadata @{ Table='group-inventory'; Property='HasDisabledMembers'; ValueProperty='Category' }

$null = $Report |
    Add-PSISection -Title 'Ownership and Data Quality' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Normal -Text ("{0:N0} groups have no ManagedBy value and {1:N0} have no description. These are documentation and ownership observations, not security verdicts." -f $UnmanagedCount, $MissingDescriptionCount) |
    Add-PSIRow -Columns 6 |
    Add-PSIChart -Title 'Group Ownership Coverage' -ChartType Doughnut -Data (Get-PSIADGroupDistribution -Data $Groups -Property HasOwner) -CategoryProperty Category -ValueProperty Count -ShowLabels $true -FilterMetadata @{ Table='group-inventory'; Property='HasOwner'; ValueProperty='Category' }

$Insights = @(
    [pscustomobject]@{ Title='Empty Groups'; Value=$EmptyCount; Description="Direct member count <= $($Rules.EmptyGroupMaximumMembers)."; Icon='info'; Table='group-inventory'; Conditions=@(@{Property='MemberCount';Operator='LessThan';Value=($Rules.EmptyGroupMaximumMembers + 1)}); Evidence=@('GroupName','GroupCategory','GroupScope','Description','ManagedBy','Created','Modified'); Export=@('GroupName','GroupCategory','GroupScope','Description','ManagedBy','Created','Modified'); Labels=$GroupLabels },
    [pscustomobject]@{ Title='Large Groups'; Value=$LargeCount; Description="Direct member count >= $($Rules.LargeGroupMemberThreshold); investigation threshold only."; Icon='users'; Table='group-inventory'; Conditions=@(@{Property='MemberCount';Operator='GreaterThanOrEqual';Value=$Rules.LargeGroupMemberThreshold}); Evidence=@('GroupName','GroupScope','MemberCount','DirectUserCount','DirectGroupCount','ManagedBy'); Export=@('GroupName','GroupScope','MemberCount','DirectUserCount','DirectGroupCount','ManagedBy'); Labels=$GroupLabels },
    [pscustomobject]@{ Title='Groups With Disabled Members'; Value=$DisabledGroupCount; Description='At least one direct disabled-user membership.'; Icon='users'; Table='group-inventory'; Conditions=@(@{Property='DisabledUserCount';Operator='GreaterThanOrEqual';Value=1}); Evidence=@('GroupName','GroupCategory','GroupScope','DisabledUserCount','MemberCount','ManagedBy'); Export=@('GroupName','GroupCategory','GroupScope','DisabledUserCount','MemberCount','ManagedBy'); Labels=$GroupLabels },
    [pscustomobject]@{ Title='Groups With Nested Groups'; Value=$NestedGroupCount; Description='At least one direct child-group relationship.'; Icon='network'; Table='group-inventory'; Conditions=@(@{Property='NestedGroupCount';Operator='GreaterThanOrEqual';Value=1}); Evidence=@('GroupName','GroupScope','NestedGroupCount','MemberCount','ManagedBy'); Export=@('GroupName','GroupScope','NestedGroupCount','MemberCount','ManagedBy'); Labels=$GroupLabels },
    [pscustomobject]@{ Title='Groups Without Owner'; Value=$UnmanagedCount; Description='ManagedBy is empty; data-governance review candidate.'; Icon='info'; Table='group-inventory'; Conditions=@(@{Property='ManagedBy';Operator='IsEmpty'}); Evidence=@('GroupName','GroupCategory','GroupScope','Description','Created','Modified'); Export=@('GroupName','GroupCategory','GroupScope','Description','Created','Modified'); Labels=$GroupLabels },
    [pscustomobject]@{ Title='Groups Missing Description'; Value=$MissingDescriptionCount; Description='Description is empty; documentation review candidate.'; Icon='info'; Table='group-inventory'; Conditions=@(@{Property='Description';Operator='IsEmpty'}); Evidence=@('GroupName','GroupCategory','GroupScope','ManagedBy','Created','Modified'); Export=@('GroupName','GroupCategory','GroupScope','ManagedBy','Created','Modified'); Labels=$GroupLabels },
    [pscustomobject]@{ Title='Disabled User Membership Records'; Value=$DisabledMembershipCount; Description='Direct membership rows where a fictional user is disabled.'; Icon='users'; Table='group-memberships'; Conditions=@(@{Property='MemberType';Operator='Equals';Value='User'},@{Property='MemberEnabled';Operator='Equals';Value='No'}); Evidence=$MemberColumns; Export=$MemberColumns; Labels=$MemberLabels },
    [pscustomobject]@{ Title='Direct Nested Relationships'; Value=$Nested.Count; Description='Parent-to-child group edges; no recursive expansion.'; Icon='network'; Table='group-nesting'; Conditions=@(); Evidence=$NestedColumns; Export=$NestedColumns; Labels=$NestedLabels }
)
$null = $Report | Add-PSISection -Title 'Investigation Insights' | Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text 'Select an Insight to inspect evidence from the active table context. Search, filters, sorting, pagination, CSV, and XLSX use the same underlying rows; no evidence dataset is embedded again.'
for ($Offset = 0; $Offset -lt $Insights.Count; $Offset += 4) {
    $null = $Report | Add-PSIRow -Columns 12
    foreach ($Insight in @($Insights | Select-Object -Skip $Offset -First 4)) {
        $null = $Report | Add-PSIInsight -Title $Insight.Title -Value $Insight.Value -Description $Insight.Description -Status Info -Icon $Insight.Icon `
            -Filter @{ Table=$Insight.Table; Conditions=@($Insight.Conditions) } -EvidenceColumns $Insight.Evidence -ExportColumns $Insight.Export -ColumnLabels $Insight.Labels
    }
}

$null = $Report |
    Add-PSISection -Title 'Group Inventory' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'group-inventory' -Title 'Group Inventory' -Data $Groups -Columns $GroupColumns -ColumnLabels $GroupLabels -Filters $GroupFilters -PageSize 25 -ExportColumns $GroupExportColumns -WorksheetName 'Group Inventory' -NullValueText 'Not provided' -EmptyMessage 'No groups match the active search and filters.'

$null = $Report |
    Add-PSISection -Title 'Membership Inventory' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text 'Each row is one direct parent-to-member relationship. Disabled status applies only to user members; group members show Not applicable.' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'group-memberships' -Title 'Direct Membership Inventory' -Data $Memberships -Columns $MemberColumns -ColumnLabels $MemberLabels -Filters $MemberFilters -PageSize 50 -ExportColumns $MemberColumns -WorksheetName 'Direct Memberships' -NullValueText 'Not provided' -EmptyMessage 'No memberships match the active search and filters.'

$ObservationRows = @(
    [pscustomobject]@{ Observation='Empty groups'; Count=$EmptyCount; Interpretation='Confirm whether each group is intentionally retained.' },
    [pscustomobject]@{ Observation='Large groups'; Count=$LargeCount; Interpretation='Review purpose and direct membership against approved access design.' },
    [pscustomobject]@{ Observation='Groups with disabled users'; Count=$DisabledGroupCount; Interpretation='Review direct disabled-user memberships against lifecycle procedures.' },
    [pscustomobject]@{ Observation='Groups with nested groups'; Count=$NestedGroupCount; Interpretation='Document direct nesting and assess intent separately.' },
    [pscustomobject]@{ Observation='Groups without owner'; Count=$UnmanagedCount; Interpretation='Assign ownership where governance requires it.' },
    [pscustomobject]@{ Observation='Groups missing description'; Count=$MissingDescriptionCount; Interpretation='Document purpose where metadata standards require it.' }
)
$null = $Report |
    Add-PSISection -Title 'Findings and Recommendations' |
    Add-PSIRow -Columns 12 |
    Add-PSIStatus -Status Info -Label 'Observation-led review' -Message 'The sample defines only member-count investigation thresholds. The items below are review candidates, not vulnerabilities or compliance findings.' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'group-observations' -Title 'Observed Review Candidates' -Data $ObservationRows -Columns @('Observation','Count','Interpretation') -ExportColumns @('Observation','Count','Interpretation') -PageSize 10 |
    Add-PSIRow -Columns 12 |
    Add-PSIRecommendation -Status Info -Title 'Confirm empty and large group intent' -Description ("{0:N0} groups meet the empty threshold and {1:N0} meet the large threshold." -f $EmptyCount, $LargeCount) -ActionText 'Review Insight evidence with owners before cleanup or redesign.' |
    Add-PSIRecommendation -Status Info -Title 'Review disabled memberships and direct nesting' -Description ("{0:N0} direct disabled-user memberships and {1:N0} nested edges are present." -f $DisabledMembershipCount, $Nested.Count) -ActionText 'Compare against approved lifecycle and access design.' |
    Add-PSIRecommendation -Status Info -Title 'Improve ownership and descriptions' -Description ("{0:N0} groups lack ManagedBy and {1:N0} lack Description." -f $UnmanagedCount, $MissingDescriptionCount) -ActionText 'Confirm documentation expectations with the data owner.'

$null = $Report |
    Add-PSISection -Title 'Method and Data Handling' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text ("{0} Generated deterministically as of {1:yyyy-MM-dd}. LargeGroupMemberThreshold = {2}; EmptyGroupMaximumMembers = {3}. Large means direct members >= threshold; empty means direct members <= threshold. Neither is a risk verdict." -f $Sample.Source, $Sample.AsOfDate, $Rules.LargeGroupMemberThreshold, $Rules.EmptyGroupMaximumMembers) |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text 'Three normalized datasets are used: GroupInventory, GroupMemberships, and NestedGroupRelationships. Membership count is direct only. Nested rows are direct edges with depth 1. No recursive group expansion, effective access calculation, live AD query, or policy decision is performed. Table, evidence, and export fields are explicitly allowlisted; fictional distinguished names and account keys remain provider-only. Charts contain small aggregate counts.'

$Assessment = $Report
if ($AsAssessment) { return $Assessment }

# Standalone output uses the same assessment object as composed output.
$StandaloneReport = New-PSIReport -Title $Assessment.Title -Subtitle $Assessment.Description -Theme $Theme
$null = $StandaloneReport | Add-PSIAssessment -Assessment $Assessment
$OutputFile = Export-PSIReport -Report $StandaloneReport -Path $OutputPath
Write-Host "Generated report: $($OutputFile.FullName)"
Write-Host ("Fictional sample: {0:N0} groups; {1:N0} direct memberships; {2:N0} direct nested edges." -f $Groups.Count, $Memberships.Count, $Nested.Count)

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
