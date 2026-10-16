function New-PSIApplicationModel {
    <# .SYNOPSIS Validate and aggregate linked generic application records. #>
    [CmdletBinding()]
    param(
        [Parameter()][object[]] $Findings = @(),
        [Parameter()][object[]] $Resources = @(),
        [Parameter()][object[]] $Evidence = @(),
        [Parameter()][object[]] $Relationships = @()
    )
    $Model = [pscustomobject]@{
        Findings = @($Findings)
        Resources = @($Resources)
        Evidence = @($Evidence)
        Relationships = @($Relationships)
        Summary = $null
    }
    [void] (Assert-PSIApplicationModel -Model $Model)
    $Groups = [ordered]@{}
    foreach ($Field in @('Severity','Category','Status')) {
        $Counts = @{}
        foreach ($Finding in $Model.Findings) {
            $Value = [string] (Get-PSIProperty -InputObject $Finding -Name $Field)
            if (-not $Counts.ContainsKey($Value)) { $Counts[$Value] = 0 }
            $Counts[$Value]++
        }
        $Groups["FindingsBy$Field"] = $Counts
    }
    $ResourcesByStatus = @{}
    foreach ($Resource in $Model.Resources) {
        $Value = [string] $Resource.Status
        if (-not $ResourcesByStatus.ContainsKey($Value)) { $ResourcesByStatus[$Value] = 0 }
        $ResourcesByStatus[$Value]++
    }
    $CriticalResourceIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Finding in $Model.Findings) {
        if ($Finding.Severity -eq 'Critical') { foreach ($Id in @($Finding.AffectedResourceIds)) { [void] $CriticalResourceIds.Add([string] $Id) } }
    }
    $Groups['ResourcesByStatus'] = $ResourcesByStatus
    $Groups['ResourcesWithCriticalFindings'] = $CriticalResourceIds.Count
    $Groups['EvidenceCount'] = $Model.Evidence.Count
    $Model.Summary = [pscustomobject] $Groups
    $Model
}
