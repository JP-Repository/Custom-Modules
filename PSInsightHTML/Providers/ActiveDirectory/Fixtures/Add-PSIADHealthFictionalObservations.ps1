function Add-PSIADHealthFictionalObservations {
    <# .SYNOPSIS Complete one explicitly fictional controller scenario for visual Health coverage. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][pscustomobject] $Snapshot,
          [Parameter(Mandatory)][pscustomobject] $Evidence)
    if ($Snapshot.Source -ne 'Fictional sample' -or $Evidence.Kind -ne 'ActiveDirectory.HealthEvidence') { throw 'Fictional Health observations may only augment the fictional sample.' }
    $Name='dc-02.corp.example'
    foreach ($Item in @($Evidence.Observations | Where-Object { $_.DC -eq $Name })) {
        if ($Item.Type -eq 'ResolverReachability') { $Item.Value=$true; $Item.CollectionState='Collected'; $Item.Confidence='Sample'; $Item.CollectionMethod='Fictional fixture probe' }
        elseif ($Item.Type -eq 'TimeSourceReachability') { $Item.Value=$true; $Item.CollectionState='Collected'; $Item.Confidence='Sample'; $Item.CollectionMethod='Fictional fixture probe' }
        elseif ($Item.Type -eq 'TimeSource') { $Item.Value.OffsetMilliseconds=5; $Item.CollectionMethod='Fictional fixture source and offset' }
        elseif ($Item.Type -eq 'EventQuery') { $Item.CollectionState='Collected'; $Item.Confidence='Sample'; $Item.Value=[pscustomobject]@{ Log='System'; WindowHours=$Evidence.EventWindowHours; Message='Fictional completed event query' }; $Item.CollectionMethod='Fictional fixture event query' }
        elseif ($Item.Type -eq 'Backup') { $Item.Value=[pscustomobject]@{ LastSuccessfulSystemStateBackup=$Snapshot.CollectedAt.AddHours(-12); Source='Fictional backup provider'; ProviderConfidence='Sample' }; $Item.CollectionState='Collected'; $Item.Confidence='Sample'; $Item.CollectionMethod='Fictional fixture provider input' }
    }
    foreach ($Item in @($Evidence.Observations | Where-Object { $_.Type -eq 'Replication' -and $_.Value.Source -eq 'dc-05.corp.example' -and $_.Value.Destination -eq 'dc-06.corp.example' })) {
        $Item.Value.CurrentFailures=4; $Item.Value.ConsecutiveFailures=4; $Item.Value.LastSuccess=$Snapshot.CollectedAt.AddHours(-5); $Item.Value.LastError='1722 (fictional current failure)'
        $Item.CollectionMethod='Fictional fixture replication failure'; $Item.Confidence='Sample'
    }
    $Evidence
}
