function New-PSIADLiveSnapshot {
    <# .SYNOPSIS Read-only, sequential collection for one explicitly resolved AD domain. #>
    [CmdletBinding()]
    param([string]$Domain,[switch]$IncludeRemoteChecks,[switch]$IncludePortChecks,[switch]$IncludeSecurityChecks,[switch]$IncludeDependencyDiscovery,[switch]$IncludeHealthEvidence,[ValidateRange(1,168)][int]$EventWindowHours=72,[ValidateRange(5,300)][int]$EventQueryTimeoutSeconds=30,[hashtable]$CommandAdapter)
    if (-not $CommandAdapter) { $CommandAdapter=Get-PSIADReadOnlyAdapter }
    $Results=[System.Collections.Generic.List[object]]::new(); $Logs=[System.Collections.Generic.List[object]]::new()
    $DomainResult=Invoke-PSIADCollector -Adapter $CommandAdapter -Id Domain -Category Inventory -Scope $Domain -Arguments @($Domain) -Results $Results -Logs $Logs
    if ($DomainResult.Status -ne 'Collected' -or $DomainResult.Data.Count -ne 1 -or -not $DomainResult.Data[0].DNSRoot) { throw 'Target domain could not be resolved; live collection stopped.' }
    $Directory=$DomainResult.Data[0]; $Scope=[string]$Directory.DNSRoot; $Now=Get-Date
    if ($Domain -and $Scope -ne $Domain) { throw "Resolved domain '$Scope' does not match requested domain '$Domain'." }
    $ForestResult=Invoke-PSIADCollector -Adapter $CommandAdapter -Id Forest -Category Inventory -Scope $Scope -Arguments @([string]$Directory.Forest) -Results $Results -Logs $Logs
    if ($ForestResult.Status -ne 'Collected' -or $ForestResult.Data.Count -ne 1) { throw 'Forest metadata could not be resolved; live collection stopped.' }
    $Forest=$ForestResult.Data[0]
    $DCResult=Invoke-PSIADCollector -Adapter $CommandAdapter -Id DCs -Category Inventory -Scope $Scope -Arguments @($Scope) -Results $Results -Logs $Logs
    if ($DCResult.Status -ne 'Collected') { throw "Domain-scoped DC inventory failed for $Scope." }
    $RawDCs=@($DCResult.Data | Where-Object { [string]$_.Domain -eq $Scope })
    if ($RawDCs.Count -eq 0) { throw "No domain controllers belonging to $Scope were returned." }
    $Results[$Results.Count-1].ResourceCount=$RawDCs.Count; $Results[$Results.Count-1].ExpectedCount=$RawDCs.Count
    $SitesResult=Invoke-PSIADCollector -Adapter $CommandAdapter -Id Sites -Category Topology -Scope $Scope -Arguments @($Scope) -Results $Results -Logs $Logs
    $SubnetResult=Invoke-PSIADCollector -Adapter $CommandAdapter -Id Subnets -Category Topology -Scope $Scope -Arguments @($Scope) -Results $Results -Logs $Logs
    $LinkResult=Invoke-PSIADCollector -Adapter $CommandAdapter -Id SiteLinks -Category Topology -Scope $Scope -Arguments @($Scope) -Results $Results -Logs $Logs
    $SiteNames=@($RawDCs | ForEach-Object { [string]$_.Site } | Where-Object { $_ } | Select-Object -Unique)
    $ScopedSubnets=@($SubnetResult.Data | Where-Object { $SubnetSite=[string]$_.Site; @($SiteNames | Where-Object { $SubnetSite -match [regex]::Escape($_) }).Count -gt 0 } | ForEach-Object { [pscustomobject]@{ Name=[string]$_.Name; Site=[string]$_.Site } })
    $UnmappedSubnets=@($SubnetResult.Data | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.Site) } | ForEach-Object { [pscustomobject]@{ Name=[string]$_.Name; Site=$null; CollectionState=$SubnetResult.Status; Source='ActiveDirectory subnet query' } })
    $ScopedLinks=@($LinkResult.Data | Where-Object { $LinkSites=[string](@($_.SitesIncluded) -join ','); @($SiteNames | Where-Object { $LinkSites -match [regex]::Escape($_) }).Count -gt 0 } | ForEach-Object { [pscustomobject]@{ Name=[string]$_.Name; Sites=@($_.SitesIncluded | ForEach-Object { [string]$_ }); Cost=$_.Cost; ReplicationIntervalMinutes=$_.ReplicationFrequencyInMinutes; HasSchedule=$null -ne $_.Schedule; ScheduleSummary=if ($null -ne $_.Schedule) { 'Custom schedule observed' } else { 'No custom schedule returned' }; CollectionState=$LinkResult.Status; CollectionMethod='ActiveDirectory site link query' } })
    $Sites=@(foreach ($Name in $SiteNames) { [pscustomobject]@{ Name=$Name; Subnets=@($ScopedSubnets | Where-Object { [string]$_.Site -match [regex]::Escape($Name) } | ForEach-Object { $_.Name }); DomainControllers=@($RawDCs | Where-Object Site -eq $Name | ForEach-Object { $_.HostName }) } })
    $DCs=@(foreach ($Raw in $RawDCs) {
        $HostName=[string]$Raw.HostName
        $Roles=@(if ($HostName -eq [string]$Forest.SchemaMaster) { 'Schema Master' }; if ($HostName -eq [string]$Forest.DomainNamingMaster) { 'Domain Naming Master' }; if ($HostName -eq [string]$Directory.RIDMaster) { 'RID Master' }; if ($HostName -eq [string]$Directory.PDCEmulator) { 'PDC Emulator' }; if ($HostName -eq [string]$Directory.InfrastructureMaster) { 'Infrastructure Master' })
        [pscustomobject]@{
            Name=$HostName; HostName=$HostName; Domain=$Scope; Forest=[string]$Forest.Name; Site=[string]$Raw.Site
            IPv4Address=[string]$Raw.IPv4Address; OS=[string]$Raw.OperatingSystem; OperatingSystemVersion=[string]$Raw.OperatingSystemVersion; Build=[string]$Raw.OperatingSystemVersion
            Writable=-not [bool]$Raw.IsReadOnly; GlobalCatalog=[bool]$Raw.IsGlobalCatalog; FSMORoles=$Roles
            ComputerObjectDN=[string]$Raw.ComputerObjectDN; ServerObjectDN=[string]$Raw.ServerObjectDN; NTDSSettingsDN=[string]$Raw.NTDSSettingsObjectDN; InvocationId=$Raw.InvocationId; Enabled=$Raw.Enabled
            Reachable=$null; Maintenance=$false; DNSRole=$null; DNSClient=@(); DNSForwarders=@(); DNSZones=@(); DNSQueryStates=@{}; ADIntegratedZone=$null; ForwardZoneHealthy=$null; ReverseZoneHealthy=$null; ConditionalForwarders=@()
            TimeSource=$null; Services=@{ NTDS='Unknown'; Netlogon='Unknown'; DNS='Unknown'; DFSR='Unknown'; KDC='Unknown'; W32Time='Unknown' }
            SysvolShare=$null; NetlogonShare=$null; DiskFreeGB=$null; DiskSizeGB=$null; DiskFreePercent=$null; SystemDrive=$null; MemoryGB=$null; MemoryAvailableGB=$null; MemoryUsedPercent=$null; CPU=$null; ServiceDetails=@(); InstalledFeatures=@(); NICAddresses=@(); NICSubnets=@(); PendingReboot=$null; UptimeDays=$null; LastBootUpTime=$null
        }
    })
    $Replication=[System.Collections.Generic.List[object]]::new(); $ReplicationFailures=[System.Collections.Generic.List[object]]::new()
    foreach ($DC in $DCs) {
        $Partners=Invoke-PSIADCollector -Adapter $CommandAdapter -Id Partners -Category Replication -Scope $DC.Name -Arguments @($DC.Name) -Results $Results -Logs $Logs
        $Failures=Invoke-PSIADCollector -Adapter $CommandAdapter -Id Failures -Category Replication -Scope $DC.Name -Arguments @($DC.Name) -Results $Results -Logs $Logs
        if ($Failures.Status -eq 'Collected') { foreach ($Failure in $Failures.Data) { $ReplicationFailures.Add([pscustomobject]@{ DC=$DC.Name; Source=[string]$Failure.Partner; NamingContext=[string]$Failure.Partition; FailureCount=$Failure.FailureCount; LastError=$Failure.LastError; FirstFailureTime=$Failure.FirstFailureTime; CollectionState='Collected'; Timestamp=$Results[$Results.Count-1].CompletedAt }) } }
        if ($Partners.Status -eq 'Collected' -and $Partners.Data.Count -eq 0) { $Results[$Results.Count-2].Status='Partial'; $Results[$Results.Count-2].Succeeded=$false; $Results[$Results.Count-2].ResourceCount=0; $Results[$Results.Count-2].CoveragePercent=0; $Results[$Results.Count-2].Notes='Query succeeded; no partner metadata returned' }
        if ($Partners.Status -ne 'Collected' -or $Failures.Status -ne 'Collected') { continue }
        foreach ($Partner in $Partners.Data) {
            $External=[string]$Partner.Partner -notin @($DCs | ForEach-Object { $_.Name })
            $Partition=[string]$Partner.Partition
            $ContextKind=if ($Partition -match '^CN=Schema,') { 'Schema' } elseif ($Partition -match '^CN=Configuration,') { 'Configuration' } else { 'DomainOrApplication' }
            $Last=$Partner.LastReplicationSuccess
            if ($null -ne $Last -and $Last -ne [datetime]::MinValue) { $Last=[datetime]$Last } else { $Last=$null }
            $Match=@($Failures.Data | Where-Object { [string]$_.Partner -eq [string]$Partner.Partner -and [string]$_.Partition -eq [string]$Partner.Partition } | Select-Object -First 1)
            $LastError=if ($Match.Count) { [string]$Match[0].LastError } elseif ([string]$Partner.LastReplicationResult -eq '0') { 'None' } else { [string]$Partner.LastReplicationResult }
            $Replication.Add([pscustomobject]@{ Source=[string]$Partner.Partner; Destination=$DC.Name; NamingContext=$Partition; NamingContextKind=$ContextKind; ResourceScope=$Scope; EvidenceScope='Replication metadata for assessed DC'; ExternalToAssessmentScope=$External; EvidenceOnly=$External; CurrentFailures=if ($Match.Count) { [int]$Match[0].FailureCount } else { [int]$Partner.ConsecutiveReplicationFailures }; ConsecutiveFailures=[int]$Partner.ConsecutiveReplicationFailures; LastSuccess=$Last; LastAttempt=$Partner.LastReplicationAttempt; LastError=$LastError; LatencyMinutes=if ($Last) { [math]::Round(($Now-$Last).TotalMinutes,1) } else { $null }; Required=$true })
        }
    }
    $EventObservations=[System.Collections.Generic.List[object]]::new(); $EventQueries=[System.Collections.Generic.List[object]]::new()
    foreach ($DC in $DCs) {
        $Remote=Invoke-PSIADCollector -Adapter $CommandAdapter -Id Remote -Category Remote -Scope $DC.Name -Arguments @($DC.Name) -Requested ([bool]$IncludeRemoteChecks) -Method 'CIM' -Results $Results -Logs $Logs
        if ($Remote.Status -eq 'Collected' -and $Remote.Data.Count) {
            $Data=$Remote.Data[0]; $DC.LastBootUpTime=$Data.OS.LastBootUpTime
            if ($Data.OS.SystemDrive) { $DC.SystemDrive=[string]$Data.OS.SystemDrive }
            if ($null -ne $Data.OS.TotalVisibleMemorySize) { $DC.MemoryGB=[math]::Round([double]$Data.OS.TotalVisibleMemorySize / 1MB, 2) }
            if ($null -ne $Data.OS.FreePhysicalMemory) { $DC.MemoryAvailableGB=[math]::Round([double]$Data.OS.FreePhysicalMemory / 1MB, 2) }
            if ($DC.MemoryGB -gt 0 -and $null -ne $DC.MemoryAvailableGB) { $DC.MemoryUsedPercent=[math]::Round(100*($DC.MemoryGB-$DC.MemoryAvailableGB)/$DC.MemoryGB,1) }
            if ($Data.OS.LastBootUpTime) { $DC.UptimeDays=[math]::Round(($Now-[datetime]$Data.OS.LastBootUpTime).TotalDays,1) }
            if ($Data.Disk -and $null -ne $Data.Disk.FreeSpace) { $DC.DiskFreeGB=[math]::Round([double]$Data.Disk.FreeSpace/1GB,2); $DC.DiskSizeGB=[math]::Round([double]$Data.Disk.Size/1GB,2); if ($Data.Disk.Size) { $DC.DiskFreePercent=[math]::Round(100*[double]$Data.Disk.FreeSpace/[double]$Data.Disk.Size,1) } }
            if ($Data.Services) { foreach ($Key in $Data.Services.Keys) { $DC.Services[$Key]=[string]$Data.Services[$Key] } }
            if ($Data.ServiceDetails) { $DC.ServiceDetails=@($Data.ServiceDetails) }
            $DC.DNSClient=@($Data.NICs | ForEach-Object { $_.DNSServerSearchOrder } | Where-Object { $_ } | Select-Object -Unique)
            $DC.NICAddresses=@($Data.NICs | ForEach-Object { $_.IPAddress } | Where-Object { $_ } | Select-Object -Unique)
            $DC.NICSubnets=@($Data.NICs | ForEach-Object { $_.IPSubnet } | Where-Object { $_ } | Select-Object -Unique)
        }
        $Cpu=Invoke-PSIADCollector -Adapter $CommandAdapter -Id Cpu -Category HealthEvidence -Scope $DC.Name -Arguments @($DC.Name) -Requested ([bool]$IncludeHealthEvidence) -Method 'CIM Win32_Processor' -Results $Results -Logs $Logs
        if ($Cpu.Status -eq 'Collected' -and $Cpu.Data.Count) { $DC.CPU=[math]::Round([double](($Cpu.Data | Measure-Object -Average).Average),1) }
        $Features=Invoke-PSIADCollector -Adapter $CommandAdapter -Id Features -Category HealthEvidence -Scope $DC.Name -Arguments @($DC.Name) -Requested ([bool]$IncludeHealthEvidence) -Method 'CIM Win32_ServerFeature' -Results $Results -Logs $Logs
        if ($Features.Status -eq 'Collected') { $DC.InstalledFeatures=@($Features.Data | ForEach-Object { [pscustomobject]@{ Id=$_.ID; Name=[string]$_.Name; Installed=$true } }) }
        $Events=Invoke-PSIADCollector -Adapter $CommandAdapter -Id Events -Category HealthEvidence -Scope $DC.Name -Arguments @($DC.Name,$EventWindowHours,$EventQueryTimeoutSeconds) -Requested ([bool]$IncludeHealthEvidence) -Method 'Windows event log' -Results $Results -Logs $Logs
        if ($Events.Status -eq 'Collected' -and $Events.Data.Count) {
            $EventResult=$Results[$Results.Count-1]
            foreach ($Item in @($Events.Data[0].Observations)) { $EventObservations.Add($Item) }
            foreach ($Query in @($Events.Data[0].Queries)) { $EventQueries.Add([pscustomobject]@{ DC=$DC.Name; Domain=$Scope; Log=$Query.Log; State=$Query.State; ErrorClass=$Query.ErrorClass; Message=$Query.Message; Timestamp=$EventResult.CompletedAt; QueryWindowHours=$EventWindowHours }) }
            $Succeeded=@($Events.Data[0].Queries | Where-Object { $_.State -eq 'Collected' }).Count
            $Total=@($Events.Data[0].Queries).Count
            if ($Total -gt 0) { $EventResult.ExpectedCount=$Total; $EventResult.ResourceCount=$Succeeded; $EventResult.CoveragePercent=[math]::Round(100*$Succeeded/$Total,1) }
            if ($Succeeded -lt $Total) { $EventResult.Status=if ($Succeeded) { 'Partial' } else { 'Failed' }; $EventResult.Succeeded=$false; $EventResult.ErrorClass=if ($Succeeded) { 'PartialQueryFailure' } else { 'QueryFailure' } }
        }
        $Share=Invoke-PSIADCollector -Adapter $CommandAdapter -Id Shares -Category Remote -Scope $DC.Name -Arguments @($DC.Name) -Requested ([bool]$IncludeRemoteChecks) -Method 'CIM Win32_Share' -Results $Results -Logs $Logs
        if ($Share.Status -eq 'Collected') { $DC.SysvolShare='SYSVOL' -in $Share.Data; $DC.NetlogonShare='NETLOGON' -in $Share.Data }
        $Time=Invoke-PSIADCollector -Adapter $CommandAdapter -Id Time -Category Remote -Scope $DC.Name -Arguments @($DC.Name) -Requested ([bool]$IncludeRemoteChecks) -Results $Results -Logs $Logs
        if ($Time.Status -eq 'Collected' -and $Time.Data.Count) { $DC.TimeSource=[string]$Time.Data[0] }
        $DNS=Invoke-PSIADCollector -Adapter $CommandAdapter -Id DNS -Category DNS -Scope $DC.Name -Arguments @($DC.Name) -Requested ([bool]($IncludeRemoteChecks -or $IncludeSecurityChecks)) -Results $Results -Logs $Logs
        if ($IncludeRemoteChecks -or $IncludeSecurityChecks) { $Results[$Results.Count-1].ExpectedCount=3 }
        if ($DNS.Status -eq 'Collected' -and $DNS.Data.Count) {
            $DnsData=$DNS.Data[0]
            $States=if ($DnsData.QueryStates) { $DnsData.QueryStates } else { @{ Forwarders='Collected'; Zones='Collected'; Conditional='Collected' } }
            $DC.DNSQueryStates=$States
            if ($States.Zones -eq 'Collected') { $DC.DNSZones=@($DnsData.Zones | ForEach-Object { [pscustomobject]@{ Name=if ($_.ZoneName) { [string]$_.ZoneName } else { [string]$_.Name }; IsDsIntegrated=$_.IsDsIntegrated; IsReverseLookupZone=$_.IsReverseLookupZone; ReplicationScope=$_.ReplicationScope; ZoneType=$_.ZoneType; DynamicUpdate=$_.DynamicUpdate; SecureSecondaries=$_.SecureSecondaries; SecondaryServers=@($_.SecondaryServers) } }) }
            $Successful=@($States.Values | Where-Object { $_ -eq 'Collected' }).Count
            $Results[$Results.Count-1].ResourceCount=$Successful
            $Results[$Results.Count-1].CoveragePercent=[math]::Round(100*$Successful/3,1)
            if ($Successful -lt 3) {
                $Results[$Results.Count-1].Status=if ($Successful -gt 0) { 'Partial' } else { 'Failed' }
                $Results[$Results.Count-1].Succeeded=$false
                $Results[$Results.Count-1].ErrorCode='DnsQueryIncomplete'
                $Results[$Results.Count-1].ErrorMessage=@($DnsData.Errors) -join '; '
                $Results[$Results.Count-1].Notes=$Results[$Results.Count-1].ErrorMessage
            }
            if ($Successful -gt 0) { $DC.DNSRole=$true }
            if ($States.Forwarders -eq 'Collected') { $DC.DNSForwarders=@($DnsData.Forwarders | ForEach-Object { [string]$_ }) }
            if ($States.Conditional -eq 'Collected') { $DC.ConditionalForwarders=@($DnsData.Conditional | ForEach-Object { [string]$_.Name }) }
            if ($States.Zones -eq 'Collected') { $DC.ADIntegratedZone=@($DnsData.Zones | Where-Object IsDsIntegrated).Count -gt 0 }
        }
    }
    $Ports=[System.Collections.Generic.List[object]]::new()
    foreach ($DC in $DCs) {
        if (-not $IncludePortChecks) { $null=Invoke-PSIADCollector -Adapter $CommandAdapter -Id Port -Category Network -Scope $DC.Name -Arguments @($DC.Name,389) -Requested $false -Results $Results -Logs $Logs; continue }
        foreach ($Port in @(53,88,135,389,445,464,636,3268,3269,5722)) {
            $Probe=Invoke-PSIADCollector -Adapter $CommandAdapter -Id Port -Category Network -Scope $DC.Name -Arguments @($DC.Name,$Port) -Results $Results -Logs $Logs
            $Ports.Add([pscustomobject]@{ Port=$Port; Protocol='TCP'; Role='Collector host to DC TCP'; Source='Assessment host'; Destination=$DC.Name; TestMethod='TCP connect'; Timestamp=$Results[$Results.Count-1].CompletedAt; CollectionState=$Probe.Status; Result=if ($Probe.Status -eq 'Collected') { if ([bool]$Probe.Data[0]) { 'Reachable' } else { 'Failed' } } else { 'NotTested' } })
        }
    }
    $Dependencies=[System.Collections.Generic.List[object]]::new()
    $Discovered=Invoke-PSIADCollector -Adapter $CommandAdapter -Id Dependencies -Category Dependencies -Scope $Scope -Arguments @($Scope) -Requested ([bool]$IncludeDependencyDiscovery) -Results $Results -Logs $Logs
    if ($Discovered.Status -eq 'Collected' -and $Discovered.Data.Count) {
        $Discovery=$Discovered.Data[0]
        $ExchangeState=if ($Discovery.ExchangeQueryStatus) { [string]$Discovery.ExchangeQueryStatus } elseif (@($Discovery.Errors | Where-Object { $_ -match '^Exchange ' }).Count) { 'Failed' } else { 'Collected' }
        $CAState=if ($Discovery.PKIQueryStatus) { [string]$Discovery.PKIQueryStatus } elseif (@($Discovery.Errors | Where-Object { $_ -match '^Enterprise CA ' }).Count) { 'Failed' } else { 'Collected' }
        if ($ExchangeState -eq 'Collected') { foreach ($Exchange in @($Discovery.Exchange)) { $Dependencies.Add([pscustomobject]@{ Id="exchange-$($Exchange.Name)"; Name=[string]$Exchange.Name; Type='Exchange'; Version='Unknown'; CU=$null; Confidence='Low'; Status='Review'; ProviderInputRequired=$false; Detail="Build $($Exchange.AdminDisplayVersion); exact CU not established" }) } }
        if ($CAState -eq 'Collected') { foreach ($CA in @($Discovery.PKI)) { $Dependencies.Add([pscustomobject]@{ Id="pki-$($CA.Name)"; Name=[string]$CA.Name; Type='PKI'; Version='Unknown'; CU=$null; Confidence='Medium'; Status='NotTested'; ProviderInputRequired=$false; Detail='Enterprise CA directory object; service health not tested' }) } }
        $SuccessCount=@(@($ExchangeState,$CAState) | Where-Object { $_ -eq 'Collected' }).Count
        $DependencyResult=$Results[$Results.Count-1]
        $DependencyResult | Add-Member -NotePropertyName ExchangeQueryStatus -NotePropertyValue $ExchangeState
        $DependencyResult | Add-Member -NotePropertyName PKIQueryStatus -NotePropertyValue $CAState
        $DependencyResult | Add-Member -NotePropertyName ExchangeConfidence -NotePropertyValue $(if ($ExchangeState -eq 'Collected') { 'DirectoryQueryOnly' } else { 'None' })
        $DependencyResult | Add-Member -NotePropertyName PKIConfidence -NotePropertyValue $(if ($CAState -eq 'Collected') { 'DirectoryQueryOnly' } else { 'None' })
        $DependencyResult | Add-Member -NotePropertyName ProviderInputRequired -NotePropertyValue $true
        $DependencyResult.ExpectedCount=2; $DependencyResult.ResourceCount=$SuccessCount
        $DependencyResult.CoveragePercent=[math]::Round(100*$SuccessCount/2,1)
        $DependencyResult.Status=if ($SuccessCount -eq 2) { 'Collected' } elseif ($SuccessCount -eq 1) { 'Partial' } else { 'Failed' }
        $DependencyResult.Succeeded=$SuccessCount -eq 2
        $DependencyResult.Notes='Exchange and Enterprise CA directory objects only; application dependencies require provider input'
        if (@($Discovery.Errors).Count) { $DependencyResult.Notes+='; '+(@($Discovery.Errors) -join '; '); $DependencyResult.ErrorCode='DirectoryQueryIncomplete'; $DependencyResult.ErrorMessage=@($Discovery.Errors) -join '; ' }
    }
    foreach ($Item in @(@('Identity sync','Identity sync'),@('AD FS','Federation'),@('Application directory dependencies','LDAP/LDAPS'),@('Hard-coded DC targets','Hard-coded DC'),@('Backup and monitoring','Backup'))) { $Dependencies.Add([pscustomobject]@{ Id=($Item[1] -replace '\W','-').ToLowerInvariant(); Name=$Item[0]; Type=$Item[1]; Version='Unknown'; CU=$null; Confidence='None'; Status='NotTested'; ProviderInputRequired=$true; Detail='Provider input required; not inferred from directory inventory' }) }
    $Security=@{}; $SecurityValues=@{}
    $SecurityCollectionResults=[System.Collections.Generic.List[object]]::new()
    $SecurityRuntimeResults=[System.Collections.Generic.List[object]]::new(); $SecurityTelemetry=[System.Collections.Generic.List[object]]::new()
    foreach ($Rule in (Import-PowerShellDataFile (Join-Path $PSScriptRoot '../Rules/Readiness/SecurityBaseline.psd1')).Rules) { $Security[$Rule.Id]='NotTested'; $SecurityValues[$Rule.Id]='Effective setting not tested' }
    foreach ($DC in $DCs) {
        $Observed=Invoke-PSIADCollector -Adapter $CommandAdapter -Id Security -Category Security -Scope $DC.Name -Arguments @($DC.Name) -Requested ([bool]$IncludeSecurityChecks) -Results $Results -Logs $Logs
        $SecurityCollectionResults.Add([pscustomobject]@{ DC=[string]$DC.Name; State=[string]$Observed.Status; Values=if ($Observed.Data.Count -gt 0 -and $Observed.Data[0] -is [hashtable]) { $Observed.Data[0].Clone() } else { @{} }; Method='Selected registry observations; effective policy not established' })
        if ($Observed.Status -eq 'Collected' -and $Observed.Data.Count -gt 0 -and $Observed.Data[0] -is [hashtable]) {
            foreach ($Key in $Observed.Data[0].Keys) { if ($SecurityValues.ContainsKey($Key)) { $SecurityValues[$Key]="$($DC.Name): $($Observed.Data[0][$Key])" } }
            $Count=@($Observed.Data[0].Keys | Where-Object { $SecurityValues.ContainsKey($_) }).Count
            $Results[$Results.Count-1].ExpectedCount=17; $Results[$Results.Count-1].ResourceCount=$Count
            $Results[$Results.Count-1].CoveragePercent=[math]::Round(100*$Count/17,1)
            if ($Count -lt 17) { $Results[$Results.Count-1].Status='Partial'; $Results[$Results.Count-1].Succeeded=$false; $Results[$Results.Count-1].Notes='Selected registry values observed; effective GPO, user rights, auditing, Defender state, and other security topics remain unverified' }
        }
        $Runtime=Invoke-PSIADCollector -Adapter $CommandAdapter -Id SecurityRuntime -Category Security -Scope $DC.Name -Arguments @($DC.Name,$EventWindowHours) -Requested ([bool]$IncludeSecurityChecks) -Method 'One optional read-only remote session' -Results $Results -Logs $Logs
        $Facts=@(); $Telemetry=@()
        if ($Runtime.Status -eq 'Collected' -and $Runtime.Data.Count) {
            $Facts=@($Runtime.Data[0].Facts); $Telemetry=@($Runtime.Data[0].Telemetry)
            foreach ($Item in $Telemetry) {
                $SecurityTelemetry.Add([pscustomobject]@{ Kind=[string]$Item.Kind; Version=[string]$Item.Version; DC=$DC.Name; Domain=$Scope; Timestamp=$Item.Timestamp; Account=[string]$Item.Account; Client=[string]$Item.Client; Service=[string]$Item.Service; SourceEvent=$Item.SourceEvent; SourceType=if ($Item.SourceType) { [string]$Item.SourceType } else { 'EventLog' }; CollectionState='Collected'; Confidence=if ($Item.Confidence) { [string]$Item.Confidence } else { 'High' }; ErrorClass=''; CollectionWindowHours=$Item.CollectionWindowHours })
            }
            $Good=@($Facts | Where-Object CollectionState -eq Collected).Count
            $Results[$Results.Count-1].ExpectedCount=[math]::Max(1,$Facts.Count)
            $Results[$Results.Count-1].ResourceCount=$Good
            $Results[$Results.Count-1].CoveragePercent=[math]::Round(100*$Good/$Results[$Results.Count-1].ExpectedCount,1)
            if ($Good -lt $Facts.Count -or $Facts.Count -eq 0) { $Results[$Results.Count-1].Status='Partial'; $Results[$Results.Count-1].Succeeded=$false; $Results[$Results.Count-1].Notes='Individual runtime observations have explicit unavailable states or no facts were returned' }
        }
        $SecurityRuntimeResults.Add([pscustomobject]@{ DC=$DC.Name; Domain=$Scope; State=$Results[$Results.Count-1].Status; Facts=$Facts; QueryWindowHours=$EventWindowHours; Timestamp=$Results[$Results.Count-1].CompletedAt; ErrorClass=$Results[$Results.Count-1].ErrorClass; Method='One optional read-only remote session' })
    }
    $PrivilegeResult=Invoke-PSIADCollector -Adapter $CommandAdapter -Id Privileged -Category Security -Scope $Scope -Arguments @($Scope,[string]$Directory.DomainSID,[string]$Forest.Name) -Requested ([bool]$IncludeSecurityChecks) -Method 'Directory queries' -Results $Results -Logs $Logs
    $Privileged=if ($PrivilegeResult.Status -eq 'Collected' -and $PrivilegeResult.Data.Count) { $PrivilegeResult.Data[0] } else { [pscustomobject]@{ Groups=@(); Members=@(); Krbtgt=$null; CollectionState=$PrivilegeResult.Status; ErrorClass=$Results[$Results.Count-1].ErrorClass } }
    if ($PrivilegeResult.Status -eq 'Collected') {
        $Expected=@($Privileged.Groups).Count+1
        $Good=@($Privileged.Groups | Where-Object CollectionState -eq Collected).Count
        if ($Privileged.Krbtgt.CollectionState -eq 'Collected') { $Good++ }
        $PartialMembers=@($Privileged.Members | Where-Object { $_.CollectionState -ne 'Collected' }).Count
        $Results[$Results.Count-1].ExpectedCount=$Expected; $Results[$Results.Count-1].ResourceCount=$Good
        $Results[$Results.Count-1].CoveragePercent=if ($Expected) { [math]::Round(100*$Good/$Expected,1) } else { 0 }
        if ($Good -lt $Expected -or $PartialMembers) { $Results[$Results.Count-1].Status='Partial'; $Results[$Results.Count-1].Succeeded=$false; $Results[$Results.Count-1].Notes='Group, account, or nested principal evidence is incomplete' }
    }
    $Gpo=Invoke-PSIADCollector -Adapter $CommandAdapter -Id GpoIntent -Category Security -Scope $Scope -Arguments @($Scope,@($DCs | ForEach-Object ComputerObjectDN)) -Requested ([bool]$IncludeSecurityChecks) -Method 'DC container GPO links; intent only' -Results $Results -Logs $Logs
    if ($Gpo.Status -eq 'Collected') {
        $Good=@($Gpo.Data | Where-Object CollectionState -eq Collected).Count
        $Results[$Results.Count-1].ExpectedCount=[math]::Max(1,$Gpo.Data.Count); $Results[$Results.Count-1].ResourceCount=$Good
        $Results[$Results.Count-1].CoveragePercent=[math]::Round(100*$Good/$Results[$Results.Count-1].ExpectedCount,1)
        if ($Good -lt $Gpo.Data.Count -or -not $Gpo.Data.Count) { $Results[$Results.Count-1].Status='Partial'; $Results[$Results.Count-1].Succeeded=$false; $Results[$Results.Count-1].Notes='DC container GPO intent incomplete; effective policy never inferred' }
    }
    foreach ($Gap in @('DFSRMigration','PendingReboot','ResolverReachability','ZoneHealth','ForwarderReachability','PDCSourceReachability','ProviderDependencyInput')) {
        $Stamp=Get-Date
        $Results.Add([pscustomobject]@{ CollectorId=$Gap; Name=$Gap; Category='Evidence gap'; Scope=$Scope; Status='NotTested'; StartedAt=$Stamp; CompletedAt=$Stamp; DurationMs=0; Requested=$true; Succeeded=$false; ResourceCount=0; ExpectedCount=1; CoveragePercent=0; ErrorCode=''; ErrorMessage=''; Notes='Requires supported read-only source or provider-supplied evidence' })
    }
    [pscustomobject]@{
        SchemaVersion='1.1'; ContractVersion='1.0'; Sample=$false; CollectedAt=$Now
        Forest=[pscustomobject]@{ Name=[string]$Forest.Name; FunctionalLevel=([string]$Forest.ForestMode -replace '^Windows','' -replace 'Forest$',''); SchemaMaster=[string]$Forest.SchemaMaster; DomainNamingMaster=[string]$Forest.DomainNamingMaster; SysvolReplication=$null; DFSRMigrationState=$null }
        Domains=@([pscustomobject]@{ Name=$Scope; NetBIOSName=[string]$Directory.NetBIOSName; SID=[string]$Directory.DomainSID; FunctionalLevel=([string]$Directory.DomainMode -replace '^Windows','' -replace 'Domain$',''); PDCEmulator=[string]$Directory.PDCEmulator; RIDMaster=[string]$Directory.RIDMaster; InfrastructureMaster=[string]$Directory.InfrastructureMaster })
        Sites=$Sites; Subnets=$ScopedSubnets; UnmappedSubnets=$UnmappedSubnets; SiteLinks=$ScopedLinks; SiteLinkCollectionState=$LinkResult.Status; DomainControllers=$DCs; Replication=$Replication.ToArray(); ReplicationFailures=$ReplicationFailures.ToArray(); Dependencies=$Dependencies.ToArray(); Security=$Security; SecurityValues=$SecurityValues; SecurityCollectionResults=$SecurityCollectionResults.ToArray(); SecurityRuntimeResults=$SecurityRuntimeResults.ToArray(); SecurityTelemetry=$SecurityTelemetry.ToArray(); PrivilegedEvidence=$Privileged; GpoIntent=@($Gpo.Data); Ports=$Ports.ToArray(); EventObservations=$EventObservations.ToArray(); EventQueries=$EventQueries.ToArray(); EventWindowHours=$EventWindowHours; BackupObservations=@()
        DNS=[pscustomobject]@{ Forwarders=@($DCs | ForEach-Object { $_.DNSForwarders } | Where-Object { $_ } | Select-Object -Unique); ForwarderReachability=@{}; ClientResolverReachability=@{}; ADIntegratedZone=$null; ReverseZone=$null; ConditionalForwarders=@($DCs | ForEach-Object { $_.ConditionalForwarders } | Where-Object { $_ } | Select-Object -Unique) }
        Time=[pscustomobject]@{ PDCSource=(@($DCs | Where-Object { $_.Name -eq [string]$Directory.PDCEmulator })[0]).TimeSource; PDCSourceReachable=$null; Hierarchy='Not independently verified' }
        Thresholds=[pscustomobject]@{ DiskFreeGBReviewBelow=10; ReplicationMaterialLatencyMinutes=120; LifecycleReviewDays=120; ReadyScoreMinimum=90; ReviewScoreMinimum=75; Owner='Provider default; review before production use' }
        CollectionResults=$Results.ToArray(); CollectionLogs=$Logs.ToArray()
    }
}
