function Add-PSIAlert {
    <#
    .SYNOPSIS
    Add an alert card.

    .DESCRIPTION
    Displays a status-bearing message with optional timestamp, details, and action.

    .PARAMETER Report
    Report or assessment with an existing row.

    .PARAMETER Status
    Alert severity.

    .PARAMETER Title
    Alert heading.

    .PARAMETER Message
    Alert description.

    .EXAMPLE
    $report | Add-PSIAlert -Status Warning -Title 'Queue' -Message 'Sample queue is growing.' | Out-Null
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Report,

        [Parameter(Mandatory = $true)]
        [string] $Status,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Title,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Message,

        [Parameter()]
        [AllowNull()]
        [object] $Timestamp = $null,

        [Parameter()]
        [AllowNull()]
        [object] $Details = $null,

        [Parameter()]
        [AllowEmptyString()]
        [string] $Action = ''
    )

    process {
        Add-PSIComponentToLastRow -Report $Report -Type 'Alert' -Properties @{
            Status    = Resolve-PSIStatus -Status $Status
            Title     = $Title
            Message   = $Message
            Timestamp = $Timestamp
            Details   = $Details
            Action    = $Action
        }
    }
}
