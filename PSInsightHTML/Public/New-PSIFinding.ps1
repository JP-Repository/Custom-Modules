function New-PSIFinding {
    <#
    .SYNOPSIS
    Define a structured finding.

    .DESCRIPTION
    Creates a finding with severity, explanation, and optional reference to existing table evidence.

    .PARAMETER Title
    Finding heading.

    .PARAMETER Status
    Canonical severity or health status.

    .PARAMETER EvidenceTableId
    ID of the table supplying evidence records.

    .PARAMETER EvidenceFilter
    Optional filter applied to that table in the evidence viewer.

    .EXAMPLE
    $finding = New-PSIFinding -Title 'Review queue' -Status Warning -EvidenceTableId 'queue-table'
    #>
    [CmdletBinding()]
    param(
        [Parameter()][AllowEmptyString()][string] $Id = '',
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Title,
        [Parameter(Mandatory = $true)][string] $Status,
        [Parameter()][AllowEmptyString()][string] $Category = '',
        [Parameter()][AllowEmptyString()][string] $Description = '',
        [Parameter()][AllowEmptyString()][string] $AffectedObject = '',
        [Parameter()][AllowEmptyString()][string] $Impact = '',
        [Parameter()][AllowEmptyString()][string] $Recommendation = '',
        [Parameter()][AllowEmptyString()][string] $RuleId = '',
        [Parameter()][AllowEmptyString()][string] $Source = '',
        [Parameter()][AllowEmptyString()][string] $EvidenceTableId = '',
        [Parameter()][hashtable] $EvidenceFilter = @{},
        [Parameter()][string[]] $EvidenceColumns = @()
    )

    $CanonicalStatus = Resolve-PSIStatus -Status $Status
    $Definition = Resolve-PSIEvidenceDefinition -TableId $EvidenceTableId -Filter $EvidenceFilter -EvidenceColumns $EvidenceColumns -ExportColumns $EvidenceColumns -UseVisibleColumns
    if ($null -ne $Definition) { $EvidenceTableId = [string] $Definition.tableId }

    [pscustomobject]@{
        Id              = ConvertTo-PSIFindingId -Id $Id
        Title           = $Title
        Status          = $CanonicalStatus
        Category        = $Category
        Description     = $Description
        AffectedObject  = $AffectedObject
        Impact          = $Impact
        Recommendation  = $Recommendation
        RuleId          = $RuleId
        Source          = $Source
        EvidenceTableId = $EvidenceTableId
        EvidenceFilter  = $EvidenceFilter
        EvidenceColumns = [string[]] $EvidenceColumns
    }
}
