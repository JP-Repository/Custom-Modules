. (Join-Path $PSScriptRoot '../../../Providers/ActiveDirectory/Shared/Resolve-PSIADCollectionOptions.ps1')
. (Join-Path $PSScriptRoot '../../../Providers/ActiveDirectory/Shared/ConvertTo-PSIADDependencyInput.ps1')
. (Join-Path $PSScriptRoot '../../../Providers/ActiveDirectory/Shared/ConvertTo-PSIADBackupInput.ps1')
. (Join-Path $PSScriptRoot '../../../Providers/ActiveDirectory/Shared/Collect-PSIADSnapshot.ps1')
function Collect-PSIADDCReadiness {
    <# .SYNOPSIS Compatibility entry point for the shared AD snapshot collector. #>
    [CmdletBinding()]
    param([switch]$UseSampleData,[string]$Domain,[switch]$IncludeRemoteChecks,[switch]$IncludePortChecks,[switch]$IncludeSecurityChecks,[switch]$IncludeDependencyDiscovery,[hashtable]$CommandAdapter)
    Collect-PSIADSnapshot -UseSampleData:$UseSampleData -Domain $Domain -Profile Core -IncludeRemoteChecks:$IncludeRemoteChecks -IncludePortChecks:$IncludePortChecks -IncludeSecurityChecks:$IncludeSecurityChecks -IncludeDependencyDiscovery:$IncludeDependencyDiscovery -CommandAdapter $CommandAdapter
}
