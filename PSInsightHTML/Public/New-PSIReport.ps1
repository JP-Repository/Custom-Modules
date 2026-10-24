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
        [object[]] $NavigationGroups = @(),

        [Parameter()]
        [ValidateSet('Sidebar', 'FluentExplorer')]
        [string] $Navigation = 'Sidebar',

        [Parameter()]
        [ValidateSet('Comfortable', 'Compact')]
        [string] $Density = 'Comfortable'
    )

    if ($Layout -eq 'Report' -and $NavigationGroups.Count -gt 0) {
        throw 'NavigationGroups require -Layout Application.'
    }
    if ($Layout -eq 'Report' -and ($Navigation -ne 'Sidebar' -or $Density -ne 'Comfortable')) {
        throw 'Navigation and Density options require -Layout Application.'
    }

    $Report = [pscustomobject]@{
        Title        = $Title
        Subtitle     = $Subtitle
        Theme        = $Theme
        GeneratedOn  = Get-Date
        # From the command's own module (manifest). $script: scope is not reliable here:
        # provider report scripts invoked with & get their own script scope.
        ModuleVersion = [string] $MyInvocation.MyCommand.Module.Version
        Sections     = [System.Collections.Generic.List[object]]::new()
        Assessments  = [System.Collections.Generic.List[object]]::new()
        Findings     = [System.Collections.Generic.List[object]]::new()
    }
    if ($Layout -eq 'Application') {
        $Report | Add-Member -NotePropertyName Layout -NotePropertyValue $Layout
        $Report | Add-Member -NotePropertyName NavigationGroups -NotePropertyValue @($NavigationGroups)
        $Report | Add-Member -NotePropertyName Navigation -NotePropertyValue $Navigation
        $Report | Add-Member -NotePropertyName Density -NotePropertyValue $Density
        $Report | Add-Member -NotePropertyName Views -NotePropertyValue ([System.Collections.Generic.List[object]]::new())
        $Report | Add-Member -NotePropertyName ActiveViewId -NotePropertyValue ''
    }
    $Report
}
