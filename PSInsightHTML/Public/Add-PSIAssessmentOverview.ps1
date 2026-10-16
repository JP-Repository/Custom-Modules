function Add-PSIAssessmentOverview {
    <# .SYNOPSIS Add a generic, application-style posture overview to the current row. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)][pscustomobject] $Report,
        [Parameter()][ValidatePattern('^[A-Za-z][A-Za-z0-9_-]*$')][string] $CheckViewId = 'checks',
        [Parameter()][ValidatePattern('^[A-Za-z][A-Za-z0-9_-]*$')][string] $FindingViewId = 'findings'
    )
    process {
        if ($null -eq $Report.PSObject.Properties['ApplicationAssessment']) { throw 'Set-PSIApplicationAssessment must run before Add-PSIAssessmentOverview.' }
        Add-PSIComponentToLastRow -Report $Report -Type AssessmentOverview -Properties @{
            Assessment=$Report.ApplicationAssessment; Model=$Report.ApplicationModel
            CheckViewId=$CheckViewId; FindingViewId=$FindingViewId
        }
    }
}
