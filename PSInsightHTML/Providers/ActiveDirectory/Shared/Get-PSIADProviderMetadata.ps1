function Get-PSIADProviderMetadata {
    <# .SYNOPSIS Describe the private AD provider without probing infrastructure. #>
    [CmdletBinding()]
    param([AllowNull()][pscustomobject] $Snapshot)
    $Capabilities=@(foreach ($Name in @('Domain','Forest','DCs','Sites','Subnets','SiteLinks','Partners','Failures','Remote','Shares','Time','DNS','Cpu','Features','Events','Port','Dependencies','Security')) {
        $Rows=if ($null -ne $Snapshot) { @($Snapshot.CollectionResults | Where-Object CollectorId -eq $Name) } else { @() }
        [pscustomobject]@{ Name=$Name; State=if (-not $Rows.Count) { 'Unknown' } elseif (@($Rows | Where-Object Status -eq 'Failed').Count) { 'Failed' } elseif (@($Rows | Where-Object Status -eq 'Partial').Count) { 'Partial' } elseif (@($Rows | Where-Object Status -eq 'NotSupported').Count) { 'NotSupported' } elseif (@($Rows | Where-Object Status -eq 'NotRequested').Count -eq $Rows.Count) { 'NotRequested' } else { 'Collected' } }
    })
    [pscustomobject]@{
        Name='ActiveDirectory'; Version='0.1.0'; PowerShellVersion='5.1'
        SupportedAssessments=@('DCReadiness2022','DCReadiness2025')
        SupportedCollectors=$Capabilities
        RequiredModules=@('ActiveDirectory')
        OptionalCapabilities=@('DnsServer','RemoteCIM','CPU','WindowsFeatureInventory','BoundedEventQueries','ProviderBackupInput','TCPConnect','DirectoryDependencyDiscovery','SelectedRegistrySecurityObservations')
        ReadOnly=$true
    }
}
