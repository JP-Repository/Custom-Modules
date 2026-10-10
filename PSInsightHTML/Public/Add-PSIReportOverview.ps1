function Add-PSIReportOverview {
    <#
    .SYNOPSIS
    Add a derived report overview.

    .DESCRIPTION
    Builds severity and assessment summary components from composed report content.

    .PARAMETER Report
    Report to extend.

    .PARAMETER IncludeTopFindings
    Include a compact list of the highest-priority findings.

    .PARAMETER MaxFindings
    Maximum number of findings to show.

    .EXAMPLE
    $report | Add-PSIReportOverview -IncludeTopFindings | Out-Null
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Report,

        [Parameter()]
        [switch] $IncludeTopFindings,

        [Parameter()]
        [ValidateRange(0, 100)]
        [int] $MaxFindings = 10
    )

    process {
        $Summary = Get-PSIReportSummary -Report $Report
        foreach ($Section in $Report.Sections) {
            if ((Get-PSIProperty -InputObject $Section -Name 'IsOverview' -DefaultValue $false) -eq $true) {
                throw 'This report already contains a report overview.'
            }
        }

        $null = $Report | Add-PSISection -Title 'Report Overview'
        $Overview = $Report.Sections[$Report.Sections.Count - 1]
        $Overview | Add-Member -NotePropertyName IsOverview -NotePropertyValue $true

        $null = $Report | Add-PSIRow -Columns 12 |
            Add-PSIStatus -Status $Summary.OverallStatus -Label 'Overall assessment' `
                -Message ('Derived from {0} structured finding(s). No findings means Neutral.' -f $Summary.FindingCount)
        $null = $Report | Add-PSIRow -Columns 12 |
            Add-PSIKPI -Title 'Critical' -Value $Summary.FindingSummary.Critical -Status Critical -Icon 'critical' -Span 3 |
            Add-PSIKPI -Title 'Warning' -Value $Summary.FindingSummary.Warning -Status Warning -Icon 'warning' -Span 3 |
            Add-PSIKPI -Title 'Informational' -Value $Summary.FindingSummary.Informational -Status Informational -Icon 'info' -Span 3 |
            Add-PSIKPI -Title 'Assessments' -Value $Summary.AssessmentCount -Status Neutral -Icon 'dashboard' -Span 3

        $null = $Report | Add-PSIRow -Columns 12 | Add-PSIText -Text 'Assessment Overview' -Size Large
        if ($Summary.AssessmentCount -eq 0) {
            $null = $Report | Add-PSIRow -Columns 12 | Add-PSIText -Text 'No assessments have been added to this report.' -Size Small
        }
        else {
            $null = $Report | Add-PSIRow -Columns 12
            foreach ($AssessmentSummary in $Summary.AssessmentSummaries) {
                $TargetIndex = -1
                for ($Index = 0; $Index -lt $Report.Sections.Count - 1; $Index++) {
                    if ([string]::Equals([string] (Get-PSIProperty -InputObject $Report.Sections[$Index] -Name 'AssessmentId'),
                        [string] $AssessmentSummary.Id, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $TargetIndex = $Index + 1
                        break
                    }
                }
                $Action = if ($TargetIndex -ge 0) { @{ Type = 'ScrollTo'; Target = "psi-section-$TargetIndex" } } else { @{} }
                $Description = if ($AssessmentSummary.FindingCount -eq 0) { 'No structured findings' } else { '{0} finding(s)' -f $AssessmentSummary.FindingCount }
                $null = $Report | Add-PSIKPI -Title $AssessmentSummary.Name -Value $AssessmentSummary.OverallStatus `
                    -Subtitle ("$Description $([char] 0x00B7) $($AssessmentSummary.SectionCount) sections") -Status $AssessmentSummary.OverallStatus `
                    -Icon 'dashboard' -Span 3 -Action $Action
            }
        }

        if ($IncludeTopFindings) {
            $null = $Report | Add-PSIRow -Columns 12 | Add-PSIText -Text 'Important Findings' -Size Large
            $OrderedFindings = [System.Collections.Generic.List[object]]::new()
            foreach ($Status in @('Critical', 'Warning', 'Unknown', 'NotChecked', 'Informational', 'Healthy', 'Neutral')) {
                foreach ($Finding in $Report.Findings) {
                    if ((Resolve-PSIStatus -Status ([string] (Get-PSIProperty -InputObject $Finding -Name 'Status'))) -eq $Status) {
                        $OrderedFindings.Add($Finding)
                    }
                }
            }
            if ($OrderedFindings.Count -eq 0) {
                $null = $Report | Add-PSIRow -Columns 12 | Add-PSIText -Text 'No structured findings were supplied.' -Size Small
            }
            elseif ($MaxFindings -gt 0) {
                $Anchors = Get-PSIFindingAnchors -Sections $Report.Sections
                $null = $Report | Add-PSIRow -Columns 12
                for ($FindingIndex = 0; $FindingIndex -lt [math]::Min($MaxFindings, $OrderedFindings.Count); $FindingIndex++) {
                    $Finding = $OrderedFindings[$FindingIndex]
                    $Status = Resolve-PSIStatus -Status ([string] (Get-PSIProperty -InputObject $Finding -Name 'Status'))
                    $Action = @{}
                    foreach ($Anchor in $Anchors) {
                        if ($null -ne $Anchor.FindingReference -and [object]::ReferenceEquals($Anchor.FindingReference, $Finding)) {
                            $Action = @{ Type = 'ScrollTo'; Target = $Anchor.Id }
                            break
                        }
                    }
                    $null = $Report | Add-PSIKPI -Title ([string] $Finding.Title) -Value $Status `
                        -Subtitle ([string] $Finding.Description) -Status $Status -Icon 'info' -Span 4 -Action $Action
                }
            }
        }
        $Report.Sections.RemoveAt($Report.Sections.Count - 1)
        $Report.Sections.Insert(0, $Overview)
        $Report
    }
}
