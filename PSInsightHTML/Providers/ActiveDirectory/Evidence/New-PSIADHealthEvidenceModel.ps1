function New-PSIADHealthEvidenceModel {
    <# .SYNOPSIS Project collected facts and explicit gaps; no health verdict is calculated. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][pscustomobject] $Snapshot)
    if (@($Snapshot.Domains).Count -ne 1 -or $null -eq $Snapshot.PSObject.Properties['DomainControllers']) { throw 'Health evidence requires a normalized single-domain snapshot.' }
    $Domain=[string]$Snapshot.Domains[0].Name
    $Results=@($Snapshot.CollectionResults)+@($Snapshot.HealthCollectionResults)
    $Sample=$Snapshot.Source -eq 'Fictional sample'
    $Items=[System.Collections.Generic.List[object]]::new()
    function AddObservation($Type,$DC,$Collector,$Value,$Method,$StateOverride,$ObservedAt,$ErrorOverride) {
        $Match=@($Results | Where-Object { $_.CollectorId -eq $Collector -and $_.Scope -eq $DC } | Select-Object -Last 1)
        $Record=if ($Match.Count) { $Match[0] } else { $null }
        $State=if ($StateOverride) { [string]$StateOverride } elseif ($Record) { [string]$Record.Status } elseif ($Sample -and $null -ne $Value) { 'Collected' } else { 'NotRequested' }
        if ($State -notin @('Collected','Partial','Failed','NotSupported','NotRequested','NotTested')) { throw "Invalid collection state '$State' for $Type." }
        $Stamp=if ($ObservedAt -is [datetime]) { $ObservedAt } elseif ($Record -and $Record.CompletedAt -is [datetime]) { $Record.CompletedAt } else { $Snapshot.CollectedAt }
        $ErrorClass=if ($ErrorOverride) { [string]$ErrorOverride } elseif ($Record -and $Record.ErrorClass) { [string]$Record.ErrorClass } else { '' }
        $Items.Add([pscustomobject]@{
            Type=[string]$Type; DC=[string]$DC; Domain=$Domain; Collector=[string]$Collector; Timestamp=[datetime]$Stamp
            CollectionState=$State; CollectionMethod=if ($Method) { [string]$Method } elseif ($Record -and $Record.CollectionMethod) { [string]$Record.CollectionMethod } else { 'Snapshot fact' }
            Confidence=if ($Type -eq 'Backup' -and $Value -and $Value.ProviderConfidence) { [string]$Value.ProviderConfidence } elseif ($State -eq 'Collected' -and $null -ne $Value) { if ($Sample) { 'Sample' } else { 'High' } } elseif ($State -eq 'Partial') { 'Low' } else { 'None' }
            ErrorClass=$ErrorClass; EmptyResult=($State -eq 'Collected' -and ($null -eq $Value -or ($Value -is [array] -and $Value.Count -eq 0))); Value=$Value
        })
    }
    foreach ($DC in @($Snapshot.DomainControllers)) {
        if ($DC.Domain -ne $Domain) { throw "DC '$($DC.Name)' lies outside the snapshot domain." }
        $Name=[string]$DC.Name
        AddObservation Reachability $Name Remote ([pscustomobject]@{ Reachable=$DC.Reachable; RemoteQueryCompleted=(@($Results | Where-Object { $_.CollectorId -eq 'Remote' -and $_.Scope -eq $Name -and $_.Status -eq 'Collected' }).Count -gt 0) }) 'Directory inventory / remote query' '' $null ''
        AddObservation CPU $Name Cpu $DC.CPU 'CIM Win32_Processor' '' $null ''
        AddObservation Memory $Name Remote ([pscustomobject]@{ TotalGB=$DC.MemoryGB; AvailableGB=$DC.MemoryAvailableGB; UsedPercent=$DC.MemoryUsedPercent }) 'CIM Win32_OperatingSystem' '' $null ''
        AddObservation Disk $Name Remote ([pscustomobject]@{ Drive=$DC.SystemDrive; TotalGB=$DC.DiskSizeGB; FreeGB=$DC.DiskFreeGB; FreePercent=$DC.DiskFreePercent }) 'CIM Win32_LogicalDisk' '' $null ''
        AddObservation Uptime $Name Remote $DC.UptimeDays 'CIM Win32_OperatingSystem' '' $null ''
        $Details=@($DC.ServiceDetails)
        foreach ($Service in @('NTDS','Netlogon','DFSR','DNS','KDC','W32Time')) {
            $Detail=@($Details | Where-Object Name -eq $Service | Select-Object -First 1)
            $State=if ($DC.Services -and $DC.Services.ContainsKey($Service)) { [string]$DC.Services[$Service] } else { 'Unknown' }
            AddObservation Service $Name Remote ([pscustomobject]@{ Name=$Service; DisplayName=if ($Detail.Count) { [string]$Detail[0].DisplayName } else { '' }; ObservedState=$State; StartMode=if ($Detail.Count) { [string]$Detail[0].StartMode } else { '' } }) 'CIM Win32_Service' '' $null ''
        }
        AddObservation Share $Name Shares ([pscustomobject]@{ Name='SYSVOL'; Present=$DC.SysvolShare }) 'CIM Win32_Share' '' $null ''
        AddObservation Share $Name Shares ([pscustomobject]@{ Name='NETLOGON'; Present=$DC.NetlogonShare }) 'CIM Win32_Share' '' $null ''
        AddObservation DNSClient $Name Remote @($DC.DNSClient) 'CIM network adapter' '' $null ''
        $ForwarderState=if ($DC.DNSQueryStates -and $DC.DNSQueryStates.ContainsKey('Forwarders')) { [string]$DC.DNSQueryStates.Forwarders } else { '' }
        $ZoneState=if ($DC.DNSQueryStates -and $DC.DNSQueryStates.ContainsKey('Zones')) { [string]$DC.DNSQueryStates.Zones } else { '' }
        AddObservation DNSForwarders $Name DNS @($DC.DNSForwarders) 'DnsServer management query' $ForwarderState $null ''
        AddObservation ResolverReachability $Name ResolverReachability $null 'No resolver probe in this profile' 'NotTested' $null ''
        AddObservation ForwarderReachability $Name ForwarderReachability $null 'No forwarder probe in this profile' 'NotTested' $null ''
        AddObservation DNSZones $Name DNS ([pscustomobject]@{ QueryStates=$DC.DNSQueryStates; Zones=@($DC.DNSZones | ForEach-Object { [pscustomobject]@{ Name=$_.Name; IsDsIntegrated=$_.IsDsIntegrated; IsReverseLookupZone=$_.IsReverseLookupZone; ReplicationScope=$_.ReplicationScope } }); ADIntegratedObserved=$DC.ADIntegratedZone; ForwardZone=$DC.ForwardZoneHealthy; ReverseZone=$DC.ReverseZoneHealthy; ConditionalForwarders=@($DC.ConditionalForwarders) }) 'DnsServer management query' $ZoneState $null ''
        AddObservation TimeSource $Name Time ([pscustomobject]@{ ObservedSource=$DC.TimeSource; ConfiguredSource=if ($Name -eq $Snapshot.Domains[0].PDCEmulator) { $Snapshot.Time.PDCSource } else { $null }; SourceReachable=if ($Name -eq $Snapshot.Domains[0].PDCEmulator) { $Snapshot.Time.PDCSourceReachable } else { $null }; SourceType=$null; OffsetMilliseconds=$null; PDC=($Name -eq $Snapshot.Domains[0].PDCEmulator) }) 'w32tm source query' '' $null ''
        AddObservation TimeSourceReachability $Name PDCSourceReachability $(if ($Name -eq $Snapshot.Domains[0].PDCEmulator) { $Snapshot.Time.PDCSourceReachable } else { $null }) 'No independent NTP probe' 'NotTested' $null ''
        AddObservation SiteMembership $Name DCs ([pscustomobject]@{ Site=$DC.Site; Domain=$DC.Domain }) 'ActiveDirectory DC query' '' $null ''
        AddObservation PendingReboot $Name PendingReboot $DC.PendingReboot $(if ($Sample) { 'Fictional fixture' } else { 'No common remote query' }) $(if ($Sample) { 'Collected' } else { 'NotTested' }) $null ''
        $Features=@($DC.InstalledFeatures)
        AddObservation WindowsFeatures $Name Features @($Features | ForEach-Object { [pscustomobject]@{ Id=$_.Id; Name=[string]$_.Name; Installed=[bool]$_.Installed } }) 'CIM Win32_ServerFeature' '' $null ''
        $Queries=@($Snapshot.EventQueries | Where-Object DC -eq $Name)
        if (-not $Queries.Count) { AddObservation EventQuery $Name Events $null 'Windows event log' '' $null '' }
        foreach ($Query in $Queries) { AddObservation EventQuery $Name Events ([pscustomobject]@{ Log=$Query.Log; WindowHours=$Query.QueryWindowHours; Message=$Query.Message }) 'Windows event log' $Query.State $Query.Timestamp $Query.ErrorClass }
        foreach ($Collector in @('Partners','Failures')) {
            $Query=@($Results | Where-Object { $_.CollectorId -eq $Collector -and $_.Scope -eq $Name } | Select-Object -Last 1)
            AddObservation ReplicationQuery $Name $Collector ([pscustomobject]@{ Query=$Collector; RecordCount=if ($Query.Count) { $Query[0].ResourceCount } else { $null } }) 'ActiveDirectory replication query' '' $null ''
        }
    }
    foreach ($Link in @($Snapshot.Replication)) {
        AddObservation Replication ([string]$Link.Destination) Partners ([pscustomobject]@{ Source=$Link.Source; Destination=$Link.Destination; NamingContext=$Link.NamingContext; CurrentFailures=$Link.CurrentFailures; ConsecutiveFailures=$Link.ConsecutiveFailures; LastSuccess=$Link.LastSuccess; LastAttempt=$Link.LastAttempt; LastError=$Link.LastError; LatencyMinutes=$Link.LatencyMinutes }) 'ActiveDirectory replication metadata' '' $null ''
    }
    foreach ($Failure in @($Snapshot.ReplicationFailures)) { AddObservation ReplicationFailure ([string]$Failure.DC) Failures ([pscustomobject]@{ Source=$Failure.Source; NamingContext=$Failure.NamingContext; FailureCount=$Failure.FailureCount; LastError=$Failure.LastError; FirstFailureTime=$Failure.FirstFailureTime }) 'ActiveDirectory replication failure query' $Failure.CollectionState $Failure.Timestamp '' }
    AddObservation SiteLinks $Domain SiteLinks @($Snapshot.SiteLinks | ForEach-Object { [pscustomobject]@{ Name=$_.Name; Sites=@($_.Sites); Cost=$_.Cost; ReplicationIntervalMinutes=$_.ReplicationIntervalMinutes; HasSchedule=$_.HasSchedule; ScheduleSummary=$_.ScheduleSummary } }) 'ActiveDirectory site link query' $Snapshot.SiteLinkCollectionState $null ''
    AddObservation DFSRMigration $Domain DFSRMigration $Snapshot.Forest.DFSRMigrationState 'Directory or provider observation' $(if ($Sample -and $Snapshot.Forest.DFSRMigrationState) { 'Collected' } else { 'NotTested' }) $null ''
    AddObservation Sites $Domain Sites @($Snapshot.Sites | ForEach-Object { [pscustomobject]@{ Name=$_.Name; DomainControllers=@($_.DomainControllers) } }) 'ActiveDirectory site query' '' $null ''
    AddObservation Subnets $Domain Subnets @($Snapshot.Subnets | ForEach-Object { [pscustomobject]@{ Name=$_.Name; Site=$_.Site } }) 'ActiveDirectory subnet query' '' $null ''
    AddObservation UnmappedSubnets $Domain Subnets @($Snapshot.UnmappedSubnets | ForEach-Object { [pscustomobject]@{ Name=$_.Name; Site=$_.Site } }) 'ActiveDirectory subnet query' '' $null ''
    AddObservation ResolverReachability $Domain ResolverReachability $Snapshot.DNS.ClientResolverReachability $(if ($Sample) { 'Fictional fixture' } else { 'No resolver probe' }) $(if ($Sample -and $Snapshot.DNS.ClientResolverReachability.Count) { 'Collected' } else { 'NotTested' }) $null ''
    AddObservation ForwarderReachability $Domain ForwarderReachability $Snapshot.DNS.ForwarderReachability $(if ($Sample) { 'Fictional fixture' } else { 'No forwarder probe' }) $(if ($Sample -and $Snapshot.DNS.ForwarderReachability.Count) { 'Collected' } else { 'NotTested' }) $null ''
    foreach ($Backup in @($Snapshot.BackupObservations)) {
        AddObservation Backup ([string]$Backup.DC) Backup ([pscustomobject]@{ LastSuccessfulSystemStateBackup=$Backup.LastSuccessfulSystemStateBackup; Source=$Backup.Source; ProviderConfidence=$Backup.Confidence }) 'Provider input' $Backup.CollectionState $Backup.EvidenceTimestamp ''
    }
    foreach ($DC in @($Snapshot.DomainControllers)) { if (-not @($Snapshot.BackupObservations | Where-Object DC -eq $DC.Name).Count) { AddObservation Backup ([string]$DC.Name) Backup $null 'Provider input' 'NotRequested' $null '' } }
    foreach ($Event in @($Snapshot.EventObservations)) {
        AddObservation Event ([string]$Event.DC) Events ([pscustomobject]@{ Log=$Event.Log; Provider=$Event.Provider; EventId=$Event.EventId; Level=$Event.Level; MessageSummary=$Event.MessageSummary; EvidenceCategory=$Event.EvidenceCategory; QueryWindowHours=$Event.QueryWindowHours }) 'Windows event log' $Event.CollectionState $Event.Timestamp ''
    }
    foreach ($Port in @($Snapshot.Ports)) { AddObservation Port ([string]$Port.Destination) Port ([pscustomobject]@{ Source=$Port.Source; Destination=$Port.Destination; Port=$Port.Port; Protocol=if ($Port.Protocol) { $Port.Protocol } else { 'Unknown' }; Method=if ($Port.TestMethod) { $Port.TestMethod } else { 'Provider observation' }; Result=$Port.Result }) 'TCP connect or provider observation' $(if ($Port.Result -eq 'NotTested') { 'NotTested' } else { '' }) $null '' }
    foreach ($Dependency in @($Snapshot.Dependencies)) { AddObservation Dependency $Domain Dependencies ([pscustomobject]@{ Name=$Dependency.Name; Type=$Dependency.Type; Status=$Dependency.Status; ProviderInputRequired=$Dependency.ProviderInputRequired }) 'Directory query or provider input' '' $null '' }
    [pscustomobject]@{
        ContractVersion='1.0'; Kind='ActiveDirectory.HealthEvidence'; Domain=$Domain; CollectedAt=$Snapshot.CollectedAt
        NoHealthVerdict=$true; Observations=$Items.ToArray(); CollectionCoverage=if ($Sample -and @($Snapshot.HealthCollectionResults).Count) { Get-PSIADCollectionCoverage -Results @($Snapshot.HealthCollectionResults) } else { $Snapshot.CollectionCoverage }
        CollectionResults=@($Results); EventWindowHours=$Snapshot.EventWindowHours
    }
}
