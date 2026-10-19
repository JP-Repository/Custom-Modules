function Invoke-PSIADCollector {
    [CmdletBinding()]
    param(
        [hashtable]$Adapter,[string]$Id,[string]$Category,[string]$Scope,
        [object[]]$Arguments,[int]$Expected=1,[bool]$Requested=$true,[string]$Method='',
        [System.Collections.Generic.List[object]]$Results,
        [System.Collections.Generic.List[object]]$Logs
    )
    $Start=Get-Date; $Data=@(); $Status='NotRequested'; $Code=''; $Message=''; $Class=''
    if ($Requested) {
        if (-not $Adapter.ContainsKey($Id) -or $Adapter[$Id] -isnot [scriptblock]) { $Status='NotSupported'; $Class='CommandUnavailable' }
        else {
            try { $Data=@(& $Adapter[$Id] @Arguments | Where-Object { $null -ne $_ }); $Status='Collected' }
            catch {
                $ToolUnavailable=$Id -eq 'DNS' -and ($_.Exception -is [System.NotSupportedException] -or $_.Exception -is [System.Management.Automation.CommandNotFoundException])
                $Class=Resolve-PSIADCollectionError -ErrorRecord $_
                $Status=if ($ToolUnavailable -or $Class -in @('Unsupported','CommandUnavailable')) { 'NotSupported' } else { 'Failed' }
                $Code=if ($ToolUnavailable) { 'ToolUnavailable' } else { $_.Exception.GetType().Name }
                $Message=if ($ToolUnavailable) { 'DNS Server PowerShell management cmdlets are unavailable on the collector host.' } else { $_.Exception.Message }
                $Logs.Add([pscustomobject]@{ Timestamp=Get-Date; Level='Warning'; Collector=$Id; Resource=$Scope; Message=$Message; ExceptionType=$Code })
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
        ErrorCode=$Code; ErrorClass=$Class; CollectionMethod=$Method; ErrorMessage=$Message; Notes=if ($Message) { $Message } elseif ($Status -eq 'Collected' -and $Data.Count -eq 0) { 'Query succeeded; no records returned' } else { '' }
    })
    [pscustomobject]@{ Status=$Status; Data=$Data }
}
