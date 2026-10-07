function Add-PSIRecommendation {
    <#
    .SYNOPSIS
    Add a recommendation card.

    .DESCRIPTION
    Displays an assessment recommendation and optional remediation text.

    .PARAMETER Report
    Report or assessment with an existing row.

    .PARAMETER Title
    Recommendation heading.

    .PARAMETER Description
    Reason or context.

    .PARAMETER ActionText
    Optional remediation action.

    .EXAMPLE
    $report | Add-PSIRecommendation -Title 'Review queue' -Description 'Sample backlog grew.' | Out-Null
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Report,

        [Parameter()]
        [string] $Status = 'Info',

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Title,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Description,

        [Parameter()]
        [AllowEmptyString()]
        [string] $ActionText = ''
    )

    process {
        Add-PSIComponentToLastRow -Report $Report -Type 'Recommendation' -Properties @{
            Status      = Resolve-PSIStatus -Status $Status
            Title       = $Title
            Description = $Description
            ActionText  = $ActionText
        }
    }
}
