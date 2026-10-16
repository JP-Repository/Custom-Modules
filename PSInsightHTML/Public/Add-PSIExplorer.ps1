function Add-PSIExplorer {
    <#
    .SYNOPSIS
    Add a generic searchable master/detail list to an application view.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Report,
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[A-Za-z][A-Za-z0-9_-]*$')]
        [string] $Id,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Title,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Data,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $TitleProperty,
        [Parameter()]
        [string] $SubtitleProperty = '',
        [Parameter()]
        [string] $StatusProperty = '',
        [Parameter()]
        [string[]] $DetailProperties = @(),
        [Parameter()]
        [hashtable] $ColumnLabels = @{},
        [Parameter()]
        [string] $EmptyMessage = 'No records available.',
        [Parameter()]
        [ValidateSet('Finding','Resource','Evidence','Check','Category','Exception')]
        [string] $EntityType = '',
        [Parameter()]
        [hashtable] $LinkViews = @{ Finding='findings'; Resource='resources'; Evidence='evidence'; Check='checks' },
        [Parameter()]
        [string[]] $FilterProperties = @()
    )
    process {
        if ((Get-PSIProperty -InputObject $Report -Name 'Layout' -DefaultValue 'Report') -ne 'Application' -or
            (Get-PSIProperty -InputObject $Report -Name 'Views' -DefaultValue @()).Count -eq 0) {
            throw 'Add-PSIExplorer requires an application view. Add a view first.'
        }
        if ($null -eq $Data) { $Data = @() }
        if ($EntityType -and $null -eq $Report.PSObject.Properties['ApplicationModel']) {
            throw 'An intelligence explorer requires Set-PSIApplicationModel first.'
        }
        if ($EntityType -in @('Check','Category','Exception') -and $null -eq $Report.PSObject.Properties['ApplicationAssessment']) {
            throw 'A Check or Category explorer requires Set-PSIApplicationAssessment first.'
        }
        if ($EntityType) {
            foreach ($Kind in @('Finding','Resource','Evidence')) {
                $Target = [string] $LinkViews[$Kind]
                if ($Target -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$') { throw "LinkViews requires a valid $Kind view ID." }
            }
            if ($EntityType -in @('Category','Exception') -and [string] $LinkViews.Check -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$') { throw 'LinkViews requires a valid Check view ID.' }
        }
        foreach ($FilterProperty in $FilterProperties) {
            if ([string]::IsNullOrWhiteSpace($FilterProperty)) { throw 'FilterProperties cannot contain empty names.' }
        }
        $Properties = @{
            Id = $Id; Title = $Title; Data = @($Data); TitleProperty = $TitleProperty
            SubtitleProperty = $SubtitleProperty; StatusProperty = $StatusProperty
            DetailProperties = @($DetailProperties); ColumnLabels = $ColumnLabels
            EmptyMessage = $EmptyMessage
            EntityType = $EntityType
            Model = if ($EntityType) { $Report.ApplicationModel } else { $null }
            LinkViews = $LinkViews
            Assessment = if ($EntityType -in @('Check','Category','Exception')) { $Report.ApplicationAssessment } else { $null }
            FilterProperties = @($FilterProperties)
        }
        $Row = Get-PSILastRow -Report $Report
        $Row.Components.Add((New-PSIComponent -Type Explorer -Properties $Properties))
        $Report
    }
}
