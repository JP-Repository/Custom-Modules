[CmdletBinding()]
param(
    [switch] $UseSampleData,
    [string] $Domain,
    [ValidateSet('Core','Operational','Health','Full')][string] $CollectionProfile = 'Operational',
    [hashtable] $CommandAdapter,
    [pscustomobject] $Snapshot,
    [string] $OutputPath,
    [ValidateSet('Light','Dark','Auto')][string] $Theme = 'Auto',
    [switch] $NoBrowser,
    [switch] $PassThru
)
$ErrorActionPreference='Stop'
$ModuleRoot=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
Import-Module (Join-Path $ModuleRoot 'PSInsightHTML.psd1') -Force
. (Join-Path $ModuleRoot 'Providers/ActiveDirectory/Shared/Import-PSIADProvider.ps1')
if ($null -eq $Snapshot) {
    $Raw=Collect-PSIADSnapshot -UseSampleData:$UseSampleData -Domain $Domain -Profile $CollectionProfile -CommandAdapter $CommandAdapter
    $Snapshot=ConvertTo-PSIADDCReadinessModel -InputObject $Raw
}
$Inventory=New-PSIADDCInventoryModel -Snapshot $Snapshot
$Presentation=New-PSIADDCInventoryPresentation -Snapshot $Snapshot -Inventory $Inventory
$Sample=$Snapshot.Source -eq 'Fictional sample'
$Report=New-PSIReport -Title $(if ($Sample) { 'DC Inventory | Fictional Sample' } else { "DC Inventory | $($Inventory.Summary.Domain)" }) -Subtitle 'Domain-scoped configuration and observation inventory' -Theme $Theme -Layout Application
$Report | Add-Member -NotePropertyName PrintDisplay -NotePropertyValue $Inventory.PrintDisplay
$null=$Report | Set-PSIApplicationModel -Model $Presentation.Model

$OSDistribution=@($Inventory.DomainControllers | Group-Object OS | Sort-Object Name | ForEach-Object { [pscustomobject]@{ OS=$_.Name; Count=$_.Count } })
$null=$Report |
    Add-PSIView -Id overview -Title 'Overview' -Subtitle 'Scope and observed inventory' -Icon NavigationHome -Initial -Commands @(@{Label='Browse controllers';Icon='ResourceServer';TargetView='controllers'}) |
    Add-PSISection -Title 'Domain inventory' |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Text $(if ($Sample) { 'Fictional sample data. No directory or network query was made.' } else { "Read-only observations for $($Inventory.Summary.Domain). Collection coverage describes completeness, not health." }) -Size Small |
    Add-PSIRow -Columns 12 |
    Add-PSIKPI -Title 'Domain controllers' -Value $Inventory.Summary.DCCount -Subtitle $Inventory.Summary.Domain -Status Informational -Icon ResourceServer -Span 3 |
    Add-PSIKPI -Title 'Sites' -Value $Inventory.Summary.SiteCount -Subtitle 'Observed sites' -Status Informational -Icon Relationship -Span 3 |
    Add-PSIKPI -Title 'Subnets' -Value $Inventory.Summary.SubnetCount -Subtitle 'Mapped subnets' -Status Informational -Icon Relationship -Span 3 |
    Add-PSIKPI -Title 'Global Catalogs' -Value $Inventory.Summary.GCCount -Subtitle 'Observed DC flags' -Status Informational -Icon ResourceServer -Span 3 |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id inventory-summary -Title 'Domain and forest context' -Data @($Inventory.Summary) -Columns @('Domain','Forest','DomainFunctionalLevel','ForestFunctionalLevel','Profile','CollectedAt') -PageSize 5 |
    Add-PSIRow -Columns 12 |
    Add-PSIChart -Title 'Observed operating systems' -ChartType Bar -Data $OSDistribution -CategoryProperty OS -ValueProperty Count

$null=$Report |
    Add-PSIView -Id controllers -Title 'Domain Controllers' -Subtitle 'Names, OS, site and role flags' -Icon ResourceServer -Badge $Inventory.Summary.DCCount |
    Add-PSISection -Title 'Controller register' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id inventory-controllers -Title 'Domain controllers' -Data @($Inventory.DomainControllers | ForEach-Object { [pscustomobject]@{ Name=$_.Name; Domain=$_.Domain; Site=$_.Site; IPv4=$_.IPv4; OS=$_.OS; Build=$_.Build; GlobalCatalog=$_.GlobalCatalog; RODC=$_.RODC; FSMORoles=$_.FSMORoles -join ', '; Reachable=$_.Reachable; CollectionState=$_.CollectionState } }) -Columns @('Name','Domain','Site','IPv4','OS','Build','GlobalCatalog','RODC','FSMORoles','Reachable','CollectionState') -PageSize 10

$SiteRows=@($Inventory.Sites | ForEach-Object { [pscustomobject]@{ Site=$_.Name; DomainControllers=@($_.DomainControllers) -join ', '; Subnets=@($_.Subnets) -join ', ' } })
$null=$Report |
    Add-PSIView -Id sites -Title 'Sites & Subnets' -Subtitle 'Site membership and address ranges' -Icon Relationship |
    Add-PSISection -Title 'Topology catalog' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id inventory-sites -Title 'Sites' -Data $SiteRows -Columns @('Site','DomainControllers','Subnets') |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id inventory-subnets -Title 'Subnets' -Data @($Inventory.Subnets) -Columns @('Name','Site') |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id inventory-sitelinks -Title 'Site links' -Data @($Inventory.SiteLinks | ForEach-Object { [pscustomobject]@{ Name=$_.Name; Sites=@($_.Sites) -join ', '; Cost=$_.Cost; FrequencyMinutes=$_.ReplicationIntervalMinutes; CollectionState=$Inventory.SiteLinkCollectionState } }) -Columns @('Name','Sites','Cost','FrequencyMinutes','CollectionState') -EmptyMessage 'No site link observations are present in this snapshot.'

$null=$Report |
    Add-PSIView -Id dns -Title 'DNS' -Subtitle 'Client resolvers and observed forwarders' -Icon Relationship |
    Add-PSISection -Title 'DNS configuration' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id inventory-dns-clients -Title 'DNS client configuration' -Data $Inventory.DNSClients -Columns @('DC','Site','PrimaryDNS','SecondaryDNS','AdditionalDNS','CollectionState') |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id inventory-dns-forwarders -Title 'DNS Server forwarders by DC' -Data $Inventory.DNSForwarders -Columns @('DC','Forwarder','CollectionState','QueryMethod') |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Text 'NotSupported means the collector could not query DNS Server tooling; it is not a DNS failure. Blank forwarder cells do not imply no forwarders unless collection completed.' -Size Small

$null=$Report |
    Add-PSIView -Id roles -Title 'FSMO & GC' -Subtitle 'Role holders and catalog flags' -Icon ResourceServer |
    Add-PSISection -Title 'Directory roles' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id inventory-fsmo -Title 'FSMO role holders' -Data $Inventory.FSMORoles -Columns @('Role','Scope','Holder') |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id inventory-gc -Title 'Global Catalog controllers' -Data @($Inventory.GlobalCatalogs | Select-Object Name,Site,OS,GlobalCatalog) -Columns @('Name','Site','OS','GlobalCatalog')

$null=$Report |
    Add-PSIView -Id time -Title 'Time' -Subtitle 'Observed and configured sources' -Icon Document |
    Add-PSISection -Title 'Time configuration' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id inventory-time -Title 'Controller time sources' -Data $Inventory.Time -Columns @('DC','PDC','ObservedSource','ConfiguredSource','SourceReachable','CollectionState')

$null=$Report |
    Add-PSIView -Id system -Title 'System' -Subtitle 'Uptime and storage observations' -Icon ResourceServer |
    Add-PSISection -Title 'System observations' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id inventory-system -Title 'System and storage' -Data $Inventory.System -Columns @('DC','UptimeDays','SystemDrive','TotalGB','FreeGB','FreePercent','CPU','MemoryGB','NICAddresses','NICSubnets','CollectionState') |
    Add-PSIRow -Columns 12 |
    Add-PSIText -Text 'CPU and feature inventory are optional Health evidence. Memory, system drive, capacity and NIC details appear only when explicitly observed. Blank values are unavailable evidence, not zero.' -Size Small

$null=$Report |
    Add-PSIView -Id services -Title 'Services & Shares' -Subtitle 'Observed service and share names' -Icon ResourceServer |
    Add-PSISection -Title 'Operational observations' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id inventory-services -Title 'Service observations' -Data $Inventory.Services -Columns @('DC','Service','ObservedState','CollectionState') |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id inventory-shares -Title 'Share observations' -Data $Inventory.Shares -Columns @('DC','Share','CollectionState')

$null=$Report |
    Add-PSIView -Id replication -Title 'Replication' -Subtitle 'Observed links and naming contexts' -Icon Relationship |
    Add-PSISection -Title 'Replication metadata' |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id inventory-replication -Title 'Inbound partner observations' -Data $Inventory.Replication -Columns @('Source','Destination','NamingContext','Direction','LastSuccess','LastResult','CurrentFailures','External','EvidenceOnly')

$null=$Report |
    Add-PSIView -Id hierarchy -Title 'Hierarchy' -Subtitle 'Forest, domain, site and DC' -Icon Relationship -Group Investigation |
    Add-PSISection -Title 'Directory hierarchy' |
    Add-PSIRow -Columns 12 |
    Add-PSITree -Id inventory-tree -Title 'Infrastructure hierarchy' -Nodes $Presentation.TreeNodes -Relationships $Presentation.Model.Relationships -DetailProperties @('Site','OS','GlobalCatalog')
$null=$Report |
    Add-PSIView -Id topology -Title 'Topology' -Subtitle 'Replication evidence endpoints' -Icon Relationship -Group Investigation |
    Add-PSISection -Title 'Replication topology' |
    Add-PSIRow -Columns 12 |
    Add-PSITopology -Id inventory-topology -Title 'Observed replication topology' -Nodes $Presentation.TopologyNodes -Relationships $Presentation.TopologyEdges -DetailProperties @('Site','OS') |
    Add-PSIRow -Columns 12 |
    Add-PSIRelationshipExplorer -Id inventory-relationships -Title 'Replication relationships' -Nodes $Presentation.TopologyNodes -Relationships $Presentation.TopologyEdges
$null=$Report |
    Add-PSIView -Id resources -Title 'Resources' -Subtitle 'Searchable inventory entities' -Icon ResourceServer -Group Investigation |
    Add-PSISection -Title 'Resource register' |
    Add-PSIRow -Columns 12 |
    Add-PSIExplorer -Id inventory-resources -Title 'Forest, domain, sites and controllers' -Data $Presentation.Model.Resources -TitleProperty Name -SubtitleProperty Type -StatusProperty Status -EntityType Resource
$null=$Report |
    Add-PSIView -Id evidence -Title 'Evidence' -Subtitle 'Collection observations' -Icon Document -Group Investigation |
    Add-PSISection -Title 'Evidence register' |
    Add-PSIRow -Columns 12 |
    Add-PSIExplorer -Id inventory-evidence -Title 'Provider collection records' -Data $Presentation.Model.Evidence -TitleProperty Title -SubtitleProperty Source -EntityType Evidence
$CoverageRows=@($Inventory.CollectionCoverage.Collectors | ForEach-Object { [pscustomobject]@{ Collector=$_.Collector; CollectionState=$_.Status; Expected=$_.Expected; Collected=$_.Collected; CoveragePercent=$_.CoveragePercent; Failures=$_.Failures; NotTested=$_.NotTested } })
$null=$Report |
    Add-PSIView -Id coverage -Title 'Collection Coverage' -Subtitle 'Evidence completeness and gaps' -Icon Document -Group Investigation |
    Add-PSISection -Title 'Collection provenance' |
    Add-PSIRow -Columns 12 |
    Add-PSIKPI -Title 'Requested evidence collected' -Value "$($Inventory.CollectionCoverage.OverallPercent)%" -Subtitle 'Completeness only; no health score' -Status Informational -Icon Document -Span 4 |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id inventory-coverage -Title 'Collector coverage' -Data $CoverageRows -Columns @('Collector','CollectionState','Expected','Collected','CoveragePercent','Failures','NotTested') |
    Add-PSIRow -Columns 12 |
    Add-PSITable -Id inventory-collection-results -Title 'Detailed collection states' -Data @($Inventory.CollectionResults | ForEach-Object { [pscustomobject]@{ Collector=$_.CollectorId; Scope=$_.Scope; CollectionState=$_.Status; Requested=$_.Requested; Notes=$_.Notes } }) -Columns @('Collector','Scope','CollectionState','Requested','Notes') -EmptyMessage 'Fictional fixture: collection results were supplied as sample values.'

if (-not $OutputPath) { $OutputPath=Join-Path $ModuleRoot 'Reports/DCInventory' }
$null=New-Item -Path $OutputPath -ItemType Directory -Force
$HtmlPath=Join-Path $OutputPath $(if ($Sample) { 'DCInventory-Sample.html' } else { 'DCInventory-Mocked.html' })
$null=Export-PSIReport -Report $Report -Path $HtmlPath
if (-not $NoBrowser) {
    try {
        if ($env:OS -eq 'Windows_NT') { Start-Process $HtmlPath }
        elseif (Get-Command open -ErrorAction SilentlyContinue) { & open $HtmlPath }
    } catch { Write-Warning "Report generated, but browser opening failed: $($_.Exception.Message)" }
}
if ($PassThru) { [pscustomobject]@{ Snapshot=$Snapshot; Inventory=$Inventory; Presentation=$Presentation; Report=$Report; HtmlPath=$HtmlPath } }
else { $HtmlPath }
