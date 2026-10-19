function Add-PSIADResources {
    <# .SYNOPSIS Materialize reusable PSI resources from one normalized AD snapshot. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][pscustomobject] $Inventory,
          [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]] $Resources)
    $SourceDescription=if ($Inventory.Source -eq 'Fictional sample') { 'Fictional' } else { 'Read-only observed' }
    $InventoryStatus=if ($Inventory.Source -eq 'Fictional sample') { 'Healthy' } else { 'Unknown' }
    $Resources.Add((New-PSIResource -Definition @{ Id='forest'; Name=$Inventory.Forest.Name; Type='Forest'; Status=$InventoryStatus; Description="$SourceDescription AD forest"; Properties=@{ FunctionalLevel=$Inventory.Forest.FunctionalLevel; SysvolReplication=$Inventory.Forest.SysvolReplication; SchemaMaster=$Inventory.Forest.SchemaMaster; DomainNamingMaster=$Inventory.Forest.DomainNamingMaster } }))
    foreach ($Domain in $Inventory.Domains) { $Resources.Add((New-PSIResource -Definition @{ Id='domain'; Name=$Domain.Name; Type='Domain'; Status=$InventoryStatus; Description="$SourceDescription AD domain"; Properties=@{ FunctionalLevel=$Domain.FunctionalLevel; PDCEmulator=$Domain.PDCEmulator; RIDMaster=$Domain.RIDMaster; InfrastructureMaster=$Domain.InfrastructureMaster } })) }
    for ($I=0; $I -lt $Inventory.Sites.Count; $I++) { $Site=$Inventory.Sites[$I]; $Resources.Add((New-PSIResource -Definition @{ Id="site-$($I+1)"; Name=$Site.Name; Type='Site'; Status=$InventoryStatus; Description="$SourceDescription AD site"; Properties=@{ Subnets=@($Site.Subnets) -join ', ' } })) }
    for ($I=0; $I -lt $Inventory.DomainControllers.Count; $I++) {
        $DC=$Inventory.DomainControllers[$I]
        $Resources.Add((New-PSIResource -Definition @{ Id="dc-$($I+1)"; Name=$DC.Name; Type='Domain Controller'; Status=if ($null -eq $DC.Reachable) { 'Unknown' } elseif ($DC.Reachable) { 'Healthy' } else { 'Warning' }; Description="$SourceDescription $($DC.OS) domain controller"; Properties=@{ Site=$DC.Site; OS=$DC.OS; Build=$DC.Build; Writable=$DC.Writable; GlobalCatalog=$DC.GlobalCatalog; FSMORoles=@($DC.FSMORoles) -join ', '; DNSClient=@($DC.DNSClient) -join ', '; TimeSource=$DC.TimeSource; DiskFreeGB=$DC.DiskFreeGB; UptimeDays=$DC.UptimeDays; PendingReboot=$DC.PendingReboot } }))
    }
    for ($I=0; $I -lt $Inventory.Dependencies.Count; $I++) { $D=$Inventory.Dependencies[$I]; $Resources.Add((New-PSIResource -Definition @{ Id="dependency-$($I+1)"; Name=$D.Name; Type=$D.Type; Status=if ($D.Status -eq 'Ready') { 'Healthy' } elseif ($D.Status -eq 'NotTested') { 'NotChecked' } else { 'Warning' }; Description=$D.Detail; Properties=@{ Version=$D.Version; CU=$D.CU; Confidence=$D.Confidence } })) }
}
