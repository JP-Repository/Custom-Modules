function Add-PSIEmailText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)][ValidateNotNull()][pscustomobject] $Email,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Text,
        [Parameter()][ValidateSet('Small', 'Normal', 'Large')][string] $Size = 'Normal'
    )
    process {
        Add-PSIEmailComponentToLastRow -Email $Email -Type 'Text' -Properties @{ Text = $Text; Size = $Size }
    }
}
