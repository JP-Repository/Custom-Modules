[CmdletBinding()]
param(
    [Parameter()][ValidateNotNullOrEmpty()][string] $OutputPath,
    [Parameter()][ValidateSet('Light','Dark','Auto')][string] $Theme = 'Auto',
    [Parameter()][hashtable] $Rules = @{},
    [Parameter()][switch] $NoBrowser,
    [Parameter()][switch] $AsAssessment
)

$ErrorActionPreference = 'Stop'
$ModuleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent
. (Join-Path $PSScriptRoot 'PSIADSitesSubnets.Provider.ps1')
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path (Join-Path $ModuleRoot 'Reports') 'PSInsightHTML-SitesSubnetsAssessment.html'
}
$Sample = New-PSIADSitesSubnetsSampleData -Rules $Rules
$Sites = $Sample.SiteInventory
$Subnets = $Sample.SubnetInventory
$DCs = $Sample.DomainControllerPlacement
$Links = $Sample.SiteLinkInventory
$Overlaps = $Sample.SubnetOverlapEvidence
$Membership = $Sample.SiteLinkMembership
$Policy = $Sample.Rules

# Every HTML field is reviewed here. Hidden provider range values never enter table rows.
$SiteColumns = @('SiteName','Region','Description','DomainControllerCount','SubnetCount','SiteLinkCount','HasDomainController','HasSiteLink','TopologyState')
$SiteLabels = @{SiteName='Site';Region='Region';Description='Description';DomainControllerCount='DC count';SubnetCount='Subnet count';SiteLinkCount='Site links';HasDomainController='Has DC';HasSiteLink='Has site link';TopologyState='Topology state'}
$SubnetColumns = @('SubnetCIDR','NetworkAddress','PrefixLength','SiteName','Description','ObservedDCCount','OverlapState','CrossSiteOverlap','CoverageState')
$SubnetLabels = @{SubnetCIDR='Subnet';NetworkAddress='Network address';PrefixLength='Prefix';SiteName='Site';Description='Description';ObservedDCCount='Observed DCs';OverlapState='Overlap state';CrossSiteOverlap='Cross-site overlap';CoverageState='DC address coverage'}
$DCColumns = @('DCName','IPv4Address','ConfiguredSite','MatchedSubnet','MatchedSubnetSite','MatchPrefixLength','SiteAssignmentState','MatchingSubnetCount')
$DCLabels = @{DCName='DC name';IPv4Address='IPv4 address';ConfiguredSite='Configured site';MatchedSubnet='Best matched subnet';MatchedSubnetSite='Matched subnet site';MatchPrefixLength='Matched prefix';SiteAssignmentState='Assignment state';MatchingSubnetCount='Matching subnets'}
$LinkColumns = @('SiteLinkName','Transport','SiteCount','Cost','ReplicationIntervalMinutes','ScheduleState','Options','CostBand','IntervalBand','TopologyState')
$LinkLabels = @{SiteLinkName='Site link';Transport='Transport';SiteCount='Member sites';Cost='Cost';ReplicationIntervalMinutes='Interval (minutes)';ScheduleState='Schedule';Options='Options';CostBand='Cost band';IntervalBand='Interval band';TopologyState='Topology state'}
$OverlapColumns = @('SubnetA','SiteA','PrefixA','SubnetB','SiteB','PrefixB','OverlapType','CrossSite')
$OverlapLabels = @{SubnetA='Subnet A';SiteA='Site A';PrefixA='Prefix A';SubnetB='Subnet B';SiteB='Site B';PrefixB='Prefix B';OverlapType='Overlap type';CrossSite='Cross-site'}
$MemberColumns = @('SiteLinkName','SiteName','Region')
$MemberLabels = @{SiteLinkName='Site link';SiteName='Member site';Region='Region'}

$SiteFilters = @(
    Add-PSIFilter -Property Region -Label 'Region' -Values @($Sites.Region | Sort-Object -Unique)
    Add-PSIFilter -Property HasDomainController -Label 'Has DC' -Values @('Yes','No')
    Add-PSIFilter -Property HasSiteLink -Label 'Has site link' -Values @('Yes','No')
    Add-PSIFilter -Property TopologyState -Label 'Topology state' -Values @('Configured','Review candidate')
    Add-PSIFilter -Property SiteName -Label 'Site' -Values @($Sites.SiteName | Sort-Object)
)
$SubnetFilters = @(
    Add-PSIFilter -Property SiteName -Label 'Site' -Values @($Sites.SiteName | Sort-Object)
    Add-PSIFilter -Property PrefixLength -Label 'Prefix' -Values @($Subnets.PrefixLength | Sort-Object -Unique)
    Add-PSIFilter -Property OverlapState -Label 'Overlap' -Values @('None','Overlap candidate')
    Add-PSIFilter -Property CrossSiteOverlap -Label 'Cross-site' -Values @('Yes','No')
    Add-PSIFilter -Property CoverageState -Label 'DC address coverage' -Values @('DC address observed','No DC address observed')
)
$DCFilters = @(
    Add-PSIFilter -Property ConfiguredSite -Label 'Configured site' -Values @($Sites.SiteName | Sort-Object)
    Add-PSIFilter -Property MatchedSubnetSite -Label 'Matched site' -Values @($Sites.SiteName | Sort-Object)
    Add-PSIFilter -Property SiteAssignmentState -Label 'Assignment state' -Values @('Matched','NoSubnetMatch','SiteMismatch','AmbiguousMatch')
)
$LinkFilters = @(
    Add-PSIFilter -Property CostBand -Label 'Cost band' -Values @('Below threshold','At or above threshold')
    Add-PSIFilter -Property IntervalBand -Label 'Interval band' -Values @('Below threshold','At or above threshold')
    Add-PSIFilter -Property TopologyState -Label 'Topology state' -Values @('Configured','Review candidate')
)
$OverlapFilters = @(
    Add-PSIFilter -Property CrossSite -Label 'Cross-site' -Values @('Yes','No')
    Add-PSIFilter -Property OverlapType -Label 'Overlap type' -Values @($Overlaps.OverlapType | Sort-Object -Unique)
)
$MemberFilters = @(
    Add-PSIFilter -Property SiteLinkName -Label 'Site link' -Values @($Links.SiteLinkName | Sort-Object)
    Add-PSIFilter -Property SiteName -Label 'Site' -Values @($Sites.SiteName | Sort-Object)
)

$UnmatchedCount = @($DCs | Where-Object SiteAssignmentState -eq 'NoSubnetMatch').Count
$MismatchCount = @($DCs | Where-Object SiteAssignmentState -eq 'SiteMismatch').Count
$OverlapSubnetCount = @($Subnets | Where-Object OverlapState -eq 'Overlap candidate').Count
$CrossOverlapCount = @($Overlaps | Where-Object CrossSite -eq 'Yes').Count
$NoDCCount = @($Sites | Where-Object HasDomainController -eq 'No').Count
$SingleDCCount = @($Sites | Where-Object DomainControllerCount -eq 1).Count
$NoLinkCount = @($Sites | Where-Object HasSiteLink -eq 'No').Count
$HighCostCount = @($Links | Where-Object { $_.Cost -ge $Policy.HighSiteLinkCostThreshold }).Count
$LongIntervalCount = @($Links | Where-Object { $_.ReplicationIntervalMinutes -ge $Policy.LongReplicationIntervalMinutes }).Count

# Build reusable assessment content through the shared component API.
$Report = New-PSIAssessment -Name 'Sites and Subnets' -Provider 'ActiveDirectory' -Title 'Active Directory Sites & Subnets Assessment' -Description 'Fictional topology investigation | PSInsightHTML'
$null = $Report |
    Add-PSISection -Title 'Executive Summary' |
    Add-PSIRow -Columns 12 |
    Add-PSIKPI -Title 'Sites' -Value $Sites.Count -Subtitle 'Configured fictional sites' -Status Info -Icon 'network' |
    Add-PSIKPI -Title 'Subnets' -Value $Subnets.Count -Subtitle 'Configured IPv4 prefixes' -Status Info -Icon 'network' |
    Add-PSIKPI -Title 'Domain Controllers' -Value $DCs.Count -Subtitle 'Fictional DC placements' -Status Info -Icon 'server' |
    Add-PSIKPI -Title 'Site Links' -Value $Links.Count -Subtitle 'IP transport examples' -Status Info -Icon 'replication' |
    Add-PSIRow -Columns 12 |
    Add-PSIKPI -Title 'DCs Without Subnet Match' -Value $UnmatchedCount -Subtitle 'Select matching evidence' -Status Info -Icon 'info' -Filter @{Table='ss-dcs';Property='SiteAssignmentState';Value='NoSubnetMatch'} |
    Add-PSIKPI -Title 'DC Site Mismatches' -Value $MismatchCount -Subtitle 'Best subnet maps to another site' -Status Info -Icon 'info' -Filter @{Table='ss-dcs';Property='SiteAssignmentState';Value='SiteMismatch'} |
    Add-PSIKPI -Title 'Overlapping Subnets' -Value $OverlapSubnetCount -Subtitle 'Unique configured subnet rows' -Status Info -Icon 'info' -Filter @{Table='ss-subnets';Property='OverlapState';Value='Overlap candidate'} |
    Add-PSIKPI -Title 'Sites Without DCs' -Value $NoDCCount -Subtitle 'Local DC presence not established' -Status Info -Icon 'info' -Filter @{Table='ss-sites';Property='HasDomainController';Value='No'} |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text ("Fictional sample data only $([char] 0x00B7) {0} sites $([char] 0x00B7) {1} subnets $([char] 0x00B7) {2} DCs $([char] 0x00B7) {3} site links. Observations are investigation candidates, not vulnerability or compliance verdicts." -f $Sites.Count,$Subnets.Count,$DCs.Count,$Links.Count)

$null = $Report |
    Add-PSISection -Title 'Site Overview' |
    Add-PSIRow -Columns 12 |
    Add-PSIStatus -Status Info -Label 'Site distribution' -Message 'The sample includes multi-DC, single-DC, and zero-DC sites across three fictional regions.' |
    Add-PSIRow -Columns 6 |
    Add-PSIChart -Title 'DCs by Site' -ChartType Bar -Data @($Sites | ForEach-Object { [pscustomobject]@{Category=$_.SiteName;Count=$_.DomainControllerCount} }) -CategoryProperty Category -ValueProperty Count -ShowLegend $false -FilterMetadata @{Table='ss-dcs';Property='ConfiguredSite';ValueProperty='Category'} |
    Add-PSIChart -Title 'Sites With / Without DCs' -ChartType Doughnut -Data (Get-PSIADSitesSubnetsDistribution -Data $Sites -Property HasDomainController) -CategoryProperty Category -ValueProperty Count -ShowLabels $true -FilterMetadata @{Table='ss-sites';Property='HasDomainController';ValueProperty='Category'}

$null = $Report |
    Add-PSISection -Title 'Domain Controller Placement' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Normal -Text ('Longest-prefix matching identified {0} DC address without a configured subnet and {1} DCs whose most-specific matching subnet maps to a different site. Overlapping candidates are evaluated separately.' -f $UnmatchedCount,$MismatchCount) |
    Add-PSIRow -Columns 6 |
    Add-PSIChart -Title 'DC Placement State' -ChartType Doughnut -Data (Get-PSIADSitesSubnetsDistribution -Data $DCs -Property SiteAssignmentState) -CategoryProperty Category -ValueProperty Count -ShowLabels $true -FilterMetadata @{Table='ss-dcs';Property='SiteAssignmentState';ValueProperty='Category'}

$null = $Report |
    Add-PSISection -Title 'Subnet Coverage' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Normal -Text 'Observed DC count means a fictional DC address falls within a configured prefix. It does not measure clients, users, applications, or subnet utilization.' |
    Add-PSIRow -Columns 6 |
    Add-PSIChart -Title 'Subnets by Site' -ChartType Bar -Data @($Sites | ForEach-Object { [pscustomobject]@{Category=$_.SiteName;Count=$_.SubnetCount} }) -CategoryProperty Category -ValueProperty Count -ShowLegend $false -FilterMetadata @{Table='ss-subnets';Property='SiteName';ValueProperty='Category'} |
    Add-PSIChart -Title 'Subnet Prefix Length' -ChartType Bar -Data (Get-PSIADSitesSubnetsDistribution -Data $Subnets -Property PrefixLength) -CategoryProperty Category -ValueProperty Count -ShowLegend $false -FilterMetadata @{Table='ss-subnets';Property='PrefixLength';ValueProperty='Category'}

$null = $Report |
    Add-PSISection -Title 'Subnet Overlap Analysis' |
    Add-PSIRow -Columns 12 |
    Add-PSIStatus -Status Info -Label 'Overlap candidates' -Message ('{0} subnet pairs overlap; {1} pairs map to different sites. Some overlaps may be intentional; compare with intended AD site design.' -f $Overlaps.Count,$CrossOverlapCount) |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'ss-overlaps' -Title 'Subnet Overlap Pairs' -Data $Overlaps -Columns $OverlapColumns -ColumnLabels $OverlapLabels -Filters $OverlapFilters -PageSize 10 -ExportColumns $OverlapColumns -WorksheetName 'Subnet Overlaps'

$null = $Report |
    Add-PSISection -Title 'Site Link Configuration' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Normal -Text 'Site-link membership is modeled as separate site/link rows, preserving all member sites without flattening the relationship. Costs and intervals are configuration observations.' |
    Add-PSIRow -Columns 6 |
    Add-PSIChart -Title 'Site Link Cost Distribution' -ChartType Doughnut -Data (Get-PSIADSitesSubnetsDistribution -Data $Links -Property CostBand) -CategoryProperty Category -ValueProperty Count -ShowLabels $true -FilterMetadata @{Table='ss-links';Property='CostBand';ValueProperty='Category'} |
    Add-PSIChart -Title 'Replication Interval Distribution' -ChartType Doughnut -Data (Get-PSIADSitesSubnetsDistribution -Data $Links -Property IntervalBand) -CategoryProperty Category -ValueProperty Count -ShowLabels $true -FilterMetadata @{Table='ss-links';Property='IntervalBand';ValueProperty='Category'}

$null = $Report |
    Add-PSISection -Title 'Topology Observations' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Normal -Text ('{0} site has no DC, {1} site has one DC, and {2} sites have no site-link membership in this fictional configuration. A site without a DC can be intentional; site-link participation should be assessed against intended routing.' -f $NoDCCount,$SingleDCCount,$NoLinkCount)

$Insights = @(
    [pscustomobject]@{Title='DCs Without Matching Subnet';Value=$UnmatchedCount;Description='DC IP address does not fall within any configured sample subnet.';Icon='network';Table='ss-dcs';Conditions=@(@{Property='SiteAssignmentState';Operator='Equals';Value='NoSubnetMatch'});Evidence=$DCColumns;Export=$DCColumns;Labels=$DCLabels},
    [pscustomobject]@{Title='DC Site Assignment Mismatches';Value=$MismatchCount;Description='Configured site differs from the most-specific matching subnet site.';Icon='server';Table='ss-dcs';Conditions=@(@{Property='SiteAssignmentState';Operator='Equals';Value='SiteMismatch'});Evidence=$DCColumns;Export=$DCColumns;Labels=$DCLabels},
    [pscustomobject]@{Title='Overlapping Subnets';Value=$OverlapSubnetCount;Description='Unique subnet definitions participating in at least one overlap pair.';Icon='network';Table='ss-subnets';Conditions=@(@{Property='OverlapState';Operator='Equals';Value='Overlap candidate'});Evidence=$SubnetColumns;Export=$SubnetColumns;Labels=$SubnetLabels},
    [pscustomobject]@{Title='Cross-Site Overlapping Subnets';Value=$CrossOverlapCount;Description='Overlap pairs whose configured sites differ.';Icon='network';Table='ss-overlaps';Conditions=@(@{Property='CrossSite';Operator='Equals';Value='Yes'});Evidence=$OverlapColumns;Export=$OverlapColumns;Labels=$OverlapLabels},
    [pscustomobject]@{Title='Sites Without Domain Controllers';Value=$NoDCCount;Description='No fictional DC is assigned to these sites.';Icon='server';Table='ss-sites';Conditions=@(@{Property='HasDomainController';Operator='Equals';Value='No'});Evidence=$SiteColumns;Export=$SiteColumns;Labels=$SiteLabels},
    [pscustomobject]@{Title='Sites With Single Domain Controller';Value=$SingleDCCount;Description='Exactly one fictional DC is assigned to these sites.';Icon='server';Table='ss-sites';Conditions=@(@{Property='DomainControllerCount';Operator='Equals';Value=1});Evidence=$SiteColumns;Export=$SiteColumns;Labels=$SiteLabels},
    [pscustomobject]@{Title='High-Cost Site Links';Value=$HighCostCount;Description=('Cost at or above demonstration threshold {0}.' -f $Policy.HighSiteLinkCostThreshold);Icon='replication';Table='ss-links';Conditions=@(@{Property='Cost';Operator='GreaterThanOrEqual';Value=$Policy.HighSiteLinkCostThreshold});Evidence=$LinkColumns;Export=$LinkColumns;Labels=$LinkLabels},
    [pscustomobject]@{Title='Long Replication Interval Site Links';Value=$LongIntervalCount;Description=('Interval at or above demonstration threshold {0} minutes.' -f $Policy.LongReplicationIntervalMinutes);Icon='replication';Table='ss-links';Conditions=@(@{Property='ReplicationIntervalMinutes';Operator='GreaterThanOrEqual';Value=$Policy.LongReplicationIntervalMinutes});Evidence=$LinkColumns;Export=$LinkColumns;Labels=$LinkLabels},
    [pscustomobject]@{Title='Sites Missing Site-Link Participation';Value=$NoLinkCount;Description='No membership row references these sites.';Icon='network';Table='ss-sites';Conditions=@(@{Property='HasSiteLink';Operator='Equals';Value='No'});Evidence=$SiteColumns;Export=$SiteColumns;Labels=$SiteLabels}
)
$null = $Report |
    Add-PSISection -Title 'Investigation Insights' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text 'Each Insight opens the shared Evidence Viewer against a single table dataset. Active table search and filters carry into evidence; evidence supports search, sorting, pagination, filtered CSV, and genuine XLSX.'
for ($Offset = 0; $Offset -lt $Insights.Count; $Offset += 3) {
    $null = $Report | Add-PSIRow -Columns 12
    foreach ($Insight in @($Insights | Select-Object -Skip $Offset -First 3)) {
        $null = $Report | Add-PSIInsight -Title $Insight.Title -Value $Insight.Value -Description $Insight.Description -Status Info -Icon $Insight.Icon -Filter @{Table=$Insight.Table;Conditions=@($Insight.Conditions)} -EvidenceColumns $Insight.Evidence -ExportColumns $Insight.Export -ColumnLabels $Insight.Labels
    }
}

$null = $Report | Add-PSISection -Title 'Site Inventory' | Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'ss-sites' -Title 'AD Site Inventory' -Data $Sites -Columns $SiteColumns -ColumnLabels $SiteLabels -Filters $SiteFilters -PageSize 10 -ExportColumns $SiteColumns -WorksheetName 'Sites'
$null = $Report | Add-PSISection -Title 'Subnet Inventory' | Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'ss-subnets' -Title 'Configured IPv4 Subnets' -Data $Subnets -Columns $SubnetColumns -ColumnLabels $SubnetLabels -Filters $SubnetFilters -PageSize 20 -ExportColumns $SubnetColumns -WorksheetName 'Subnets'
$null = $Report | Add-PSISection -Title 'Domain Controller Placement Inventory' | Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'ss-dcs' -Title 'DC-to-Site Placement' -Data $DCs -Columns $DCColumns -ColumnLabels $DCLabels -Filters $DCFilters -PageSize 20 -ExportColumns $DCColumns -WorksheetName 'DC Placement' -NullValueText 'No subnet match'
$null = $Report | Add-PSISection -Title 'Site Link Inventory' | Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'ss-links' -Title 'Site Link Configuration' -Data $Links -Columns $LinkColumns -ColumnLabels $LinkLabels -Filters $LinkFilters -PageSize 10 -ExportColumns $LinkColumns -WorksheetName 'Site Links' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'ss-membership' -Title 'Site Link Membership' -Data $Membership -Columns $MemberColumns -ColumnLabels $MemberLabels -Filters $MemberFilters -PageSize 20 -ExportColumns $MemberColumns -WorksheetName 'Site Link Membership'

$null = $Report |
    Add-PSISection -Title 'Findings and Recommendations' |
    Add-PSIRow -Columns 12 |
    Add-PSIRecommendation -Status Info -Title 'Review unmatched DC addresses' -Description ("$UnmatchedCount DC address has no configured subnet match in the sample.") -ActionText 'Confirm whether a subnet definition is missing or the DC address is intentionally outside the configured topology.' |
    Add-PSIRecommendation -Status Info -Title 'Review site assignment mismatches' -Description ("$MismatchCount DCs resolve to a subnet assigned to a different site.") -ActionText 'Compare each DC address, most-specific subnet, and intended site assignment.' |
    Add-PSIRecommendation -Status Info -Title 'Review cross-site overlaps' -Description ("$CrossOverlapCount overlap pairs map to different sites; overlap alone is not a defect.") -ActionText 'Document intended precedence and correct definitions only when they conflict with the approved site design.' |
    Add-PSIRecommendation -Status Info -Title 'Validate local DC and site-link intent' -Description ("$NoDCCount site has no DC, $SingleDCCount has one DC, and $NoLinkCount sites have no link membership.") -ActionText 'Review local authentication, resilience, and topology requirements for each site.' |
    Add-PSIRecommendation -Status Info -Title 'Review site-link thresholds' -Description ("$HighCostCount links meet the sample cost threshold and $LongIntervalCount meet the sample interval threshold.") -ActionText 'Document intentionally high costs and long intervals against the approved replication design.'

$null = $Report |
    Add-PSISection -Title 'Method and Data Handling' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text ("$($Sample.Source) All names use example.invalid and addresses use private 10.77.0.0/16 examples. No live AD, DNS, or network calls are made.") |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text ('Demonstration rules: ExpectedMinimumDCsPerSite = {0}; HighSiteLinkCostThreshold = {1}; LongReplicationIntervalMinutes = {2}. Values are configurable report investigation thresholds, not Microsoft policy, compliance, or vulnerability requirements.' -f $Policy.ExpectedMinimumDCsPerSite,$Policy.HighSiteLinkCostThreshold,$Policy.LongReplicationIntervalMinutes) |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text 'IPv4 CIDRs are canonicalized to network boundaries. The matching provider compares every containing configured subnet and selects the longest prefix. Equal-best prefixes mapped to different sites are ambiguous. Overlap pairs are recorded separately; cross-site overlap deserves design review. Observed DC counts include any DC address within a prefix, including broader overlapping prefixes, and do not imply client inventory or subnet utilization.' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text 'Normalized site, subnet, DC placement, site-link, overlap-pair, and site-link membership datasets each appear once as table rows. Charts hold small aggregates; KPIs and Insights hold reference metadata. Export columns are explicit reviewed allowlists. The report is standalone with embedded CSS and JavaScript.'

$Assessment = $Report
if ($AsAssessment) { return $Assessment }

# Standalone output uses the same assessment object as composed output.
$StandaloneReport = New-PSIReport -Title $Assessment.Title -Subtitle $Assessment.Description -Theme $Theme
$null = $StandaloneReport | Add-PSIAssessment -Assessment $Assessment
$OutputFile = Export-PSIReport -Report $StandaloneReport -Path $OutputPath
Write-Host "Generated report: $($OutputFile.FullName)"
Write-Host ('Fictional sample: {0} sites; {1} subnets; {2} DCs; {3} links; {4} overlap pairs; {5} membership rows.' -f $Sites.Count,$Subnets.Count,$DCs.Count,$Links.Count,$Overlaps.Count,$Membership.Count)
if (-not $NoBrowser) {
    $IsWindowsHost = $env:OS -eq 'Windows_NT'
    $IsMacHost = $false; $IsLinuxHost = $false
    if (-not $IsWindowsHost -and $PSVersionTable.PSEdition -eq 'Core') {
        $IsMacHost = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)
        $IsLinuxHost = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Linux)
    }
    try {
        if ($IsWindowsHost) { Start-Process -FilePath $OutputFile.FullName -ErrorAction Stop }
        elseif ($IsMacHost) { $OpenProcess = Start-Process -FilePath 'open' -ArgumentList @($OutputFile.FullName) -Wait -PassThru -ErrorAction Stop; if ($OpenProcess.ExitCode -ne 0) { throw "macOS open exited with code $($OpenProcess.ExitCode)." } }
        elseif ($IsLinuxHost) { $OpenProcess = Start-Process -FilePath 'xdg-open' -ArgumentList @($OutputFile.FullName) -Wait -PassThru -ErrorAction Stop; if ($OpenProcess.ExitCode -ne 0) { throw "xdg-open exited with code $($OpenProcess.ExitCode)." } }
        else { throw 'No supported browser-open command was detected.' }
        Write-Host 'Browser open requested.'
    }
    catch { Write-Warning "Could not open the report in the default browser: $($_.Exception.Message)" }
}
$OutputFile
