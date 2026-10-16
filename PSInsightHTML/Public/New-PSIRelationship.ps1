function New-PSIRelationship {
    <# .SYNOPSIS Define a directed or bidirectional resource relationship. #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable] $Definition)
    New-PSIContractObject -Kind Relationship -Definition $Definition
}
