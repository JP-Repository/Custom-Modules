function Compare-PSIConditionValues {
    [CmdletBinding()]
    param(
        [Parameter()][AllowNull()][object] $Left,
        [Parameter()][AllowNull()][object] $Right
    )

    if ($null -eq $Left -or $null -eq $Right) { return $null }

    if ($Left -is [bool] -or $Right -is [bool]) {
        $LeftBool = $false
        $RightBool = $false
        if ($Left -is [bool]) { $LeftBool = $Left; $LeftValid = $true }
        else { $LeftValid = $Left -is [string] -and [bool]::TryParse($Left, [ref] $LeftBool) }
        if ($Right -is [bool]) { $RightBool = $Right; $RightValid = $true }
        else { $RightValid = $Right -is [string] -and [bool]::TryParse($Right, [ref] $RightBool) }
        if (-not ($LeftValid -and $RightValid)) { return $null }
        return [Math]::Sign([int] $LeftBool - [int] $RightBool)
    }

    $Culture = [System.Globalization.CultureInfo]::InvariantCulture
    $NumberStyle = [System.Globalization.NumberStyles]::Float
    $LeftNumber = [decimal] 0
    $RightNumber = [decimal] 0
    if ([decimal]::TryParse([string] $Left, $NumberStyle, $Culture, [ref] $LeftNumber) -and
        [decimal]::TryParse([string] $Right, $NumberStyle, $Culture, [ref] $RightNumber)) {
        return $LeftNumber.CompareTo($RightNumber)
    }

    $LeftDate = [datetimeoffset]::MinValue
    $RightDate = [datetimeoffset]::MinValue
    $DateStyle = [System.Globalization.DateTimeStyles]::AllowWhiteSpaces -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
    if (($Left -is [datetime] -or $Left -is [datetimeoffset] -or $Left -is [string]) -and
        ($Right -is [datetime] -or $Right -is [datetimeoffset] -or $Right -is [string])) {
        $LeftDateText = if ($Left -is [datetime] -or $Left -is [datetimeoffset]) { $Left.ToString('o', $Culture) } else { [string] $Left }
        $RightDateText = if ($Right -is [datetime] -or $Right -is [datetimeoffset]) { $Right.ToString('o', $Culture) } else { [string] $Right }
        if ([datetimeoffset]::TryParse($LeftDateText, $Culture, $DateStyle, [ref] $LeftDate) -and
            [datetimeoffset]::TryParse($RightDateText, $Culture, $DateStyle, [ref] $RightDate)) {
            return $LeftDate.UtcDateTime.CompareTo($RightDate.UtcDateTime)
        }
    }

    if ($Left -is [string] -and $Right -is [string]) {
        return [string]::Compare($Left, $Right, [System.StringComparison]::OrdinalIgnoreCase)
    }
    return $null
}
