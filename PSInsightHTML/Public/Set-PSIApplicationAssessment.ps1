function Set-PSIApplicationAssessment {
    <# .SYNOPSIS Attach an assessment to an Application report and resolve its linked posture. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)][pscustomobject] $Report,
        [Parameter(Mandatory = $true)][pscustomobject] $Assessment
    )
    process {
        if ((Get-PSIProperty -InputObject $Report -Name Layout -DefaultValue 'Report') -ne 'Application') { throw 'Assessment experience requires New-PSIReport -Layout Application.' }
        if ($null -eq $Report.PSObject.Properties['ApplicationModel']) { throw 'Set-PSIApplicationModel must run before Set-PSIApplicationAssessment.' }
        $Resolved = Resolve-PSIAssessmentPosture -Assessment $Assessment -Model $Report.ApplicationModel
        if ($null -eq $Report.PSObject.Properties['ApplicationAssessment']) { $Report | Add-Member -NotePropertyName ApplicationAssessment -NotePropertyValue $Resolved }
        else { $Report.ApplicationAssessment = $Resolved }
        $Report
    }
}
