function New-PSIReport {
    <#
    .SYNOPSIS
    Create a report object.

    .DESCRIPTION
    Creates the generic report container; no HTML is written until Export-PSIReport runs.

    .PARAMETER Title
    Report heading.

    .PARAMETER Subtitle
    Optional text below the heading.

    .PARAMETER Theme
    Initial Light, Dark, or Auto theme.

    .EXAMPLE
    $report = New-PSIReport -Title 'Service Health' -Theme Auto
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Title,

        [Parameter()]
        [string] $Subtitle = '',

        [Parameter()]
        [ValidateSet('Light', 'Dark', 'Auto')]
        [string] $Theme = 'Light'
    )

    [pscustomobject]@{
        Title        = $Title
        Subtitle     = $Subtitle
        Theme        = $Theme
        GeneratedOn  = Get-Date
        ModuleVersion = '0.10.0'
        Sections     = [System.Collections.Generic.List[object]]::new()
        Assessments  = [System.Collections.Generic.List[object]]::new()
        Findings     = [System.Collections.Generic.List[object]]::new()
    }
}
