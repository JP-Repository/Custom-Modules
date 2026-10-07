function Add-PSISection {
    <#
    .SYNOPSIS
    Add a report section.

    .DESCRIPTION
    Appends a titled section and returns the same report object.

    .PARAMETER Report
    Report or assessment to extend.

    .PARAMETER Title
    Section heading.

    .EXAMPLE
    $report | Add-PSISection -Title 'Summary' | Out-Null
    #>
    [CmdletBinding()]
    param(
        [Parameter(
            ValueFromPipeline = $true,
            Mandatory = $true
        )]
        [ValidateNotNull()]
        [pscustomobject] $Report,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Title
    )

    process {
        $RequiredProperties = if ($Report.PSObject.TypeNames -contains 'PSInsightHTML.Assessment') {
            @('Id', 'Name', 'Title', 'Provider', 'Description', 'Metadata', 'Sections', 'Findings')
        }
        else {
            @('Title', 'Subtitle', 'Theme', 'GeneratedOn', 'ModuleVersion', 'Sections')
        }

        foreach ($PropertyName in $RequiredProperties) {
            if ($null -eq $Report.PSObject.Properties[$PropertyName]) {
                throw "The supplied object is not a valid PSInsightHTML report. Missing property '$PropertyName'. Create reports with New-PSIReport."
            }
        }

        if ($Report.Sections -isnot [System.Collections.Generic.List[object]]) {
            throw 'The supplied object is not a valid PSInsightHTML report. Sections must be a List[object]. Create reports with New-PSIReport.'
        }

        $Section = [pscustomobject]@{
            Title = $Title
            Rows  = [System.Collections.Generic.List[object]]::new()
        }
        if ($Report.PSObject.TypeNames -contains 'PSInsightHTML.Assessment') {
            $Section | Add-Member -NotePropertyName AssessmentId -NotePropertyValue $Report.Id
            $Section | Add-Member -NotePropertyName AssessmentName -NotePropertyValue $Report.Name
        }

        $Report.Sections.Add($Section)
        $Report
    }
}
