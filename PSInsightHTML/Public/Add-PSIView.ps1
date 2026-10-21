function Add-PSIView {
    <#
    .SYNOPSIS
    Register a generic application workspace view.

    .DESCRIPTION
    Sections added after this call belong to the new view. The original flat
    report Sections collection remains available to existing components.
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

        [Parameter()]
        [string] $Subtitle = '',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Icon = 'Document',

        [Parameter()]
        [string] $Group = 'Workspace',

        [Parameter()]
        [string] $Badge = '',

        [Parameter()]
        [Nullable[int]] $TabCount,

        [Parameter()]
        [switch] $Disabled,

        [Parameter()]
        [object[]] $Commands = @(),

        [Parameter()]
        [switch] $Initial
    )

    process {
        if ((Get-PSIProperty -InputObject $Report -Name 'Layout' -DefaultValue 'Report') -ne 'Application' -or
            $null -eq $Report.PSObject.Properties['Views'] -or
            $Report.Views -isnot [System.Collections.Generic.List[object]]) {
            throw 'Add-PSIView requires a report created with New-PSIReport -Layout Application.'
        }
        if (@($Report.NavigationGroups).Count -gt 0) {
            throw 'NavigationGroups and application Views cannot be combined.'
        }
        if ($Report.Sections.Count -gt 0 -and $Report.Views.Count -eq 0) {
            throw 'Add the first application view before adding sections.'
        }
        if (@($Report.Views | Where-Object { $_.Id -ieq $Id }).Count -gt 0) {
            throw "Application view ID '$Id' is already registered."
        }
        if ($Initial -and @($Report.Views | Where-Object { $_.State.Initial }).Count -gt 0) {
            throw 'Only one application view can be initial.'
        }
        if ($Initial -and $Disabled) { throw 'The initial application view cannot be disabled.' }
        if ($null -ne $TabCount -and [int]$TabCount -lt 0) { throw 'TabCount must be nonnegative.' }
        if ([string]::IsNullOrWhiteSpace($Group)) { throw 'Application view Group cannot be empty.' }
        [void] (Get-PSIIcon -Name $Icon -Variant Regular -Strict)
        [void] (Get-PSIIcon -Name $Icon -Variant Filled -Strict)
        $ViewCommands = [System.Collections.Generic.List[object]]::new()
        foreach ($Command in $Commands) {
            $CommandLabel = [string] (Get-PSIProperty -InputObject $Command -Name 'Label')
            $CommandIcon = [string] (Get-PSIProperty -InputObject $Command -Name 'Icon' -DefaultValue 'Document')
            $TargetView = [string] (Get-PSIProperty -InputObject $Command -Name 'TargetView')
            if ([string]::IsNullOrWhiteSpace($CommandLabel) -or $TargetView -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$') {
                throw 'View commands require a Label and a valid TargetView ID.'
            }
            [void] (Get-PSIIcon -Name $CommandIcon -Strict)
            $ViewCommands.Add([pscustomobject]@{ Label=$CommandLabel; Icon=$CommandIcon; TargetView=$TargetView })
        }
        $View = [pscustomobject]@{
            Id       = $Id
            Title    = $Title
            Subtitle = $Subtitle
            Icon     = $Icon
            Group    = $Group
            Badge    = $Badge
            TabCount = $TabCount
            Disabled = [bool] $Disabled
            Sections = [System.Collections.Generic.List[object]]::new()
            Commands = $ViewCommands
            State    = @{ Initial = [bool] $Initial }
        }
        $Report.Views.Add($View)
        $Report.ActiveViewId = $Id
        $Report
    }
}
