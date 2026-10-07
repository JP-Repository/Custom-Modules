function Add-PSIInsight {
    <#
    .SYNOPSIS
    Add an investigation insight.

    .DESCRIPTION
    Adds a metric that can open filtered evidence from an existing table dataset.

    .PARAMETER Report
    Report or assessment with an existing row.

    .PARAMETER Title
    Insight label.

    .PARAMETER Value
    Displayed metric.

    .PARAMETER Filter
    Table ID and conditions defining the evidence context.

    .PARAMETER EvidenceColumns
    Columns shown in the evidence viewer.

    .EXAMPLE
    $report | Add-PSIInsight -Title 'Review items' -Value 3 -Status Warning | Out-Null
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
        [string] $Description = '',

        [Parameter()]
        [string] $Status = 'Info',

        [Parameter()]
        [AllowEmptyString()]
        [string] $Icon = '',

        [Parameter()]
        [hashtable] $Filter = @{},

        [Parameter()]
        [string[]] $EvidenceColumns = @(),

        [Parameter()]
        [string[]] $ExportColumns = @(),

        [Parameter()]
        [hashtable] $ColumnLabels = @{}
    )

    process {
        if ($Filter.Count -gt 0) {
            if (-not $Filter.ContainsKey('Table') -or [string]::IsNullOrWhiteSpace([string] $Filter.Table)) {
                throw "Insight Filter metadata must contain a non-empty 'Table' value."
            }
            if (-not $Filter.ContainsKey('Conditions')) {
                throw "Insight Filter metadata must contain a 'Conditions' collection (which may be empty to reference all records)."
            }
            foreach ($Condition in @($Filter.Conditions)) {
                if ($null -eq $Condition -or [string]::IsNullOrWhiteSpace([string] $Condition.Property)) {
                    throw 'Each insight filter condition must contain a non-empty Property.'
                }
                if ([string] $Condition.Operator -notin @('Equals', 'NotEquals', 'GreaterThanOrEqual', 'LessThan', 'IsEmpty', 'IsNotEmpty', 'Contains', 'In')) {
                    throw "Insight filter operator '$($Condition.Operator)' is not supported."
                }
            }
        }
        foreach ($Column in @($EvidenceColumns) + @($ExportColumns)) {
            if ([string]::IsNullOrWhiteSpace($Column)) { throw 'Evidence and export column names cannot be empty.' }
        }
        Add-PSIComponentToLastRow -Report $Report -Type 'Insight' -Properties @{
            Title = $Title
            Value = $Value
            Description = $Description
            Status = Resolve-PSIStatus -Status $Status
            Icon = $Icon
            Filter = $Filter
            EvidenceColumns = [string[]] $EvidenceColumns
            ExportColumns = [string[]] $ExportColumns
            ColumnLabels = $ColumnLabels
        }
    }
}
