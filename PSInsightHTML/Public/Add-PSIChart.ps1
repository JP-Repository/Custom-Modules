function Add-PSIChart {
    <#
    .SYNOPSIS
    Add an inline SVG chart.

    .DESCRIPTION
    Renders Bar, Line, Doughnut, or Pie charts from generic objects without an external chart library.

    .PARAMETER Report
    Report or assessment with an existing row.

    .PARAMETER ChartType
    Bar, Line, Doughnut, or Pie.

    .PARAMETER Data
    Generic chart records.

    .PARAMETER CategoryProperty
    Property used for categories.

    .PARAMETER ValueProperty
    Numeric property used for values.

    .PARAMETER FilterMetadata
    Optional chart-point table-filter mapping.

    .EXAMPLE
    $report | Add-PSIChart -Title 'By status' -ChartType Bar -Data $counts -CategoryProperty Status -ValueProperty Count | Out-Null
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Report,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Title,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Bar', 'Line', 'Doughnut', 'Pie')]
        [string] $ChartType = 'Bar',

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Data,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $CategoryProperty,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $ValueProperty,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $SeriesProperty,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $StatusProperty,

        [Parameter()]
        [hashtable] $FilterMetadata = @{},

        [Parameter()]
        [ValidateRange(320, 1600)]
        [int] $Width = 900,

        [Parameter()]
        [ValidateRange(180, 900)]
        [int] $Height = 320,

        [Parameter()]
        [bool] $ShowLegend = $true,

        [Parameter()]
        [bool] $ShowLabels = $false,

        [Parameter()]
        [AllowEmptyString()]
        [string] $EmptyMessage = 'No chart data is available.'
    )

    process {
        $FilterMetadata = @{} + $FilterMetadata
        if ($FilterMetadata.Count -gt 0) {
            foreach ($RequiredKey in @('Table', 'Property')) {
                if (-not $FilterMetadata.ContainsKey($RequiredKey) -or
                    [string]::IsNullOrWhiteSpace([string] $FilterMetadata[$RequiredKey])) {
                    throw "FilterMetadata must contain a non-empty '$RequiredKey' value."
                }
            }

            if (-not $FilterMetadata.ContainsKey('ValueProperty')) {
                $FilterMetadata['ValueProperty'] = $CategoryProperty
            }
            if ([string]::IsNullOrWhiteSpace([string] $FilterMetadata['ValueProperty'])) {
                throw "FilterMetadata 'ValueProperty' must not be empty."
            }
        }

        Add-PSIComponentToLastRow -Report $Report -Type 'Chart' -Properties @{
            Title            = $Title
            ChartType        = $ChartType
            Data             = [object[]] $Data
            CategoryProperty = $CategoryProperty
            ValueProperty    = $ValueProperty
            SeriesProperty   = $SeriesProperty
            StatusProperty   = $StatusProperty
            FilterMetadata   = $FilterMetadata
            Width            = $Width
            Height           = $Height
            ShowLegend       = $ShowLegend
            ShowLabels       = $ShowLabels
            EmptyMessage     = $EmptyMessage
        }
    }
}
