function Add-PSITree {
    <#
    .SYNOPSIS Add a keyboard-accessible hierarchy of application resources.
    .DESCRIPTION Nodes optionally supply NodeId, ParentId, ResourceId, Label, NodeType, Status, Icon and SortOrder. Missing parents and cycles become roots with a diagnostic. External nodes require IsExternal and EvidenceOnly.
    .EXAMPLE $Report | Add-PSITree -Id service-tree -Title 'Service hierarchy' -Nodes $Hierarchy
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
    process { Add-PSIRelationshipComponent -Report $Report -Type Tree -Id $Id -Title $Title -Nodes $Nodes -Relationships $Relationships -DetailProperties $DetailProperties -LinkViews $LinkViews }
}
