function Add-PSIStatus {
    <#
    .SYNOPSIS
    Add a status indicator.

    .DESCRIPTION
    Displays a canonical status with optional label and message.

    .PARAMETER Report
    Report or assessment with an existing row.

    .PARAMETER Status
    Healthy, Warning, Critical, Informational, Neutral, Unknown, or NotChecked.

    .PARAMETER Label
    Optional status label.

    .EXAMPLE
    $report | Add-PSIStatus -Status Healthy -Label 'Overall service' | Out-Null
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Report,

        [Parameter(Mandatory = $true)]
        [string] $Status,

        [Parameter()]
        [AllowEmptyString()]
        [string] $Label = '',

        [Parameter()]
        [AllowEmptyString()]
        [string] $Message = ''
    )

    process {
        Add-PSIComponentToLastRow -Report $Report -Type 'Status' -Properties @{
            Status  = Resolve-PSIStatus -Status $Status
            Label   = $Label
            Message = $Message
        }
    }
}
