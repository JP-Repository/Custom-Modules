function Get-PSIADHealthRuleOutcome {
    <# .SYNOPSIS Interpret existing normalized Health observations; never collects data. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable] $Rule,
        [Parameter(Mandatory)][object[]] $Observations,
        [Parameter(Mandatory)][hashtable] $Thresholds,
        [Parameter(Mandatory)][datetime] $AsOf,
        [AllowNull()][pscustomobject] $DC
    )
    $Id=[string]$Rule.Id
    $Scoped=if ($Rule.Scope -eq 'Domain') { @($Observations | Where-Object { $_.DC -eq $_.Domain }) } else { @($Observations | Where-Object { $null -ne $DC -and $_.DC -eq $DC.Name }) }
    function Pick([string]$Type,[string]$Name='') {
        @($Scoped | Where-Object { $_.Type -eq $Type -and (-not $Name -or ($_.Value -and [string]$_.Value.Name -eq $Name) -or ($_.Value -and [string]$_.Value.Query -eq $Name)) })
    }
    $Items=[System.Collections.Generic.List[object]]::new()
    foreach ($Requirement in @($Rule.EvidenceRequirements)) {
        $Parts=[string]$Requirement -split ':',2
        foreach ($Item in @(Pick $Parts[0] $(if ($Parts.Count -gt 1) { $Parts[1] } else { '' }))) { $Items.Add($Item) }
    }
    $Relevant=$Items.ToArray()
    $State='NotTested'; $Observed='Required evidence was not collected.'; $Expected='Collected, sufficiently complete evidence.'
    $Applicable=$true
    if ($null -ne $DC) {
        if ($Id -in @('sysvol-share','netlogon-share','dfsr-service','dfsr-folder') -and $DC.Writable -eq $false) { $Applicable=$false }
        if ($Id -in @('dns-service','dns-zones','dns-forwarders') -and $DC.DNSRole -eq $false) { $Applicable=$false }
        if ($Id -eq 'pdc-source') {
            $Source=@($Scoped | Where-Object Type -eq TimeSource)
            if ($Source.Count -and $Source[0].Value -and $Source[0].Value.PDC -eq $false) { $Applicable=$false }
        }
    }
    if (-not $Applicable) { return [pscustomobject]@{ Status='NotApplicable'; Observed='Role or DC type does not require this check.'; Expected='Not applicable'; Observations=$Relevant } }
    $Usable=@($Relevant | Where-Object { $_.CollectionState -eq 'Collected' -and $null -ne $_.Value })
    if ($Usable.Count -eq 0) {
        $States=@($Relevant | ForEach-Object { $_.CollectionState } | Sort-Object -Unique)
        if ($States.Count) { $Observed='Collection state: ' + ($States -join ', ') + '. No sufficient fact was observed.' }
        return [pscustomobject]@{ Status=$State; Observed=$Observed; Expected=$Expected; Observations=$Relevant }
    }
    $First=$Usable[0].Value
    switch ([string]$Rule.Evaluation) {
        ADRole {
            $Installed=@($First | Where-Object { $_.Name -eq 'AD-Domain-Services' -and $_.Installed -eq $true })
            $Observed="AD DS role observed: $($Installed.Count -gt 0)"; $Expected='AD DS role observed'; $State=if ($Installed.Count) { 'Ready' } else { 'Review' }
        }
        Reachability {
            if ($null -ne $First.Reachable) { $Observed="Reachable: $($First.Reachable)"; $Expected='DC reachable'; $State=if ($First.Reachable) { 'Ready' } else { 'Blocked' } }
        }
        Service {
            $Matching=@($Usable | Where-Object { $_.Value.Name -eq $Id -or ($Id -eq 'dfsr-service' -and $_.Value.Name -eq 'DFSR') -or ($Id -eq 'dns-service' -and $_.Value.Name -eq 'DNS') -or ($Id -eq 'w32time-service' -and $_.Value.Name -eq 'W32Time') })
            if ($Matching.Count) {
                $Value=$Matching[0].Value; $Observed="$($Value.Name): $($Value.ObservedState)"; $Expected='Running'
                if ($Value.ObservedState -and $Value.ObservedState -ne 'Unknown') { $State=if ($Value.ObservedState -in @('Running','Started')) { 'Ready' } elseif ($Rule.Critical) { 'Blocked' } else { 'Review' } }
            }
        }
        Share {
            if ($null -ne $First.Present) { $Observed="Share present: $($First.Present)"; $Expected='Present'; $State=if ($First.Present) { 'Ready' } else { 'Blocked' } }
        }
        Replication {
            $PartnerQuery=@($Usable | Where-Object { $_.Type -eq 'ReplicationQuery' -and $_.Value.Query -eq 'Partners' })
            $FailureQuery=@($Usable | Where-Object { $_.Type -eq 'ReplicationQuery' -and $_.Value.Query -eq 'Failures' })
            if ($PartnerQuery.Count -and $FailureQuery.Count) {
                $Links=@($Usable | Where-Object Type -eq 'Replication')
                $Failures=@($Usable | Where-Object Type -eq 'ReplicationFailure')
                $State='Ready'; $Expected='No current failures; last successful inbound replication within configured window.'
                $Observed="$($Links.Count) inbound links; $($Failures.Count) failure records."
                if ($Links.Count -eq 0) { $State='Review'; $Observed+=' No inbound partner records were returned.' }
                foreach ($Link in $Links) {
                    $Value=$Link.Value; $Current=if ($null -ne $Value.CurrentFailures) { [int]$Value.CurrentFailures } else { 0 }
                    $Consecutive=if ($null -ne $Value.ConsecutiveFailures) { [int]$Value.ConsecutiveFailures } else { 0 }
                    if ($Current -gt 0 -or $Consecutive -gt 0) { $State='Review'; $Observed+=" $($Value.Source): $Current current, $Consecutive consecutive failures; error $($Value.LastError)." }
                    if ($Consecutive -ge [int]$Thresholds.ReplicationCriticalConsecutiveFailures -or ($null -ne $Value.LastSuccess -and $AsOf.Subtract([datetime]$Value.LastSuccess).TotalMinutes -gt [double]$Thresholds.ReplicationCriticalStaleMinutes)) { $State='Blocked' }
                }
                if ($Failures.Count -and $State -eq 'Ready') { $State='Review'; $Observed+=' Failure records require validation.' }
            } else { $Observed='Partner and failure queries must both complete before replication can be assessed.' }
        }
        DFSRMigration {
            if ($First) { $Observed="Migration state: $First"; $Expected='Eliminated'; $State=if ([string]$First -eq 'Eliminated') { 'Ready' } else { 'Review' } }
        }
        DNSClient {
            $Addresses=@($First | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
            $Observed="$($Addresses.Count) configured resolver addresses."; $Expected='At least one configured resolver'; $State=if ($Addresses.Count) { 'Ready' } else { 'Review' }
        }
        DNSZones {
            if ($null -ne $First.ADIntegratedObserved) { $Observed="AD-integrated observed: $($First.ADIntegratedObserved); reverse zone healthy: $($First.ReverseZone)"; $Expected='Observed AD-integrated zone'; $State=if ($First.ADIntegratedObserved -and $First.ReverseZone -ne $false) { 'Ready' } else { 'Review' } }
        }
        DNSForwarders {
            $Values=@($First | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }); $Observed="$($Values.Count) forwarder addresses returned."; $Expected='Review configured forwarding policy'; $State='Ready'
        }
        Probe {
            if ($First -is [bool]) { $Observed="Reachable: $First"; $Expected='Reachable'; $State=if ($First) { 'Ready' } else { 'Review' } }
            elseif ($First -is [System.Collections.IDictionary] -and $First.Count) { $Bad=@($First.Keys | Where-Object { $First[$_] -ne $true }); $Observed="$($Bad.Count) failed of $($First.Count) tested endpoints"; $Expected='Tested endpoints reachable'; $State=if ($Bad.Count) { 'Review' } else { 'Ready' } }
        }
        TimeSource {
            if (-not [string]::IsNullOrWhiteSpace([string]$First.ObservedSource)) { $Observed="Observed source: $($First.ObservedSource)"; $Expected='A valid observed source; independent reachability and offset assessed separately.'; $State=if ($First.ObservedSource -match '(?i)local cmos|free.running') { 'Review' } else { 'Ready' } }
        }
        PDCSource {
            if (-not [string]::IsNullOrWhiteSpace([string]$First.ConfiguredSource)) { $Observed="Configured PDC source: $($First.ConfiguredSource)"; $Expected='Configured source observed; reachability assessed separately'; $State=if ($First.ConfiguredSource -match '(?i)local cmos|free.running') { 'Review' } else { 'Ready' } }
        }
        TimeOffset {
            if ($null -ne $First.OffsetMilliseconds) { $Observed="Measured offset: $($First.OffsetMilliseconds) ms"; $Expected="Absolute offset < $($Thresholds.TimeOffsetReviewMilliseconds) ms"; $State=if ([math]::Abs([double]$First.OffsetMilliseconds) -ge [double]$Thresholds.TimeOffsetReviewMilliseconds) { 'Review' } else { 'Ready' } } else { $Observed='No reliable measured offset available.' }
        }
        Disk {
            if ($null -ne $First.FreeGB) { $Observed="$($First.Drive): $($First.FreeGB) GB free"; $Expected=">= $($Thresholds.DiskReviewFreeGB) GB free"; $State=if ([double]$First.FreeGB -lt [double]$Thresholds.DiskCriticalFreeGB) { 'Blocked' } elseif ([double]$First.FreeGB -lt [double]$Thresholds.DiskReviewFreeGB) { 'Review' } else { 'Ready' } }
        }
        Memory {
            if ($null -ne $First.UsedPercent) { $Observed="$($First.UsedPercent)% used (point-in-time)"; $Expected="< $($Thresholds.MemoryReviewPercent)%"; $State=if ([double]$First.UsedPercent -ge [double]$Thresholds.MemoryReviewPercent) { 'Review' } else { 'Ready' } }
        }
        CPU {
            if ($First -is [ValueType]) { $Observed="$First% used (point-in-time)"; $Expected="< $($Thresholds.CpuReviewPercent)%"; $State=if ([double]$First -ge [double]$Thresholds.CpuReviewPercent) { 'Review' } else { 'Ready' } }
        }
        Uptime {
            if ($First -is [ValueType]) { $Observed="$First days since boot"; $Expected="< $($Thresholds.UptimeReviewDays) days for review threshold"; $State=if ([double]$First -ge [double]$Thresholds.UptimeReviewDays) { 'Review' } else { 'Ready' } }
        }
        Site {
            $Observed="Site: $($First.Site)"; $Expected='Assigned site'; $State=if ([string]::IsNullOrWhiteSpace([string]$First.Site)) { 'Review' } else { 'Ready' }
        }
        UnmappedSubnets {
            $Values=@($First | Where-Object { $null -ne $_ -and $_.Name }); $Observed="$($Values.Count) unmapped subnets"; $Expected='No observed unmapped subnets'; $State=if ($Values.Count) { 'Review' } else { 'Ready' }
        }
        SiteLinks {
            $Values=@($First | Where-Object { $null -ne $_ -and $_.Name }); $Observed="$($Values.Count) site links returned by completed query"; $Expected='Review against site design'; $State='Ready'
        }
        Events {
            $Queries=@($Usable | Where-Object Type -eq 'EventQuery')
            $Incomplete=@($Relevant | Where-Object { $_.Type -eq 'EventQuery' -and $_.CollectionState -ne 'Collected' })
            if ($Incomplete.Count) { $Observed="$($Incomplete.Count) event queries were incomplete or failed; no clean-event conclusion is possible." }
            elseif ($Queries.Count) {
                $Hits=@($Scoped | Where-Object { $_.Type -eq 'Event' -and $_.CollectionState -eq 'Collected' -and $_.Value.Level -in @('Error','Critical') -and $_.Value.EvidenceCategory -in @('Directory Services','Replication','DFSR','DNS','Netlogon','Time','System') })
                $Observed="$($Hits.Count) selected severe operational events in $($Queries[0].Value.WindowHours) hour query window across completed query scope"; $Expected='No selected severe operational events in the completed bounded query scope'; $State=if ($Hits.Count) { 'Review' } else { 'Ready' }
            }
        }
        Backup {
            if ($Usable[0].Confidence -in @('High','Medium','Sample') -and $null -ne $First.LastSuccessfulSystemStateBackup) {
                $Age=$AsOf.Subtract([datetime]$First.LastSuccessfulSystemStateBackup).TotalDays
                $Observed="Last successful system-state backup: $([math]::Round($Age,1)) days ago ($($First.Source))"; $Expected="<= $($Thresholds.BackupHealthyDays) day"
                $State=if ($Age -gt [double]$Thresholds.BackupCriticalDays) { 'Blocked' } elseif ($Age -gt [double]$Thresholds.BackupHealthyDays) { 'Review' } else { 'Ready' }
            } else { $Observed='Backup provider input or confidence is insufficient.' }
        }
        Ports {
            $Tested=@($Usable | Where-Object { $_.Value.Result -in @('Open','Closed','Succeeded','Failed','Reachable','Unreachable') })
            if ($Tested.Count) { $Failed=@($Tested | Where-Object { $_.Value.Result -in @('Closed','Failed','Unreachable') }); $Observed="$($Failed.Count) failed of $($Tested.Count) tested ports"; $Expected='Observed tested ports reachable'; $State=if ($Failed.Count) { 'Review' } else { 'Ready' } }
        }
        PendingReboot {
            if ($First -is [bool]) { $Observed="Pending reboot: $First"; $Expected='No pending reboot'; $State=if ($First) { 'Review' } else { 'Ready' } }
        }
    }
    [pscustomobject]@{ Status=$State; Observed=$Observed; Expected=$Expected; Observations=$Relevant }
}
