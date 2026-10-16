function Set-PSIApplicationModel {
    <# .SYNOPSIS Attach a validated intelligence model to an application report. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)][pscustomobject] $Report,
        [Parameter(Mandatory = $true)][pscustomobject] $Model
    )
    process {
        if ((Get-PSIProperty -InputObject $Report -Name Layout -DefaultValue 'Report') -ne 'Application') {
            throw 'An intelligence model requires New-PSIReport -Layout Application.'
        }
        [void] (Assert-PSIApplicationModel -Model $Model)
        if ($null -eq $Report.PSObject.Properties['ApplicationModel']) {
            $Report | Add-Member -NotePropertyName ApplicationModel -NotePropertyValue $Model
        }
        else { $Report.ApplicationModel = $Model }
        $Report
    }
}
