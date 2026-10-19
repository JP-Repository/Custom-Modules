function New-PSIADDCInventoryModel {
    <# .SYNOPSIS Project a normalized, domain-scoped AD snapshot into inventory facts without health interpretation. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][pscustomobject] $Snapshot)

    if ($null -eq $Snapshot.PSObject.Properties['DomainControllers'] -or @($Snapshot.Domains).Count -ne 1) {
        throw 'DC inventory requires one normalized, domain-scoped AD snapshot.'
    }
    $Domain = $Snapshot.Domains[0]
    $DomainName = [string] $Domain.Name
    $Controllers = @($Snapshot.DomainControllers | Where-Object { $_.Domain -eq $DomainName })
    if ($Controllers.Count -ne @($Snapshot.DomainControllers).Count) {
        throw 'Normalized snapshot contains DCs outside the selected domain.'
    }
    $Sites = @($Snapshot.Sites | Where-Object { $_.Name -in @($Controllers | ForEach-Object { $_.Site }) })
    $Subnets = @($Snapshot.Subnets | Where-Object { $_.Site -in @($Sites | ForEach-Object { $_.Name }) })
    $Results = @($Snapshot.CollectionResults)
    function Field($Object, $Name) {
        if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) { return $null }
        return $Object.$Name
    }
    function State($Collector, $Scope, $Sample) {
        if ($Sample) { return 'FictionalSample' }
        $Found = @($Results | Where-Object { $_.CollectorId -eq $Collector -and $_.Scope -eq $Scope })
        if ($Found.Count) { return [string] $Found[0].Status }
        return 'NotRequested'
    }
    $Sample = $Snapshot.Source -eq 'Fictional sample'
    $DCs = @(
        foreach ($DC in $Controllers) {
            $Addresses = @(Field $DC 'DNSClient')
            $Addresses = @($Addresses | Where-Object { $null -ne $_ -and [string] $_ -ne '' })
            $RemoteState = State 'Remote' $DC.Name $Sample
            [pscustomobject]@{
                Name = [string] $DC.Name; FQDN = [string] $DC.Name; Domain = $DomainName; Site = [string] $DC.Site
                IPv4 = Field $DC 'IPv4Address'; NICAddresses=@((Field $DC 'NICAddresses')); NICSubnets=@((Field $DC 'NICSubnets')); OS = Field $DC 'OS'; Build = Field $DC 'Build'
                GlobalCatalog = Field $DC 'GlobalCatalog'; RODC = if ($null -ne (Field $DC 'Writable')) { -not [bool] $DC.Writable } else { $null }
                FSMORoles = @((Field $DC 'FSMORoles')); Reachable = Field $DC 'Reachable'; CollectionState = $RemoteState
                UptimeDays = Field $DC 'UptimeDays'; CPU = Field $DC 'CPU'; CPUState = State 'Cpu' $DC.Name $Sample; MemoryGB = Field $DC 'MemoryGB'
                MemoryAvailableGB = Field $DC 'MemoryAvailableGB'; MemoryUsedPercent = Field $DC 'MemoryUsedPercent'
                InstalledFeatures = @((Field $DC 'InstalledFeatures')); FeatureState = State 'Features' $DC.Name $Sample
                SystemDrive = Field $DC 'SystemDrive'; DiskTotalGB = Field $DC 'DiskSizeGB'; DiskFreeGB = Field $DC 'DiskFreeGB'; DiskFreePercent = Field $DC 'DiskFreePercent'
                TimeSource = Field $DC 'TimeSource'; PrimaryDNS = if ($Addresses.Count -gt 0) { $Addresses[0] } else { $null }
                SecondaryDNS = if ($Addresses.Count -gt 1) { $Addresses[1] } else { $null }
                AdditionalDNS = @($Addresses | Select-Object -Skip 2); DNSClientState = $RemoteState
                DNSRole = Field $DC 'DNSRole'; DNSForwarders = @((Field $DC 'DNSForwarders'))
                Services = Field $DC 'Services'; Shares = @($(if (Field $DC 'SysvolShare') { 'SYSVOL' }), $(if (Field $DC 'NetlogonShare') { 'NETLOGON' }) | Where-Object { $_ })
                ShareState = State 'Shares' $DC.Name $Sample; TimeState = State 'Time' $DC.Name $Sample
                DNSState = State 'DNS' $DC.Name $Sample
            }
        }
    )
    $RoleNames = @('Schema Master','Domain Naming Master','PDC Emulator','RID Master','Infrastructure Master')
    $RoleHolders = @{
        'Schema Master' = Field $Snapshot.Forest 'SchemaMaster'; 'Domain Naming Master' = Field $Snapshot.Forest 'DomainNamingMaster'
        'PDC Emulator' = Field $Domain 'PDCEmulator'; 'RID Master' = Field $Domain 'RIDMaster'; 'Infrastructure Master' = Field $Domain 'InfrastructureMaster'
    }
    $Roles = @(foreach ($Name in $RoleNames) {
        [pscustomobject]@{ Role=$Name; Scope=if ($Name -in @('Schema Master','Domain Naming Master')) { 'Forest' } else { $DomainName }; Holder=$RoleHolders[$Name] }
    })
    $DNSClients = @($DCs | ForEach-Object { [pscustomobject]@{ DC=$_.Name; Site=$_.Site; PrimaryDNS=$_.PrimaryDNS; SecondaryDNS=$_.SecondaryDNS; AdditionalDNS=($_.AdditionalDNS -join ', '); CollectionState=$_.DNSClientState } })
    $Forwarders = @(
        foreach ($DC in $DCs) {
            $Values = @($DC.DNSForwarders | Where-Object { $_ })
            if ($Values.Count -eq 0) { [pscustomobject]@{ DC=$DC.Name; Forwarder=$null; CollectionState=$DC.DNSState; QueryMethod='DNS Server observation' } }
            else { foreach ($Value in $Values) { [pscustomobject]@{ DC=$DC.Name; Forwarder=[string] $Value; CollectionState=$DC.DNSState; QueryMethod='DNS Server observation' } } }
        }
    )
    $Time = @($DCs | ForEach-Object { [pscustomobject]@{ DC=$_.Name; PDC=($_.Name -eq $Domain.PDCEmulator); ObservedSource=$_.TimeSource; ConfiguredSource=if ($_.Name -eq $Domain.PDCEmulator) { Field $Snapshot.Time 'PDCSource' } else { $null }; SourceReachable=if ($_.Name -eq $Domain.PDCEmulator) { Field $Snapshot.Time 'PDCSourceReachable' } else { $null }; CollectionState=$_.TimeState } })
    $System = @($DCs | ForEach-Object { [pscustomobject]@{ DC=$_.Name; UptimeDays=$_.UptimeDays; SystemDrive=$_.SystemDrive; TotalGB=$_.DiskTotalGB; FreeGB=$_.DiskFreeGB; FreePercent=$_.DiskFreePercent; CPU=$_.CPU; MemoryGB=$_.MemoryGB; NICAddresses=$_.NICAddresses -join ', '; NICSubnets=$_.NICSubnets -join ', '; CollectionState=$_.CollectionState } })
    $Services = @(foreach ($DC in $DCs) { if ($DC.Services) { foreach ($Name in @($DC.Services.Keys | Sort-Object)) { [pscustomobject]@{ DC=$DC.Name; Service=$Name; ObservedState=$DC.Services[$Name]; CollectionState=$DC.CollectionState } } } })
    $Shares = @(foreach ($DC in $DCs) { if ($DC.Shares.Count) { foreach ($Name in $DC.Shares) { [pscustomobject]@{ DC=$DC.Name; Share=$Name; CollectionState=$DC.ShareState } } } else { [pscustomobject]@{ DC=$DC.Name; Share=$null; CollectionState=$DC.ShareState } } })
    $Replication = @($Snapshot.Replication | ForEach-Object { [pscustomobject]@{ Source=$_.Source; Destination=$_.Destination; NamingContext=$_.NamingContext; Direction='Inbound to destination'; LastSuccess=$_.LastSuccess; LastResult=$_.LastError; CurrentFailures=$_.CurrentFailures; EvidenceOnly=[bool] $_.EvidenceOnly; External=[bool] $_.ExternalToAssessmentScope } })
    $Summary = [pscustomobject]@{
        Domain=$DomainName; Forest=[string] $Snapshot.Forest.Name; DomainFunctionalLevel=Field $Domain 'FunctionalLevel'
        ForestFunctionalLevel=Field $Snapshot.Forest 'FunctionalLevel'; PDC=$RoleHolders['PDC Emulator']
        RIDMaster=$RoleHolders['RID Master']; InfrastructureMaster=$RoleHolders['Infrastructure Master']
        SchemaMaster=$RoleHolders['Schema Master']; DomainNamingMaster=$RoleHolders['Domain Naming Master']
        DCCount=$DCs.Count; GCCount=@($DCs | Where-Object { $_.GlobalCatalog -eq $true }).Count
        SiteCount=$Sites.Count; SubnetCount=$Subnets.Count; Profile=[string] $Snapshot.CollectionProfile; CollectedAt=$Snapshot.CollectedAt
    }
    [pscustomobject]@{
        Source=$Snapshot.Source; Summary=$Summary; DomainControllers=$DCs; Sites=$Sites; Subnets=$Subnets; UnmappedSubnets=@($Snapshot.UnmappedSubnets)
        SiteLinks=@($Snapshot.SiteLinks); SiteLinkCollectionState=$Snapshot.SiteLinkCollectionState; FSMORoles=$Roles; GlobalCatalogs=@($DCs | Where-Object { $_.GlobalCatalog -eq $true })
        DNSClients=$DNSClients; DNSForwarders=$Forwarders; Time=$Time; System=$System; Services=$Services; Shares=$Shares
        Replication=$Replication; CollectionCoverage=$Snapshot.CollectionCoverage; CollectionResults=$Results
        PrintDisplay=@{ ReportIdentity=@{ Kicker='PSInsightHTML / DC inventory' }; Scope=$DomainName; Profile=[string]$Snapshot.CollectionProfile; CoveragePercent=$Snapshot.CollectionCoverage.OverallPercent; Tables=@('inventory-summary','inventory-controllers','inventory-sites','inventory-subnets','inventory-dns-clients','inventory-dns-forwarders','inventory-fsmo','inventory-gc','inventory-time','inventory-system','inventory-coverage'); Resources=@{ Columns=@(@{Property='Name';Label='Resource'},@{Property='Type';Label='Type'},@{Property='Site';Label='Site'},@{Property='OS';Label='OS'},@{Property='GlobalCatalog';Label='GC';Format='Boolean'}) } }
    }
}
