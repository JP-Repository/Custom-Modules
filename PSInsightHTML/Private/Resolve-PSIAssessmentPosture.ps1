function Resolve-PSIAssessmentPosture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][pscustomobject] $Assessment,
        [Parameter()][AllowNull()][pscustomobject] $Model = $null
    )
    [void] (Assert-PSIApplicationAssessment -Assessment $Assessment -Model $Model)
    $Points = @{ Ready=100.0; Review=50.0; Blocked=0.0; NotTested=0.0; Unknown=0.0 }
    $Counts = [ordered]@{ Ready=0; Review=0; Blocked=0; NotTested=0; NotApplicable=0; Unknown=0; Blockers=0; CriticalFindings=0 }
    $CategoryScores = [System.Collections.Generic.List[object]]::new()
    $OverallNumerator = 0.0
    $OverallDenominator = 0.0
    foreach ($Category in $Assessment.Categories) {
        $Numerator = 0.0
        $Denominator = 0.0
        $CategoryChecks = @($Assessment.Checks | Where-Object { $_.CategoryId -ieq $Category.Id })
        $CategoryCounts = @{ Ready=0; Review=0; Blocked=0; NotTested=0; NotApplicable=0; Unknown=0 }
        foreach ($Check in $CategoryChecks) {
            $Status = [string] $Check.Status
            $CategoryCounts[$Status]++
            $Counts[$Status]++
            if ($Status -ne 'NotApplicable') {
                $Weight = [double] $Check.Weight
                $Denominator += $Weight
                $Numerator += $Weight * [double] $Points[$Status]
            }
            if ($Check.IsBlocking -and $Status -in @('Review','Blocked')) { $Counts.Blockers++ }
        }
        $Score = if ($Denominator -gt 0) { [math]::Round($Numerator / $Denominator, 1) } else { $null }
        $Category.Score = $Score
        $Category.Status = if ($CategoryCounts.Blocked -gt 0) { 'Blocked' }
            elseif ($CategoryCounts.NotTested -gt 0) { 'NotTested' }
            elseif ($CategoryCounts.Unknown -gt 0) { 'Unknown' }
            elseif ($CategoryCounts.Review -gt 0) { 'Review' }
            elseif ($CategoryCounts.Ready -gt 0) { 'Ready' }
            else { 'NotApplicable' }
        if ($null -ne $Score) {
            $OverallNumerator += [double] $Category.Weight * [double] $Score
            $OverallDenominator += [double] $Category.Weight
        }
        $CategoryScores.Add([pscustomobject]@{
            Id=$Category.Id; Name=$Category.Name; Score=$Score; Weight=[double] $Category.Weight
            Status=$Category.Status; CheckCount=$CategoryChecks.Count; ApplicableCheckWeight=$Denominator
            Counts=[pscustomobject] $CategoryCounts
            WeightedContribution=if ($null -ne $Score) { [math]::Round([double] $Category.Weight * [double] $Score, 2) } else { $null }
        })
    }
    if ($null -ne $Model) {
        $AssessmentFindingIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Id in @($Assessment.FindingIds)) { [void] $AssessmentFindingIds.Add([string] $Id) }
        foreach ($Finding in $Model.Findings) {
            if ($AssessmentFindingIds.Contains([string] $Finding.Id) -and $Finding.Severity -eq 'Critical' -and $Finding.Status -notin @('Resolved','AcceptedRisk','NotApplicable')) {
                $Counts.CriticalFindings++
            }
        }
    }
    $Score = if ($OverallDenominator -gt 0) { [math]::Round($OverallNumerator / $OverallDenominator, 1) } else { $null }
    $Thresholds = $Assessment.Thresholds
    $Reasons = [System.Collections.Generic.List[string]]::new()
    if ($Counts.Blockers -gt 0) { $Reasons.Add("$($Counts.Blockers) blocking checks require action.") }
    if ($Counts.CriticalFindings -gt 0) { $Reasons.Add("$($Counts.CriticalFindings) open critical findings affect this assessment.") }
    if ($Counts.Blocked -gt 0) { $Reasons.Add("$($Counts.Blocked) checks are blocked.") }
    if ($Counts.NotTested -gt 0) { $Reasons.Add("$($Counts.NotTested) checks were not tested and count as zero until assessed.") }
    if ($Counts.Unknown -gt 0) { $Reasons.Add("$($Counts.Unknown) checks have unknown results and count as zero until assessed.") }
    if ($Counts.Review -gt 0) { $Reasons.Add("$($Counts.Review) checks require review and contribute half credit.") }
    if ($Counts.NotApplicable -gt 0) { $Reasons.Add("$($Counts.NotApplicable) not-applicable checks are excluded from the score denominator.") }
    $Decision = if ($Counts.Blockers -gt 0 -or $Counts.CriticalFindings -gt 0 -or $Counts.Blocked -gt 0) { 'NotReady' }
        elseif ($Counts.NotTested -gt 0) { 'Incomplete' }
        elseif ($Counts.Unknown -gt 0 -or $null -eq $Score) { 'Unknown' }
        elseif ($Score -ge [double] $Thresholds.Ready -and $Counts.Review -eq 0) { 'Ready' }
        elseif ($Score -ge [double] $Thresholds.Review) { 'ReadyWithReview' }
        else { 'ReviewRequired' }
    if ($Reasons.Count -eq 0) { $Reasons.Add('All applicable checks are ready.') }
    $Status = switch ($Decision) { Ready { 'Healthy' } ReadyWithReview { 'Warning' } ReviewRequired { 'Warning' } NotReady { 'Critical' } Incomplete { 'NotChecked' } default { 'Unknown' } }
    $Assessment.Score = $Score
    $Assessment.Decision = $Decision
    $Assessment.OverallStatus = $Status
    $Assessment.ScoreExplanation = [pscustomobject]@{
        CategoryScores=$CategoryScores.ToArray(); Counts=[pscustomobject] $Counts; Reasons=$Reasons.ToArray()
        CheckPoints=@{ Ready=100; Review=50; Blocked=0; NotTested=0; Unknown=0; NotApplicable='Excluded' }
        CategoryFormula='Weighted mean of applicable check points; category weights combine category scores.'
        Thresholds=$Thresholds; ExcludedCategoryCount=@($CategoryScores | Where-Object { $null -eq $_.Score }).Count
    }
    $Assessment
}
