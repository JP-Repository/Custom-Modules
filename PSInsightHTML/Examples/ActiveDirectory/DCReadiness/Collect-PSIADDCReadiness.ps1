function Collect-PSIADDCReadiness {
    <# .SYNOPSIS Select the fictional fixture or read-only, domain-scoped collection. #>
    [CmdletBinding()]
    param([switch]$UseSampleData,[string]$Domain,[switch]$IncludeRemoteChecks,[switch]$IncludePortChecks,[switch]$IncludeSecurityChecks,[switch]$IncludeDependencyDiscovery,[hashtable]$CommandAdapter)
    if ($UseSampleData) { return New-PSIADDCReadinessSample }
    New-PSIADLiveSnapshot -Domain $Domain -IncludeRemoteChecks:$IncludeRemoteChecks -IncludePortChecks:$IncludePortChecks -IncludeSecurityChecks:$IncludeSecurityChecks -IncludeDependencyDiscovery:$IncludeDependencyDiscovery -CommandAdapter $CommandAdapter
}
