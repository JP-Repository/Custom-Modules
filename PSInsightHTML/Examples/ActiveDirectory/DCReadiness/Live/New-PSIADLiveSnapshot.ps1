function New-PSIADLiveSnapshot {
    <# .SYNOPSIS Read-only, sequential collection for one explicitly resolved AD domain. #>
    [CmdletBinding()]
    param([string]$Domain,[switch]$IncludeRemoteChecks,[switch]$IncludePortChecks,[switch]$IncludeSecurityChecks,[switch]$IncludeDependencyDiscovery,[hashtable]$CommandAdapter)
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
    $ScopedLinks=@($LinkResult.Data | Where-Object { $LinkSites=[string](@($_.SitesIncluded) -join ','); @($SiteNames | Where-Object { $LinkSites -match [regex]::Escape($_) }).Count -gt 0 } | ForEach-Object { [pscustomobject]@{ Name=[string]$_.Name; Sites=@($_.SitesIncluded | ForEach-Object { [string]$_ }); Cost=$_.Cost; ReplicationIntervalMinutes=$_.ReplicationFrequencyInMinutes; HasSchedule=$null -ne $_.Schedule } })
    $Sites=@(foreach ($Name in $SiteNames) { [pscustomobject]@{ Name=$Name; Subnets=@($ScopedSubnets | Where-Object { [string]$_.Site -match [regex]::Escape($Name) } | ForEach-Object { $_.Name }); DomainControllers=@($RawDCs | Where-Object Site -eq $Name | ForEach-Object { $_.HostName }) } })
    $DCs=@(foreach ($Raw in $RawDCs) {
        $HostName=[string]$Raw.HostName
        $Roles=@(if ($HostName -eq [string]$Forest.SchemaMaster) { 'Schema Master' }; if ($HostName -eq [string]$Forest.DomainNamingMaster) { 'Domain Naming Master' }; if ($HostName -eq [string]$Directory.RIDMaster) { 'RID Master' }; if ($HostName -eq [string]$Directory.PDCEmulator) { 'PDC Emulator' }; if ($HostName -eq [string]$Directory.InfrastructureMaster) { 'Infrastructure Master' })
        [pscustomobject]@{
            Name=$HostName; HostName=$HostName; Domain=$Scope; Forest=[string]$Forest.Name; Site=[string]$Raw.Site
            IPv4Address=[string]$Raw.IPv4Address; OS=[string]$Raw.OperatingSystem; OperatingSystemVersion=[string]$Raw.OperatingSystemVersion; Build=[string]$Raw.OperatingSystemVersion
            Writable=-not [bool]$Raw.IsReadOnly; GlobalCatalog=[bool]$Raw.IsGlobalCatalog; FSMORoles=$Roles
            ComputerObjectDN=[string]$Raw.ComputerObjectDN; ServerObjectDN=[string]$Raw.ServerObjectDN; NTDSSettingsDN=[string]$Raw.NTDSSettingsObjectDN; InvocationId=$Raw.InvocationId; Enabled=$Raw.Enabled
            Reachable=$null; Maintenance=$false; DNSRole=$null; DNSClient=@(); DNSForwarders=@(); ADIntegratedZone=$null; ForwardZoneHealthy=$null; ReverseZoneHealthy=$null; ConditionalForwarders=@()
            TimeSource=$null; Services=@{ NTDS='Unknown'; Netlogon='Unknown'; DNS='Unknown'; DFSR='Unknown'; KDC='Unknown'; W32Time='Unknown' }
            SysvolShare=$null; NetlogonShare=$null; DiskFreeGB=$null; DiskSizeGB=$null; DiskFreePercent=$null; PendingReboot=$null; UptimeDays=$null; LastBootUpTime=$null
        }
    })
    $Replication=[System.Collections.Generic.List[object]]::new()
    foreach ($DC in $DCs) {
        $Partners=Invoke-PSIADCollector -Adapter $CommandAdapter -Id Partners -Category Replication -Scope $DC.Name -Arguments @($DC.Name) -Results $Results -Logs $Logs
        $Failures=Invoke-PSIADCollector -Adapter $CommandAdapter -Id Failures -Category Replication -Scope $DC.Name -Arguments @($DC.Name) -Results $Results -Logs $Logs
        if ($Partners.Status -eq 'Collected' -and $Partners.Data.Count -eq 0) { $Results[$Results.Count-2].Status='Partial'; $Results[$Results.Count-2].ResourceCount=0; $Results[$Results.Count-2].CoveragePercent=0; $Results[$Results.Count-2].Notes='Query succeeded; no partner metadata returned' }
        if ($Partners.Status -ne 'Collected' -or $Failures.Status -ne 'Collected') { continue }
        foreach ($Partner in $Partners.Data) {
            if ([string]$Partner.Partner -notin @($DCs | ForEach-Object { $_.Name })) {
                $Results[$Results.Count-2].Status='Partial'; $Results[$Results.Count-2].ResourceCount=0; $Results[$Results.Count-2].CoveragePercent=0; $Results[$Results.Count-2].Notes='Partner outside selected domain omitted from normalized in-scope links'
                continue
            }
            $Last=$Partner.LastReplicationSuccess
            if ($null -ne $Last -and $Last -ne [datetime]::MinValue) { $Last=[datetime]$Last } else { $Last=$null }
            $Match=@($Failures.Data | Where-Object { [string]$_.Partner -eq [string]$Partner.Partner -and [string]$_.Partition -eq [string]$Partner.Partition } | Select-Object -First 1)
            $LastError=if ($Match.Count) { [string]$Match[0].LastError } elseif ([string]$Partner.LastReplicationResult -eq '0') { 'None' } else { [string]$Partner.LastReplicationResult }
            $Replication.Add([pscustomobject]@{ Source=[string]$Partner.Partner; Destination=$DC.Name; NamingContext=[string]$Partner.Partition; CurrentFailures=if ($Match.Count) { [int]$Match[0].FailureCount } else { [int]$Partner.ConsecutiveReplicationFailures }; ConsecutiveFailures=[int]$Partner.ConsecutiveReplicationFailures; LastSuccess=$Last; LastAttempt=$Partner.LastReplicationAttempt; LastError=$LastError; LatencyMinutes=if ($Last) { [math]::Round(($Now-$Last).TotalMinutes,1) } else { $null }; Required=$true })
        }
    }
    foreach ($DC in $DCs) {
        $Remote=Invoke-PSIADCollector -Adapter $CommandAdapter -Id Remote -Category Remote -Scope $DC.Name -Arguments @($DC.Name) -Requested ([bool]$IncludeRemoteChecks) -Results $Results -Logs $Logs
        if ($Remote.Status -eq 'Collected' -and $Remote.Data.Count) {
            $Data=$Remote.Data[0]; $DC.LastBootUpTime=$Data.OS.LastBootUpTime
            if ($Data.OS.LastBootUpTime) { $DC.UptimeDays=[math]::Round(($Now-[datetime]$Data.OS.LastBootUpTime).TotalDays,1) }
            if ($Data.Disk -and $null -ne $Data.Disk.FreeSpace) { $DC.DiskFreeGB=[math]::Round([double]$Data.Disk.FreeSpace/1GB,2); $DC.DiskSizeGB=[math]::Round([double]$Data.Disk.Size/1GB,2); if ($Data.Disk.Size) { $DC.DiskFreePercent=[math]::Round(100*[double]$Data.Disk.FreeSpace/[double]$Data.Disk.Size,1) } }
            if ($Data.Services) { foreach ($Key in $Data.Services.Keys) { $DC.Services[$Key]=[string]$Data.Services[$Key] } }
            $DC.DNSClient=@($Data.NICs | ForEach-Object { $_.DNSServerSearchOrder } | Where-Object { $_ } | Select-Object -Unique)
        }
        $Share=Invoke-PSIADCollector -Adapter $CommandAdapter -Id Shares -Category Remote -Scope $DC.Name -Arguments @($DC.Name) -Requested ([bool]$IncludeRemoteChecks) -Results $Results -Logs $Logs
        if ($Share.Status -eq 'Collected') { $DC.SysvolShare='SYSVOL' -in $Share.Data; $DC.NetlogonShare='NETLOGON' -in $Share.Data }
        $Time=Invoke-PSIADCollector -Adapter $CommandAdapter -Id Time -Category Remote -Scope $DC.Name -Arguments @($DC.Name) -Requested ([bool]$IncludeRemoteChecks) -Results $Results -Logs $Logs
        if ($Time.Status -eq 'Collected' -and $Time.Data.Count) { $DC.TimeSource=[string]$Time.Data[0] }
        $DNS=Invoke-PSIADCollector -Adapter $CommandAdapter -Id DNS -Category DNS -Scope $DC.Name -Arguments @($DC.Name) -Requested ([bool]$IncludeRemoteChecks) -Results $Results -Logs $Logs
        if ($DNS.Status -eq 'Collected' -and $DNS.Data.Count) { $DC.DNSRole=$true; $DC.DNSForwarders=@($DNS.Data[0].Forwarders | ForEach-Object { [string]$_ }); $DC.ConditionalForwarders=@($DNS.Data[0].Conditional | ForEach-Object { [string]$_.Name }); $DC.ADIntegratedZone=@($DNS.Data[0].Zones | Where-Object IsDsIntegrated).Count -gt 0 }
    }
    $Ports=[System.Collections.Generic.List[object]]::new()
    foreach ($DC in $DCs) {
        if (-not $IncludePortChecks) { $null=Invoke-PSIADCollector -Adapter $CommandAdapter -Id Port -Category Network -Scope $DC.Name -Arguments @($DC.Name,389) -Requested $false -Results $Results -Logs $Logs; continue }
        foreach ($Port in @(53,88,135,389,445,464,636,3268,3269,5722)) {
            $Probe=Invoke-PSIADCollector -Adapter $CommandAdapter -Id Port -Category Network -Scope $DC.Name -Arguments @($DC.Name,$Port) -Results $Results -Logs $Logs
            $Ports.Add([pscustomobject]@{ Port=$Port; Role='Collector host to DC TCP'; Source='Assessment host'; Destination=$DC.Name; Result=if ($Probe.Status -eq 'Collected') { if ([bool]$Probe.Data[0]) { 'Reachable' } else { 'Failed' } } else { 'NotTested' } })
        }
    }
    $Dependencies=[System.Collections.Generic.List[object]]::new()
    $Discovered=Invoke-PSIADCollector -Adapter $CommandAdapter -Id Dependencies -Category Dependencies -Scope $Scope -Arguments @($Scope) -Requested ([bool]$IncludeDependencyDiscovery) -Results $Results -Logs $Logs
    if ($Discovered.Status -eq 'Collected' -and $Discovered.Data.Count) {
        foreach ($Exchange in @($Discovered.Data[0].Exchange)) { $Dependencies.Add([pscustomobject]@{ Id="exchange-$($Exchange.Name)"; Name=[string]$Exchange.Name; Type='Exchange'; Version='Unknown'; CU=$null; Confidence='Low'; Status='Review'; Detail="Build $($Exchange.AdminDisplayVersion); exact CU not established" }) }
        foreach ($CA in @($Discovered.Data[0].PKI)) { $Dependencies.Add([pscustomobject]@{ Id="pki-$($CA.Name)"; Name=[string]$CA.Name; Type='PKI'; Version='Unknown'; CU=$null; Confidence='Medium'; Status='NotTested'; Detail='Enterprise CA directory object; service health not tested' }) }
        $Results[$Results.Count-1].Status='Partial'; $Results[$Results.Count-1].ResourceCount=0; $Results[$Results.Count-1].CoveragePercent=0; $Results[$Results.Count-1].Notes='Only Exchange and Enterprise CA directory discovery; application dependencies require provider input'
        if (@($Discovered.Data[0].Errors).Count) { $Results[$Results.Count-1].Notes+='; '+(@($Discovered.Data[0].Errors) -join '; ') }
    }
    foreach ($Item in @(@('Identity sync','Identity sync'),@('AD FS','Federation'),@('Application directory dependencies','LDAP/LDAPS'),@('Hard-coded DC targets','Hard-coded DC'),@('Backup and monitoring','Backup'))) { $Dependencies.Add([pscustomobject]@{ Id=($Item[1] -replace '\W','-').ToLowerInvariant(); Name=$Item[0]; Type=$Item[1]; Version='Unknown'; CU=$null; Confidence='None'; Status='NotTested'; Detail='Provider input required; not inferred from directory inventory' }) }
    $Security=@{}; $SecurityValues=@{}
    foreach ($Rule in (Import-PowerShellDataFile (Join-Path $PSScriptRoot '../Rules/SecurityBaseline.psd1')).Rules) { $Security[$Rule.Id]='NotTested'; $SecurityValues[$Rule.Id]='Effective setting not tested' }
    foreach ($DC in $DCs) {
        $Observed=Invoke-PSIADCollector -Adapter $CommandAdapter -Id Security -Category Security -Scope $DC.Name -Arguments @($DC.Name) -Requested ([bool]$IncludeSecurityChecks) -Results $Results -Logs $Logs
        if ($Observed.Status -eq 'Collected' -and $Observed.Data.Count -gt 0 -and $Observed.Data[0] -is [hashtable]) {
            foreach ($Key in $Observed.Data[0].Keys) { if ($SecurityValues.ContainsKey($Key)) { $SecurityValues[$Key]="$($DC.Name): $($Observed.Data[0][$Key])" } }
            $Count=@($Observed.Data[0].Keys | Where-Object { $SecurityValues.ContainsKey($_) }).Count
            $Results[$Results.Count-1].ExpectedCount=17; $Results[$Results.Count-1].ResourceCount=$Count
            $Results[$Results.Count-1].CoveragePercent=[math]::Round(100*$Count/17,1)
            if ($Count -lt 17) { $Results[$Results.Count-1].Status='Partial'; $Results[$Results.Count-1].Notes='Selected registry values observed; effective policy and other security topics remain unverified' }
        }
    }
    foreach ($Gap in @('DFSRMigration','PendingReboot','ResolverReachability','ZoneHealth','ForwarderReachability','PDCSourceReachability','ProviderDependencyInput')) {
        $Stamp=Get-Date
        $Results.Add([pscustomobject]@{ CollectorId=$Gap; Name=$Gap; Category='Evidence gap'; Scope=$Scope; Status='NotTested'; StartedAt=$Stamp; CompletedAt=$Stamp; DurationMs=0; Requested=$true; Succeeded=$false; ResourceCount=0; ExpectedCount=1; CoveragePercent=0; ErrorCode=''; ErrorMessage=''; Notes='Requires supported read-only source or provider-supplied evidence' })
    }
    [pscustomobject]@{
        SchemaVersion='1.1'; ContractVersion='1.0'; Sample=$false; CollectedAt=$Now
        Forest=[pscustomobject]@{ Name=[string]$Forest.Name; FunctionalLevel=([string]$Forest.ForestMode -replace '^Windows','' -replace 'Forest$',''); SchemaMaster=[string]$Forest.SchemaMaster; DomainNamingMaster=[string]$Forest.DomainNamingMaster; SysvolReplication=$null; DFSRMigrationState=$null }
        Domains=@([pscustomobject]@{ Name=$Scope; NetBIOSName=[string]$Directory.NetBIOSName; SID=[string]$Directory.DomainSID; FunctionalLevel=([string]$Directory.DomainMode -replace '^Windows','' -replace 'Domain$',''); PDCEmulator=[string]$Directory.PDCEmulator; RIDMaster=[string]$Directory.RIDMaster; InfrastructureMaster=[string]$Directory.InfrastructureMaster })
        Sites=$Sites; Subnets=$ScopedSubnets; SiteLinks=$ScopedLinks; DomainControllers=$DCs; Replication=$Replication.ToArray(); Dependencies=$Dependencies.ToArray(); Security=$Security; SecurityValues=$SecurityValues; Ports=$Ports.ToArray()
        DNS=[pscustomobject]@{ Forwarders=@($DCs | ForEach-Object { $_.DNSForwarders } | Where-Object { $_ } | Select-Object -Unique); ForwarderReachability=@{}; ClientResolverReachability=@{}; ADIntegratedZone=$null; ReverseZone=$null; ConditionalForwarders=@($DCs | ForEach-Object { $_.ConditionalForwarders } | Where-Object { $_ } | Select-Object -Unique) }
        Time=[pscustomobject]@{ PDCSource=(@($DCs | Where-Object { $_.Name -eq [string]$Directory.PDCEmulator })[0]).TimeSource; PDCSourceReachable=$null; Hierarchy='Not independently verified' }
        Thresholds=[pscustomobject]@{ DiskFreeGBReviewBelow=10; ReplicationMaterialLatencyMinutes=120; LifecycleReviewDays=120; ReadyScoreMinimum=90; ReviewScoreMinimum=75; Owner='Provider default; review before production use' }
        CollectionResults=$Results.ToArray(); CollectionLogs=$Logs.ToArray()
    }
}
