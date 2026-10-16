function Invoke-PSIADCollector {
    [CmdletBinding()]
    param(
        [hashtable]$Adapter,[string]$Id,[string]$Category,[string]$Scope,
        [object[]]$Arguments,[int]$Expected=1,[bool]$Requested=$true,
        [System.Collections.Generic.List[object]]$Results,
        [System.Collections.Generic.List[object]]$Logs
    )
    $Start=Get-Date; $Data=@(); $Status='NotRequested'; $Code=''; $Message=''
    if ($Requested) {
        if (-not $Adapter.ContainsKey($Id) -or $Adapter[$Id] -isnot [scriptblock]) { $Status='NotSupported' }
        else {
            try { $Data=@(& $Adapter[$Id] @Arguments | Where-Object { $null -ne $_ }); $Status='Collected' }
            catch {
                $Status=if ($_.Exception -is [System.NotSupportedException]) { 'NotSupported' } else { 'Failed' }
                $Code=$_.Exception.GetType().Name; $Message=$_.Exception.Message
                $Logs.Add([pscustomobject]@{ Timestamp=Get-Date; Level='Warning'; Collector=$Id; Resource=$Scope; Message='Collection query failed'; ExceptionType=$Code })
            }
        }
    }
    $Succeeded=if ($Status -eq 'Collected') { 1 } else { 0 }
    $End=Get-Date
    $Results.Add([pscustomobject]@{
        CollectorId=$Id; Name=$Id; Category=$Category; Scope=$Scope; Status=$Status
        StartedAt=$Start; CompletedAt=$End; DurationMs=[math]::Round(($End-$Start).TotalMilliseconds,2)
        Requested=$Requested; Succeeded=$Succeeded -eq 1; ResourceCount=$Succeeded; ExpectedCount=$Expected
        CoveragePercent=if ($Expected -gt 0) { [math]::Round(100*$Succeeded/$Expected,1) } else { $null }
        ErrorCode=$Code; ErrorMessage=$Message; Notes=if ($Status -eq 'Collected' -and $Data.Count -eq 0) { 'Query succeeded; no records returned' } else { '' }
    })
    [pscustomobject]@{ Status=$Status; Data=$Data }
}
