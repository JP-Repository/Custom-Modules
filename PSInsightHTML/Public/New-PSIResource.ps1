function New-PSIResource {
    <# .SYNOPSIS Define a generic resource. #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable] $Definition)
    New-PSIContractObject -Kind Resource -Definition $Definition
}
