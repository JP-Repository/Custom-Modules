function Add-PSIAssessment {
    <#
    .SYNOPSIS
    Compose an assessment into a report.

    .DESCRIPTION
    Validates identifiers, then adds assessment sections, findings, and metadata to the report.

    .PARAMETER Report
    Destination report object.

    .PARAMETER Assessment
    Completed assessment to compose.

    .EXAMPLE
    $report | Add-PSIAssessment -Assessment $assessment | Out-Null
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Report,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [pscustomobject] $Assessment
    )

    process {
        foreach ($PropertyName in @('Sections', 'Assessments', 'Findings')) {
            $Property = $Report.PSObject.Properties[$PropertyName]
            if ($null -eq $Property -or $Property.Value -isnot [System.Collections.Generic.List[object]]) {
                throw "The report requires a $PropertyName List[object]. Create it with New-PSIReport."
            }
        }
        if ($Assessment.PSObject.TypeNames -notcontains 'PSInsightHTML.Assessment' -or
            $Assessment.Sections -isnot [System.Collections.Generic.List[object]] -or
            $Assessment.Findings -isnot [System.Collections.Generic.List[object]]) {
            throw 'The supplied assessment is invalid. Create it with New-PSIAssessment.'
        }
        foreach ($Existing in $Report.Assessments) {
            if ([string]::Equals([string] $Existing.Id, [string] $Assessment.Id, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Assessment ID '$($Assessment.Id)' already exists in this report."
            }
        }

        # Check the entire composition before changing the report, so a collision
        # cannot leave a partly appended assessment behind.
        $null = Assert-PSIReportIds -Sections $Report.Sections -AdditionalSections $Assessment.Sections
        foreach ($Section in $Assessment.Sections) {
            $ExistingId = [string] (Get-PSIProperty -InputObject $Section -Name 'AssessmentId')
            if (-not [string]::IsNullOrWhiteSpace($ExistingId) -and $ExistingId -ne $Assessment.Id) {
                throw "Section '$($Section.Title)' belongs to assessment '$ExistingId', not '$($Assessment.Id)'."
            }
        }
        foreach ($Section in $Assessment.Sections) {
            if ($null -eq $Section.PSObject.Properties['AssessmentId']) {
                $Section | Add-Member -NotePropertyName AssessmentId -NotePropertyValue $Assessment.Id
            }
            if ($null -eq $Section.PSObject.Properties['AssessmentName']) {
                $Section | Add-Member -NotePropertyName AssessmentName -NotePropertyValue $Assessment.Name
            }
            $Report.Sections.Add($Section)
        }
        foreach ($Finding in $Assessment.Findings) { $Report.Findings.Add($Finding) }
        $Report.Assessments.Add([pscustomobject]@{
            Id          = $Assessment.Id
            Name        = $Assessment.Name
            Title       = $Assessment.Title
            Provider    = $Assessment.Provider
            Description = $Assessment.Description
            Assessment = $Assessment
            SectionCount = $Assessment.Sections.Count
            FindingCount = $Assessment.Findings.Count
        })
        $Report
    }
}
