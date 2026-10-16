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
            if (-not $Names.ContainsKey([string] $Link.Source) -or -not $Names.ContainsKey([string] $Link.Destination)) { throw 'Replication link references an unknown DC.' }
            if ($null -ne $Link.LastSuccess -and $Link.LastSuccess -isnot [datetime]) { throw 'Replication LastSuccess must be a typed DateTime or null when unavailable.' }
        }
        if ($InputObject.CollectedAt -isnot [datetime]) { throw 'CollectedAt must be a typed DateTime.' }
        [pscustomobject]@{
            SchemaVersion=if ($InputObject.SchemaVersion) { [string]$InputObject.SchemaVersion } else { '1.0' }
            ContractVersion='1.0'; Source=if ($InputObject.Sample) { 'Fictional sample' } else { 'Live read-only AD collection' }
            CollectedAt=[datetime] $InputObject.CollectedAt
            Forest=$InputObject.Forest; Domains=@($InputObject.Domains); Sites=@($InputObject.Sites)
            DomainControllers=@($InputObject.DomainControllers); Replication=@($InputObject.Replication)
            Dependencies=@($InputObject.Dependencies); Security=$InputObject.Security; SecurityValues=$InputObject.SecurityValues
            Ports=@($InputObject.Ports); DNS=$InputObject.DNS; Time=$InputObject.Time; Thresholds=$InputObject.Thresholds
            CollectionResults=@($InputObject.CollectionResults); CollectionLogs=@($InputObject.CollectionLogs)
            CollectionCoverage=if ($InputObject.Sample) { [pscustomobject]@{ OverallPercent=100; Expected=1; Collected=1; Collectors=@([pscustomobject]@{ Collector='Fictional fixture'; Status='Collected'; Expected=1; Collected=1; CoveragePercent=100; Failures=0; NotTested=0 }) } } else { Get-PSIADCollectionCoverage -Results @($InputObject.CollectionResults) }
        }
    }
}
