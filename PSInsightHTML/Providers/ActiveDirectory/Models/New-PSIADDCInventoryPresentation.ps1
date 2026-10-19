function New-PSIADDCInventoryPresentation {
    <# .SYNOPSIS Create neutral PSI resources, evidence and relationship views from one inventory projection. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][pscustomobject] $Snapshot,
          [Parameter(Mandatory)][pscustomobject] $Inventory)

    $Resources=[System.Collections.Generic.List[object]]::new()
    $Relationships=[System.Collections.Generic.List[object]]::new()
    $Evidence=[System.Collections.Generic.List[object]]::new()
    $Nodes=[System.Collections.Generic.List[object]]::new()
    $Resources.Add((New-PSIResource -Definition @{ Id='forest'; Name=$Inventory.Summary.Forest; Type='Forest'; Status='Unknown'; Properties=@{ FunctionalLevel=$Inventory.Summary.ForestFunctionalLevel } }))
    $Resources.Add((New-PSIResource -Definition @{ Id='domain'; Name=$Inventory.Summary.Domain; Type='Domain'; Status='Unknown'; Properties=@{ FunctionalLevel=$Inventory.Summary.DomainFunctionalLevel } }))
    $Relationships.Add((New-PSIRelationship -Definition @{ Id='rel-domain-forest'; SourceResourceId='domain'; TargetResourceId='forest'; Type='belongs-to'; Status='Unknown' }))
    $Nodes.Add(@{ NodeId='forest'; ResourceId='forest'; Icon='ResourceServer' })
    $Nodes.Add(@{ NodeId='domain'; ResourceId='domain'; ParentId='forest'; Icon='ResourceServer' })
    $SiteIds=@{}
    for ($I=0; $I -lt $Inventory.Sites.Count; $I++) {
        $Site=$Inventory.Sites[$I]; $Id="site-$($I+1)"; $SiteIds[[string] $Site.Name]=$Id
        $Resources.Add((New-PSIResource -Definition @{ Id=$Id; Name=$Site.Name; Type='Site'; Status='Unknown'; Properties=@{ Subnets=@($Site.Subnets) -join ', ' } }))
        $Relationships.Add((New-PSIRelationship -Definition @{ Id="rel-$Id"; SourceResourceId=$Id; TargetResourceId='domain'; Type='located-in'; Status='Unknown' }))
        $Nodes.Add(@{ NodeId=$Id; ResourceId=$Id; ParentId='domain'; Icon='Relationship' })
    }
    $DCIds=@{}
    for ($I=0; $I -lt $Inventory.DomainControllers.Count; $I++) {
        $DC=$Inventory.DomainControllers[$I]; $Id="dc-$($I+1)"; $DCIds[[string]$DC.Name]=$Id
        $Resources.Add((New-PSIResource -Definition @{ Id=$Id; Name=$DC.Name; Type='Domain Controller'; Status='Unknown'; Properties=@{ Site=$DC.Site; OS=$DC.OS; Build=$DC.Build; IPv4=$DC.IPv4; GlobalCatalog=$DC.GlobalCatalog; FSMORoles=$DC.FSMORoles -join ', '; TimeSource=$DC.TimeSource; CollectionState=$DC.CollectionState } }))
        $Relationships.Add((New-PSIRelationship -Definition @{ Id="rel-$Id-site"; SourceResourceId=$Id; TargetResourceId=$SiteIds[[string]$DC.Site]; Type='located-in'; Status='Unknown' }))
        $Nodes.Add(@{ NodeId=$Id; ResourceId=$Id; ParentId=$SiteIds[[string]$DC.Site]; Icon='ResourceServer' })
    }
    $ReplicationNodes=[System.Collections.Generic.List[object]]::new()
    foreach ($DC in $Inventory.DomainControllers) { $ReplicationNodes.Add(@{ NodeId=$DCIds[[string]$DC.Name]; ResourceId=$DCIds[[string]$DC.Name]; Icon='ResourceServer' }) }
    $ReplicationEdges=[System.Collections.Generic.List[object]]::new()
    $ExternalIds=@{}
    for ($I=0; $I -lt $Inventory.Replication.Count; $I++) {
        $Link=$Inventory.Replication[$I]
        if (-not $DCIds.ContainsKey([string]$Link.Destination)) { continue }
        if ($DCIds.ContainsKey([string]$Link.Source)) { $SourceId=$DCIds[[string]$Link.Source] }
        elseif ($Link.External -and $Link.EvidenceOnly) {
            if (-not $ExternalIds.ContainsKey([string]$Link.Source)) {
                $ExternalIds[[string]$Link.Source]="external-$($ExternalIds.Count+1)"
                $ReplicationNodes.Add(@{ NodeId=$ExternalIds[[string]$Link.Source]; Label=$Link.Source; NodeType='External evidence endpoint'; Status='Unknown'; IsExternal=$true; EvidenceOnly=$true; Icon='Relationship' })
            }
            $SourceId=$ExternalIds[[string]$Link.Source]
        } else { continue }
        $ReplicationEdges.Add(@{ Id="replication-$($I+1)"; SourceId=$SourceId; TargetId=$DCIds[[string]$Link.Destination]; Type='replicates-with'; Label='Replication observation'; Direction='Directed'; Status='Unknown'; Category='Replication'; Description="Naming context: $($Link.NamingContext)"; IsExternal=[bool]$Link.External; EvidenceOnly=[bool]$Link.EvidenceOnly })
        if ($DCIds.ContainsKey([string]$Link.Source)) {
            $Relationships.Add((New-PSIRelationship -Definition @{ Id="rel-replication-$($I+1)"; SourceResourceId=$SourceId; TargetResourceId=$DCIds[[string]$Link.Destination]; Type='replicates-with'; Status='Unknown'; Description="Observed naming context: $($Link.NamingContext)" }))
        }
    }
    for ($I=0; $I -lt @($Snapshot.CollectionResults).Count; $I++) {
        $Item=$Snapshot.CollectionResults[$I]; if ($null -eq $Item) { continue }
        $Linked=@(if ($DCIds.ContainsKey([string]$Item.Scope)) { $DCIds[[string]$Item.Scope] } else { 'domain' })
        $Evidence.Add((New-PSIADObservationEvidence -Id "inventory-observation-$($I+1)" -Title "$($Item.CollectorId) / $($Item.Scope)" -Snapshot $Snapshot -CollectionResult $Item -Summary "Collection state: $($Item.Status). $($Item.Notes)" -ResourceIds $Linked))
    }
    if ($Evidence.Count -eq 0 -and $Snapshot.Source -eq 'Fictional sample') {
        $Evidence.Add((New-PSIEvidenceRecord -Definition @{ Id='inventory-fictional-fixture'; Title='Fictional sample snapshot'; Type='AD collection observation'; Source=$Snapshot.Source; CollectedAt=$Snapshot.CollectedAt; Summary='Deterministic fictional inventory values; no live collection occurred.'; Data=@{ CollectionState='FictionalSample' }; Metadata=@{ CollectionState='Collected'; Scope=$Inventory.Summary.Domain }; ResourceIds=@('domain') }))
    }
    foreach ($Relationship in $Relationships) {
        foreach ($Resource in $Resources) { if ($Resource.Id -in @($Relationship.SourceResourceId,$Relationship.TargetResourceId)) { $Resource.RelationshipIds=@($Resource.RelationshipIds)+@($Relationship.Id) } }
    }
    foreach ($Observation in $Evidence) {
        foreach ($Resource in $Resources) { if ($Resource.Id -in @($Observation.ResourceIds)) { $Resource.EvidenceIds=@($Resource.EvidenceIds)+@($Observation.Id) } }
    }
    [pscustomobject]@{
        Model=(New-PSIApplicationModel -Resources $Resources.ToArray() -Evidence $Evidence.ToArray() -Relationships $Relationships.ToArray())
        TreeNodes=$Nodes.ToArray(); TopologyNodes=$ReplicationNodes.ToArray(); TopologyEdges=$ReplicationEdges.ToArray()
    }
}
