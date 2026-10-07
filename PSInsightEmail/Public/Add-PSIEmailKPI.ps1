function Add-PSIEmailKPI {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)][ValidateNotNull()][pscustomobject] $Email,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string] $Title,
        [Parameter(Mandatory = $true)][AllowNull()][object] $Value,
        [Parameter()][AllowEmptyString()][string] $Subtitle = '',
        [Parameter()][ValidateSet('Neutral', 'Informational', 'Healthy', 'Warning', 'Critical')][string] $Status = 'Neutral'
    )
    process {
        Add-PSIEmailComponentToLastRow -Email $Email -Type 'KPI' -Properties @{
            Title = $Title; Value = $Value; Subtitle = $Subtitle; Status = (Resolve-PSIEmailStatus $Status)
        }
    }
}
