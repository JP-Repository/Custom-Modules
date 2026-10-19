function ConvertTo-PSIADDCReadinessModel {
    <# .SYNOPSIS Validate and normalize a provider-owned AD inventory without target-specific interpretation. #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true, ValueFromPipeline = $true)][pscustomobject] $InputObject)
    process {
        foreach ($Field in @('Forest','Domains','Sites','DomainControllers','Replication','Dependencies','Security','SecurityValues','Ports','DNS','Time','Thresholds')) {
            if ($null -eq $InputObject.PSObject.Properties[$Field] -or $null -eq $InputObject.$Field) { throw "DC readiness snapshot requires $Field." }
        }
        if ([string]::IsNullOrWhiteSpace([string] $InputObject.Forest.Name) -or @($InputObject.Domains).Count -eq 0) { throw 'Forest and at least one domain are required.' }
        $Names = @{}
        foreach ($DC in @($InputObject.DomainControllers)) {
            if ([string]::IsNullOrWhiteSpace([string] $DC.Name) -or $Names.ContainsKey([string] $DC.Name)) { throw 'DC names must be non-empty and unique.' }
            $Names[[string] $DC.Name] = $true
            if ($DC.Domain -notin @($InputObject.Domains | ForEach-Object { $_.Name })) { throw "DC '$($DC.Name)' references an unknown domain." }
            if ($DC.Site -notin @($InputObject.Sites | ForEach-Object { $_.Name })) { throw "DC '$($DC.Name)' references an unknown site." }
            foreach ($Service in @('NTDS','Netlogon','DNS','DFSR','KDC','W32Time')) {
                if (-not $DC.Services.ContainsKey($Service)) { throw "DC '$($DC.Name)' has no $Service service observation." }
            }
        }
        foreach ($Link in @($InputObject.Replication)) {
            if (-not $Names.ContainsKey([string] $Link.Destination)) { throw 'Replication destination must be an assessed DC.' }
            if (-not $Names.ContainsKey([string] $Link.Source) -and -not ($Link.ExternalToAssessmentScope -eq $true -and $Link.EvidenceOnly -eq $true -and -not [string]::IsNullOrWhiteSpace([string]$Link.Source))) { throw 'Replication link references an unknown DC without evidence-only scope metadata.' }
            if ($null -ne $Link.LastSuccess -and $Link.LastSuccess -isnot [datetime]) { throw 'Replication LastSuccess must be a typed DateTime or null when unavailable.' }
        }
        if ($InputObject.CollectedAt -isnot [datetime]) { throw 'CollectedAt must be a typed DateTime.' }
        [pscustomobject]@{
            SchemaVersion=if ($InputObject.SchemaVersion) { [string]$InputObject.SchemaVersion } else { '1.0' }
            ContractVersion='1.0'; Source=if ($InputObject.Sample) { 'Fictional sample' } else { 'Live read-only AD collection' }
            CollectionProfile=if ($InputObject.CollectionProfile) { [string]$InputObject.CollectionProfile } else { 'Core' }
            CollectedAt=[datetime] $InputObject.CollectedAt
            Forest=$InputObject.Forest; Domains=@($InputObject.Domains); Sites=@($InputObject.Sites)
            Subnets=@(if ($null -ne $InputObject.PSObject.Properties['Subnets']) { $InputObject.Subnets } else { foreach ($Site in $InputObject.Sites) { foreach ($Subnet in @($Site.Subnets)) { [pscustomobject]@{ Name=[string]$Subnet; Site=[string]$Site.Name } } } })
            UnmappedSubnets=@(if ($InputObject.UnmappedSubnets) { $InputObject.UnmappedSubnets })
            SiteLinks=@(if ($null -ne $InputObject.PSObject.Properties['SiteLinks']) { $InputObject.SiteLinks })
            SiteLinkCollectionState=if ($InputObject.SiteLinkCollectionState) { [string]$InputObject.SiteLinkCollectionState } elseif ($InputObject.Sample) { 'Collected' } else { 'NotTested' }
            DomainControllers=@($InputObject.DomainControllers); Replication=@($InputObject.Replication)
            ReplicationFailures=@(if ($InputObject.ReplicationFailures) { $InputObject.ReplicationFailures })
            Relationships=@($InputObject.Replication)
            Dependencies=@($InputObject.Dependencies); Security=$InputObject.Security; SecurityValues=$InputObject.SecurityValues
            SecurityCollectionResults=@(if ($InputObject.PSObject.Properties['SecurityCollectionResults']) { $InputObject.SecurityCollectionResults })
            SecurityRuntimeResults=@(if ($InputObject.PSObject.Properties['SecurityRuntimeResults']) { $InputObject.SecurityRuntimeResults })
            SecurityTelemetry=@(if ($InputObject.PSObject.Properties['SecurityTelemetry']) { $InputObject.SecurityTelemetry })
            PrivilegedEvidence=if ($InputObject.PSObject.Properties['PrivilegedEvidence']) { $InputObject.PrivilegedEvidence } else { $null }
            GpoIntent=@(if ($InputObject.PSObject.Properties['GpoIntent']) { $InputObject.GpoIntent })
            SecurityObservations=@(foreach ($Key in @($InputObject.SecurityValues.Keys | Sort-Object)) { [pscustomobject]@{ Name=$Key; Value=[string]$InputObject.SecurityValues[$Key]; State=[string]$InputObject.Security[$Key]; EvidenceType='Selected registry or provider observation; effective policy not established' } })
            Services=@(foreach ($DC in @($InputObject.DomainControllers)) { [pscustomobject]@{ DomainController=[string]$DC.Name; States=$DC.Services; QueryState=if ($InputObject.Sample) { 'FictionalSample' } else { $Remote=@($InputObject.CollectionResults | Where-Object { $_.CollectorId -eq 'Remote' -and $_.Scope -eq $DC.Name }); if ($Remote.Count) { [string]$Remote[0].Status } else { 'NotRequested' } } } })
            Ports=@($InputObject.Ports); DNS=$InputObject.DNS; Time=$InputObject.Time; Thresholds=$InputObject.Thresholds
            EventObservations=@(if ($InputObject.EventObservations) { $InputObject.EventObservations }); EventQueries=@(if ($InputObject.EventQueries) { $InputObject.EventQueries })
            EventWindowHours=if ($InputObject.EventWindowHours) { [int]$InputObject.EventWindowHours } else { 72 }
            BackupObservations=@(if ($InputObject.BackupObservations) { $InputObject.BackupObservations })
            HealthCollectionResults=@(if ($InputObject.HealthCollectionResults) { $InputObject.HealthCollectionResults })
            CollectionResults=@($InputObject.CollectionResults); CollectionLogs=@($InputObject.CollectionLogs)
            CollectionEvents=@($InputObject.CollectionLogs)
            Metadata=[pscustomobject]@{ ResourceScope=[string]$InputObject.Domains[0].Name; EvidenceScope=[string]$InputObject.Forest.Name; CollectionProfile=if ($InputObject.CollectionProfile) { [string]$InputObject.CollectionProfile } else { 'Core' }; ReadOnly=$true }
            CollectionCoverage=if ($InputObject.Sample) { [pscustomobject]@{ OverallPercent=100; Expected=1; Collected=1; Collectors=@([pscustomobject]@{ Collector='Fictional fixture'; Status='Collected'; Expected=1; Collected=1; CoveragePercent=100; Failures=0; NotTested=0 }) } } else { Get-PSIADCollectionCoverage -Results @($InputObject.CollectionResults) }
        }
    }
}
