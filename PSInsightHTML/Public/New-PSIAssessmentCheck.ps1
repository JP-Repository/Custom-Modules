function New-PSIAssessmentCheck {
    <# .SYNOPSIS Define a generic weighted assessment check. #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable] $Definition)
    New-PSIAssessmentContractObject -Kind Check -Definition $Definition
}
