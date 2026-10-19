function Resolve-PSIADComplianceApplicability {
    <# .SYNOPSIS Resolve technical mapping applicability from an existing normalized snapshot. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject] $Snapshot,
        [Parameter(Mandatory)][hashtable] $MappingPack,
        [Parameter(Mandatory)][hashtable] $Mapping,
        [Parameter(Mandatory)][string] $ResourceId
    )
    $Match=[regex]::Match($ResourceId,'^dc-(\d+)$')
    if (-not $Match.Success) { return [pscustomobject]@{ State='NotApplicable'; Reason='Resource is outside the selected domain controller scope.'; Confidence='High'; OSVersion=$null } }
    $Index=[int]$Match.Groups[1].Value-1
    if ($Index -lt 0 -or $Index -ge @($Snapshot.DomainControllers).Count) { return [pscustomobject]@{ State='Unknown'; Reason='Domain controller resource could not be resolved in the snapshot.'; Confidence='Low'; OSVersion=$null } }
    $DC=$Snapshot.DomainControllers[$Index]
    $Roles=@($MappingPack.ApplicableRoles)+@($Mapping.ApplicableRoles) | Where-Object { $_ }
    foreach ($Role in $Roles) {
        if ($Role -eq 'DomainController') { continue }
        if ($Role -eq 'DNSServer') {
            if ($null -eq $DC.DNSRole) { return [pscustomobject]@{ State='Unknown'; Reason='DNS Server role fact is missing.'; Confidence='Low'; OSVersion=$null } }
            if (-not [bool]$DC.DNSRole) { return [pscustomobject]@{ State='NotApplicable'; Reason='DNS Server role is explicitly absent.'; Confidence='High'; OSVersion=$null } }
            continue
        }
        return [pscustomobject]@{ State='Unknown'; Reason="Unsupported role requirement '$Role'."; Confidence='Low'; OSVersion=$null }
    }
    $Feature=@($DC.InstalledFeatures | Where-Object { $_.Name -eq 'AD-Domain-Services' })
    if ($Feature.Count -and $Feature[0].Installed -eq $false) { return [pscustomobject]@{ State='NotApplicable'; Reason='Explicit feature evidence shows AD Domain Services is not installed.'; Confidence='High'; OSVersion=$null } }
    foreach ($FeatureName in @($Mapping.RequiredFeatures | Where-Object { $_ })) {
        $Required=@($DC.InstalledFeatures | Where-Object { $_.Name -eq $FeatureName })
        if (-not $Required.Count) { return [pscustomobject]@{ State='Unknown'; Reason="Installed feature fact '$FeatureName' is missing."; Confidence='Low'; OSVersion=$null } }
        if ($Required[0].Installed -eq $false) { return [pscustomobject]@{ State='NotApplicable'; Reason="Required feature '$FeatureName' is explicitly absent."; Confidence='High'; OSVersion=$null } }
    }
    $OS=[string]$DC.OS
    if (-not $OS.Trim()) { return [pscustomobject]@{ State='Unknown'; Reason='Operating system fact is missing.'; Confidence='Low'; OSVersion=$null } }
    foreach ($OSNames in @(@($MappingPack.ApplicableOperatingSystems),@($Mapping.ApplicableOperatingSystems))) {
        $Names=@($OSNames | Where-Object { $_ })
        if ($Names.Count -and -not @($Names | Where-Object { $OS.StartsWith([string]$_,[System.StringComparison]::OrdinalIgnoreCase) }).Count) {
            return [pscustomobject]@{ State='NotApplicable'; Reason="Operating system '$OS' is outside this mapping scope."; Confidence='High'; OSVersion=$null }
        }
    }
    $VersionMatch=[regex]::Match($OS,'\b(20\d{2})\b')
    $Version=if ($VersionMatch.Success) { $VersionMatch.Groups[1].Value } else { $null }
    foreach ($Versions in @(@($MappingPack.ApplicableVersions),@($Mapping.ApplicableVersions))) {
        $RequiredVersions=@($Versions | Where-Object { $_ })
        if ($RequiredVersions.Count -and -not $VersionMatch.Success) { return [pscustomobject]@{ State='Unknown'; Reason="Operating system version is not known from '$OS'."; Confidence='Low'; OSVersion=$null } }
        if ($RequiredVersions.Count -and $Version -notin $RequiredVersions) {
            if ($MappingPack.EvaluationMode -in @('FutureTarget','ContextOnly') -or $Mapping.ContextOnly) {
                return [pscustomobject]@{ State='ContextOnly'; Reason="$OS is outside the $($MappingPack.FrameworkVersion) target; observations are future-state context only."; Confidence='High'; OSVersion=$Version }
            }
            return [pscustomobject]@{ State='NotApplicable'; Reason="$OS is outside the selected version scope."; Confidence='High'; OSVersion=$Version }
        }
    }
    if ($MappingPack.EvaluationMode -eq 'ContextOnly' -or $Mapping.ContextOnly) { return [pscustomobject]@{ State='ContextOnly'; Reason='Mapping is explicitly designated as context only.'; Confidence='High'; OSVersion=$Version } }
    [pscustomobject]@{ State='Applicable'; Reason="$OS is within the selected technical mapping scope; organizational control selection is not established."; Confidence='High'; OSVersion=$Version }
}
