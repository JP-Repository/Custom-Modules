function Collect-PSIADSnapshot {
    <# .SYNOPSIS Collect one domain-scoped read-only AD snapshot for later assessments. #>
    [CmdletBinding()]
    param(
        [switch] $UseSampleData,
        [string] $Domain,
        [ValidateSet('Core','Operational','Health','Security','Dependencies','Full')][string] $Profile = 'Core',
        [switch] $IncludeRemoteChecks,
        [switch] $IncludePortChecks,
        [switch] $IncludeSecurityChecks,
        [switch] $IncludeDependencyDiscovery,
        [switch] $IncludeHealthEvidence,
        [ValidateRange(1,168)][int] $EventWindowHours = 72,
        [ValidateRange(5,300)][int] $EventQueryTimeoutSeconds = 30,
        [object[]] $DependencyInput = @(),
        [object[]] $BackupInput = @(),
        [hashtable] $CommandAdapter
    )
    $Options=Resolve-PSIADCollectionOptions -Profile $Profile -IncludeRemoteChecks:$IncludeRemoteChecks -IncludePortChecks:$IncludePortChecks -IncludeSecurityChecks:$IncludeSecurityChecks -IncludeDependencyDiscovery:$IncludeDependencyDiscovery -IncludeHealthEvidence:$IncludeHealthEvidence
    $Raw=if ($UseSampleData) { New-PSIADDCReadinessSample }
        else { New-PSIADLiveSnapshot -Domain $Domain -IncludeRemoteChecks:$Options.IncludeRemoteChecks -IncludePortChecks:$Options.IncludePortChecks -IncludeSecurityChecks:$Options.IncludeSecurityChecks -IncludeDependencyDiscovery:$Options.IncludeDependencyDiscovery -IncludeHealthEvidence:$Options.IncludeHealthEvidence -EventWindowHours $EventWindowHours -EventQueryTimeoutSeconds $EventQueryTimeoutSeconds -CommandAdapter $CommandAdapter }
    if ($UseSampleData -and $Options.IncludeSecurityChecks) { $Raw=Add-PSIADSecuritySampleFacts -Raw $Raw }
    if ($DependencyInput.Count) {
        $Added=@($DependencyInput | ConvertTo-PSIADDependencyInput)
        $Raw.Dependencies=@($Raw.Dependencies)+$Added
    }
    $Backups=@($BackupInput | ConvertTo-PSIADBackupInput -Domain $(if ($Raw.Domains) { [string]$Raw.Domains[0].Name } else { [string]$Raw.Forest.Name }) -DomainControllers @($Raw.DomainControllers | ForEach-Object { $_.Name }))
    $Raw | Add-Member -NotePropertyName BackupObservations -NotePropertyValue $Backups -Force
    $Raw | Add-Member -NotePropertyName EventWindowHours -NotePropertyValue $EventWindowHours -Force
    $Raw | Add-Member -NotePropertyName CollectionProfile -NotePropertyValue $Options.Profile -Force
    $Raw
}
