function Add-PSIRelationshipComponent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject] $Report,
        [Parameter(Mandatory)][ValidateSet('Tree','Topology','RelationshipExplorer')][string] $Type,
        [Parameter(Mandatory)][string] $Id,
        [Parameter(Mandatory)][string] $Title,
        [AllowNull()][object[]] $Nodes,
        [AllowNull()][object[]] $Relationships,
        [string[]] $DetailProperties = @(),
        [string[]] $FilterProperties = @(),
        [hashtable] $LinkViews = @{ Resource='resources'; Finding='findings'; Evidence='evidence' },
        [int] $MaxNodes = 100
    )
    if ((Get-PSIProperty -InputObject $Report -Name 'Layout' -DefaultValue 'Report') -ne 'Application' -or
        (Get-PSIProperty -InputObject $Report -Name 'Views' -DefaultValue @()).Count -eq 0) {
        throw "$Type requires an application view. Add a view first."
    }
    $Model = Get-PSIProperty -InputObject $Report -Name 'ApplicationModel' -DefaultValue $null
    if ($null -eq $Model) { throw "$Type requires Set-PSIApplicationModel first." }
    foreach ($Kind in @('Resource','Finding','Evidence')) {
        if ([string] $LinkViews[$Kind] -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$') { throw "$Type LinkViews requires a valid $Kind view ID." }
    }
    foreach ($Property in $FilterProperties) {
        if ($Property -notin $DetailProperties -or $Property -cnotmatch '^[A-Za-z][A-Za-z0-9_]{0,63}$') { throw "$Type FilterProperties must be valid DetailProperties." }
    }
    $Presentation = Resolve-PSIRelationshipPresentation -Model $Model -Nodes $Nodes -Relationships $Relationships -DetailProperties $DetailProperties
    $Row = Get-PSILastRow -Report $Report
    $Row.Components.Add((New-PSIComponent -Type $Type -Properties @{
        Id=$Id; Title=$Title; Presentation=$Presentation; LinkViews=$LinkViews; MaxNodes=$MaxNodes; FilterProperties=@($FilterProperties)
    }))
    $Report
}
