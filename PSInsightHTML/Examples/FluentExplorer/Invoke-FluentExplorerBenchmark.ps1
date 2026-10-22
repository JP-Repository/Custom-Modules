#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Light', 'Dark', 'Auto')][string] $Theme = 'Auto',
    [string] $OutputPath = (Join-Path $PSScriptRoot 'FluentExplorer-Benchmark.html')
)

$ModuleRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $ModuleRoot 'PSInsightHTML.psd1') -Force

# All names, measurements and findings below are fictional presentation data.
$Services = @(
    [pscustomobject]@{ Name='Atlas API'; Region='North'; Status='Healthy'; Availability='99.98%'; Owner='Platform' }
    [pscustomobject]@{ Name='Beacon Queue'; Region='West'; Status='Warning'; Availability='98.74%'; Owner='Messaging' }
    [pscustomobject]@{ Name='Cedar Gateway'; Region='South'; Status='Healthy'; Availability='99.95%'; Owner='Network' }
    [pscustomobject]@{ Name='Delta Index'; Region='East'; Status='Critical'; Availability='96.30%'; Owner='Search' }
    [pscustomobject]@{ Name='Echo Metrics'; Region='North'; Status='Healthy'; Availability='99.91%'; Owner='Observability' }
    [pscustomobject]@{ Name='Fjord Archive'; Region='West'; Status='Unknown'; Availability=$null; Owner='Storage' }
)
$Report = New-PSIReport -Title 'Infrastructure Explorer' -Subtitle 'Fictional controller and service snapshot' `
    -Layout Application -Navigation FluentExplorer -Density Compact -Theme $Theme

$Nodes = @(
    @{ Id='forest'; Label='root.example.com'; Type='Forest'; Icon='Relationship'; Status='Unknown'; Count=1; Target='topology' }
    @{ Id='domain'; Label='root.example.com'; Type='Domain'; ParentId='forest'; Icon='Relationship'; Status='Unknown'; Count=6; Target='topology' }
    @{ Id='sites'; Label='Sites'; Type='Category'; ParentId='domain'; Icon='Relationship'; Status='Unknown'; Count=3 }
    @{ Id='hq'; Label='HQ'; Type='Site'; ParentId='sites'; Icon='Relationship'; Status='Healthy'; Count=2 }
    @{ Id='dc01'; Label='DC01'; Type='Domain Controller'; ParentId='hq'; Icon='ResourceServer'; Status='Healthy'; Target='overview' }
    @{ Id='dc02'; Label='DC02'; Type='Domain Controller'; ParentId='hq'; Icon='ResourceServer'; Status='Healthy'; Target='overview' }
    @{ Id='branch1'; Label='Branch1'; Type='Site'; ParentId='sites'; Icon='Relationship'; Status='Unknown'; Count=2 }
    @{ Id='dc03'; Label='DC03'; Type='Domain Controller'; ParentId='branch1'; Icon='ResourceServer'; Status='Warning'; Target='overview' }
    @{ Id='dc04'; Label='DC04'; Type='Domain Controller'; ParentId='branch1'; Icon='ResourceServer'; Status='Critical'; Target='overview' }
    @{ Id='branch2'; Label='Branch2'; Type='Site'; ParentId='sites'; Icon='Relationship'; Status='Healthy'; Count=2 }
    @{ Id='dc05'; Label='DC05'; Type='Domain Controller'; ParentId='branch2'; Icon='ResourceServer'; Status='Healthy'; Target='overview' }
    @{ Id='dc06'; Label='DC06'; Type='Domain Controller'; ParentId='branch2'; Icon='ResourceServer'; Status='Healthy'; Target='overview' }
    @{ Id='ous'; Label='OUs'; Type='Category'; ParentId='domain'; Icon='Document'; Status='Unknown' }
    @{ Id='groups'; Label='Groups'; Type='Category'; ParentId='domain'; Icon='ResourceServer'; Status='Unknown' }
    @{ Id='users'; Label='Users'; Type='Category'; ParentId='domain'; Icon='ResourceServer'; Status='Unknown' }
    @{ Id='computers'; Label='Computers'; Type='Category'; ParentId='domain'; Icon='ResourceServer'; Status='Unknown' }
    @{ Id='serviceaccounts'; Label='Service Accounts'; Type='Category'; ParentId='domain'; Icon='SecurityShield'; Status='Unknown' }
    @{ Id='gpos'; Label='GPOs'; Type='Category'; ParentId='domain'; Icon='Rules'; Status='Unknown' }
    @{ Id='dns'; Label='DNS'; Type='Category'; ParentId='domain'; Icon='Relationship'; Status='Unknown' }
    @{ Id='certificates'; Label='Certificates'; Type='Category'; ParentId='domain'; Icon='Document'; Status='Unknown' }
    @{ Id='trusts'; Label='Trusts'; Type='Category'; ParentId='domain'; Icon='Relationship'; Status='Unknown' }
    @{ Id='adconnect'; Label='AD Connect'; Type='Category'; ParentId='domain'; Icon='Relationship'; Status='Unknown' }
)
$Report | Add-PSIResourceExplorer -Id infrastructure -Title 'Resources' -Nodes $Nodes -SelectedId dc01 | Out-Null

$DcSamples = @(
    @{ Id='dc01'; Name='DC01'; Site='HQ'; IPv4='192.0.2.10'; Status='Healthy'; Replication='Healthy'; DNS='Healthy'; Uptime='42 days'; Roles='AD DS, DNS, GC'; Fsmo='PDC Emulator'; OS='Windows Server 2022' }
    @{ Id='dc02'; Name='DC02'; Site='HQ'; IPv4='192.0.2.11'; Status='Healthy'; Replication='Healthy'; DNS='Healthy'; Uptime='38 days'; Roles='AD DS, DNS, GC'; Fsmo='RID Master'; OS='Windows Server 2022' }
    @{ Id='dc03'; Name='DC03'; Site='Branch1'; IPv4='198.51.100.10'; Status='Warning'; Replication='Warning'; DNS='Healthy'; Uptime='97 days'; Roles='AD DS, DNS'; Fsmo='None'; OS='Windows Server 2022' }
    @{ Id='dc04'; Name='DC04'; Site='Branch1'; IPv4='198.51.100.11'; Status='Critical'; Replication='Healthy'; DNS='Critical'; Uptime='131 days'; Roles='AD DS, DNS'; Fsmo='None'; OS='Windows Server 2019' }
    @{ Id='dc05'; Name='DC05'; Site='Branch2'; IPv4='203.0.113.10'; Status='Healthy'; Replication='Healthy'; DNS='Healthy'; Uptime='31 days'; Roles='AD DS, DNS, GC'; Fsmo='Infrastructure Master'; OS='Windows Server 2022' }
    @{ Id='dc06'; Name='DC06'; Site='Branch2'; IPv4='203.0.113.11'; Status='Healthy'; Replication='Healthy'; DNS='Healthy'; Uptime='29 days'; Roles='AD DS, DNS'; Fsmo='None'; OS='Windows Server 2022' }
)
# The topology model carries only the fields needed for graph presentation.
# ParentId and Containment edges describe hierarchy. Replication edges below
# are separately declared fictional examples; they are never inferred from sites.
$TopologyResources = @(
    (New-PSIResource -Definition @{ Id='forest'; Name='root.example.com'; Type='Forest'; Status='Unknown' })
    (New-PSIResource -Definition @{ Id='domain'; Name='root.example.com'; Type='Domain'; Status='Unknown' })
    (New-PSIResource -Definition @{ Id='hq'; Name='HQ'; Type='Site'; Status='Unknown' })
    (New-PSIResource -Definition @{ Id='branch1'; Name='Branch1'; Type='Site'; Status='Unknown' })
    (New-PSIResource -Definition @{ Id='branch2'; Name='Branch2'; Type='Site'; Status='Unknown' })
    foreach ($Dc in $DcSamples) {
        New-PSIResource -Definition @{ Id=$Dc.Id; Name=$Dc.Name; Type='Domain Controller'; Status=$Dc.Status; Properties=@{ Site=$Dc.Site; IPv4=$Dc.IPv4 } }
    }
)
$TopologyNodes = @(
    @{ NodeId='forest'; ResourceId='forest'; Label='root.example.com'; NodeType='Forest'; Status='Unknown'; Icon='Relationship' }
    @{ NodeId='domain'; ResourceId='domain'; ParentId='forest'; Label='root.example.com'; NodeType='Domain'; Status='Unknown'; Icon='Relationship' }
    @{ NodeId='hq'; ResourceId='hq'; ParentId='domain'; Label='HQ'; NodeType='Site'; Status='Unknown'; Icon='Relationship' }
    @{ NodeId='branch1'; ResourceId='branch1'; ParentId='domain'; Label='Branch1'; NodeType='Site'; Status='Unknown'; Icon='Relationship' }
    @{ NodeId='branch2'; ResourceId='branch2'; ParentId='domain'; Label='Branch2'; NodeType='Site'; Status='Unknown'; Icon='Relationship' }
    foreach ($Dc in $DcSamples) {
        $SiteId = switch ($Dc.Site) { HQ { 'hq' } Branch1 { 'branch1' } Branch2 { 'branch2' } }
        @{ NodeId=$Dc.Id; ResourceId=$Dc.Id; ParentId=$SiteId; Label=$Dc.Name; Icon='ResourceServer' }
    }
)
$TopologyRelationshipSpecs = @(
    @{ Id='forest-domain'; SourceResourceId='forest'; TargetResourceId='domain'; Type='contains'; Category='Containment'; Label='Forest contains domain'; Status='Unknown' }
    @{ Id='domain-hq'; SourceResourceId='domain'; TargetResourceId='hq'; Type='contains'; Category='Containment'; Label='Domain contains HQ'; Status='Unknown' }
    @{ Id='domain-branch1'; SourceResourceId='domain'; TargetResourceId='branch1'; Type='contains'; Category='Containment'; Label='Domain contains Branch1'; Status='Unknown' }
    @{ Id='domain-branch2'; SourceResourceId='domain'; TargetResourceId='branch2'; Type='contains'; Category='Containment'; Label='Domain contains Branch2'; Status='Unknown' }
)
foreach ($Dc in $DcSamples) {
    $SiteId = switch ($Dc.Site) { HQ { 'hq' } Branch1 { 'branch1' } Branch2 { 'branch2' } }
    $TopologyRelationshipSpecs += @{ Id=$SiteId + '-' + $Dc.Id; SourceResourceId=$SiteId; TargetResourceId=$Dc.Id; Type='contains'; Category='Containment'; Label='Site contains ' + $Dc.Name; Status='Unknown' }
}
$TopologyRelationshipSpecs += @(
    @{ Id='rep-dc01-dc02'; SourceResourceId='dc01'; TargetResourceId='dc02'; Type='replicates-to'; Category='Replication'; Label='Sample replication DC01 to DC02'; Status='Healthy'; Description='Explicit fictional replication link.' }
    @{ Id='rep-dc01-dc03'; SourceResourceId='dc01'; TargetResourceId='dc03'; Type='replicates-to'; Category='Replication'; Label='Sample replication DC01 to DC03'; Status='Warning'; Description='Explicit fictional replication link needing review.' }
    @{ Id='rep-dc02-dc05'; SourceResourceId='dc02'; TargetResourceId='dc05'; Type='replicates-to'; Category='Replication'; Label='Sample replication DC02 to DC05'; Status='Healthy'; Description='Explicit fictional replication link.' }
    @{ Id='rep-dc03-dc04'; SourceResourceId='dc03'; TargetResourceId='dc04'; Type='replicates-to'; Category='Replication'; Label='Sample replication DC03 to DC04'; Status='Unknown'; Description='Explicit fictional link with no health conclusion.' }
)
$TopologyRelationships = @($TopologyRelationshipSpecs | ForEach-Object { New-PSIRelationship -Definition $_ })
$TopologyModel = New-PSIApplicationModel -Resources $TopologyResources -Relationships $TopologyRelationships
$Report | Set-PSIApplicationModel -Model $TopologyModel | Out-Null
$DcChecks = @($DcSamples | ForEach-Object {
    [pscustomobject]@{ Name=$_.Name; Site=$_.Site; Replication=$_.Replication; DNS=$_.DNS; Status=$_.Status }
})
$StatusCounts = @(
    [pscustomobject]@{ Status='Healthy'; Count=4 }
    [pscustomobject]@{ Status='Warning'; Count=1 }
    [pscustomobject]@{ Status='Critical'; Count=1 }
)
$InspectorItems = @(
    foreach ($Dc in $DcSamples) {
        $FindingBlocks = @()
        $RecommendationBlocks = @()
        if ($Dc.DNS -eq 'Critical') {
            $FindingBlocks = @(@{ Title='DNS check requires review'; Text='Synthetic DNS observation for ' + $Dc.Name + '. Reference: dns-' + $Dc.Id; Status='Critical' })
            $RecommendationBlocks = @(@{ Title='Inspect DNS sample evidence'; Text='Review the fictional DNS check and compare the affected controller with its site peer.' })
        }
        elseif ($Dc.Replication -eq 'Warning') {
            $FindingBlocks = @(@{ Title='Replication check needs attention'; Text='Synthetic replication observation for ' + $Dc.Name + '. Reference: replication-' + $Dc.Id; Status='Warning' })
            $RecommendationBlocks = @(@{ Title='Inspect replication sample evidence'; Text='Review the fictional replication check and its related site context.' })
        }
        @{
            Id='inspector-' + $Dc.Id; ResourceId=$Dc.Id
            Title=$Dc.Name + '.root.example.com'; Subtitle='Synthetic domain controller'; Status=$Dc.Status
            Breadcrumb=@('Infrastructure','Sites',$Dc.Site)
            Actions=@(@{ Label='View checks'; TargetView='checks' })
            Metadata=[ordered]@{ Site=$Dc.Site; Roles=$Dc.Roles }
            Properties=[ordered]@{
                OS=$Dc.OS; IPv4=$Dc.IPv4; FSMO=$Dc.Fsmo; Uptime=$Dc.Uptime
                Replication=$Dc.Replication; DNS=$Dc.DNS
                'Functional Level'='Windows Server 2016'; Hardware='Fictional virtual machine'
            }
            Sections=@(
                @{ Id='Evidence'; Title='Evidence'; Blocks=@(
                    @{ Title='Heartbeat sample'; Text='Fictional monitor reference: heartbeat-' + $Dc.Id; Status=$Dc.Status },
                    @{ Title='Directory sample'; Text='Fictional directory reference: directory-' + $Dc.Id; Status='Informational' },
                    @{ Title='Replication and DNS sample'; Text='Fictional check references: replication-' + $Dc.Id + ', dns-' + $Dc.Id; Status=$Dc.Status }
                ) },
                @{ Id='Findings'; Title='Findings'; Blocks=$FindingBlocks },
                @{ Id='Recommendations'; Title='Recommendations'; Blocks=$RecommendationBlocks },
                @{ Id='Related'; Title='Related'; Blocks=@(
                    @{ Title='Domain'; Text='root.example.com'; ResourceId='domain'; ActionLabel='Open domain' }
                ) }
            )
        }
    }
)
$Report | Add-PSIInspector -Id dc-context -Title 'Context Inspector' -Items $InspectorItems | Out-Null

$Report | Add-PSIView -Id overview -Title Summary -Subtitle 'Fictional infrastructure health' -Icon NavigationHome -TabCount 2 -Initial |
    Add-PSISection -Title 'Health Overview' | Add-PSIRow |
    Add-PSIKPI -Title 'Overall' -Value 'Critical' -Subtitle 'DNS sample needs review' -Status Critical -Icon SeverityError -Span 2 |
    Add-PSIKPI -Title 'Controllers' -Value 6 -Subtitle '4 healthy / 3 sites' -Status Info -Icon ResourceServer -Span 2 |
    Add-PSIKPI -Title 'Replication' -Value '1 warning' -Subtitle 'DC03' -Status Warning -Icon SeverityWarning -Span 2 |
    Add-PSIKPI -Title 'DNS' -Value '1 critical' -Subtitle 'DC04' -Status Critical -Icon SeverityError -Span 2 |
    Add-PSIKPI -Title 'Evidence' -Value '6 / 6' -Subtitle 'Sample DC records present' -Status Info -Icon Document -Span 2 |
    Add-PSIKPI -Title 'Attention' -Value 2 -Subtitle 'Affected controllers' -Status Warning -Icon SeverityWarning -Span 2 | Out-Null
$Report | Add-PSISection -Title 'Requires Attention' | Add-PSIRow |
    Add-PSIAlert -Status Critical -Title 'DC04 - DNS' -Message 'Fictional DNS check is critical. Select DC04 to inspect its evidence.' |
    Add-PSIAlert -Status Warning -Title 'DC03 - Replication' -Message 'Fictional replication check needs review. Select DC03 to inspect its evidence.' | Out-Null

$Report | Add-PSIView -Id checks -Title Checks -Subtitle 'Synthetic controller checks' -Icon Rules -TabCount 6 |
    Add-PSISection -Title 'Controller checks' | Add-PSIRow |
    Add-PSITable -Id controller-checks -Title 'Replication and DNS' -Data $DcChecks -Columns @('Name','Site','Replication','DNS','Status') -PageSize 6 | Out-Null
$Report | Add-PSISection -Title 'Controller status' | Add-PSIRow |
    Add-PSIChart -Title 'Controllers by status' -ChartType Bar -Data $StatusCounts -CategoryProperty Status -ValueProperty Count -ShowLabels $true | Out-Null
$Report | Add-PSISection -Title 'Sample Trends' | Add-PSIRow |
    Add-PSISparkline -Label CPU -CurrentValue '12%' -Values @(18,20,17,16,14,17,12,12) -Status Healthy -Span 3 |
    Add-PSISparkline -Label Memory -CurrentValue '58%' -Values @(50,52,54,55,54,57,58,58) -Status Healthy -Span 3 |
    Add-PSISparkline -Label Disk -CurrentValue '34%' -Values @(29,29,30,31,31,32,33,34) -Status Warning -Span 3 |
    Add-PSISparkline -Label 'LDAP latency' -CurrentValue '18 ms' -Values @(16,17,15,20,19,18,17,18) -Status Info -Span 3 | Out-Null

$Report | Add-PSIView -Id services -Title Evidence -Subtitle 'Searchable fictional inventory' -Icon Document -TabCount 6 |
    Add-PSISection -Title 'Service inventory' | Add-PSIRow |
    Add-PSITable -Id service-evidence -Title 'Service evidence' -Data $Services -Columns @('Name','Region','Status','Availability','Owner') -PageSize 5 | Out-Null

$Report | Add-PSIView -Id topology -Title Topology -Subtitle 'Fictional site distribution' -Icon Relationship -TabCount 3 |
    Add-PSISection -Title 'Fictional topology' | Add-PSIRow |
    Add-PSIText -Text 'Legend: dashed = containment; solid = explicitly declared fictional replication. Node text shows status. Unknown = no verdict; evidence-only = unassessed context.' -Size Small |
    Add-PSIRow |
    Add-PSITopology -Id infrastructure-topology -Title 'Forest, sites and controllers' -Nodes $TopologyNodes -DetailProperties @('Site','IPv4') -FilterProperties @('Site') -MaxNodes 30 -LinkViews @{ Resource='overview'; Finding='notes'; Evidence='services' } | Out-Null

$Report | Add-PSIView -Id notes -Title Actions -Subtitle 'Sample follow-up only' -Icon Document -TabCount 2 |
    Add-PSISection -Title 'Suggested sample review' | Add-PSIRow |
    Add-PSIRecommendation -Status Critical -Title 'Review DC04 DNS evidence' -Description 'The fictional DNS check is critical.' -ActionText 'Open DC04 in Resources and inspect its evidence reference.' |
    Add-PSIRecommendation -Status Warning -Title 'Review DC03 replication evidence' -Description 'The fictional replication check is warning.' -ActionText 'Open DC03 in Resources and inspect its evidence reference.' | Out-Null
$Report | Add-PSISection -Title 'About this snapshot' | Add-PSIRow |
    Add-PSIText -Text 'This standalone benchmark contains synthetic services only. No live infrastructure was queried.' | Out-Null

Export-PSIReport -Report $Report -Path $OutputPath | Out-Null
Write-Output (Resolve-Path -LiteralPath $OutputPath).Path
