function Test-PSICondition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()][object] $InputObject,
        [Parameter(Mandatory = $true)][ValidateNotNull()][object] $Condition
    )

    $Property = [string] (Get-PSIProperty -InputObject $Condition -Name 'Property')
    $Operator = [string] (Get-PSIProperty -InputObject $Condition -Name 'Operator')
    $Expected = Get-PSIProperty -InputObject $Condition -Name 'Value'
    $Actual = Get-PSITableValue -InputObject $InputObject -Name $Property

    switch ($Operator) {
        'IsNull' { return $null -eq $Actual }
        'IsNotNull' { return $null -ne $Actual }
        'Contains' {
            if ($null -eq $Actual -or $null -eq $Expected -or $Actual -is [System.Collections.IEnumerable] -and $Actual -isnot [string]) { return $false }
            return ([string] $Actual).IndexOf([string] $Expected, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
        }
        'Match' {
            if ($null -eq $Actual -or $null -eq $Expected) { return $false }
            try { return [regex]::IsMatch([string] $Actual, [string] $Expected, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) }
            catch [System.ArgumentException] { return $false }
        }
    }

    if ($null -eq $Actual -or $null -eq $Expected) {
        if ($Operator -eq 'Equals') { return $null -eq $Actual -and $null -eq $Expected }
        if ($Operator -eq 'NotEquals') { return ($null -eq $Actual) -ne ($null -eq $Expected) }
        return $false
    }
    $Comparison = Compare-PSIConditionValues -Left $Actual -Right $Expected
    if ($null -eq $Comparison) { return $false }
    switch ($Operator) {
        'Equals' { return $Comparison -eq 0 }
        'NotEquals' { return $Comparison -ne 0 }
        'GreaterThan' { return $Comparison -gt 0 }
        'GreaterThanOrEqual' { return $Comparison -ge 0 }
        'LessThan' { return $Comparison -lt 0 }
        'LessThanOrEqual' { return $Comparison -le 0 }
        default { return $false }
    }
}
