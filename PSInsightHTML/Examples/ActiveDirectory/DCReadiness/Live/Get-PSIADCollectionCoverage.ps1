function Get-PSIADCollectionCoverage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Results)
    $Rows=@(foreach ($Group in @($Results | Group-Object CollectorId)) {
        $Items=@($Group.Group); $Expected=($Items | Measure-Object ExpectedCount -Sum).Sum; $Succeeded=($Items | Measure-Object ResourceCount -Sum).Sum
        $Failed=@($Items | Where-Object Status -eq 'Failed').Count
        $Unavailable=@($Items | Where-Object { $_.Status -in @('NotRequested','NotSupported','NotTested') }).Count
        $NotTested=@($Items | Where-Object Status -eq 'NotTested').Count
        $Status=if ($Failed -eq $Items.Count) { 'Failed' } elseif ($Succeeded -eq $Expected -and $Expected -gt 0) { 'Collected' } elseif ($Succeeded -gt 0) { 'Partial' } elseif ($Unavailable -eq $Items.Count) { if (@($Items | Where-Object Status -eq 'NotSupported').Count) { 'NotSupported' } elseif ($NotTested) { 'NotTested' } else { 'NotRequested' } } else { 'Partial' }
        [pscustomobject]@{ Collector=$Group.Name; Status=$Status; Expected=[int]$Expected; Collected=[int]$Succeeded; CoveragePercent=if ($Expected -gt 0) { [math]::Round(100*$Succeeded/$Expected,1) } else { $null }; Failures=$Failed; NotTested=$NotTested }
    })
    $Requested=@($Results | Where-Object Requested)
    $ExpectedTotal=($Requested | Measure-Object ExpectedCount -Sum).Sum
    $SucceededTotal=($Requested | Measure-Object ResourceCount -Sum).Sum
    [pscustomobject]@{ OverallPercent=if ($ExpectedTotal -gt 0) { [math]::Round(100*$SucceededTotal/$ExpectedTotal,1) } else { $null }; Expected=[int]$ExpectedTotal; Collected=[int]$SucceededTotal; Collectors=$Rows }
}
