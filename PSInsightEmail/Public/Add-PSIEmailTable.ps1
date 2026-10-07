function Add-PSIEmailTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)][ValidateNotNull()][pscustomobject] $Email,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Title,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]] $Data,
        [Parameter()][string[]] $Columns,
        [Parameter()][hashtable] $ColumnLabels = @{},
        [Parameter()][ValidateRange(1, 500)][int] $MaxRows = 20,
        [Parameter()][bool] $ZebraStriping = $true
    )
    process {
        if (-not $PSBoundParameters.ContainsKey('Columns')) {
            $Columns = if ($Data.Count -gt 0 -and $null -ne $Data[0]) {
                @($Data[0].PSObject.Properties | Select-Object -ExpandProperty Name)
            } else { @() }
        }
        $SeenColumns = @{}
        foreach ($Column in @($Columns)) {
            if ([string]::IsNullOrWhiteSpace($Column) -or $SeenColumns.ContainsKey($Column.ToLowerInvariant())) {
                throw 'Table Columns must contain unique, non-empty property names.'
            }
            $SeenColumns[$Column.ToLowerInvariant()] = $true
        }
        Add-PSIEmailComponentToLastRow -Email $Email -Type 'Table' -Properties @{
            Title = $Title; Data = [object[]] $Data; Columns = [string[]] $Columns
            ColumnLabels = $ColumnLabels; MaxRows = $MaxRows; ZebraStriping = $ZebraStriping
        }
    }
}
