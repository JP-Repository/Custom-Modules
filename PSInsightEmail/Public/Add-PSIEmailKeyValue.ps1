function Add-PSIEmailKeyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)][ValidateNotNull()][pscustomobject] $Email,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Title,
        [Parameter(Mandatory = $true)][ValidateNotNull()][System.Collections.IDictionary] $Data
    )
    process {
        Add-PSIEmailComponentToLastRow -Email $Email -Type 'KeyValue' -Properties @{ Title = $Title; Data = $Data }
    }
}
