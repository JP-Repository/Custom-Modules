function Get-PSIADDCReadinessOutcome {
    [CmdletBinding()]
    param([pscustomobject] $Inventory, [hashtable] $Rule, [string] $TargetOS)
    $RuleCoverage=Get-PSIADRuleCoverage -Inventory $Inventory -RuleId ([string]$Rule.Id)
    if (-not $RuleCoverage.Complete) {
        return [pscustomobject]@{ Status='NotTested'; Observed=$RuleCoverage.Reason; Expected='Complete, supported collection evidence'; Action='Review collector coverage and permissions before interpreting this check.' }
    }
    $Status='Ready'; $Observed='Observed in normalized inventory'; $Expected='Ready for the selected target'
    $Action='Retain this observation and validate it during change planning.'
    $DCs=@($Inventory.DomainControllers)
    $ObservedDCs=if ($Inventory.Source -eq 'Fictional sample') { @($DCs | Where-Object Reachable) } else { $DCs }
    switch ($Rule.Id) {
        'functional-level' {
            $Levels=@([string] $Inventory.Forest.FunctionalLevel)+@($Inventory.Domains | ForEach-Object { [string] $_.FunctionalLevel })
            $Observed="Forest $($Inventory.Forest.FunctionalLevel); domains $(@($Inventory.Domains | ForEach-Object { $_.FunctionalLevel }) -join ', ')"
            $Expected=if ($TargetOS -eq '2025') { '2016 or later forest and domain functional levels' } else { 'Supported by the published AD DS interoperability matrix' }
            if ($TargetOS -eq '2025' -and @($Levels | Where-Object { $_ -notin @('2016','2025') }).Count -gt 0) { $Status='Blocked' }
            elseif ($TargetOS -eq '2022' -and @($Levels | Where-Object { $_ -eq '2025' }).Count -gt 0) { $Status='Blocked' }
            elseif ($TargetOS -eq '2022' -and @($Levels | Where-Object { $_ -notin @('2012R2','2016') }).Count -gt 0) { $Status='Review' }
            $Action='Check the Microsoft interoperability matrix before planning a functional-level change.'
        }
        'dc-inventory' {
            $Unavailable=@($DCs | Where-Object { -not $_.Reachable })
            $Pending=@($DCs | Where-Object { $_.PendingReboot })
            $Expired=@($DCs | Where-Object { $_.OS -eq 'Windows Server 2016' -and $Inventory.CollectedAt.Date -gt [datetime]'2027-01-12' })
            $NearSupportEnd=@($DCs | Where-Object { $_.OS -eq 'Windows Server 2016' -and (([datetime]'2027-01-12') - $Inventory.CollectedAt).TotalDays -le $Inventory.Thresholds.LifecycleReviewDays })
            $Observed="$($DCs.Count) DCs, $($Unavailable.Count) unavailable, $($Pending.Count) pending reboot; $($NearSupportEnd.Count) Server 2016 DCs near 2027-01-12 extended support end, $($Expired.Count) past end"
            if ($Expired.Count -gt 0) { $Status='Blocked' }
            elseif ($Unavailable.Count -gt 0 -or $Pending.Count -gt 0 -or $NearSupportEnd.Count -gt 0) { $Status='Review' }
            $Action='Confirm maintenance and reboot plans; review source OS support dates and exact builds before transition.'
        }
        'fsmo-gc' {
            $Holders=@($Inventory.Forest.SchemaMaster,$Inventory.Forest.DomainNamingMaster,$Inventory.Domains[0].RIDMaster,$Inventory.Domains[0].PDCEmulator,$Inventory.Domains[0].InfrastructureMaster)
            $Missing=@($Holders | Where-Object { $_ -notin @($DCs | ForEach-Object { $_.Name }) })
            $Observed="Five FSMO assignments; $(@($DCs | Where-Object { $_.GlobalCatalog }).Count) Global Catalog DCs"
            if ($Missing.Count -gt 0 -or @($DCs | Where-Object { $_.GlobalCatalog }).Count -eq 0) { $Status='Blocked' }
            $Action='Validate all role holders and GC placement before transition.'
        }
        'sites-subnets' {
            $Unmapped=@($Inventory.Sites | Where-Object { @($_.Subnets).Count -eq 0 })
            $Observed="$(@($Inventory.Sites).Count) sites; $($Unmapped.Count) without mapped subnets"
            if ($Unmapped.Count -gt 0) { $Status='Review' }
            $Action='Confirm site, subnet and DC placement with the network owner.'
        }
        'replication' {
            $Material=@($Inventory.Replication | Where-Object { $_.Required -and (($_.CurrentFailures -gt 0 -and $_.ConsecutiveFailures -ge 2) -or ($Inventory.CollectedAt - $_.LastSuccess).TotalMinutes -gt $Inventory.Thresholds.ReplicationMaterialLatencyMinutes) })
            $Transient=@($Inventory.Replication | Where-Object { $_.LastError -ne 'None' -and $_.CurrentFailures -eq 0 })
            $Observed="$($Material.Count) material current failures; $($Transient.Count) recovered historical errors; $(@($Inventory.Replication).Count) links"
            if ($Material.Count -gt 0) { $Status='Blocked' } elseif ($Transient.Count -gt 0) { $Status='Review' }
            $Expected="No material current failures; sampled latency below $($Inventory.Thresholds.ReplicationMaterialLatencyMinutes) minutes (fictional profile)"
            $Action='Review current partner state, last success, consecutive failures, RPC errors and naming contexts.'
        }
        'replication-coverage' {
            $Observed="$(@($Inventory.Replication | Select-Object -ExpandProperty NamingContext -Unique).Count) naming contexts; $(@($Inventory.Replication).Count) sampled links"
            if (@($Inventory.Replication).Count -eq 0) { $Status='NotTested' }
            $Action='Confirm all required naming contexts and topology-specific partners in a live assessment.'
        }
        'sysvol' {
            $Missing=@($ObservedDCs | Where-Object { -not $_.SysvolShare -or -not $_.NetlogonShare -or $_.Services.DFSR -ne 'Running' })
            $Observed="$($Inventory.Forest.SysvolReplication); DFSR migration $($Inventory.Forest.DFSRMigrationState); $($Missing.Count) active share/service gaps"
            if ($Inventory.Forest.SysvolReplication -ne 'DFSR' -or $Inventory.Forest.DFSRMigrationState -ne 'Eliminated' -or $Missing.Count -gt 0) { $Status='Blocked' }
            $Action='Confirm DFSR migration, SYSVOL replication and SYSVOL/NETLOGON shares.'
        }
        'dns-client' {
            $Missing=@($ObservedDCs | Where-Object { @($_.DNSClient).Count -lt 2 })
            $Unreachable=@($ObservedDCs | ForEach-Object { $_.DNSClient } | Where-Object { $Inventory.DNS.ClientResolverReachability[$_] -eq $false } | Sort-Object -Unique)
            $Unknown=@($ObservedDCs | ForEach-Object { $_.DNSClient } | Where-Object { $null -eq $Inventory.DNS.ClientResolverReachability[$_] } | Sort-Object -Unique)
            $Primaries=@($ObservedDCs | ForEach-Object { @($_.DNSClient)[0] })
            $Concentrated=@($Primaries | Select-Object -Unique).Count -eq 1 -and $Primaries.Count -gt 1
            $Observed="$($Missing.Count) without secondary; $($Unreachable.Count) unreachable and $($Unknown.Count) untested resolvers; primary concentration $Concentrated"
            if ($Missing.Count -gt 0 -or $Unreachable.Count -gt 0 -or $Unknown.Count -gt 0 -or $Concentrated) { $Status='Review' }
            $Action='Review resolver reachability and resilience; self-DNS alone is not invalid.'
        }
        'dns-zones' {
            $Poor=@($ObservedDCs | Where-Object { -not $_.ADIntegratedZone -or -not $_.ForwardZoneHealthy -or -not $_.ReverseZoneHealthy })
            $Observed="$($Poor.Count) active DC zone concerns; conditional forwarders $(@($Inventory.DNS.ConditionalForwarders) -join ', ')"
            if ($Poor.Count -gt 0) { $Status='Review' }
            $Action='Validate AD-integrated forward/reverse zones and conditional forwarders.'
        }
        'dns-forwarders' {
            $Bad=@($Inventory.DNS.Forwarders | Where-Object { $Inventory.DNS.ForwarderReachability[$_] -eq $false })
            $Unknown=@($Inventory.DNS.Forwarders | Where-Object { $null -eq $Inventory.DNS.ForwarderReachability[$_] })
            $Observed="$($Bad.Count) unreachable and $($Unknown.Count) untested forwarders"
            if ($Bad.Count -gt 0 -or $Unknown.Count -gt 0) { $Status='Review' }
            $Action='Confirm upstream resolver reachability and redundancy.'
        }
        'time' {
            $Local=@($ObservedDCs | Where-Object { $_.TimeSource -match 'Local CMOS|Free-running' })
            $Observed="PDC source $($Inventory.Time.PDCSource), reachable $($Inventory.Time.PDCSourceReachable); $($Local.Count) local-clock DCs"
            if (-not $Inventory.Time.PDCSourceReachable -or $Local.Count -gt 0) { $Status='Review' }
            $Action='Confirm PDC upstream and domain hierarchy using time-source evidence.'
        }
        'services' {
            $ServiceIssues=@(foreach ($DC in $ObservedDCs) { foreach ($Name in @('NTDS','Netlogon','DFSR','KDC','W32Time')) { if ($DC.Services[$Name] -ne 'Running') { "$($DC.Name):$Name" } }; if ($DC.DNSRole -and $DC.Services.DNS -ne 'Running') { "$($DC.Name):DNS" } })
            $Observed="$($ServiceIssues.Count) core service observations need review; service state alone is not complete health proof"
            if ($ServiceIssues.Count -gt 0) { $Status='Review' }
            $Action='Review NTDS, Netlogon, DNS by role, DFSR, KDC and W32Time alongside functional tests.'
        }
        'disk' {
            $Low=@($ObservedDCs | Where-Object { $_.DiskFreeGB -lt $Inventory.Thresholds.DiskFreeGBReviewBelow })
            $Observed="$($Low.Count) active DCs below $($Inventory.Thresholds.DiskFreeGBReviewBelow) GB free"
            $Expected="At least $($Inventory.Thresholds.DiskFreeGBReviewBelow) GB free (fictional organization threshold)"
            if ($Low.Count -gt 0) { $Status='Review' }
            $Action='Review absolute free GB and growth; percentage alone is insufficient.'
        }
        'ports' {
            $Failed=@($Inventory.Ports | Where-Object { $_.Role -ne 'Not tested' -and $_.Result -eq 'Failed' })
            $Untested=@($Inventory.Ports | Where-Object { $_.Result -eq 'NotTested' })
            $Observed="$($Failed.Count) tested path failures; $($Untested.Count) topology-specific paths untested"
            if ($Failed.Count -gt 0 -or $Untested.Count -gt 0) { $Status='Review' }
            $Action='Test relevant ports by role and site topology; include dynamic RPC where testable.'
        }
        'exchange' {
            $Exchange=@($Inventory.Dependencies | Where-Object { $_.Type -eq 'Exchange' })
            if ($Exchange.Count -eq 0) { $Status='NotApplicable'; $Observed='No Exchange deployment reported' }
            else {
                $Item=$Exchange[0]; $Observed="$($Item.Name), CU $($Item.CU), confidence $($Item.Confidence)"
                if ($Item.Confidence -ne 'High' -or ($null -eq $Item.CU -and $Item.Version -ne 'SE')) { $Status='Review' }
                elseif ($Item.Version -eq 'SE') { $Status='Ready' }
                elseif ($TargetOS -eq '2025') {
                    if ($Item.Version -eq '2016' -or ($Item.Version -eq '2019' -and [int] $Item.CU -lt 14)) { $Status='Blocked' } else { $Status='Review' }
                }
                elseif (($Item.Version -eq '2019' -and [int] $Item.CU -lt 12) -or ($Item.Version -eq '2016' -and [int] $Item.CU -lt 23)) { $Status='Blocked' }
                else { $Status='Review' }
            }
            $Expected=if ($TargetOS -eq '2025') { 'Exchange SE or 2019 CU14+; Exchange 2016 unsupported with 2025 AD servers' } else { 'Exchange SE, 2019 CU12+, or 2016 CU23+ for 2022 AD server compatibility' }
            $Action='Confirm exact CU/build and lifecycle. For Exchange PrepareAD with a 2025 Schema Master, check its November 2025 or later cumulative update.'
        }
        'dependencies' {
            $Pending=@($Inventory.Dependencies | Where-Object { $_.Status -eq 'NotTested' })
            $Review=@($Inventory.Dependencies | Where-Object { $_.Status -eq 'Review' })
            $Observed="$($Pending.Count) untested; $($Review.Count) review dependencies"
            if ($Pending.Count -gt 0) { $Status='NotTested' } elseif ($Review.Count -gt 0) { $Status='Review' }
            $Action='Request owner validation for identity sync, AD FS, PKI, LDAP clients, fixed DC targets, NPS, backup and monitoring.'
        }
        default {
            if ($Rule.Id -match '^security-(.+)$') {
                $Key=$Matches[1]; $Status=[string] $Inventory.Security[$Key]
                if ($Status -notin @('Ready','Review','Blocked','NotTested','NotApplicable','Unknown')) { $Status='Unknown' }
                $Observed=[string] $Inventory.SecurityValues[$Key]
                if (-not $Observed) { $Observed='No effective value supplied'; $Status='NotTested' }
                $Expected=[string] $Rule.Recommended
                $Action='Review the effective policy with security and application owners before enforcement.'
            }
            elseif ($Rule.Id -match '^postbuild-') {
                $Status='NotTested'; $Observed='No target DC has been built'; $Expected=[string] $Rule.Expected
                $Action='Perform this validation after promotion; no deployment action is executed.'
            }
            else { throw "Unknown DC readiness rule '$($Rule.Id)'." }
        }
    }
    [pscustomobject]@{ Status=$Status; Observed=$Observed; Expected=$Expected; Action=$Action }
}
