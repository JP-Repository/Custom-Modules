function New-PSIADGroupPolicyAssessment {
    <#
    .SYNOPSIS
    Create an Active Directory Group Policy assessment.

    .DESCRIPTION
    Builds the Group Policy object and link sample assessment. No live infrastructure collection is performed.

    .PARAMETER UseSampleData
    Explicitly select fictional local sample data.

    .PARAMETER Path
    Output path for a standalone HTML report.

    .PARAMETER AsAssessment
    Return an assessment object for composition instead of writing HTML.

    .PARAMETER Theme
    Initial Light, Dark, or Auto theme for standalone output.

    .PARAMETER NoBrowser
    Do not attempt to open standalone output in a browser.

    .EXAMPLE
    New-PSIADGroupPolicyAssessment -UseSampleData -GpoCount 180 -NoBrowser
    #>
    [CmdletBinding()]
    param(
        [Parameter()][switch] $UseSampleData,
        [Parameter()][ValidateNotNullOrEmpty()][string] $Path,
        [Parameter()][ValidateSet('Light', 'Dark', 'Auto')][string] $Theme = 'Auto',
    [Parameter()][ValidateRange(100, 250)][int] $GpoCount = 180,
    [Parameter()][datetime] $AsOfDate = [datetime]::new(2026, 9, 27),
        [Parameter()][switch] $NoBrowser,
    [Parameter()][switch] $AsAssessment
    )

    if (-not $UseSampleData) {
        throw 'Specify -UseSampleData. Provided data and live collection are not implemented for this report.'
    }

    $InvokeParameters = @{}
    foreach ($Key in $PSBoundParameters.Keys) {
        if ($Key -notin @('UseSampleData', 'Path')) { $InvokeParameters[$Key] = $PSBoundParameters[$Key] }
    }
    if ($PSBoundParameters.ContainsKey('Path')) { $InvokeParameters['OutputPath'] = $Path }
    $ReportScript = Join-Path -Path $script:ModuleRoot -ChildPath 'Providers/ActiveDirectory/GroupPolicy/Private/Report.ps1'
    & $ReportScript @InvokeParameters
}
