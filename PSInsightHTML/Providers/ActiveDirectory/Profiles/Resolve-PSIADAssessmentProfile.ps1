function Resolve-PSIADAssessmentProfile {
    <# .SYNOPSIS Validate and resolve provider-owned assessment configuration without executing assessments. #>
    [CmdletBinding(DefaultParameterSetName='Path')]
    param(
        [Parameter(Mandatory, ParameterSetName='Path')][ValidateNotNullOrEmpty()][string] $Path,
        [Parameter(Mandatory, ParameterSetName='Profile')][hashtable] $Profile
    )

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        if ([System.IO.Path]::GetExtension($Path) -ne '.psd1' -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw "Assessment profile must be an existing .psd1 file: '$Path'."
        }
        $Profile=Import-PowerShellDataFile -LiteralPath $Path
    }
    $AllowedKeys=@('Name','Description','Assessments','Frameworks','TargetOS','ControlSelections','ControlExclusions','ThresholdOverrides','Tags','Metadata')
    foreach ($Key in $Profile.Keys) { if ($Key -notin $AllowedKeys) { throw "Unknown assessment profile field '$Key'." } }
    if ($Profile.Name -isnot [string] -or [string]::IsNullOrWhiteSpace($Profile.Name)) { throw 'Assessment profile Name is required.' }
    if ($Profile.ContainsKey('Description') -and $Profile.Description -isnot [string]) { throw 'Assessment profile Description must be text.' }
    if ($Profile.ContainsKey('Metadata') -and $Profile.Metadata -isnot [hashtable]) { throw 'Assessment profile Metadata must be a hashtable.' }

    $KnownAssessments=@('Inventory','Health','Security','Readiness2022','Readiness2025','Compliance')
    $SelectedAssessments=New-Object 'System.Collections.Generic.List[string]'
    foreach ($Assessment in @($Profile.Assessments)) {
        if ($Assessment -isnot [string] -or $Assessment -notin $KnownAssessments) { throw "Unknown assessment '$Assessment'." }
        if ($Assessment -in $SelectedAssessments) { throw "Duplicate assessment '$Assessment'." }
        $SelectedAssessments.Add($Assessment)
    }
    if ($SelectedAssessments.Count -eq 0) { throw 'Assessment profile must select at least one assessment.' }

    $TargetOS=$null
    if ($Profile.ContainsKey('TargetOS')) {
        if ($Profile.TargetOS -isnot [string] -or $Profile.TargetOS -cnotin @('2022','2025')) { throw "Invalid TargetOS '$($Profile.TargetOS)'; use 2022 or 2025." }
        $TargetOS=[string]$Profile.TargetOS
    }

    $Tags=New-Object 'System.Collections.Generic.List[string]'
    foreach ($Tag in @($Profile.Tags | Where-Object { $null -ne $_ })) {
        if ($Tag -isnot [string] -or [string]::IsNullOrWhiteSpace($Tag)) { throw 'Profile Tags must contain nonempty text.' }
        if ($Tag -in $Tags) { throw "Duplicate profile tag '$Tag'." }
        $Tags.Add($Tag)
    }

    $Frameworks=New-Object 'System.Collections.Generic.List[object]'
    $Packs=@{}
    foreach ($Entry in @($Profile.Frameworks | Where-Object { $null -ne $_ })) {
        if ($Entry -isnot [hashtable]) { throw 'Each framework selection must be a hashtable.' }
        foreach ($Key in $Entry.Keys) { if ($Key -notin @('FrameworkId','Version','Mode')) { throw "Unknown framework selection field '$Key'." } }
        if ([string]::IsNullOrWhiteSpace([string]$Entry.FrameworkId)) { throw 'FrameworkId is required.' }
        $Id=[string]$Entry.FrameworkId
        if ($Packs.ContainsKey($Id)) { throw "Duplicate framework '$Id'." }
        $Pack=Get-PSIADControlMappings -FrameworkId $Id
        if ($Entry.Version -isnot [string] -or $Entry.Version -cne $Pack.FrameworkVersion) { throw "Unknown version '$($Entry.Version)' for framework '$Id'; expected '$($Pack.FrameworkVersion)'." }
        if ($Entry.Mode -isnot [string] -or $Entry.Mode -cne $Pack.EvaluationMode) { throw "Invalid mode '$($Entry.Mode)' for framework '$Id'; expected '$($Pack.EvaluationMode)'." }
        $Packs[$Id]=$Pack
        $Frameworks.Add([pscustomobject]@{ FrameworkId=$Id; Version=[string]$Pack.FrameworkVersion; Mode=[string]$Pack.EvaluationMode; Name=[string]$Pack.Framework })
    }
    if ($Frameworks.Count -gt 0 -and 'Compliance' -notin $SelectedAssessments) { throw 'Frameworks require the Compliance assessment.' }
    if ('Compliance' -in $SelectedAssessments -and $Frameworks.Count -eq 0) { throw 'Compliance assessment requires at least one selected framework.' }

    $Includes=@{}; $Excludes=@{}
    foreach ($Kind in @('ControlSelections','ControlExclusions')) {
        $Target=if ($Kind -eq 'ControlSelections') { $Includes } else { $Excludes }
        foreach ($Selection in @($Profile[$Kind] | Where-Object { $null -ne $_ })) {
            if ($Selection -isnot [hashtable]) { throw "$Kind entries must be hashtables." }
            foreach ($Key in $Selection.Keys) { if ($Key -notin @('FrameworkId','ControlIds')) { throw "Unknown $Kind field '$Key'." } }
            $Id=[string]$Selection.FrameworkId
            if (-not $Packs.ContainsKey($Id)) { throw "$Kind references unselected framework '$Id'." }
            if ($Target.ContainsKey($Id)) { throw "Duplicate $Kind entry for framework '$Id'." }
            $Ids=New-Object 'System.Collections.Generic.List[string]'
            foreach ($ControlId in @($Selection.ControlIds)) {
                if ($ControlId -isnot [string] -or [string]::IsNullOrWhiteSpace($ControlId)) { throw "$Kind requires nonempty ControlIds." }
                if ($ControlId -in $Ids) { throw "Duplicate control ID '$ControlId' in $Kind for '$Id'." }
                $Known=@($Packs[$Id].Controls | Where-Object { $_.MappingType -ne 'Supporting' -and $_.ControlId -ceq $ControlId })
                if ($Known.Count -ne 1) { throw "Unknown selected control ID '$ControlId' for framework '$Id'." }
                $Ids.Add($ControlId)
            }
            if ($Ids.Count -eq 0) { throw "$Kind entry for '$Id' must contain at least one control ID." }
            $Target[$Id]=$Ids.ToArray()
        }
    }
    $SelectedControls=New-Object 'System.Collections.Generic.List[object]'
    $ExcludedControls=New-Object 'System.Collections.Generic.List[object]'
    foreach ($Framework in $Frameworks) {
        $Id=$Framework.FrameworkId
        foreach ($Control in @($Packs[$Id].Controls | Where-Object { $_.MappingType -ne 'Supporting' })) {
            $ControlId=[string]$Control.ControlId
            if ($Includes.ContainsKey($Id) -and $Excludes.ContainsKey($Id) -and $ControlId -in $Includes[$Id] -and $ControlId -in $Excludes[$Id]) {
                throw "Control '$ControlId' in '$Id' is both included and excluded."
            }
            $Identity="$Id|$($Framework.Version)|$ControlId"
            $Record=[pscustomobject]@{ FrameworkId=$Id; Version=$Framework.Version; ControlId=$ControlId; Identity=$Identity }
            if (($Includes.ContainsKey($Id) -and $ControlId -notin $Includes[$Id]) -or ($Excludes.ContainsKey($Id) -and $ControlId -in $Excludes[$Id])) {
                $ExcludedControls.Add($Record)
            } else {
                $SelectedControls.Add($Record)
            }
        }
    }

    $ThresholdOverrides=@{}
    if ($Profile.ContainsKey('ThresholdOverrides')) {
        if ($Profile.ThresholdOverrides -isnot [hashtable]) { throw 'ThresholdOverrides must be a hashtable keyed by Health or Security.' }
        foreach ($Area in $Profile.ThresholdOverrides.Keys) {
            if ($Area -notin @('Health','Security')) { throw "Unknown threshold area '$Area'." }
            if ($Area -notin $SelectedAssessments) { throw "Threshold area '$Area' requires its assessment to be selected." }
            $Overrides=$Profile.ThresholdOverrides[$Area]
            if ($Overrides -isnot [hashtable]) { throw "$Area threshold overrides must be a hashtable." }
            $Defaults=Import-PowerShellDataFile (Join-Path $PSScriptRoot "../Rules/$Area/Thresholds.psd1")
            $Resolved=@{}
            foreach ($Key in $Overrides.Keys) {
                if (-not $Defaults.ContainsKey($Key) -or $Key -in @('Version','Source')) { throw "Unknown or read-only $Area threshold '$Key'." }
                $Value=$Overrides[$Key]
                if ($Value -isnot [ValueType] -or $Value -is [bool] -or [double]::IsNaN([double]$Value) -or [double]::IsInfinity([double]$Value) -or [double]$Value -le 0) { throw "$Area threshold '$Key' must be a finite positive number." }
                if ($Key -match '(Days|Failures|Minutes|Milliseconds|MB)$' -and [double]$Value % 1 -ne 0) { throw "$Area threshold '$Key' must be a whole number." }
                if ($Key -match '(Percent|ScoreMinimum)$' -and [double]$Value -gt 100) { throw "$Area threshold '$Key' cannot exceed 100." }
                $Resolved[$Key]=[double]$Value
                $Defaults[$Key]=[double]$Value
            }
            if ([double]$Defaults.ReviewScoreMinimum -gt [double]$Defaults.ReadyScoreMinimum) { throw "$Area score threshold ordering is invalid." }
            if ($Area -eq 'Health' -and ([double]$Defaults.DiskCriticalFreeGB -ge [double]$Defaults.DiskReviewFreeGB -or [double]$Defaults.BackupHealthyDays -ge [double]$Defaults.BackupCriticalDays)) { throw 'Health threshold ordering is invalid.' }
            $ThresholdOverrides[$Area]=$Resolved
        }
    }

    $Metadata=@{}
    if ($Profile.ContainsKey('Metadata')) { foreach ($Key in $Profile.Metadata.Keys) { $Metadata[$Key]=$Profile.Metadata[$Key] } }
    [pscustomobject]@{
        Name=[string]$Profile.Name; Description=[string]$Profile.Description
        SelectedAssessments=$SelectedAssessments.ToArray(); SelectedFrameworks=$Frameworks.ToArray()
        SelectedControls=$SelectedControls.ToArray(); ExcludedControls=$ExcludedControls.ToArray()
        TargetOS=$TargetOS; ThresholdOverrides=$ThresholdOverrides; Tags=$Tags.ToArray(); Metadata=$Metadata
    }
}
