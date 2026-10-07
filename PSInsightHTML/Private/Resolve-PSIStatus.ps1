function Resolve-PSIStatus {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [string] $Status,

        [Parameter()]
        [switch] $AllowInvalid
    )

    $Candidate = if ($null -eq $Status) { '' } else { $Status.Trim() }
    foreach ($Canonical in $PSIStatusValues) {
        if ([string]::Equals($Candidate, $Canonical, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $Canonical
        }
    }
    foreach ($Alias in $PSIStatusAliases.Keys) {
        if ([string]::Equals($Candidate, [string] $Alias, [System.StringComparison]::OrdinalIgnoreCase)) {
            return [string] $PSIStatusAliases[$Alias]
        }
    }

    if ($AllowInvalid) { return $null }
    throw "Unsupported PSInsightHTML status '$Status'. Supported values: $($PSIStatusValues -join ', '), Info (alias for Informational)."
}
