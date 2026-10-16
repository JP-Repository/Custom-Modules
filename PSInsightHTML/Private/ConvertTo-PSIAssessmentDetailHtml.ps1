function ConvertTo-PSIAssessmentDetailHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Check','Category')][string] $Kind,
        [Parameter(Mandatory = $true)][pscustomobject] $Record,
        [Parameter(Mandatory = $true)][pscustomobject] $Assessment,
        [Parameter(Mandatory = $true)][pscustomobject] $Model,
        [Parameter(Mandatory = $true)][hashtable] $LinkViews
    )
    $B = [System.Text.StringBuilder]::new()
    $Name = ConvertTo-PSIHtmlEncoded -Value $Record.Name
    $IconName = if ($Kind -eq 'Category') { [string] $Record.Icon } else { 'Rules' }
    $Icon = Get-PSIIcon -Name $IconName
    [void] $B.AppendLine("<header class=`"psi-intelligence-heading`"><span class=`"psi-intelligence-heading-icon`">$Icon</span><div><p class=`"psi-app-explorer-detail-eyebrow`">$Kind investigation</p><h4>$Name</h4></div></header>")
    $Canonical = Resolve-PSIAssessmentStatus -Status ([string] $Record.Status)
    $Class = if ($Canonical -eq 'NotChecked') { 'not-checked' } else { $Canonical.ToLowerInvariant() }
    $Status = ConvertTo-PSIHtmlEncoded -Value $Record.Status
    $Description = ConvertTo-PSIHtmlEncoded -Value $Record.Description
    [void] $B.AppendLine("<div class=`"psi-intelligence-meta`"><span class=`"psi-status-badge psi-status-$Class`">$Status</span><span>Weight $($Record.Weight)</span></div><p class=`"psi-intelligence-summary`">$Description</p>")
    if ($Kind -eq 'Category') {
        $Score = if ($null -eq $Record.Score) { 'N/A' } else { "$($Record.Score)%" }
        [void] $B.AppendLine("<section class=`"psi-intelligence-block`"><h5>Category posture</h5><p>Score: $Score from $(@($Record.CheckIds).Count) linked checks.</p></section><section class=`"psi-intelligence-block`"><h5>Checks</h5>")
        [void] $B.AppendLine((ConvertTo-PSIIntelligenceLinksHtml -Ids @($Record.CheckIds) -Records $Assessment.Checks -View ([string] $LinkViews.Check) -LabelProperty Name))
        [void] $B.AppendLine('</section>')
    }
    else {
        $Category = @($Assessment.Categories | Where-Object { $_.Id -ieq $Record.CategoryId })[0]
        $CategoryName = ConvertTo-PSIHtmlEncoded -Value $Category.Name
        $Observed = ConvertTo-PSIHtmlEncoded -Value $Record.ObservedState
        $Expected = ConvertTo-PSIHtmlEncoded -Value $Record.ExpectedState
        $Blocking = if ($Record.IsBlocking) { '<strong class="psi-assessment-blocker">Blocking check</strong>' } else { '' }
        [void] $B.AppendLine("<p class=`"psi-intelligence-summary`">Category: $CategoryName $Blocking</p><section class=`"psi-intelligence-block`"><h5>Observed / Expected</h5><dl><div><dt>Observed</dt><dd>$Observed</dd></div><div><dt>Expected</dt><dd>$Expected</dd></div></dl></section>")
        [void] $B.AppendLine('<section class="psi-intelligence-block"><h5>Affected resources</h5>')
        [void] $B.AppendLine((ConvertTo-PSIIntelligenceLinksHtml -Ids @($Record.ResourceIds) -Records $Model.Resources -View ([string] $LinkViews.Resource) -LabelProperty Name))
        [void] $B.AppendLine('</section><section class="psi-intelligence-block"><h5>Findings</h5>')
        [void] $B.AppendLine((ConvertTo-PSIIntelligenceLinksHtml -Ids @($Record.FindingIds) -Records $Model.Findings -View ([string] $LinkViews.Finding) -LabelProperty Title))
        [void] $B.AppendLine('</section><section class="psi-intelligence-block"><h5>Evidence</h5>')
        [void] $B.AppendLine((ConvertTo-PSIIntelligenceLinksHtml -Ids @($Record.EvidenceIds) -Records $Model.Evidence -View ([string] $LinkViews.Evidence) -LabelProperty Title))
        [void] $B.AppendLine('</section>')
        $Action = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Record.Recommendation -Name Action -DefaultValue 'No provider recommendation supplied.')
        $Method = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Record.Validation -Name Method -DefaultValue 'No validation method supplied.')
        $ExpectedResult = ConvertTo-PSIHtmlEncoded -Value (Get-PSIProperty -InputObject $Record.Validation -Name ExpectedResult -DefaultValue '')
        [void] $B.AppendLine("<section class=`"psi-intelligence-block`"><h5>Recommendation</h5><p>$Action</p></section><section class=`"psi-intelligence-block`"><h5>Validation</h5><p>$Method</p><small>$ExpectedResult</small></section>")
        if (@($Record.Frameworks).Count -gt 0) {
            $Frameworks = ConvertTo-PSIHtmlEncoded -Value (@($Record.Frameworks) -join ', ')
            [void] $B.AppendLine("<section class=`"psi-intelligence-block`"><h5>Framework / source</h5><p>$Frameworks</p></section>")
        }
    }
    $B.ToString()
}
