function Add-PSIEmailDivider {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true, ValueFromPipeline = $true)][ValidateNotNull()][pscustomobject] $Email)
    process {
        Add-PSIEmailComponentToLastRow -Email $Email -Type 'Divider' -Properties @{}
    }
}
