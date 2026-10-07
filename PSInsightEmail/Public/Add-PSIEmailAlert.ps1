function Add-PSIEmailAlert {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)][ValidateNotNull()][pscustomobject] $Email,
        [Parameter(Mandatory = $true)][ValidateSet('Neutral', 'Informational', 'Healthy', 'Warning', 'Critical')][string] $Status,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Title,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Message
    )
    process {
        Add-PSIEmailComponentToLastRow -Email $Email -Type 'Alert' -Properties @{
            Status = (Resolve-PSIEmailStatus $Status); Title = $Title; Message = $Message
        }
    }
}
