function ConvertTo-PSIAssessmentOverviewHtml {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable] $Properties)
    $A = $Properties.Assessment
    $Model = $Properties.Model
    $B = [System.Text.StringBuilder]::new()
    $SafeName = ConvertTo-PSIHtmlEncoded -Value $A.Name
    $SafeType = ConvertTo-PSIHtmlEncoded -Value $A.AssessmentType
    $SafeTarget = ConvertTo-PSIHtmlEncoded -Value $A.Target
    $SafeProfile = ConvertTo-PSIHtmlEncoded -Value $A.Profile
    $SafeDescription = ConvertTo-PSIHtmlEncoded -Value $A.Description
    $DecisionLabel = ([string] $A.Decision -creplace '([a-z])([A-Z])','$1 $2').ToUpperInvariant()
    $SafeDecision = ConvertTo-PSIHtmlEncoded -Value $DecisionLabel
    $StatusClass = if ($A.OverallStatus -eq 'NotChecked') { 'not-checked' } else { ([string] $A.OverallStatus).ToLowerInvariant() }
    $ScoreNumber = if ($null -eq $A.Score) { 0 } else { [math]::Max(0,[math]::Min(100,[double] $A.Score)) }
    $ScoreText = if ($null -eq $A.Score) { 'N/A' } else { "$($A.Score)%" }
    $SafeScore = ConvertTo-PSIHtmlEncoded -Value $ScoreText
    $Counts = $A.ScoreExplanation.Counts
    $Icon = Get-PSIIcon -Name 'SecurityShield' -Size 22
    $ReasonText = @($A.ScoreExplanation.Reasons | Select-Object -First 2 | ForEach-Object { ConvertTo-PSIHtmlEncoded -Value $_ }) -join ' '
    $CoverageMarkup = ''
    if ($null -ne $A.Metadata -and $null -ne $A.Metadata.EvidenceCoveragePercent) {
        $Coverage = ConvertTo-PSIHtmlEncoded -Value "$($A.Metadata.EvidenceCoveragePercent)%"
        $CoverageMarkup = "<div class=`"psi-assessment-coverage`"><strong>$Coverage</strong><span>Evidence coverage</span></div>"
    }
    [void] $B.AppendLine("<section class=`"psi-assessment-overview`" data-psi-assessment-overview><div class=`"psi-assessment-hero psi-status-$StatusClass`"><div class=`"psi-assessment-hero-copy`"><p class=`"psi-assessment-eyebrow`">$Icon $SafeType assessment</p><h3>$SafeName</h3><p>$SafeDescription</p><div class=`"psi-assessment-identity`"><span>Target: $SafeTarget</span><span>Profile: $SafeProfile</span></div><div class=`"psi-assessment-verdict`"><strong class=`"psi-assessment-decision`">$SafeDecision</strong><p class=`"psi-assessment-decision-reason`">$ReasonText</p></div></div><div class=`"psi-assessment-measures`"><div class=`"psi-assessment-gauge`" role=`"img`" aria-label=`"Posture score $SafeScore`" style=`"--psi-posture-score:$ScoreNumber`"><div><strong>$SafeScore</strong><small>Posture score</small></div></div>$CoverageMarkup</div></div>")
    [void] $B.AppendLine('<div class="psi-assessment-counts">')
    foreach ($Metric in @(
        @{ Label='Blockers'; Value=($Counts.Blockers + $Counts.CriticalFindings); Class='critical' },
        @{ Label='Review'; Value=$Counts.Review; Class='warning' },
        @{ Label='Ready'; Value=$Counts.Ready; Class='healthy' },
        @{ Label='Not tested'; Value=$Counts.NotTested; Class='not-checked' }
    )) {
        [void] $B.AppendLine("<div class=`"psi-assessment-count psi-status-$($Metric.Class)`"><strong>$($Metric.Value)</strong><span>$($Metric.Label)</span></div>")
    }
    [void] $B.AppendLine('</div><div class="psi-assessment-overview-grid"><section class="psi-assessment-panel"><header><h4>Category posture</h4><span>Weighted score</span></header><div class="psi-assessment-categories">')
    $CheckView = ConvertTo-PSIHtmlEncoded -Value $Properties.CheckViewId
    foreach ($Category in $A.Categories) {
        $CategoryName = ConvertTo-PSIHtmlEncoded -Value $Category.Name
        $CategoryId = ConvertTo-PSIHtmlEncoded -Value $Category.Id
        $CategoryScore = if ($null -eq $Category.Score) { 'N/A' } else { "$($Category.Score)%" }
        $CategoryProgress = if ($null -eq $Category.Score) { 0 } else { [double] $Category.Score }
        $IconMarkup = Get-PSIIcon -Name $Category.Icon -Size 19
        $CheckCount = @($Category.CheckIds).Count
        $CategoryStatus = ConvertTo-PSIHtmlEncoded -Value $Category.Status
        $CategoryClass = switch ([string] $Category.Status) { Ready { 'healthy' } Review { 'warning' } Blocked { 'critical' } NotTested { 'not-checked' } default { 'neutral' } }
        $CategoryCounts = @($A.ScoreExplanation.CategoryScores | Where-Object { $_.Id -eq $Category.Id } | Select-Object -First 1)
        $CategoryCountText = if ($CategoryCounts.Count -gt 0) { "$($CategoryCounts[0].Counts.Ready) Ready | $($CategoryCounts[0].Counts.Review) Review | $($CategoryCounts[0].Counts.Blocked) Blocked | $($CategoryCounts[0].Counts.NotTested) Not Tested" } else { "$CheckCount checks" }
        $SafeCountText = ConvertTo-PSIHtmlEncoded -Value $CategoryCountText
        [void] $B.AppendLine("<button type=`"button`" class=`"psi-assessment-category psi-status-$CategoryClass`" data-psi-category-target=`"$CheckView`" data-psi-category-id=`"$CategoryId`" aria-label=`"$CategoryName, $CategoryScore, $CategoryStatus, $SafeCountText. View checks`"><span class=`"psi-assessment-category-icon`">$IconMarkup</span><span class=`"psi-assessment-category-copy`"><strong>$CategoryName</strong><small>$SafeCountText</small><span class=`"psi-assessment-progress`" style=`"--psi-progress:$CategoryProgress`"></span></span><span class=`"psi-assessment-category-result`"><strong>$CategoryScore</strong><small>$CategoryStatus</small></span></button>")
    }
    [void] $B.AppendLine('</div></section><section class="psi-assessment-panel"><header><h4>Why this decision</h4><span>Score and verdict</span></header><ul class="psi-assessment-reasons">')
    foreach ($Reason in $A.ScoreExplanation.Reasons) { [void] $B.AppendLine('<li>' + (ConvertTo-PSIHtmlEncoded -Value $Reason) + '</li>') }
    [void] $B.AppendLine('</ul><p class="psi-assessment-explanation">Ready = 100 points; Review = 50; Blocked, Not Tested and Unknown = 0. Not Applicable is excluded. Applicable check scores are weighted within each category, then category scores are weighted overall. The decision is evaluated separately.</p></section></div>')
    [void] $B.AppendLine('<div class="psi-assessment-overview-grid"><section class="psi-assessment-panel"><header><h4>Top blockers</h4><span>Action required</span></header><div class="psi-assessment-actions">')
    foreach ($Check in @($A.Checks | Where-Object { $_.Status -eq 'Blocked' -or ($_.IsBlocking -and $_.Status -eq 'Review') } | Select-Object -First 5)) {
        $Title = ConvertTo-PSIHtmlEncoded -Value $Check.Name
        $Id = ConvertTo-PSIHtmlEncoded -Value $Check.Id
        [void] $B.AppendLine("<button type=`"button`" data-psi-cross-view=`"$CheckView`" data-psi-cross-id=`"$Id`">$Title <span aria-hidden=`"true`">&#8599;</span></button>")
    }
    [void] $B.AppendLine('</div></section><section class="psi-assessment-panel"><header><h4>Priority findings</h4><span>Linked evidence</span></header><div class="psi-assessment-actions">')
    $FindingView = ConvertTo-PSIHtmlEncoded -Value $Properties.FindingViewId
    $FindingIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Id in @($A.FindingIds)) { [void] $FindingIds.Add([string] $Id) }
    foreach ($Finding in @($Model.Findings | Where-Object { $FindingIds.Contains([string] $_.Id) -and $_.Status -notin @('Resolved','AcceptedRisk','NotApplicable') } | Sort-Object { switch ($_.Severity) { Critical { 0 } Warning { 1 } default { 2 } } } | Select-Object -First 5)) {
        $Title = ConvertTo-PSIHtmlEncoded -Value $Finding.Title
        $Id = ConvertTo-PSIHtmlEncoded -Value $Finding.Id
        [void] $B.AppendLine("<button type=`"button`" data-psi-cross-view=`"$FindingView`" data-psi-cross-id=`"$Id`">$Title <span aria-hidden=`"true`">&#8599;</span></button>")
    }
    [void] $B.AppendLine('</div></section></div>')
    $Scope = ConvertTo-PSIHtmlEncoded -Value $A.Scope
    [void] $B.AppendLine("<div class=`"psi-assessment-overview-grid`"><section class=`"psi-assessment-panel`"><header><h4>Recommended next actions</h4><span>Provider supplied</span></header><ul class=`"psi-assessment-reasons`">")
    foreach ($Recommendation in @($A.Recommendations)) { [void] $B.AppendLine('<li>' + (ConvertTo-PSIHtmlEncoded -Value $Recommendation) + '</li>') }
    [void] $B.AppendLine("</ul></section><section class=`"psi-assessment-panel`"><header><h4>Scope &amp; evidence</h4><span>Assessment coverage</span></header><p>$Scope</p><p>$(@($A.ResourceIds).Count) linked resources &middot; $(@($A.EvidenceIds).Count) linked evidence records &middot; $($Counts.NotApplicable) not applicable checks</p></section></div></section>")
    $B.ToString()
}
