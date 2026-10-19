function Add-PSIADRelationships {
    <# .SYNOPSIS Construct shared AD membership/dependency relationships without assessment findings. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][pscustomobject] $Inventory,
          [Parameter(Mandatory)][System.Collections.Generic.List[object]] $Resources,
          [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]] $Relationships)
    $Relationships.Add((New-PSIRelationship -Definition @{ Id='rel-domain-forest'; SourceResourceId='domain'; TargetResourceId='forest'; Type='belongs-to'; Status='Healthy' }))
    for ($I=0; $I -lt $Inventory.DomainControllers.Count; $I++) {
        $SiteIndex=[array]::IndexOf(@($Inventory.Sites | ForEach-Object { $_.Name }),$Inventory.DomainControllers[$I].Site)
        $Relationships.Add((New-PSIRelationship -Definition @{ Id="rel-dc-$($I+1)"; SourceResourceId="dc-$($I+1)"; TargetResourceId="site-$($SiteIndex+1)"; Type='located-in'; Status='Healthy' }))
    }
    for ($I=0; $I -lt $Inventory.Dependencies.Count; $I++) { $Relationships.Add((New-PSIRelationship -Definition @{ Id="rel-dependency-$($I+1)"; SourceResourceId="dependency-$($I+1)"; TargetResourceId='domain'; Type='depends-on'; Status='Warning' })) }
    foreach ($Link in $Relationships) { foreach ($Resource in $Resources) { if ($Resource.Id -in @($Link.SourceResourceId,$Link.TargetResourceId)) { $Resource.RelationshipIds=@($Resource.RelationshipIds)+@($Link.Id) } } }
}
