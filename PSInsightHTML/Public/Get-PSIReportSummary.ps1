function Get-PSIReportSummary {
    <#
    .SYNOPSIS
    Summarize a composed report.

    .DESCRIPTION
    Derives assessment, section, table, and finding counts and overall status.

    .PARAMETER Report
    Report to summarize.

    .EXAMPLE
    $summary = Get-PSIReportSummary -Report $report
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Report
    )

    process {
        if ($Report.Sections -isnot [System.Collections.Generic.List[object]] -or
            $Report.Findings -isnot [System.Collections.Generic.List[object]] -or
            $Report.Assessments -isnot [System.Collections.Generic.List[object]]) {
            throw 'The supplied object is not a valid PSInsightHTML report. Create it with New-PSIReport.'
        }
        $Counts = Get-PSIFindingSummary -Findings $Report.Findings.ToArray()
        $TableCount = 0
        foreach ($Section in $Report.Sections) {
            foreach ($Row in $Section.Rows) {
                foreach ($Component in $Row.Components) {
                    if ($Component.Type -eq 'Table') { $TableCount++ }
                }
            }
        }
        $AssessmentSummaries = [System.Collections.Generic.List[object]]::new()
        foreach ($Entry in $Report.Assessments) {
            $Assessment = Get-PSIProperty -InputObject $Entry -Name 'Assessment'
            if ($null -ne $Assessment) { $AssessmentSummaries.Add((Get-PSIAssessmentSummary -Assessment $Assessment)) }
        }
        [pscustomobject]@{
            OverallStatus = Resolve-PSIOverallStatus -FindingSummary $Counts
            FindingSummary = $Counts
            FindingCount = $Counts.Total
            AssessmentCount = $Report.Assessments.Count
            SectionCount = $Report.Sections.Count
            TableCount = $TableCount
            AssessmentSummaries = $AssessmentSummaries.ToArray()
        }
    }
}
