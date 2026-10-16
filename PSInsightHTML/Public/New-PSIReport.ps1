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
        [string] $Theme = 'Light',

        [Parameter()]
        [ValidateSet('Report', 'Application')]
        [string] $Layout = 'Report',

        [Parameter()]
        [object[]] $NavigationGroups = @()
    )

    if ($Layout -eq 'Report' -and $NavigationGroups.Count -gt 0) {
        throw 'NavigationGroups require -Layout Application.'
    }

    $Report = [pscustomobject]@{
        Title        = $Title
        Subtitle     = $Subtitle
        Theme        = $Theme
        GeneratedOn  = Get-Date
        ModuleVersion = '0.10.0'
        Sections     = [System.Collections.Generic.List[object]]::new()
        Assessments  = [System.Collections.Generic.List[object]]::new()
        Findings     = [System.Collections.Generic.List[object]]::new()
    }
    if ($Layout -eq 'Application') {
        $Report | Add-Member -NotePropertyName Layout -NotePropertyValue $Layout
        $Report | Add-Member -NotePropertyName NavigationGroups -NotePropertyValue @($NavigationGroups)
        $Report | Add-Member -NotePropertyName Views -NotePropertyValue ([System.Collections.Generic.List[object]]::new())
        $Report | Add-Member -NotePropertyName ActiveViewId -NotePropertyValue ''
    }
    $Report
}
