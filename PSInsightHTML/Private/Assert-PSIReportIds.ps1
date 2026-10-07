function Assert-PSIReportIds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IEnumerable] $Sections,

        [Parameter()]
        [System.Collections.IEnumerable] $AdditionalSections = @(),

        [Parameter()]
        [AllowEmptyString()]
        [string] $ProposedTableId = ''
    )

    $TableIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Section in @($Sections) + @($AdditionalSections)) {
        foreach ($Row in @($Section.Rows)) {
            foreach ($Component in @($Row.Components)) {
                if ($Component.Type -ne 'Table') { continue }
                $TableId = [string] (Get-PSIProperty -InputObject $Component.Properties -Name 'Id')
                if ([string]::IsNullOrWhiteSpace($TableId)) { continue }
                if (-not $TableIds.Add($TableId)) {
                    throw "Table ID '$TableId' already exists in this report. Assign a unique table ID before composing or exporting."
                }
            }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($ProposedTableId) -and -not $TableIds.Add($ProposedTableId)) {
        throw "Table ID '$ProposedTableId' already exists in this report. Assign a unique table ID before adding the table."
    }
    ,$TableIds
}
