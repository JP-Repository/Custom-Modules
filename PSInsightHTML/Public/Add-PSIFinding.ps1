function Add-PSIFinding {
    <#
    .SYNOPSIS
    Add a finding to a report or assessment.

    .DESCRIPTION
    Adds a structured finding card and records the finding for derived summaries.

    .PARAMETER Report
    Report or assessment with an existing row.

    .PARAMETER Finding
    Object created by New-PSIFinding.

    .EXAMPLE
    $assessment | Add-PSIFinding -Finding $finding | Out-Null
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Report,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Finding
    )

    process {
        $Title = [string] (Get-PSIProperty -InputObject $Finding -Name 'Title')
        if ([string]::IsNullOrWhiteSpace($Title)) { throw 'A Finding requires a non-empty Title.' }
        $Status = Resolve-PSIStatus -Status ([string] (Get-PSIProperty -InputObject $Finding -Name 'Status'))
        $EvidenceTableId = [string] (Get-PSIProperty -InputObject $Finding -Name 'EvidenceTableId')
        $EvidenceFilter = Get-PSIProperty -InputObject $Finding -Name 'EvidenceFilter'
        $EvidenceColumns = @((Get-PSIProperty -InputObject $Finding -Name 'EvidenceColumns' -DefaultValue @()))
        $Definition = Resolve-PSIEvidenceDefinition -TableId $EvidenceTableId -Filter $EvidenceFilter -EvidenceColumns $EvidenceColumns -ExportColumns $EvidenceColumns -UseVisibleColumns
        if ($null -ne $Definition) { $EvidenceTableId = [string] $Definition.tableId }

        $Result = Add-PSIComponentToLastRow -Report $Report -Type 'Finding' -Properties @{
            Id              = ConvertTo-PSIFindingId -Id ([string] (Get-PSIProperty -InputObject $Finding -Name 'Id'))
            Title           = $Title
            Status          = $Status
            Category        = [string] (Get-PSIProperty -InputObject $Finding -Name 'Category')
            Description     = [string] (Get-PSIProperty -InputObject $Finding -Name 'Description')
            AffectedObject  = [string] (Get-PSIProperty -InputObject $Finding -Name 'AffectedObject')
            Impact          = [string] (Get-PSIProperty -InputObject $Finding -Name 'Impact')
            Recommendation  = [string] (Get-PSIProperty -InputObject $Finding -Name 'Recommendation')
            RuleId          = [string] (Get-PSIProperty -InputObject $Finding -Name 'RuleId')
            Source          = [string] (Get-PSIProperty -InputObject $Finding -Name 'Source')
            EvidenceTableId = $EvidenceTableId
            EvidenceFilter  = $EvidenceFilter
            EvidenceColumns = [string[]] $EvidenceColumns
            FindingReference = $Finding
        }
        if ($null -ne $Report.PSObject.Properties['Findings'] -and
            $Report.Findings -is [System.Collections.Generic.List[object]]) {
            $Report.Findings.Add($Finding)
        }
        $Result
    }
}
