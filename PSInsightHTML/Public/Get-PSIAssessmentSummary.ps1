function Get-PSIAssessmentSummary {
    <#
    .SYNOPSIS
    Summarize an assessment.

    .DESCRIPTION
    Derives section and finding counts and the overall status without rendering HTML.

    .PARAMETER Assessment
    Assessment to summarize.

    .EXAMPLE
    $summary = Get-PSIAssessmentSummary -Assessment $assessment
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Assessment
    )

    process {
        if ($Assessment.PSObject.TypeNames -notcontains 'PSInsightHTML.Assessment' -or
            $Assessment.Sections -isnot [System.Collections.Generic.List[object]] -or
            $Assessment.Findings -isnot [System.Collections.Generic.List[object]]) {
            throw 'The supplied object is not a valid PSInsightHTML Assessment.'
        }
        $Counts = Get-PSIFindingSummary -Findings $Assessment.Findings.ToArray()
        [pscustomobject]@{
            Id = $Assessment.Id
            Name = $Assessment.Name
            Title = $Assessment.Title
            Provider = $Assessment.Provider
            SectionCount = $Assessment.Sections.Count
            FindingCount = $Counts.Total
            Critical = $Counts.Critical
            Warning = $Counts.Warning
            Healthy = $Counts.Healthy
            Informational = $Counts.Informational
            Neutral = $Counts.Neutral
            Unknown = $Counts.Unknown
            NotChecked = $Counts.NotChecked
            OverallStatus = Resolve-PSIOverallStatus -FindingSummary $Counts
        }
    }
}
