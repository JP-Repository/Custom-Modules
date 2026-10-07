[CmdletBinding()]
param(
    [Parameter()][ValidateNotNullOrEmpty()][string] $OutputPath,
    [Parameter()][ValidateSet('Light','Dark','Auto')][string] $Theme = 'Auto',
    [Parameter()][ValidateRange(50,60)][int] $DNSServerCount = 56,
    [Parameter()][hashtable] $Rules = @{},
    [Parameter()][datetime] $AsOfDate = [datetime]::new(2026, 9, 27),
    [Parameter()][switch] $NoBrowser,
    [Parameter()][switch] $AsAssessment
)

$ErrorActionPreference = 'Stop'
$ModuleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent
. (Join-Path $PSScriptRoot 'PSIADDNS.Provider.ps1')
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path (Join-Path $ModuleRoot 'Reports') 'PSInsightHTML-DNSAssessment.html'
}

$Sample = New-PSIADDNSSampleData -DNSServerCount $DNSServerCount -Rules $Rules -AsOfDate $AsOfDate
$Servers = $Sample.DNSServerInventory
$Resolvers = $Sample.DNSClientResolvers
$Zones = $Sample.DNSZones
$Forwarders = $Sample.DNSForwarders
$Conditional = $Sample.DNSConditionalForwarders
$Policy = $Sample.Rules
$ADZoneCount = @($Zones | Where-Object IsADIntegrated -eq 'Yes').Count
$PublicServerCount = @($Servers | Where-Object HasPublicResolver -eq 'Yes').Count
$ResolverObservationCount = @($Servers | Where-Object HasResolverObservation -eq 'Yes').Count
$ConditionalZoneCount = @($Conditional.ZoneName | Sort-Object -Unique).Count
$AgingEnabledCount = @($Zones | Where-Object AgingEnabled -eq 'Yes').Count
$ScavengingEnabledCount = @($Servers | Where-Object ScavengingEnabled -eq 'Yes').Count
$UnknownResolverCount = @($Resolvers | Where-Object ResolutionState -eq 'Unrecognized').Count
$SingleResolverCount = @($Servers | Where-Object ResolverCount -eq 1).Count
$MixedResolverCount = @($Servers | Where-Object HasMixedResolvers -eq 'Yes').Count
$NoAgingCount = @($Zones | Where-Object AgingEnabled -eq 'No').Count
$NoScavengingCount = @($Servers | Where-Object ScavengingEnabled -eq 'No').Count
$NonsecureUpdateCount = @($Zones | Where-Object DynamicUpdate -eq 'Nonsecure and secure').Count
$ConditionalReviewCount = @($Conditional | Where-Object ForwarderState -eq 'Review candidate').Count
$BelowMinimumCount = @($Servers | Where-Object BelowResolverMinimum -eq 'Yes').Count
$DuplicateResolverServerCount = @($Servers | Where-Object HasDuplicateResolvers -eq 'Yes').Count
$NoResolverCount = @($Servers | Where-Object ResolverCount -eq 0).Count
$NonstandardForwarderCount = @($Servers | Where-Object ForwarderProfile -ne 'Standard internal sample').Count
$ExternalForwarderCount = @($Forwarders | Where-Object IsPublic -eq 'Yes').Count

# Only these visible fields enter the HTML; evidence and exports use narrower reviewed allowlists.
$ServerColumns = @('ServerName','Domain','Site','IPv4Address','OperatingSystem','IsDomainController','DNSServiceState','ZoneCount','ForwarderCount','ForwarderProfile','ScavengingEnabled','ScavengingIntervalDays','ResolverCount','PublicResolverCount','UnrecognizedResolverCount','HasPublicResolver','HasMixedResolvers','HasDuplicateResolvers','BelowResolverMinimum','HasResolverObservation','ConfigurationState')
$ServerLabels = @{ ServerName='DNS server'; Domain='Domain'; Site='Site'; IPv4Address='IPv4 address'; OperatingSystem='Operating system'; IsDomainController='Domain controller'; DNSServiceState='DNS service'; ZoneCount='Sample AD zone count'; ForwarderCount='Forwarders'; ForwarderProfile='Forwarder profile'; ScavengingEnabled='Scavenging'; ScavengingIntervalDays='Scavenging interval (days)'; ResolverCount='Client resolvers'; PublicResolverCount='External sample resolvers'; UnrecognizedResolverCount='Unrecognized resolvers'; HasPublicResolver='Has external sample resolver'; HasMixedResolvers='Mixed internal/external'; HasDuplicateResolvers='Duplicate resolvers'; BelowResolverMinimum='Below resolver minimum'; HasResolverObservation='Resolver observation'; ConfigurationState='Configuration state' }
$ServerExportColumns = @('ServerName','Domain','Site','IPv4Address','OperatingSystem','DNSServiceState','ZoneCount','ForwarderCount','ForwarderProfile','ScavengingEnabled','ScavengingIntervalDays','ResolverCount','PublicResolverCount','UnrecognizedResolverCount','ConfigurationState')
$ServerEvidenceColumns = @('ServerName','Domain','Site','IPv4Address','DNSServiceState','ResolverCount','PublicResolverCount','UnrecognizedResolverCount','ForwarderProfile','ScavengingEnabled','ConfigurationState')
$ResolverColumns = @('ServerName','Site','Interface','ResolverOrder','ResolverAddress','ResolverType','IsInternalResolver','IsPublicResolver','IsSelfReference','IsLoopback','ResolutionState')
$ResolverLabels = @{ ServerName='DNS server'; Site='Site'; Interface='Interface'; ResolverOrder='Resolver order'; ResolverAddress='Resolver address'; ResolverType='Resolver type'; IsInternalResolver='Known internal'; IsPublicResolver='External sample'; IsSelfReference='Self reference'; IsLoopback='Loopback'; ResolutionState='Classification' }
$ResolverExportColumns = @('ServerName','Site','Interface','ResolverOrder','ResolverAddress','ResolverType','IsInternalResolver','IsPublicResolver','IsSelfReference','IsLoopback','ResolutionState')
$ZoneColumns = @('ZoneName','Domain','ZoneType','IsADIntegrated','ReplicationScope','DynamicUpdate','AgingEnabled','NoRefreshIntervalDays','RefreshIntervalDays','RecordCount','ReverseLookup','ZoneState')
$ZoneLabels = @{ ZoneName='Zone name'; Domain='Domain'; ZoneType='Zone type'; IsADIntegrated='AD integrated'; ReplicationScope='Replication scope'; DynamicUpdate='Dynamic update'; AgingEnabled='Aging'; NoRefreshIntervalDays='No-refresh (days)'; RefreshIntervalDays='Refresh (days)'; RecordCount='Sample records'; ReverseLookup='Reverse lookup'; ZoneState='Zone state' }
$ZoneExportColumns = @('ZoneName','Domain','ZoneType','IsADIntegrated','ReplicationScope','DynamicUpdate','AgingEnabled','NoRefreshIntervalDays','RefreshIntervalDays','RecordCount','ReverseLookup','ZoneState')
$ForwarderColumns = @('ServerName','Site','ForwarderOrder','ForwarderAddress','ForwarderType','IsInternal','IsPublic','TimeoutSeconds','UseRootHintsIfUnavailable')
$ForwarderLabels = @{ ServerName='DNS server'; Site='Site'; ForwarderOrder='Order'; ForwarderAddress='Forwarder address'; ForwarderType='Forwarder type'; IsInternal='Internal sample'; IsPublic='External sample'; TimeoutSeconds='Timeout (seconds)'; UseRootHintsIfUnavailable='Use root hints if unavailable' }
$ConditionalColumns = @('ZoneName','MasterServer','ReplicationScope','StoredInAD','MasterType','ForwarderState','TargetVerification')
$ConditionalLabels = @{ ZoneName='Forwarder zone'; MasterServer='Master server'; ReplicationScope='Replication scope'; StoredInAD='Stored in AD'; MasterType='Target type'; ForwarderState='Review state'; TargetVerification='Target verification' }

$Sites = @($Servers.Site | Sort-Object -Unique)
$ServerFilters = @(
    Add-PSIFilter -Property Domain -Label 'Domain' -Values @($Servers.Domain | Sort-Object -Unique)
    Add-PSIFilter -Property Site -Label 'Site' -Values $Sites
    Add-PSIFilter -Property DNSServiceState -Label 'DNS service' -Values @('Running','Stopped')
    Add-PSIFilter -Property ScavengingEnabled -Label 'Scavenging' -Values @('Yes','No')
    Add-PSIFilter -Property HasPublicResolver -Label 'External sample resolver' -Values @('Yes','No')
    Add-PSIFilter -Property HasMixedResolvers -Label 'Mixed resolvers' -Values @('Yes','No')
    Add-PSIFilter -Property BelowResolverMinimum -Label 'Below minimum' -Values @('Yes','No')
    Add-PSIFilter -Property HasResolverObservation -Label 'Resolver observation' -Values @('Yes','No')
    Add-PSIFilter -Property ForwarderProfile -Label 'Forwarder profile' -Values @($Servers.ForwarderProfile | Sort-Object -Unique)
)
$ResolverFilters = @(
    Add-PSIFilter -Property Site -Label 'Site' -Values $Sites
    Add-PSIFilter -Property ResolverType -Label 'Resolver type' -Values @($Resolvers.ResolverType | Sort-Object -Unique)
    Add-PSIFilter -Property ResolutionState -Label 'Classification' -Values @($Resolvers.ResolutionState | Sort-Object -Unique)
    Add-PSIFilter -Property IsPublicResolver -Label 'External sample' -Values @('Yes','No')
    Add-PSIFilter -Property IsSelfReference -Label 'Self reference' -Values @('Yes','No')
)
$ZoneFilters = @(
    Add-PSIFilter -Property ZoneType -Label 'Zone type' -Values @($Zones.ZoneType | Sort-Object -Unique)
    Add-PSIFilter -Property IsADIntegrated -Label 'AD integrated' -Values @('Yes','No')
    Add-PSIFilter -Property ReplicationScope -Label 'Replication scope' -Values @($Zones.ReplicationScope | Sort-Object -Unique)
    Add-PSIFilter -Property DynamicUpdate -Label 'Dynamic update' -Values @($Zones.DynamicUpdate | Sort-Object -Unique)
    Add-PSIFilter -Property AgingEnabled -Label 'Aging' -Values @('Yes','No')
    Add-PSIFilter -Property ReverseLookup -Label 'Reverse lookup' -Values @('Yes','No')
)
$ForwarderFilters = @(
    Add-PSIFilter -Property Site -Label 'Site' -Values $Sites
    Add-PSIFilter -Property ForwarderType -Label 'Forwarder type' -Values @('Internal sample','External sample')
    Add-PSIFilter -Property IsPublic -Label 'External sample' -Values @('Yes','No')
    Add-PSIFilter -Property UseRootHintsIfUnavailable -Label 'Use root hints' -Values @('Yes','No')
)
$ConditionalFilters = @(
    Add-PSIFilter -Property ForwarderState -Label 'Review state' -Values @('Configured','Review candidate')
    Add-PSIFilter -Property StoredInAD -Label 'Stored in AD' -Values @('Yes','No')
    Add-PSIFilter -Property ReplicationScope -Label 'Replication scope' -Values @($Conditional.ReplicationScope | Sort-Object -Unique)
    Add-PSIFilter -Property MasterType -Label 'Target type' -Values @('Internal sample','External sample')
)

# Build reusable assessment content through the shared component API.
$Report = New-PSIAssessment -Name 'DNS' -Provider 'ActiveDirectory' -Title 'Active Directory DNS Health Assessment' `
    -Description 'Fictional DNS configuration and resolver review | PSInsightHTML'

$null = $Report |
    Add-PSISection -Title 'Executive Summary' |
    Add-PSIRow -Columns 12 |
    Add-PSIKPI -Title 'DNS Servers' -Value $Servers.Count -Subtitle 'Fictional DNS-capable domain controllers' -Status Info -Icon 'server' |
    Add-PSIKPI -Title 'DNS Zones' -Value $Zones.Count -Subtitle 'Logical zones in sample catalog' -Status Info -Icon 'domain' |
    Add-PSIKPI -Title 'AD-Integrated Zones' -Value $ADZoneCount -Subtitle 'Select to filter zone inventory' -Status Info -Icon 'database' -Filter @{ Table='dns-zones'; Property='IsADIntegrated'; Value='Yes' } |
    Add-PSIKPI -Title 'Servers With External Resolvers' -Value $PublicServerCount -Subtitle 'Documentation-address examples' -Status Info -Icon 'network' -Filter @{ Table='dns-servers'; Property='HasPublicResolver'; Value='Yes' } |
    Add-PSIRow -Columns 12 |
    Add-PSIKPI -Title 'Resolver Observations' -Value $ResolverObservationCount -Subtitle 'Servers meeting sample review criteria' -Status Info -Icon 'info' -Filter @{ Table='dns-servers'; Property='HasResolverObservation'; Value='Yes' } |
    Add-PSIKPI -Title 'Conditional Forwarder Zones' -Value $ConditionalZoneCount -Subtitle 'Each can have multiple master targets' -Status Info -Icon 'cloud' |
    Add-PSIKPI -Title 'Zones With Aging Enabled' -Value $AgingEnabledCount -Subtitle 'Select to filter zone inventory' -Status Info -Icon 'settings' -Filter @{ Table='dns-zones'; Property='AgingEnabled'; Value='Yes' } |
    Add-PSIKPI -Title 'Servers With Scavenging Enabled' -Value $ScavengingEnabledCount -Subtitle 'Select to filter server inventory' -Status Info -Icon 'settings' -Filter @{ Table='dns-servers'; Property='ScavengingEnabled'; Value='Yes' }
$null = $Report | Add-PSIRow -Columns 12 | Add-PSIText -Size Small -Text (
    "Fictional sample data only · {0} DNS-capable DCs · {1} resolver rows · {2} logical zones · {3} standard forwarder rows · {4} conditional-forwarder targets · as of {5:yyyy-MM-dd}. These are configuration observations, not security verdicts." -f $Servers.Count, $Resolvers.Count, $Zones.Count, $Forwarders.Count, $Conditional.Count, $Sample.AsOfDate)

$null = $Report |
    Add-PSISection -Title 'DNS Server Overview' |
    Add-PSIRow -Columns 12 |
    Add-PSIStatus -Status Info -Label 'Fictional server population' -Message 'The sample contains root and child-domain DNS-capable DCs across eight sites. A stopped DNS service or resolver variation is a review candidate, not a confirmed outage.' |
    Add-PSIRow -Columns 6 |
    Add-PSIChart -Title 'DNS Servers by Site' -ChartType Bar -Data (Get-PSIADDNSDistribution -Data $Servers -Property Site) -CategoryProperty Category -ValueProperty Count -ShowLegend $false -FilterMetadata @{ Table='dns-servers'; Property='Site'; ValueProperty='Category' }

$null = $Report |
    Add-PSISection -Title 'DNS Client Resolver Analysis' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Normal -Text ("{0} servers include external sample resolver addresses; {1} resolver rows are unrecognized; {2} servers have exactly one resolver and {3} have none. {4} servers mix known internal and external sample resolvers. Classification is based on the fictional inventory and sample address catalogs only." -f $PublicServerCount, $UnknownResolverCount, $SingleResolverCount, $NoResolverCount, $MixedResolverCount) |
    Add-PSIRow -Columns 6 |
    Add-PSIChart -Title 'Resolver Classification' -ChartType Doughnut -Data (Get-PSIADDNSDistribution -Data $Resolvers -Property ResolutionState) -CategoryProperty Category -ValueProperty Count -ShowLabels $true -FilterMetadata @{ Table='dns-resolvers'; Property='ResolutionState'; ValueProperty='Category' } |
    Add-PSIChart -Title 'Resolver Types' -ChartType Bar -Data (Get-PSIADDNSDistribution -Data $Resolvers -Property ResolverType) -CategoryProperty Category -ValueProperty Count -ShowLegend $false -FilterMetadata @{ Table='dns-resolvers'; Property='ResolverType'; ValueProperty='Category' }

$null = $Report |
    Add-PSISection -Title 'Zone Configuration' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text ("{0} of {1} zones are AD integrated. The catalog includes forward and reverse lookup zones, root and child-domain examples, and Domain, Forest, and non-applicable replication-scope labels. Configuration differences are shown for review without a policy verdict." -f $ADZoneCount, $Zones.Count) |
    Add-PSIRow -Columns 6 |
    Add-PSIChart -Title 'DNS Zone Types' -ChartType Doughnut -Data (Get-PSIADDNSDistribution -Data $Zones -Property ZoneType) -CategoryProperty Category -ValueProperty Count -ShowLabels $true -FilterMetadata @{ Table='dns-zones'; Property='ZoneType'; ValueProperty='Category' } |
    Add-PSIChart -Title 'Dynamic Update Configuration' -ChartType Bar -Data (Get-PSIADDNSDistribution -Data $Zones -Property DynamicUpdate) -CategoryProperty Category -ValueProperty Count -ShowLegend $false -FilterMetadata @{ Table='dns-zones'; Property='DynamicUpdate'; ValueProperty='Category' } |
    Add-PSIRow -Columns 6 |
    Add-PSIChart -Title 'Zone Replication Scope' -ChartType Bar -Data (Get-PSIADDNSDistribution -Data $Zones -Property ReplicationScope) -CategoryProperty Category -ValueProperty Count -ShowLegend $false -FilterMetadata @{ Table='dns-zones'; Property='ReplicationScope'; ValueProperty='Category' }

$null = $Report |
    Add-PSISection -Title 'Aging and Scavenging' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Normal -Text ("{0} zones have aging enabled and {1} do not. {2} DNS servers have scavenging enabled and {3} do not. Enabled intervals vary in the sample; disabled settings are observations requiring context, not automatic defects." -f $AgingEnabledCount, $NoAgingCount, $ScavengingEnabledCount, $NoScavengingCount) |
    Add-PSIRow -Columns 6 |
    Add-PSIChart -Title 'Zone Aging Configuration' -ChartType Doughnut -Data (Get-PSIADDNSDistribution -Data $Zones -Property AgingEnabled) -CategoryProperty Category -ValueProperty Count -ShowLabels $true -FilterMetadata @{ Table='dns-zones'; Property='AgingEnabled'; ValueProperty='Category' } |
    Add-PSIChart -Title 'Server Scavenging Configuration' -ChartType Doughnut -Data (Get-PSIADDNSDistribution -Data $Servers -Property ScavengingEnabled) -CategoryProperty Category -ValueProperty Count -ShowLabels $true -FilterMetadata @{ Table='dns-servers'; Property='ScavengingEnabled'; ValueProperty='Category' }

$null = $Report |
    Add-PSISection -Title 'Forwarder Analysis' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text ("{0} servers differ from the two-address internal sample profile, and {1} forwarder rows use external documentation addresses. Compare profiles with intended design; root-hints behavior and target reachability are not tested." -f $NonstandardForwarderCount, $ExternalForwarderCount) |
    Add-PSIRow -Columns 6 |
    Add-PSIChart -Title 'Forwarder Profiles by Server' -ChartType Bar -Data (Get-PSIADDNSDistribution -Data $Servers -Property ForwarderProfile) -CategoryProperty Category -ValueProperty Count -ShowLegend $false -FilterMetadata @{ Table='dns-servers'; Property='ForwarderProfile'; ValueProperty='Category' } |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'dns-forwarders' -Title 'Standard DNS Forwarders' -Data $Forwarders -Columns $ForwarderColumns -ColumnLabels $ForwarderLabels -Filters $ForwarderFilters -PageSize 25 -ExportColumns $ForwarderColumns -WorksheetName 'DNS Forwarders' -NullValueText 'Not provided'

$null = $Report |
    Add-PSISection -Title 'Conditional Forwarders' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text ("{0} logical conditional-forwarder zones have {1} target rows. {2} target rows use external sample addresses and are marked for review. Target availability is Not checked; no DNS query is made." -f $ConditionalZoneCount, $Conditional.Count, $ConditionalReviewCount) |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'dns-conditional-forwarders' -Title 'Conditional Forwarder Targets' -Data $Conditional -Columns $ConditionalColumns -ColumnLabels $ConditionalLabels -Filters $ConditionalFilters -PageSize 20 -ExportColumns $ConditionalColumns -WorksheetName 'Conditional Forwarders' -NullValueText 'Not provided'

$Insights = @(
    [pscustomobject]@{ Title='Servers With Public / External Resolvers'; Value=$PublicServerCount; Description='Fictional external sample resolver addresses on DNS-capable DCs.'; Icon='network'; Table='dns-servers'; Conditions=@(@{Property='HasPublicResolver';Operator='Equals';Value='Yes'}); Evidence=$ServerEvidenceColumns; Export=$ServerExportColumns; Labels=$ServerLabels },
    [pscustomobject]@{ Title='Unknown / Unrecognized Resolver Addresses'; Value=$UnknownResolverCount; Description='Addresses absent from both the fictional internal inventory and the external sample catalog.'; Icon='info'; Table='dns-resolvers'; Conditions=@(@{Property='ResolutionState';Operator='Equals';Value='Unrecognized'}); Evidence=$ResolverExportColumns; Export=$ResolverExportColumns; Labels=$ResolverLabels },
    [pscustomobject]@{ Title='Servers With Only One Resolver'; Value=$SingleResolverCount; Description='Exactly one configured DNS client resolver.'; Icon='server'; Table='dns-servers'; Conditions=@(@{Property='ResolverCount';Operator='Equals';Value=1}); Evidence=$ServerEvidenceColumns; Export=$ServerExportColumns; Labels=$ServerLabels },
    [pscustomobject]@{ Title='Mixed Internal + External Resolvers'; Value=$MixedResolverCount; Description='Both known internal and external sample resolver types on one server.'; Icon='network'; Table='dns-servers'; Conditions=@(@{Property='HasMixedResolvers';Operator='Equals';Value='Yes'}); Evidence=$ServerEvidenceColumns; Export=$ServerExportColumns; Labels=$ServerLabels },
    [pscustomobject]@{ Title='Zones Without Aging'; Value=$NoAgingCount; Description='AgingEnabled is No; review intentional exceptions.'; Icon='database'; Table='dns-zones'; Conditions=@(@{Property='AgingEnabled';Operator='Equals';Value='No'}); Evidence=$ZoneExportColumns; Export=$ZoneExportColumns; Labels=$ZoneLabels },
    [pscustomobject]@{ Title='Servers Without Scavenging'; Value=$NoScavengingCount; Description='ScavengingEnabled is No; configuration observation only.'; Icon='settings'; Table='dns-servers'; Conditions=@(@{Property='ScavengingEnabled';Operator='Equals';Value='No'}); Evidence=$ServerEvidenceColumns; Export=$ServerExportColumns; Labels=$ServerLabels },
    [pscustomobject]@{ Title='Zones Allowing Nonsecure Dynamic Updates'; Value=$NonsecureUpdateCount; Description='DynamicUpdate is Nonsecure and secure; inspect approved zone design.'; Icon='security'; Table='dns-zones'; Conditions=@(@{Property='DynamicUpdate';Operator='Equals';Value='Nonsecure and secure'}); Evidence=$ZoneExportColumns; Export=$ZoneExportColumns; Labels=$ZoneLabels },
    [pscustomobject]@{ Title='Conditional Forwarder Review'; Value=$ConditionalReviewCount; Description='External sample master targets; reachability not checked.'; Icon='cloud'; Table='dns-conditional-forwarders'; Conditions=@(@{Property='ForwarderState';Operator='Equals';Value='Review candidate'}); Evidence=$ConditionalColumns; Export=$ConditionalColumns; Labels=$ConditionalLabels },
    [pscustomobject]@{ Title='Below Configured Resolver Minimum'; Value=$BelowMinimumCount; Description="Fewer than $($Policy.MinimumResolverCount) configured client resolvers."; Icon='info'; Table='dns-servers'; Conditions=@(@{Property='BelowResolverMinimum';Operator='Equals';Value='Yes'}); Evidence=$ServerEvidenceColumns; Export=$ServerExportColumns; Labels=$ServerLabels },
    [pscustomobject]@{ Title='Duplicate Resolver Entries'; Value=$DuplicateResolverServerCount; Description='Same resolver address appears more than once for one server.'; Icon='info'; Table='dns-servers'; Conditions=@(@{Property='HasDuplicateResolvers';Operator='Equals';Value='Yes'}); Evidence=$ServerEvidenceColumns; Export=$ServerExportColumns; Labels=$ServerLabels },
    [pscustomobject]@{ Title='Servers With No Resolver'; Value=$NoResolverCount; Description='No DNS client resolver row is configured in the sample.'; Icon='server'; Table='dns-servers'; Conditions=@(@{Property='ResolverCount';Operator='Equals';Value=0}); Evidence=$ServerEvidenceColumns; Export=$ServerExportColumns; Labels=$ServerLabels },
    [pscustomobject]@{ Title='Nonstandard Forwarder Profiles'; Value=$NonstandardForwarderCount; Description='Profile differs from the two-address internal sample baseline.'; Icon='network'; Table='dns-servers'; Conditions=@(@{Property='ForwarderProfile';Operator='NotEquals';Value='Standard internal sample'}); Evidence=$ServerEvidenceColumns; Export=$ServerExportColumns; Labels=$ServerLabels }
)
$null = $Report | Add-PSISection -Title 'Investigation Insights' | Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text 'Select an Insight to inspect records from the active shared table. Evidence inherits table search and filters, supports its own search, sorting, pagination, CSV, and XLSX, and does not embed another bulk dataset.'
for ($Offset = 0; $Offset -lt $Insights.Count; $Offset += 4) {
    $null = $Report | Add-PSIRow -Columns 12
    foreach ($Insight in @($Insights | Select-Object -Skip $Offset -First 4)) {
        $null = $Report | Add-PSIInsight -Title $Insight.Title -Value $Insight.Value -Description $Insight.Description -Status Info -Icon $Insight.Icon `
            -Filter @{ Table=$Insight.Table; Conditions=@($Insight.Conditions) } -EvidenceColumns $Insight.Evidence -ExportColumns $Insight.Export -ColumnLabels $Insight.Labels
    }
}

$null = $Report |
    Add-PSISection -Title 'DNS Server Inventory' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'dns-servers' -Title 'DNS-Capable Domain Controllers' -Data $Servers -Columns $ServerColumns -ColumnLabels $ServerLabels -Filters $ServerFilters -PageSize 20 -ExportColumns $ServerExportColumns -WorksheetName 'DNS Servers' -NullValueText 'Not configured' -EmptyMessage 'No servers match the current search and filters.'

$null = $Report |
    Add-PSISection -Title 'Zone and Resolver Evidence' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'dns-resolvers' -Title 'DNS Client Resolver Inventory' -Data $Resolvers -Columns $ResolverColumns -ColumnLabels $ResolverLabels -Filters $ResolverFilters -PageSize 25 -ExportColumns $ResolverExportColumns -WorksheetName 'Client Resolvers' -NullValueText 'Not provided' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'dns-zones' -Title 'DNS Zone Inventory' -Data $Zones -Columns $ZoneColumns -ColumnLabels $ZoneLabels -Filters $ZoneFilters -PageSize 20 -ExportColumns $ZoneExportColumns -WorksheetName 'DNS Zones' -NullValueText 'Not configured'

$Observations = @(
    [pscustomobject]@{ Observation='Servers with external sample resolvers'; Count=$PublicServerCount; Interpretation='Confirm approved client resolver design; documentation addresses are not operational public DNS.' },
    [pscustomobject]@{ Observation='Unrecognized resolver rows'; Count=$UnknownResolverCount; Interpretation='Validate address ownership against the fictional inventory model.' },
    [pscustomobject]@{ Observation='Servers below resolver minimum'; Count=$BelowMinimumCount; Interpretation='Review against the configured sample minimum and intended redundancy.' },
    [pscustomobject]@{ Observation='Nonsecure dynamic-update zones'; Count=$NonsecureUpdateCount; Interpretation='Confirm that update mode is intentionally approved for each zone.' },
    [pscustomobject]@{ Observation='Zones without aging'; Count=$NoAgingCount; Interpretation='Document intended aging and scavenging exceptions.' },
    [pscustomobject]@{ Observation='Nonstandard forwarder profiles'; Count=$NonstandardForwarderCount; Interpretation='Compare per-server profiles with the fictional internal sample baseline.' },
    [pscustomobject]@{ Observation='Conditional targets for review'; Count=$ConditionalReviewCount; Interpretation='External sample targets require owner review; availability was not checked.' }
)
$null = $Report |
    Add-PSISection -Title 'Findings and Recommendations' |
    Add-PSIRow -Columns 12 |
    Add-PSIStatus -Status Info -Label 'Configuration observations' -Message 'Review candidates below use only sample inventory comparisons and the configured resolver minimum. No live queries, vulnerability determination, or compliance assessment is performed.' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id 'dns-observations' -Title 'Observed Review Candidates' -Data $Observations -Columns @('Observation','Count','Interpretation') -ExportColumns @('Observation','Count','Interpretation') -PageSize 10 |
    Add-PSIRow -Columns 12 |
    Add-PSIRecommendation -Status Info -Title 'Review client resolver configuration' -Description ("{0} servers use external sample resolvers; {1} resolver rows are unrecognized; {2} servers are below the configured minimum." -f $PublicServerCount, $UnknownResolverCount, $BelowMinimumCount) -ActionText 'Compare evidence with approved internal resolver architecture before changing client settings.' |
    Add-PSIRecommendation -Status Info -Title 'Confirm zone update and aging intent' -Description ("{0} zones allow nonsecure and secure updates; {1} zones have aging disabled." -f $NonsecureUpdateCount, $NoAgingCount) -ActionText 'Review zone ownership, update design, and documented scavenging exceptions.' |
    Add-PSIRecommendation -Status Info -Title 'Compare forwarder profiles and targets' -Description ("{0} servers differ from the sample internal profile and {1} conditional target rows are marked for review." -f $NonstandardForwarderCount, $ConditionalReviewCount) -ActionText 'Validate owner intent and target reachability in an authorized environment.'

$null = $Report |
    Add-PSISection -Title 'Method and Data Handling' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text ("{0} Fixed sample date: {1:yyyy-MM-dd}. Report rule: MinimumResolverCount = {2}. A resolver observation means zero/fewer-than-minimum entries, an external sample address, an unrecognized address, or a duplicate. ConfigurationState is a review label, not a DNS health or security verdict." -f $Sample.Source, $Sample.AsOfDate, $Policy.MinimumResolverCount) |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text 'All names use example.invalid. Server addresses 198.51.100.10-65, external examples 203.0.113.53-60, and sample forwarders use documentation ranges; no report code sends DNS traffic to them. Known internal resolver classification uses the fictional DNS-server inventory plus loopback. Unrecognized means absent from that inventory and the external sample catalog. Conditional target availability is Not checked. Server zone counts cover eligible sample AD-integrated zones by Domain or Forest scope; standalone non-AD zones are not assigned to individual servers.' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Size Small -Text 'The provider creates separate DNS server, client resolver, zone, standard forwarder, and conditional-forwarder datasets. Each appears once as table rows. Charts contain only small aggregates; KPIs and Insights reference table IDs and conditions. Export fields are explicitly allowlisted. No live AD/DNS access, external CSS, JavaScript, image, CDN, or network retrieval is used.'

$Assessment = $Report
if ($AsAssessment) { return $Assessment }

# Standalone output uses the same assessment object as composed output.
$StandaloneReport = New-PSIReport -Title $Assessment.Title -Subtitle $Assessment.Description -Theme $Theme
$null = $StandaloneReport | Add-PSIAssessment -Assessment $Assessment
$OutputFile = Export-PSIReport -Report $StandaloneReport -Path $OutputPath
Write-Host "Generated report: $($OutputFile.FullName)"
Write-Host ("Fictional sample: {0} DNS servers; {1} resolvers; {2} zones; {3} forwarders; {4} conditional targets." -f $Servers.Count, $Resolvers.Count, $Zones.Count, $Forwarders.Count, $Conditional.Count)
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
