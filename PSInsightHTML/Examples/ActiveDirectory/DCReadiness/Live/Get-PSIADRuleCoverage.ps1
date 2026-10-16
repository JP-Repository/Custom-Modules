function Get-PSIADRuleCoverage {
    [CmdletBinding()]
    param([pscustomobject]$Inventory,[string]$RuleId)
    if ($Inventory.Source -eq 'Fictional sample') { return [pscustomobject]@{ Complete=$true; Reason='' } }
    $Required=switch -Regex ($RuleId) {
        '^functional-level$' { @('Domain','Forest'); break }
        '^dc-inventory$' { @('DCs','PendingReboot'); break }
        '^fsmo-gc$' { @('Domain','Forest','DCs'); break }
        '^sites-subnets$' { @('Sites','Subnets'); break }
        '^replication(-coverage)?$' { @('Partners','Failures'); break }
        '^sysvol$' { @('Shares','Remote','DFSRMigration'); break }
        '^dns-client$' { @('Remote','ResolverReachability'); break }
        '^dns-zones$' { @('DNS','ZoneHealth'); break }
        '^dns-forwarders$' { @('DNS','ForwarderReachability'); break }
        '^time$' { @('Time','PDCSourceReachability'); break }
        '^services$' { @('Remote'); break }
        '^disk$' { @('Remote'); break }
        '^ports$' { @('Port'); break }
        '^exchange$' { @('Dependencies'); break }
        '^dependencies$' { @('Dependencies','ProviderDependencyInput'); break }
        '^security-' { @('Security'); break }
        '^postbuild-' { @('PostBuild'); break }
        default { @('UnknownCollector') }
    }
    $Missing=@(foreach ($Name in $Required) {
        $Records=@($Inventory.CollectionResults | Where-Object CollectorId -eq $Name)
        if ($Name -eq 'Dependencies' -and $RuleId -eq 'exchange' -and @($Inventory.Dependencies | Where-Object Type -eq 'Exchange').Count -gt 0 -and @($Records | Where-Object Status -eq 'Partial').Count -gt 0) { continue }
        if ($Records.Count -eq 0 -or @($Records | Where-Object Status -ne 'Collected').Count -gt 0) { $Name }
    })
    if ($RuleId -eq 'disk' -and @($Inventory.DomainControllers | Where-Object { $null -eq $_.DiskFreeGB }).Count) { $Missing+=@('DiskFreeGB') }
    if ($RuleId -eq 'services' -and @($Inventory.DomainControllers | Where-Object { @($_.Services.Values | Where-Object { $_ -eq 'Unknown' }).Count -gt 0 }).Count) { $Missing+=@('ServiceState') }
    if ($RuleId -match '^replication' -and @($Inventory.Replication | Where-Object { $null -eq $_.LastSuccess }).Count) { $Missing+=@('LastReplicationSuccess') }
    [pscustomobject]@{ Complete=$Missing.Count -eq 0; Reason=if ($Missing.Count) { 'Required evidence unavailable or incomplete: '+($Missing -join ', ') } else { '' } }
}
