[CmdletBinding()]
param(
    [Parameter()][ValidateNotNullOrEmpty()][string] $OutputPath,
    [Parameter()][ValidateSet('Light', 'Dark', 'Auto')][string] $Theme = 'Auto',
    [Parameter()][ValidateRange(50, 60)][int] $DomainControllerCount = 56,
    [Parameter()][hashtable] $Thresholds = @{},
    [Parameter()][datetime] $AsOfDate = [datetime]::new(2026, 9, 27, 12, 0, 0),
    [Parameter()][switch] $NoBrowser,
    [Parameter()][switch] $AsAssessment
)

$ErrorActionPreference = 'Stop'
$ModuleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent
. (Join-Path $PSScriptRoot 'PSIADReplication.Provider.ps1')
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path (Join-Path $ModuleRoot 'Reports') 'PSInsightHTML-ReplicationAssessment.html'
}

$Sample = New-PSIADReplicationSampleData -DomainControllerCount $DomainControllerCount -Thresholds $Thresholds -AsOfDate $AsOfDate
$Dcs = $Sample.DomainControllerInventory
$Relationships = $Sample.ReplicationRelationships
$Errors = $Sample.ReplicationErrors
$Sites = $Sample.SiteReplicationSummary
$Rules = $Sample.Thresholds
$HealthyCount = @($Relationships | Where-Object ReplicationState -eq 'Healthy').Count
$WarningCount = @($Relationships | Where-Object ReplicationState -eq 'Warning').Count
$CriticalCount = @($Relationships | Where-Object ReplicationState -eq 'Critical').Count
$UnknownCount = @($Relationships | Where-Object ReplicationState -eq 'Unknown').Count
$CriticalAgeCount = @($Relationships | Where-Object CriticalAge -eq 'Yes').Count
$WarningAgeCount = @($Relationships | Where-Object { $null -ne $_.ReplicationAgeMinutes -and $_.ReplicationAgeMinutes -ge $Rules.WarningReplicationAgeMinutes }).Count
$InterSiteIssueCount = @($Relationships | Where-Object { $_.LinkType -eq 'Inter-site' -and $_.ReplicationState -ne 'Healthy' }).Count
$RepeatedFailureCount = @($Relationships | Where-Object { $_.ConsecutiveFailures -ge $Rules.ConsecutiveFailureThreshold }).Count
$RpcCount = @($Errors | Where-Object ErrorCategory -eq 'RPC').Count
$MultiplePartnerDcs = @($Dcs | Where-Object { $_.FailingPartnerCount -ge $Rules.MultipleFailingPartnerThreshold })
$NeverSuccessfulCount = @($Relationships | Where-Object { $null -eq $_.LastSuccess }).Count
$RecoveredCount = @($Relationships | Where-Object RecoveryState -eq 'Recovered').Count
$WorstAge = [int] (($Relationships | Where-Object { $null -ne $_.ReplicationAgeMinutes } | Measure-Object -Property ReplicationAgeMinutes -Maximum).Maximum)
$DistinctErrorCodes = @($Errors.ErrorCode | Sort-Object -Unique).Count

# The visible, evidence, and export fields are reviewed separately. Full relationship rows appear once in HTML.
$RelationshipColumns = @('SourceDC','DestinationDC','SourceSite','DestinationSite','NamingContextLabel','NamingContext','LastAttempt','LastSuccess','ReplicationAgeMinutes','ConsecutiveFailures','PreviousFailureCount','LastResultCode','LastResultMessage','ReplicationState','AgeBucket','LinkType','IsFailure','CriticalAge','RecoveryState','PartnerAvailability','ErrorCategory')
$RelationshipLabels = @{
    SourceDC='Source DC'; DestinationDC='Destination DC'; SourceSite='Source site'; DestinationSite='Destination site'
    NamingContextLabel='Naming context type'; NamingContext='Naming context'; LastAttempt='Last attempt'; LastSuccess='Last success'
    ReplicationAgeMinutes='Age (minutes)'; ConsecutiveFailures='Consecutive failures'; PreviousFailureCount='Previous failures in sample'
    LastResultCode='Last result code'; LastResultMessage='Last result message'; ReplicationState='Replication state'
    AgeBucket='Age bucket'; LinkType='Site relationship'; IsFailure='Current failure'; CriticalAge='Critical age threshold'
    RecoveryState='Recovery state'; PartnerAvailability='Partner availability'; ErrorCategory='Error category'
}
$RelationshipExportColumns = @('SourceDC','DestinationDC','SourceSite','DestinationSite','NamingContext','LastAttempt','LastSuccess','ReplicationAgeMinutes','ConsecutiveFailures','LastResultCode','LastResultMessage','ReplicationState','LinkType','PartnerAvailability')
$RelationshipEvidenceColumns = @('SourceDC','DestinationDC','SourceSite','DestinationSite','NamingContext','LastAttempt','LastSuccess','ReplicationAgeMinutes','ConsecutiveFailures','LastResultCode','LastResultMessage','ReplicationState')
$DcColumns = @('DCName','Site','Domain','OperatingSystem','IPv4Address','InboundPartnerCount','OutboundPartnerCount','FailingPartnerCount','WorstReplicationAgeMinutes','UnknownRelationshipCount','ReplicationState','MultipleFailingPartners')
$DcLabels = @{ DCName='Domain controller'; Site='Site'; Domain='Domain'; OperatingSystem='Operating system'; IPv4Address='IPv4 address'; InboundPartnerCount='Inbound partners'; OutboundPartnerCount='Outbound partners'; FailingPartnerCount='Failing inbound partners'; WorstReplicationAgeMinutes='Worst age (minutes)'; UnknownRelationshipCount='Unknown relationships'; ReplicationState='Aggregate state'; MultipleFailingPartners='Multiple failing partners' }
$DcExportColumns = @('DCName','Site','Domain','OperatingSystem','IPv4Address','InboundPartnerCount','OutboundPartnerCount','FailingPartnerCount','WorstReplicationAgeMinutes','ReplicationState')
$ErrorColumns = @('SourceDC','DestinationDC','SourceSite','DestinationSite','NamingContext','ErrorCode','ErrorMessage','ErrorCategory','ConsecutiveFailures','LastAttempt','LastSuccess','PartnerAvailability')
$ErrorLabels = @{ SourceDC='Source DC'; DestinationDC='Destination DC'; SourceSite='Source site'; DestinationSite='Destination site'; NamingContext='Naming context'; ErrorCode='Error code'; ErrorMessage='Error message'; ErrorCategory='Error category'; ConsecutiveFailures='Consecutive failures'; LastAttempt='Last attempt'; LastSuccess='Last success'; PartnerAvailability='Partner availability' }
$ErrorExportColumns = @('SourceDC','DestinationDC','SourceSite','DestinationSite','NamingContext','ErrorCode','ErrorMessage','ConsecutiveFailures','LastAttempt','LastSuccess')
$SiteColumns = @('SiteName','DomainControllerCount','ReplicationRelationshipCount','HealthyCount','WarningCount','CriticalCount','UnknownCount','FailureCount','WorstReplicationAgeMinutes')
$SiteLabels = @{ SiteName='Destination site'; DomainControllerCount='Domain controllers'; ReplicationRelationshipCount='Inbound relationships'; HealthyCount='Healthy'; WarningCount='Warning'; CriticalCount='Critical'; UnknownCount='Unknown'; FailureCount='Current failures'; WorstReplicationAgeMinutes='Worst age (minutes)' }

$SiteValues = @($Sites.SiteName)
$RelationshipFilters = @(
    Add-PSIFilter -Property ReplicationState -Label 'State' -Values @('Healthy','Warning','Critical','Unknown')
    Add-PSIFilter -Property SourceSite -Label 'Source site' -Values $SiteValues
    Add-PSIFilter -Property DestinationSite -Label 'Destination site' -Values $SiteValues
    Add-PSIFilter -Property NamingContextLabel -Label 'Naming context' -Values @($Relationships.NamingContextLabel | Sort-Object -Unique)
    Add-PSIFilter -Property LastResultCode -Label 'Last result code' -Values @($Relationships.LastResultCode | Sort-Object -Unique)
    Add-PSIFilter -Property LinkType -Label 'Site relationship' -Values @('Intra-site','Inter-site')
    Add-PSIFilter -Property AgeBucket -Label 'Age bucket' -Values @($Relationships.AgeBucket | Sort-Object -Unique)
    Add-PSIFilter -Property IsFailure -Label 'Current failure' -Values @('Yes','No')
    Add-PSIFilter -Property CriticalAge -Label 'Critical age threshold' -Values @('Yes','No')
    Add-PSIFilter -Property RecoveryState -Label 'Recovery' -Values @('Recovered','Not observed')
)
$DcFilters = @(
    Add-PSIFilter -Property Site -Label 'Site' -Values $SiteValues
    Add-PSIFilter -Property ReplicationState -Label 'Aggregate state' -Values @($Dcs.ReplicationState | Sort-Object -Unique)
    Add-PSIFilter -Property MultipleFailingPartners -Label 'Multiple failing partners' -Values @('Yes','No')
)
$ErrorFilters = @(
    Add-PSIFilter -Property ErrorCode -Label 'Error code' -Values @($Errors.ErrorCode | Sort-Object -Unique)
    Add-PSIFilter -Property ErrorCategory -Label 'Error category' -Values @($Errors.ErrorCategory | Sort-Object -Unique)
    Add-PSIFilter -Property DestinationSite -Label 'Destination site' -Values $SiteValues
    Add-PSIFilter -Property PartnerAvailability -Label 'Partner availability' -Values @($Errors.PartnerAvailability | Sort-Object -Unique)
)

$SiteFailureChart = @($Sites | ForEach-Object { [pscustomobject]@{ Category=$_.SiteName; Count=$_.FailureCount } })
$ProblemRelationships = @($Relationships | Where-Object ReplicationState -ne 'Healthy')
# Build reusable assessment content through the shared component API.
$Report = New-PSIAssessment -Name 'Replication' -Provider 'ActiveDirectory' -Title 'Active Directory Replication Health Assessment' `
    -Description 'Fictional multi-site replication snapshot | PSInsightHTML'

$null = $Report |
    Add-PSISection -Title 'Executive Summary' |
    Add-PSIRow -Columns 12 |
    Add-PSIKPI -Title 'Domain Controllers' -Value $Dcs.Count -Subtitle 'Fictional inventory' -Status Info -Icon 'server' |
    Add-PSIKPI -Title 'Replication Relationships' -Value $Relationships.Count -Subtitle 'Inbound partner and naming-context rows' -Status Info -Icon 'replication' |
    Add-PSIKPI -Title 'Healthy Relationships' -Value $HealthyCount -Subtitle 'Select to filter relationship inventory' -Status Info -Icon 'healthy' -Filter @{ Table='replication-relationships'; Property='ReplicationState'; Value='Healthy' } |
    Add-PSIKPI -Title 'Relationships With Failures' -Value $Errors.Count -Subtitle 'Current nonzero result codes' -Status Info -Icon 'warning' -Filter @{ Table='replication-relationships'; Property='IsFailure'; Value='Yes' } |
    Add-PSIRow -Columns 12 |
    Add-PSIKPI -Title 'Critical Replication Age' -Value $CriticalAgeCount -Subtitle "Age >= $($Rules.CriticalReplicationAgeMinutes) minutes" -Status Info -Icon 'critical' -Filter @{ Table='replication-relationships'; Property='CriticalAge'; Value='Yes' } |
    Add-PSIKPI -Title 'Sites' -Value $Sites.Count -Subtitle 'Fictional AD sites' -Status Info -Icon 'network' |
    Add-PSIKPI -Title 'Worst Replication Age' -Value "$WorstAge min" -Subtitle 'Known last-success timestamps only' -Status Info -Icon 'info' |
    Add-PSIKPI -Title 'Distinct Error Codes' -Value $DistinctErrorCodes -Subtitle 'Current failed attempts' -Status Info -Icon 'warning'
$null = $Report | Add-PSIRow -Columns 12 | Add-PSIText -Size Small -Text (
    "Fictional sample data only $([char] 0x00B7) {0} DCs $([char] 0x00B7) {1} sites $([char] 0x00B7) {2:N0} relationship rows $([char] 0x00B7) {3} current error rows $([char] 0x00B7) as of {4:yyyy-MM-dd HH:mm}. States are report-defined operational observations, not security or compliance verdicts." -f $Dcs.Count, $Sites.Count, $Relationships.Count, $Errors.Count, $Sample.AsOfDate)

$null = $Report |
    Add-PSISection -Title 'Domain Controller Overview' |
    Add-PSIRow -Columns 12 |
    Add-PSIStatus -Status Info -Label 'Inventory method' -Message 'Partner counts are unique source or destination DCs, not naming-context row counts. Aggregate DC state uses the most severe inbound relationship state; missing success is counted separately.' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'replication-dcs' -Title 'Domain Controller Inventory' -Data $Dcs -Columns $DcColumns -ColumnLabels $DcLabels -Filters $DcFilters -PageSize 20 -ExportColumns $DcExportColumns -WorksheetName 'Domain Controllers' -NullValueText 'Not available'

$null = $Report |
    Add-PSISection -Title 'Replication Health Overview' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Normal -Text ("{0:N0} Healthy, {1:N0} Warning, {2:N0} Critical, and {3:N0} Unknown relationship rows. Critical and Warning are based on configured age/failure thresholds; Unknown indicates no recorded success with fewer than the configured consecutive failures." -f $HealthyCount, $WarningCount, $CriticalCount, $UnknownCount) |
    Add-PSIRow -Columns 6 |
    Add-PSIChart -Title 'Replication State Distribution' -ChartType Doughnut -Data (Get-PSIADReplicationDistribution -Data $Relationships -Property ReplicationState) -CategoryProperty Category -ValueProperty Count -ShowLabels $true -FilterMetadata @{ Table='replication-relationships'; Property='ReplicationState'; ValueProperty='Category' } |
    Add-PSIChart -Title 'Inter-site vs Intra-site Relationships' -ChartType Pie -Data (Get-PSIADReplicationDistribution -Data $Relationships -Property LinkType) -CategoryProperty Category -ValueProperty Count -ShowLabels $true -FilterMetadata @{ Table='replication-relationships'; Property='LinkType'; ValueProperty='Category' }

$null = $Report |
    Add-PSISection -Title 'Replication Age Analysis' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Normal -Text ("{0:N0} rows are at least {1} minutes old; {2:N0} are at least {3} minutes old. Age is measured from last success to the fixed sample time. Rows without a last success have no numeric age and use a separate bucket." -f $WarningAgeCount, $Rules.WarningReplicationAgeMinutes, $CriticalAgeCount, $Rules.CriticalReplicationAgeMinutes) |
    Add-PSIRow -Columns 6 |
    Add-PSIChart -Title 'Last-success Age Buckets' -ChartType Bar -Data (Get-PSIADReplicationDistribution -Data $Relationships -Property AgeBucket) -CategoryProperty Category -ValueProperty Count -ShowLegend $false -FilterMetadata @{ Table='replication-relationships'; Property='AgeBucket'; ValueProperty='Category' }

$null = $Report |
    Add-PSISection -Title 'Replication Failure Analysis' |
    Add-PSIRow -Columns 12 |
    Add-PSIStatus -Status Info -Label 'Current attempt results' -Message ("{0:N0} current failed attempts include {1:N0} RPC-coded rows; {2:N0} rows have at least {3} consecutive failures. Error codes describe observed results, not confirmed root causes." -f $Errors.Count, $RpcCount, $RepeatedFailureCount, $Rules.ConsecutiveFailureThreshold) |
    Add-PSIRow -Columns 6 |
    Add-PSIChart -Title 'Current Failure Codes' -ChartType Bar -Data (Get-PSIADReplicationDistribution -Data $Errors -Property ErrorCode) -CategoryProperty Category -ValueProperty Count -ShowLegend $false -FilterMetadata @{ Table='replication-errors'; Property='ErrorCode'; ValueProperty='Category' }

$null = $Report |
    Add-PSISection -Title 'Site Replication Analysis' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text ("Site counts use destination DC location. {0:N0} non-healthy relationships cross sites. More relationships in a site do not by themselves indicate a problem." -f $InterSiteIssueCount) |
    Add-PSIRow -Columns 6 |
    Add-PSIChart -Title 'Current Failures by Destination Site' -ChartType Bar -Data $SiteFailureChart -CategoryProperty Category -ValueProperty Count -ShowLegend $false -FilterMetadata @{ Table='replication-relationships'; Property='DestinationSite'; ValueProperty='Category' } |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'replication-sites' -Title 'Site Replication Summary' -Data $Sites -Columns $SiteColumns -ColumnLabels $SiteLabels -PageSize 10 -ExportColumns $SiteColumns -WorksheetName 'Site Summary' -NullValueText 'Not available'

$null = $Report |
    Add-PSISection -Title 'Naming Context Analysis' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text 'Each source/destination partner pair has four fictional naming-context rows. The chart counts non-healthy rows by context; selecting a bar filters the complete relationship inventory to that context.' |
    Add-PSIRow -Columns 6 |
    Add-PSIChart -Title 'Non-Healthy Rows by Naming Context' -ChartType Bar -Data (Get-PSIADReplicationDistribution -Data $ProblemRelationships -Property NamingContextLabel) -CategoryProperty Category -ValueProperty Count -ShowLegend $false -FilterMetadata @{ Table='replication-relationships'; Property='NamingContextLabel'; ValueProperty='Category' }

$Insights = @(
    [pscustomobject]@{ Title='Replication Failures'; Value=$Errors.Count; Description='Current nonzero result codes.'; Icon='warning'; Table='replication-relationships'; Conditions=@(@{Property='IsFailure';Operator='Equals';Value='Yes'}); Evidence=$RelationshipEvidenceColumns; Export=$RelationshipExportColumns; Labels=$RelationshipLabels },
    [pscustomobject]@{ Title='Repeated Consecutive Failures'; Value=$RepeatedFailureCount; Description="At least $($Rules.ConsecutiveFailureThreshold) consecutive failed attempts."; Icon='critical'; Table='replication-relationships'; Conditions=@(@{Property='ConsecutiveFailures';Operator='GreaterThanOrEqual';Value=$Rules.ConsecutiveFailureThreshold}); Evidence=$RelationshipEvidenceColumns; Export=$RelationshipExportColumns; Labels=$RelationshipLabels },
    [pscustomobject]@{ Title='Age at Warning Threshold'; Value=$WarningAgeCount; Description="Last success at least $($Rules.WarningReplicationAgeMinutes) minutes ago; includes critical-age rows."; Icon='info'; Table='replication-relationships'; Conditions=@(@{Property='ReplicationAgeMinutes';Operator='GreaterThanOrEqual';Value=$Rules.WarningReplicationAgeMinutes}); Evidence=$RelationshipEvidenceColumns; Export=$RelationshipExportColumns; Labels=$RelationshipLabels },
    [pscustomobject]@{ Title='Age at Critical Threshold'; Value=$CriticalAgeCount; Description="Last success at least $($Rules.CriticalReplicationAgeMinutes) minutes ago."; Icon='critical'; Table='replication-relationships'; Conditions=@(@{Property='ReplicationAgeMinutes';Operator='GreaterThanOrEqual';Value=$Rules.CriticalReplicationAgeMinutes}); Evidence=$RelationshipEvidenceColumns; Export=$RelationshipExportColumns; Labels=$RelationshipLabels },
    [pscustomobject]@{ Title='RPC-coded Failures'; Value=$RpcCount; Description='Current result code 1722. Investigate connectivity and related causes; code alone does not prove root cause.'; Icon='network'; Table='replication-errors'; Conditions=@(@{Property='ErrorCategory';Operator='Equals';Value='RPC'}); Evidence=$ErrorExportColumns; Export=$ErrorExportColumns; Labels=$ErrorLabels },
    [pscustomobject]@{ Title='Inter-site Replication Issues'; Value=$InterSiteIssueCount; Description='Inter-site rows with Warning, Critical, or Unknown state.'; Icon='network'; Table='replication-relationships'; Conditions=@(@{Property='LinkType';Operator='Equals';Value='Inter-site'},@{Property='ReplicationState';Operator='In';Values=@('Warning','Critical','Unknown')}); Evidence=$RelationshipEvidenceColumns; Export=$RelationshipExportColumns; Labels=$RelationshipLabels },
    [pscustomobject]@{ Title='DCs With Multiple Failing Partners'; Value=$MultiplePartnerDcs.Count; Description="At least $($Rules.MultipleFailingPartnerThreshold) distinct failing inbound source DCs."; Icon='server'; Table='replication-dcs'; Conditions=@(@{Property='FailingPartnerCount';Operator='GreaterThanOrEqual';Value=$Rules.MultipleFailingPartnerThreshold}); Evidence=$DcExportColumns; Export=$DcExportColumns; Labels=$DcLabels },
    [pscustomobject]@{ Title='Never Successful / Missing Last Success'; Value=$NeverSuccessfulCount; Description='No last successful replication timestamp is available in the fictional snapshot.'; Icon='info'; Table='replication-relationships'; Conditions=@(@{Property='LastSuccess';Operator='IsEmpty'}); Evidence=$RelationshipEvidenceColumns; Export=$RelationshipExportColumns; Labels=$RelationshipLabels },
    [pscustomobject]@{ Title='Recovered After Previous Failures'; Value=$RecoveredCount; Description='Current attempt succeeded after earlier simulated failures; prior failures are sample-only history.'; Icon='healthy'; Table='replication-relationships'; Conditions=@(@{Property='RecoveryState';Operator='Equals';Value='Recovered'}); Evidence=$RelationshipEvidenceColumns; Export=$RelationshipExportColumns; Labels=$RelationshipLabels }
)
$null = $Report | Add-PSISection -Title 'Investigation Insights' | Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text 'Insights open evidence from the active table dataset. Existing table search and filters are carried into the Evidence Viewer; evidence can be searched, sorted, paged, and exported without a second bulk payload.'
for ($Offset = 0; $Offset -lt $Insights.Count; $Offset += 3) {
    $null = $Report | Add-PSIRow -Columns 12
    foreach ($Insight in @($Insights | Select-Object -Skip $Offset -First 3)) {
        $null = $Report | Add-PSIInsight -Title $Insight.Title -Value $Insight.Value -Description $Insight.Description -Status Info -Icon $Insight.Icon `
            -Filter @{ Table=$Insight.Table; Conditions=@($Insight.Conditions) } -EvidenceColumns $Insight.Evidence -ExportColumns $Insight.Export -ColumnLabels $Insight.Labels
    }
}

$null = $Report |
    Add-PSISection -Title 'Replication Relationship Inventory' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'replication-relationships' -Title 'Inbound Replication Relationships' -Data $Relationships -Columns $RelationshipColumns -ColumnLabels $RelationshipLabels -Filters $RelationshipFilters -PageSize 25 -ExportColumns $RelationshipExportColumns -WorksheetName 'Relationships' -NullValueText 'No recorded success' -EmptyMessage 'No relationships match the active search and filters.'

$null = $Report |
    Add-PSISection -Title 'Error Evidence' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text 'This focused table contains only current nonzero result codes. Its rows are a small projection of failed relationship events for investigation; the complete relationship inventory remains in its own table.' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'replication-errors' -Title 'Current Replication Error Rows' -Data $Errors -Columns $ErrorColumns -ColumnLabels $ErrorLabels -Filters $ErrorFilters -PageSize 20 -ExportColumns $ErrorExportColumns -WorksheetName 'Replication Errors' -NullValueText 'No recorded success' -EmptyMessage 'No error rows match the active search and filters.'

$ObservationRows = @(
    [pscustomobject]@{ Observation='Repeated failures'; Count=$RepeatedFailureCount; Interpretation='Investigate attempts meeting the configured consecutive-failure threshold.' },
    [pscustomobject]@{ Observation='Age at warning threshold'; Count=$WarningAgeCount; Interpretation='Review age against expected replication schedule and topology.' },
    [pscustomobject]@{ Observation='RPC-coded failures'; Count=$RpcCount; Interpretation='Code 1722 merits connectivity investigation; root cause is not determined here.' },
    [pscustomobject]@{ Observation='Inter-site issues'; Count=$InterSiteIssueCount; Interpretation='Compare failing relationships with site connectivity evidence.' },
    [pscustomobject]@{ Observation='DCs with multiple failing partners'; Count=$MultiplePartnerDcs.Count; Interpretation='Review distinct failing inbound source partners and affected naming contexts.' },
    [pscustomobject]@{ Observation='Missing last success'; Count=$NeverSuccessfulCount; Interpretation='No numeric age can be calculated; verify whether replication ever succeeded.' }
)
$null = $Report |
    Add-PSISection -Title 'Findings and Recommendations' |
    Add-PSIRow -Columns 12 |
    Add-PSIStatus -Status Info -Label 'Investigation candidates' -Message 'These counts are evidence-linked operational observations. Error codes and threshold states alone do not establish a security vulnerability or a root cause.' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'replication-observations' -Title 'Observed Review Candidates' -Data $ObservationRows -Columns @('Observation','Count','Interpretation') -ExportColumns @('Observation','Count','Interpretation') -PageSize 10 |
    Add-PSIRow -Columns 12 |
    Add-PSIRecommendation -Status Info -Title 'Investigate repeated failed attempts' -Description ("{0:N0} relationships meet the configured {1}-failure threshold." -f $RepeatedFailureCount, $Rules.ConsecutiveFailureThreshold) -ActionText 'Inspect source, destination, naming context, last result, and partner connectivity before changing topology.' |
    Add-PSIRecommendation -Status Info -Title 'Review delayed replication and missing success' -Description ("{0:N0} relationships meet the warning-age threshold and {1:N0} have no last-success timestamp." -f $WarningAgeCount, $NeverSuccessfulCount) -ActionText 'Compare with approved schedules and investigate missing-success records separately.' |
    Add-PSIRecommendation -Status Info -Title 'Review site connectivity and repeated RPC results' -Description ("{0:N0} inter-site rows are non-healthy and {1:N0} current failures have RPC code 1722." -f $InterSiteIssueCount, $RpcCount) -ActionText 'Use the evidence views to scope network, DNS, and partner checks; do not infer a single root cause from the code.'

$null = $Report |
    Add-PSISection -Title 'Method and Thresholds' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text ("{0} Fixed sample time: {1:yyyy-MM-dd HH:mm}. Report-defined thresholds: WarningReplicationAgeMinutes = {2}; CriticalReplicationAgeMinutes = {3}; ConsecutiveFailureThreshold = {4}; MultipleFailingPartnerThreshold = {5}. These are demonstration investigation thresholds, not Microsoft policy or compliance verdicts." -f $Sample.Source, $Sample.AsOfDate, $Rules.WarningReplicationAgeMinutes, $Rules.CriticalReplicationAgeMinutes, $Rules.ConsecutiveFailureThreshold, $Rules.MultipleFailingPartnerThreshold) |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text 'Age is elapsed whole minutes since last success. A failed current attempt can have a recent or old last success. Missing last success yields Unknown unless the configured consecutive-failure threshold is met. DC state uses the most severe inbound row; failing-partner count deduplicates source DCs. Site summaries group by destination site. Age buckets are fixed demo presentation ranges: 0-15, 16-60, 61-180, 181-360, 361+ minutes, and Never successful. Recovered rows contain explicitly simulated prior failures.' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text 'Error labels are provider-level sample descriptions: 1722 = RPC server unavailable; 8453 = replication access denied; 8524 = DNS lookup failure. Error codes do not prove root cause. The provider creates four normalized datasets: DC inventory, relationships, current error projection, and site summary. Relationships appear once as table rows; Insights and charts contain only references or small aggregates. All DC names use example.invalid and IPv4 addresses use the documentation range 198.51.100.0/24. No live AD query or external asset is used.'

$Assessment = $Report
if ($AsAssessment) { return $Assessment }

# Standalone output uses the same assessment object as composed output.
$StandaloneReport = New-PSIReport -Title $Assessment.Title -Subtitle $Assessment.Description -Theme $Theme
$null = $StandaloneReport | Add-PSIAssessment -Assessment $Assessment
$OutputFile = Export-PSIReport -Report $StandaloneReport -Path $OutputPath
Write-Host "Generated report: $($OutputFile.FullName)"
Write-Host ("Fictional sample: {0} DCs; {1} sites; {2} relationships; {3} current error rows." -f $Dcs.Count, $Sites.Count, $Relationships.Count, $Errors.Count)
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
        elseif ($IsMacHost) {
            $OpenProcess = Start-Process -FilePath 'open' -ArgumentList @($OutputFile.FullName) -Wait -PassThru -ErrorAction Stop
            if ($OpenProcess.ExitCode -ne 0) { throw "macOS open exited with code $($OpenProcess.ExitCode)." }
        }
        elseif ($IsLinuxHost) {
            $OpenProcess = Start-Process -FilePath 'xdg-open' -ArgumentList @($OutputFile.FullName) -Wait -PassThru -ErrorAction Stop
            if ($OpenProcess.ExitCode -ne 0) { throw "xdg-open exited with code $($OpenProcess.ExitCode)." }
        }
        else { throw 'No supported browser-open command was detected.' }
        Write-Host 'Browser open requested.'
    }
    catch { Write-Warning "Could not open the report in the default browser: $($_.Exception.Message)" }
}
$OutputFile
