function New-PSIApplicationFinding {
    <# .SYNOPSIS Define a generic application finding, separate from the legacy report finding card. #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable] $Definition)
    New-PSIContractObject -Kind Finding -Definition $Definition
}
