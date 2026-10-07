function Add-PSIKPI {
    <#
    .SYNOPSIS
    Add a KPI card.

    .DESCRIPTION
    Adds a generic KPI with optional status, icon, trend, filter action, or evidence drill-down.

    .PARAMETER Report
    Report or assessment with an existing row.

    .PARAMETER Title
    Card label.

    .PARAMETER Value
    Displayed metric or value.

    .PARAMETER Status
    Canonical health or severity status.

    .PARAMETER DrillDown
    Optional records for the shared evidence viewer.

    .PARAMETER Filter
    Optional table-filter action metadata.

    .EXAMPLE
    $report | Add-PSIKPI -Title 'Available' -Value 12 -Status Healthy | Out-Null
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
        [AllowNull()]
        [object] $Value,

        [Parameter()]
        [AllowEmptyString()]
        [string] $Subtitle = '',

        [Parameter()]
        [string] $Status = 'Unknown',

        [Parameter()]
        [ValidateRange(1, 12)]
        [int] $Span = 3,

        [Parameter()]
        [AllowEmptyString()]
        [string] $Icon = '',

        [Parameter()]
        [AllowEmptyString()]
        [string] $Trend = '',

        [Parameter()]
        [object] $Action = @{},

        [Parameter()]
        [AllowNull()]
        [object] $DrillDown = $null,

        [Parameter()]
        [hashtable] $Filter = @{}
    )

    process {
        if ($null -ne $Action -and $Action -isnot [System.Collections.IDictionary] -and $Action -isnot [pscustomobject]) {
            throw 'KPI Action must be a hashtable, dictionary, or PSCustomObject.'
        }
        if ($Filter.Count -gt 0) {
            foreach ($RequiredKey in @('Table', 'Property')) {
                if (-not $Filter.ContainsKey($RequiredKey) -or [string]::IsNullOrWhiteSpace([string] $Filter[$RequiredKey])) {
                    throw "KPI Filter metadata must contain a non-empty '$RequiredKey' value."
                }
            }
            if (-not $Filter.ContainsKey('Value') -and -not $Filter.ContainsKey('Values')) {
                throw "KPI Filter metadata must contain either 'Value' or 'Values'."
            }
        }

        Add-PSIComponentToLastRow -Report $Report -Type 'KPI' -Properties @{
            Title    = $Title
            Value    = $Value
            Subtitle = $Subtitle
            Status   = Resolve-PSIStatus -Status $Status
            Span     = $Span
            Icon     = $Icon
            Trend    = $Trend
            Action   = $Action
            DrillDown = $DrillDown
            Filter   = $Filter
        }
    }
}
