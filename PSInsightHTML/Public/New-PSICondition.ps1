function New-PSICondition {
    <#
    .SYNOPSIS
    Define a table presentation condition.

    .DESCRIPTION
    Creates an ordered cell or row rule; a matching status controls visual formatting only.

    .PARAMETER Property
    Data property to compare.

    .PARAMETER Operator
    Comparison operator.

    .PARAMETER Value
    Expected value unless using IsNull or IsNotNull.

    .PARAMETER Status
    Status token for matching content.

    .PARAMETER Scope
    Cell or Row formatting scope.

    .EXAMPLE
    $rule = New-PSICondition -Property Status -Operator Equals -Value Warning -Status Warning -Scope Row
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Property,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Equals', 'NotEquals', 'GreaterThan', 'GreaterThanOrEqual', 'LessThan', 'LessThanOrEqual', 'Contains', 'Match', 'IsNull', 'IsNotNull')]
        [string] $Operator,

        [Parameter()]
        [AllowNull()]
        [object] $Value,

        [Parameter(Mandatory = $true)]
        [string] $Status,

        [Parameter()]
        [ValidateSet('Cell', 'Row')]
        [string] $Scope = 'Cell'
    )

    if ($Operator -notin @('IsNull', 'IsNotNull') -and -not $PSBoundParameters.ContainsKey('Value')) {
        throw "Condition operator '$Operator' requires a Value."
    }
    if ($Operator -eq 'Match') {
        try {
            $null = [regex]::new([string] $Value, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
        catch {
            throw "Condition Match pattern is invalid: $($_.Exception.Message)"
        }
    }

    [pscustomobject]@{
        Property = $Property
        Operator = $Operator
        Value    = $Value
        Status   = Resolve-PSIStatus -Status $Status
        Scope    = $Scope
    }
}
