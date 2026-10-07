function Resolve-PSIEvidenceDefinition {
    [CmdletBinding()]
    param(
        [Parameter()][AllowEmptyString()][string] $TableId = '',
        [Parameter()][AllowNull()][object] $Filter = $null,
        [Parameter()][string[]] $EvidenceColumns = @(),
        [Parameter()][string[]] $ExportColumns = @(),
        [Parameter()][hashtable] $Labels = @{},
        [Parameter()][switch] $UseVisibleColumns
    )

    $FilterTable = [string] (Get-PSIProperty -InputObject $Filter -Name 'Table')
    if (-not [string]::IsNullOrWhiteSpace($FilterTable)) {
        if (-not [string]::IsNullOrWhiteSpace($TableId) -and $TableId -ne $FilterTable) {
            throw 'EvidenceTableId and EvidenceFilter.Table must reference the same table.'
        }
        $TableId = $FilterTable
    }
    $SingleProperty = [string] (Get-PSIProperty -InputObject $Filter -Name 'Property')
    $RawConditions = Get-PSIProperty -InputObject $Filter -Name 'Conditions'
    $HasFilter = $null -ne $Filter -and $Filter -is [System.Collections.IDictionary] -and $Filter.Count -gt 0
    if ([string]::IsNullOrWhiteSpace($TableId)) {
        if ($HasFilter -or -not [string]::IsNullOrWhiteSpace($SingleProperty) -or $null -ne $RawConditions) {
            throw 'EvidenceFilter requires an EvidenceTableId or a matching Table entry.'
        }
        return $null
    }

    $Conditions = [System.Collections.Generic.List[object]]::new()
    if ($null -ne $RawConditions) {
        foreach ($Condition in @($RawConditions)) { $Conditions.Add($Condition) }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($SingleProperty)) {
        $Operator = [string] (Get-PSIProperty -InputObject $Filter -Name 'Operator' -DefaultValue 'Equals')
        $SingleCondition = [ordered]@{ Property = $SingleProperty; Operator = $Operator }
        $Values = Get-PSIProperty -InputObject $Filter -Name 'Values'
        if ($Operator -eq 'In') { $SingleCondition['Values'] = @($Values) }
        else { $SingleCondition['Value'] = Get-PSIProperty -InputObject $Filter -Name 'Value' }
        $Conditions.Add($SingleCondition)
    }
    elseif ($HasFilter -and [string]::IsNullOrWhiteSpace($FilterTable)) {
        throw 'EvidenceFilter must contain Property or Conditions.'
    }

    foreach ($Condition in $Conditions) {
        $Property = [string] (Get-PSIProperty -InputObject $Condition -Name 'Property')
        $Operator = [string] (Get-PSIProperty -InputObject $Condition -Name 'Operator' -DefaultValue 'Equals')
        if ([string]::IsNullOrWhiteSpace($Property)) { throw 'Each evidence condition requires a non-empty Property.' }
        if ($Operator -notin @('Equals', 'NotEquals', 'GreaterThanOrEqual', 'LessThan', 'IsEmpty', 'IsNotEmpty', 'Contains', 'In')) {
            throw "Evidence filter operator '$Operator' is not supported by the table viewer."
        }
    }
    foreach ($Column in @($EvidenceColumns) + @($ExportColumns)) {
        if ([string]::IsNullOrWhiteSpace($Column)) { throw 'Evidence and export columns cannot contain empty names.' }
    }

    return [ordered]@{
        tableId = $TableId
        conditions = $Conditions.ToArray()
        evidenceColumns = [string[]] $EvidenceColumns
        exportColumns = [string[]] $ExportColumns
        labels = $Labels
        useVisibleColumns = [bool] $UseVisibleColumns
    }
}
