function Add-PSITopology {
    <#
    .SYNOPSIS Add a standalone SVG relationship topology with a text-list fallback.
    .DESCRIPTION Uses application resources and relationships by default. Nodes and Relationships can scope or supplement the presentation. MaxNodes limits the graph until filters reduce its scope.
    .EXAMPLE $Report | Add-PSITopology -Id service-map -Title 'Service dependencies' -MaxNodes 100
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory,ValueFromPipeline)][pscustomobject] $Report,
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z][A-Za-z0-9_-]*$')][string] $Id,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Title,
        [AllowNull()][object[]] $Nodes,
        [AllowNull()][object[]] $Relationships,
        [string[]] $DetailProperties = @(),
        [string[]] $FilterProperties = @(),
        [ValidateRange(1,500)][int] $MaxNodes = 100,
        [hashtable] $LinkViews = @{ Resource='resources'; Finding='findings'; Evidence='evidence' }
    )
    process { Add-PSIRelationshipComponent -Report $Report -Type Topology -Id $Id -Title $Title -Nodes $Nodes -Relationships $Relationships -DetailProperties $DetailProperties -FilterProperties $FilterProperties -LinkViews $LinkViews -MaxNodes $MaxNodes }
}
