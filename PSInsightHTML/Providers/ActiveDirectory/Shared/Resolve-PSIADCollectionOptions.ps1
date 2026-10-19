function Resolve-PSIADCollectionOptions {
    <# .SYNOPSIS Resolve provider collection scope without selecting an assessment. #>
    [CmdletBinding()]
    param(
        [ValidateSet('Core','Operational','Health','Security','Dependencies','Full')][string] $Profile = 'Core',
        [switch] $IncludeRemoteChecks,
        [switch] $IncludePortChecks,
        [switch] $IncludeSecurityChecks,
        [switch] $IncludeDependencyDiscovery,
        [switch] $IncludeHealthEvidence
    )
    [pscustomobject]@{
        Profile=$Profile
        IncludeRemoteChecks=($IncludeRemoteChecks.IsPresent -or $IncludeHealthEvidence.IsPresent -or $Profile -in @('Operational','Health','Full'))
        IncludePortChecks=($IncludePortChecks.IsPresent -or $Profile -eq 'Full')
        IncludeSecurityChecks=($IncludeSecurityChecks.IsPresent -or $Profile -in @('Security','Full'))
        IncludeDependencyDiscovery=($IncludeDependencyDiscovery.IsPresent -or $Profile -in @('Dependencies','Full'))
        IncludeHealthEvidence=($IncludeHealthEvidence.IsPresent -or $Profile -in @('Health','Full'))
    }
}
