function Add-PSIRelationshipExplorer {
    <#
    .SYNOPSIS Add an accessible master/detail relationship list to an application view.
    .EXAMPLE $Report | Add-PSIRelationshipExplorer -Id service-links -Title 'Service relationships'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory,ValueFromPipeline)][pscustomobject] $Report,
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z][A-Za-z0-9_-]*$')][string] $Id,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Title,
        [AllowNull()][object[]] $Nodes,
        [AllowNull()][object[]] $Relationships,
        [string[]] $DetailProperties = @(),
        [hashtable] $LinkViews = @{ Resource='resources'; Finding='findings'; Evidence='evidence' }
    )
    process { Add-PSIRelationshipComponent -Report $Report -Type RelationshipExplorer -Id $Id -Title $Title -Nodes $Nodes -Relationships $Relationships -DetailProperties $DetailProperties -LinkViews $LinkViews }
}
