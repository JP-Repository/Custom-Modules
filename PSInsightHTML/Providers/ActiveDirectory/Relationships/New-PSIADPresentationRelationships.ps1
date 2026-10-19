function New-PSIADPresentationRelationships {
    <# .SYNOPSIS Map normalized AD resources and replication observations to generic presentation nodes and edges. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][pscustomobject] $Inventory, [Parameter(Mandatory)][pscustomobject] $Model)
    $SiteIds=@{}
    for ($I=0; $I -lt $Inventory.Sites.Count; $I++) { $SiteIds[[string] $Inventory.Sites[$I].Name]="site-$($I+1)" }
    $InfrastructureNodes=@(
        foreach ($Resource in $Model.Resources) {
            $Parent=if ($Resource.Id -eq 'domain') { 'forest' }
                elseif ($Resource.Type -eq 'Site' -or $Resource.Id -like 'dependency-*') { 'domain' }
                elseif ($Resource.Type -eq 'Domain Controller') { [string] $SiteIds[[string] $Resource.Properties.Site] }
                else { '' }
            @{ NodeId=$Resource.Id; ResourceId=$Resource.Id; ParentId=$Parent; Icon='ResourceServer' }
        }
    )
    $DcIds=@{}
    $ReplicationNodes=[System.Collections.Generic.List[object]]::new()
    foreach ($Resource in @($Model.Resources | Where-Object { $_.Type -eq 'Domain Controller' })) {
        $DcIds[[string] $Resource.Name]=$Resource.Id
        $ReplicationNodes.Add(@{ NodeId=$Resource.Id; ResourceId=$Resource.Id; Icon='ResourceServer' })
    }
    $ExternalIds=@{}
    $ReplicationEdges=[System.Collections.Generic.List[object]]::new()
    for ($I=0; $I -lt $Inventory.Replication.Count; $I++) {
        $Link=$Inventory.Replication[$I]
        $SourceName=[string] $Link.Source
        if ($DcIds.ContainsKey($SourceName)) { $SourceId=[string] $DcIds[$SourceName] }
        else {
            if (-not ($Link.ExternalToAssessmentScope -and $Link.EvidenceOnly)) { continue }
            if (-not $ExternalIds.ContainsKey($SourceName)) {
                $ExternalIds[$SourceName]="external-partner-$($ExternalIds.Count+1)"
                $ReplicationNodes.Add(@{ NodeId=$ExternalIds[$SourceName]; Label=$SourceName; NodeType='External replication partner'; Status='Unknown'; Icon='Relationship'; IsExternal=$true; EvidenceOnly=$true; Description='Replication evidence endpoint outside the assessed resource scope.' })
            }
            $SourceId=[string] $ExternalIds[$SourceName]
        }
        $Status=if ($null -eq $Link.LastSuccess) { 'Unknown' } elseif ($Link.CurrentFailures -gt 0) { 'Critical' } elseif ($Link.LastError -and $Link.LastError -ne 'None') { 'Warning' } else { 'Healthy' }
        $ReplicationEdges.Add([pscustomobject]@{ Id="replication-link-$($I+1)"; SourceId=$SourceId; TargetId=[string] $DcIds[[string] $Link.Destination]; Type='replicates-with'; Label='Replication observation'; Direction='Directed'; Status=$Status; Category=[string] $Link.NamingContextKind; Description="Naming context: $($Link.NamingContext); last result: $($Link.LastError)"; IsExternal=[bool] $Link.ExternalToAssessmentScope; EvidenceOnly=[bool] $Link.EvidenceOnly })
    }
    [pscustomobject]@{ InfrastructureNodes=$InfrastructureNodes; ReplicationNodes=$ReplicationNodes.ToArray(); ReplicationEdges=$ReplicationEdges.ToArray() }
}
