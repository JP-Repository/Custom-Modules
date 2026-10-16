function New-PSIEvidenceRecord {
    <# .SYNOPSIS Define typed evidence data without converting it to HTML. #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable] $Definition)
    New-PSIContractObject -Kind Evidence -Definition $Definition
}
