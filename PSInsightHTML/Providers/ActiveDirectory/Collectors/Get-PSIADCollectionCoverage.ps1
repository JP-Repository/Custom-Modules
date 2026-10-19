function Get-PSIADCollectionCoverage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Results)
    $Rows=@(foreach ($Group in @($Results | Group-Object CollectorId)) {
        $Items=@($Group.Group); $RequestedItems=@($Items | Where-Object Requested)
        $Expected=($RequestedItems | Measure-Object ExpectedCount -Sum).Sum; $Succeeded=($RequestedItems | Measure-Object ResourceCount -Sum).Sum
        $Failed=@($Items | Where-Object Status -eq 'Failed').Count
        $Unsupported=@($Items | Where-Object Status -eq 'NotSupported').Count
        $NotTested=@($Items | Where-Object Status -eq 'NotTested').Count
        $Status=if ($RequestedItems.Count -eq 0) { 'NotRequested' }
            elseif ($Failed -eq $RequestedItems.Count) { 'Failed' }
            elseif ($Unsupported -eq $RequestedItems.Count) { 'NotSupported' }
            elseif ($NotTested -eq $RequestedItems.Count) { 'NotTested' }
            elseif (@($RequestedItems | Where-Object Status -ne 'Collected').Count -eq 0 -and $Succeeded -eq $Expected) { 'Collected' }
            else { 'Partial' }
        $Reasons=@($Items | Where-Object { $_.Status -ne 'Collected' -and $_.Requested } | ForEach-Object { if ($_.Notes) { [string]$_.Notes } elseif ($_.ErrorMessage) { [string]$_.ErrorMessage } else { "Collection state $($_.Status) for $($_.Scope)" } } | Select-Object -Unique)
        [pscustomobject]@{ Collector=$Group.Name; Status=$Status; Expected=[int]$Expected; Collected=[int]$Succeeded; CoveragePercent=if ($Expected -gt 0) { [math]::Round(100*$Succeeded/$Expected,1) } else { $null }; Failures=$Failed; NotSupported=$Unsupported; NotTested=$NotTested; NotRequested=@($Items | Where-Object Status -eq 'NotRequested').Count; Reason=$Reasons -join '; ' }
    })
    $Requested=@($Results | Where-Object Requested)
    $ExpectedTotal=($Requested | Measure-Object ExpectedCount -Sum).Sum
    $SucceededTotal=($Requested | Measure-Object ResourceCount -Sum).Sum
    [pscustomobject]@{ OverallPercent=if ($ExpectedTotal -gt 0) { [math]::Round(100*$SucceededTotal/$ExpectedTotal,1) } else { $null }; Expected=[int]$ExpectedTotal; Collected=[int]$SucceededTotal; Formula='Collected observations divided by requested expected observations; Partial credits completed subqueries. NotRequested is excluded. NotSupported and Failed are both absent evidence but retain distinct states and reasons.'; Collectors=$Rows }
}
