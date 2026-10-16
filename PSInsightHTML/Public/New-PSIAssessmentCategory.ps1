function New-PSIAssessmentCategory {
    <# .SYNOPSIS Define a generic weighted assessment category. #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable] $Definition)
    New-PSIAssessmentContractObject -Kind Category -Definition $Definition
}
