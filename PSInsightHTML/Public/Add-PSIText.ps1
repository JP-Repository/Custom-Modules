function Add-PSIText {
    <#
    .SYNOPSIS
    Add a text component.

    .DESCRIPTION
    Adds HTML-encoded explanatory text to the latest row.

    .PARAMETER Report
    Report or assessment with an existing row.

    .PARAMETER Text
    Text to display.

    .PARAMETER Size
    Supported typography size.

    .EXAMPLE
    $report | Add-PSIText -Text 'Fictional sample' | Out-Null
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Report,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Text,

        [Parameter()]
        [ValidateSet('Small', 'Normal', 'Large')]
        [string] $Size = 'Normal'
    )

    process {
        Add-PSIComponentToLastRow -Report $Report -Type 'Text' -Properties @{
            Text = $Text
            Size = $Size
        }
    }
}
