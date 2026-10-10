function Add-PSITable {
    <#
    .SYNOPSIS
    Add an interactive table.

    .DESCRIPTION
    Accepts generic objects and supports columns, search, filters, sorting, pagination, export, and conditional formatting.

    .PARAMETER Report
    Report or assessment with an existing row.

    .PARAMETER Data
    Records to display.

    .PARAMETER Title
    Table heading.

    .PARAMETER Columns
    Optional explicit property order.

    .PARAMETER Filters
    Definitions created by Add-PSIFilter.

    .PARAMETER Conditions
    Rules created by New-PSICondition.

    .PARAMETER PageSize
    Number of rows per page.

    .EXAMPLE
    $report | Add-PSITable -Title 'Services' -Data $services -Columns @('Name','Status') | Out-Null
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Report,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Data,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Title,

        [Parameter()]
        [ValidateRange(1, 12)]
        [int] $Span = 12,

        [Parameter()]
        [string[]] $Columns,

        [Parameter()]
        [hashtable] $ColumnLabels = @{},

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]] $Filters = @(),

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]] $Conditions = @(),

        [Parameter()]
        [AllowEmptyString()]
        [string] $Id = '',

        [Parameter()]
        [ValidateRange(1, 500)]
        [int] $PageSize = 10,

        [Parameter()]
        [bool] $EnableSearch = $true,

        [Parameter()]
        [bool] $EnableSorting = $true,

        [Parameter()]
        [bool] $EnablePagination = $true,

        [Parameter()]
        [AllowEmptyString()]
        [string] $EmptyMessage = 'No records match your filters.',

        [Parameter()]
        [AllowEmptyString()]
        [string] $NullValueText = [char] 0x2014,

        [Parameter()]
        [bool] $EnableExport = $true,

        [Parameter()]
        [string[]] $ExportColumns,

        [Parameter()]
        [ValidateSet('Csv', 'Xlsx', 'Print')]
        [string[]] $ExportFormats = @('Csv', 'Xlsx', 'Print'),

        [Parameter()]
        [AllowEmptyString()]
        [string] $ExportFileName = '',

        [Parameter()]
        [AllowEmptyString()]
        [string] $WorksheetName = ''
    )

    process {
        if (-not [string]::IsNullOrEmpty($Id) -and $Id -notmatch '^[A-Za-z][A-Za-z0-9_-]*$') {
            throw 'Table Id must start with a letter and contain only letters, numbers, underscores, or hyphens.'
        }
        if ([string]::IsNullOrWhiteSpace($Id)) {
            $Id = 'psi-table-' + [guid]::NewGuid().ToString('N')
        }
        $null = Assert-PSIReportIds -Sections $Report.Sections -ProposedTableId $Id

        $FilterProperties = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($FilterDefinition in $Filters) {
            if ($null -eq $FilterDefinition -or $null -eq $FilterDefinition.PSObject.Properties['Property']) {
                throw 'Each table filter must be created with Add-PSIFilter and contain a Property.'
            }
            if ([string] $FilterDefinition.Type -notin @('Select', 'MultiSelect')) {
                throw "Table filter '$($FilterDefinition.Property)' has an unsupported Type."
            }
            if (@($FilterDefinition.Values).Count -eq 0) {
                throw "Table filter '$($FilterDefinition.Property)' must contain selectable Values."
            }
            if (-not $FilterProperties.Add([string] $FilterDefinition.Property)) {
                throw "Table filter property '$($FilterDefinition.Property)' is defined more than once."
            }
        }

        foreach ($Condition in $Conditions) {
            if ($null -eq $Condition -or [string]::IsNullOrWhiteSpace([string] (Get-PSIProperty -InputObject $Condition -Name 'Property'))) {
                throw 'Each table condition must contain a non-empty Property.'
            }
            $ConditionOperator = [string] (Get-PSIProperty -InputObject $Condition -Name 'Operator')
            if ($ConditionOperator -notin @('Equals', 'NotEquals', 'GreaterThan', 'GreaterThanOrEqual', 'LessThan', 'LessThanOrEqual', 'Contains', 'Match', 'IsNull', 'IsNotNull')) {
                throw "Table condition operator '$ConditionOperator' is not supported."
            }
            $ConditionScope = [string] (Get-PSIProperty -InputObject $Condition -Name 'Scope')
            if ($ConditionScope -notin @('Cell', 'Row')) {
                throw "Table condition scope '$ConditionScope' must be Cell or Row."
            }
            $null = Resolve-PSIStatus -Status ([string] (Get-PSIProperty -InputObject $Condition -Name 'Status'))
        }

        if ($PSBoundParameters.ContainsKey('Columns') -and $Columns.Count -gt 0) {
            $ResolvedColumns = [System.Collections.Generic.List[string]]::new()
            $SeenColumns = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($Column in $Columns) {
                if ([string]::IsNullOrWhiteSpace($Column)) {
                    throw 'Explicit table column names cannot be null, empty, or whitespace.'
                }

                if (-not $SeenColumns.Add($Column)) {
                    throw "Explicit table column '$Column' is duplicated."
                }

                $ResolvedColumns.Add($Column)
            }

            $ColumnNames = $ResolvedColumns.ToArray()
        }
        else {
            $ColumnNames = @(Get-PSITableColumnNames -Data $Data)
        }

        if ($PSBoundParameters.ContainsKey('ExportColumns')) {
            $SeenExportColumns = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($ExportColumn in $ExportColumns) {
                if ([string]::IsNullOrWhiteSpace($ExportColumn) -or -not $SeenExportColumns.Add($ExportColumn)) {
                    throw 'ExportColumns must contain unique, non-empty column names.'
                }
                if (-not (@($ColumnNames) | Where-Object { [string]::Equals([string] $_, $ExportColumn, [System.StringComparison]::OrdinalIgnoreCase) })) {
                    throw "Export column '$ExportColumn' must be a visible table column."
                }
            }
        }
        else {
            $ExportColumns = [string[]] $ColumnNames
        }
        if ($EnableExport -and @($ExportFormats).Count -eq 0) {
            throw 'ExportFormats must contain at least one format when export is enabled.'
        }

        foreach ($FilterDefinition in $Filters) {
            if (-not (@($ColumnNames) | Where-Object { [string]::Equals([string] $_, [string] $FilterDefinition.Property, [System.StringComparison]::OrdinalIgnoreCase) })) {
                throw "Table filter property '$($FilterDefinition.Property)' is not included in the table columns."
            }
        }

        Add-PSIComponentToLastRow -Report $Report -Type 'Table' -Properties @{
            Title             = $Title
            Span              = $Span
            Data              = [object[]] $Data
            Columns           = [string[]] $ColumnNames
            ColumnLabels      = $ColumnLabels
            Filters           = [object[]] $Filters
            Conditions        = [object[]] $Conditions
            Id                = $Id
            PageSize          = $PageSize
            EnableSearch      = $EnableSearch
            EnableSorting     = $EnableSorting
            EnablePagination  = $EnablePagination
            EmptyMessage      = $EmptyMessage
            NullValueText     = $NullValueText
            EnableExport      = $EnableExport
            ExportColumns     = [string[]] $ExportColumns
            ExportFormats     = [string[]] $ExportFormats
            ExportFileName    = $ExportFileName
            WorksheetName     = $WorksheetName
        }
    }
}
