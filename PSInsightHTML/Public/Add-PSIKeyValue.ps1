function Add-PSIKeyValue {
    <#
    .SYNOPSIS
    Add a key-value summary.

    .DESCRIPTION
    Displays an ordered dictionary of labels and values in a report card.

    .PARAMETER Report
    Report or assessment with an existing row.

    .PARAMETER Title
    Card heading.

    .PARAMETER Data
    Dictionary containing the displayed key-value pairs.

    .EXAMPLE
    $report | Add-PSIKeyValue -Title 'Scope' -Data ([ordered]@{ Region = 'West' }) | Out-Null
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
        [ValidateNotNull()]
        [System.Collections.IDictionary] $Data,

        [Parameter()]
        [ValidateRange(1, 12)]
        [int] $Span = 6
    )

    process {
        Add-PSIComponentToLastRow -Report $Report -Type 'KeyValue' -Properties @{
            Title = $Title
            Data = $Data
            Span = $Span
        }
    }
}
